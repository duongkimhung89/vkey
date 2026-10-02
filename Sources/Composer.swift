import Foundation

enum TypingMode: String { case telex, vni }

/// One conversion engine lives for exactly one active word.  It is created on the
/// word's first key and released on reset, so no engine instance, history or
/// text survives a committed word.
struct Composer {
    static let maximumRawLength = 28 // Stay below the engine's 32-entry buffer capacity.
    /// The keys that produced `text`, in typing order.
    private(set) var raw = ""
    /// The converted word as it should appear in the document.
    private(set) var text = ""
    var mode: TypingMode = .telex
    /// Spell checking: marks apply only where Vietnamese allows them, and a
    /// word that cannot be Vietnamese returns to the keys typed when it ends.
    /// Off, every mark applies freely and nothing is given back.
    var checksSpelling = true
    var isEmpty: Bool { raw.isEmpty }

    private var engine: VNEngine?
    /// Set once a key the engine has no code for arrives; the word then stays as typed.
    private var literal = false

    mutating func reset() {
        raw = ""
        text = ""
        engine = nil
        literal = false
    }

    mutating func append(_ character: Character) {
        raw.append(character)
        guard !literal, let code = VietnameseData.keyCode(for: character) else {
            literal = true
            text = raw
            return
        }
        let engine = self.engine ?? Self.makeEngine(mode: mode, checksSpelling: checksSpelling)
        self.engine = engine
        engine.handleKeyEvent(keyCode: code, character: character,
                              isUppercase: character.isUppercase, hasOtherModifier: false)
        text = engine.getCurrentWord()
    }

    /// Remove the last character of the word, as Backspace does in any editor.
    /// Marks on the remaining letters stay ("tiếng" → "tiến"), and typing can
    /// continue on the shortened word.
    mutating func backspace() {
        guard !raw.isEmpty else { return }
        guard !literal, let engine else {
            raw.removeLast()
            text = raw
            if raw.isEmpty { reset() }
            return
        }
        let before = engine.buffer.getKeystrokeSequence()
        engine.handleKeyEvent(keyCode: VietnameseData.KEY_DELETE, character: "\u{8}",
                              isUppercase: false, hasOtherModifier: false)
        text = engine.getCurrentWord()
        // Drop the keys that belonged to the removed character.  The engine
        // keeps one record per key in typing order, tagged with its character.
        let surviving = Set(engine.buffer.getKeystrokeSequence().map(\.entryId))
        if before.count == raw.count {
            raw = String(zip(raw, before).filter { surviving.contains($0.1.entryId) }.map(\.0))
        } else {
            raw = text
        }
        if text.isEmpty || raw.isEmpty { reset() }
    }

    /// The text to leave in the document when the word ends.  Marks that
    /// landed on something that cannot be a Vietnamese syllable mean the keys
    /// were not Vietnamese ("windows" showing as "ưindows"), so the keys come
    /// back as typed.  A word left in plain letters by a repeated key is not
    /// touched: that is Telex's own way of cancelling a mark ("tesst" → "test").
    var committedText: String {
        let text = Self.closingOpenHorn(in: self.text)
        guard checksSpelling, text != raw, !text.allSatisfy(\.isASCII) else { return text }
        let keys = Array(raw.lowercased())
        let stretched = keys.count >= 2 && keys[keys.count - 1] == keys[keys.count - 2]
        return VietnameseSyllable.isPossible(text, stretched: stretched) ? text : raw
    }

    /// The engine writes "uow" as "ươ" because a final consonant usually
    /// follows (hương, được).  A word that ends there is spelled "uơ" (huơ, thuở).
    private static func closingOpenHorn(in text: String) -> String {
        var letters = Array(text)
        guard letters.count >= 3, "ơớờởỡợƠỚỜỞỠỢ".contains(letters[letters.count - 1]) else { return text }
        switch letters[letters.count - 2] {
        case "ư": letters[letters.count - 2] = "u"
        case "Ư": letters[letters.count - 2] = "U"
        default: return text
        }
        return String(letters)
    }

    private static func makeEngine(mode: TypingMode, checksSpelling: Bool) -> VNEngine {
        let engine = VNEngine()
        engine.vInputType = mode == .telex ? 0 : 1
        engine.vCodeTable = 0
        engine.vCheckSpelling = checksSpelling ? 1 : 0
        engine.useSpellCheckingBefore = checksSpelling
        engine.vRestoreIfWrongSpelling = 0
        engine.vQuickTelex = 0
        engine.vUseMacro = 0
        engine.vUseSmartSwitchKey = 0
        engine.vUpperCaseFirstChar = 0
        engine.vUseModernOrthography = 1
        return engine
    }

    static func convert(_ raw: String, mode: TypingMode) -> String {
        // The host controller limits an active word to this size. Keep the
        // adapter safe if a future caller bypasses that controller or a test
        // supplies an oversized string; the upstream buffer is finite.
        guard raw.count <= maximumRawLength else { return raw }
        var composer = Composer()
        composer.mode = mode
        for c in raw { composer.append(c) }
        return composer.text
    }
}

// MARK: - Keys for a word

extension Composer {
    /// The keys that type `word` in `mode`, the reverse of `convert`: each
    /// letter is followed by the key for its mark (â: a6 / aa, đ: d9 / dd),
    /// and the tone key comes after the last letter, or right after its vowel
    /// when `toneAtEnd` is false.  Nil when the word holds a character that
    /// no keys type.
    static func keys(for word: String, mode: TypingMode, toneAtEnd: Bool = true) -> String? {
        // In a word written in capitals the mark and tone keys are capitals too (NGUYEENX).
        let allCaps = word.count > 1 && word == word.uppercased()
        func cased(_ key: Character) -> String { allCaps ? key.uppercased() : String(key) }

        var keys = "", toneKey = ""
        for character in word {
            guard let parts = letterParts[character.lowercased()] else {
                guard character.isASCII, character.isLetter else { return nil }
                keys.append(character)
                continue
            }
            keys += character.isUppercase ? parts.plain.uppercased() : String(parts.plain)
            if let mark = parts.mark {
                keys += cased(mark.key(for: parts.plain, in: mode))
            }
            if parts.tone > 0 {
                let key = cased(Array(mode == .telex ? "sfrxj" : "12345")[parts.tone - 1])
                if toneAtEnd { toneKey = key } else { keys += key }
            }
        }
        return keys + toneKey
    }

    /// What turns a plain letter into a Vietnamese one.
    private enum Mark {
        case circumflex // â ê ô
        case breve      // ă
        case horn       // ơ ư
        case stroke     // đ

        func key(for letter: Character, in mode: TypingMode) -> Character {
            switch (mode, self) {
            case (.telex, .circumflex), (.telex, .stroke): return letter
            case (.telex, .breve), (.telex, .horn): return "w"
            case (.vni, .circumflex): return "6"
            case (.vni, .breve): return "8"
            case (.vni, .horn): return "7"
            case (.vni, .stroke): return "9"
            }
        }
    }

    /// Every lowercase vowel and đ → its plain letter, mark and tone
    /// (1...5: sắc, huyền, hỏi, ngã, nặng, the order of the VNI keys).
    private static let letterParts: [String: (plain: Character, mark: Mark?, tone: Int)] = {
        let rows: [(plain: Character, mark: Mark?, forms: String)] = [
            ("a", nil, "aáàảãạ"), ("a", .breve, "ăắằẳẵặ"), ("a", .circumflex, "âấầẩẫậ"),
            ("e", nil, "eéèẻẽẹ"), ("e", .circumflex, "êếềểễệ"), ("i", nil, "iíìỉĩị"),
            ("o", nil, "oóòỏõọ"), ("o", .circumflex, "ôốồổỗộ"), ("o", .horn, "ơớờởỡợ"),
            ("u", nil, "uúùủũụ"), ("u", .horn, "ưứừửữự"), ("y", nil, "yýỳỷỹỵ"),
        ]
        var parts: [String: (plain: Character, mark: Mark?, tone: Int)] = ["đ": ("d", .stroke, 0)]
        for row in rows {
            for (tone, form) in row.forms.enumerated() {
                parts[String(form)] = (row.plain, row.mark, tone)
            }
        }
        return parts
    }()
}
