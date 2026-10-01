import Foundation

/// The part of an IMKit text client that VKey uses.  Kept as a protocol so the
/// typing logic can be exercised without a running input method.
protocol TextClient {
    func selectedRange() -> NSRange
    func insertText(_ text: String, replacementRange: NSRange)
    func setMarkedText(_ text: String, selectionRange: NSRange, replacementRange: NSRange)
}

struct KeyStroke {
    static let backspace: UInt16 = 51
    static let escape: UInt16 = 53

    var keyCode: UInt16
    var characters: String?
    /// Command, Control or Option is held: a shortcut, never part of a word.
    var hasShortcutModifier = false
    var isNumericPad = false
}

/// Typing state for one text client: the active word and how it is shown.
///
/// Direct mode keeps the active word as ordinary document text, so the host
/// draws no underline.  A key that only adds its own letter is left to the
/// application, exactly as without an input method; VKey steps in only when a
/// key changes letters already typed, and then replaces just the part that
/// changed.  It needs a client that reports its selection and honours
/// `replacementRange`.  Clients that cannot (terminals, some cross-platform
/// toolkits) get the standard IMKit marked text instead.
///
/// Where the word is comes from VKey's own record of the edits it knows
/// about, not from the caret the client reports.  Browsers and Electron apps
/// keep their text in another process and report the caret a few edits late
/// when typing is fast; such a report is recognised as one of the positions
/// the caret has passed through, and only a caret found anywhere else means
/// the user moved it.
final class InputSession {
    private static let noRange = NSRange(location: NSNotFound, length: 0)
    private static let noMarkedRange = NSRange(location: NSNotFound, length: NSNotFound)
    /// Edits a client may leave unconfirmed before its reported caret is taken
    /// to mean nothing.  Far beyond what a late client ever trails by.
    static let maximumUnconfirmedEdits = 32

    private var composer = Composer()
    var mode: TypingMode {
        get { composer.mode }
        set { composer.mode = newValue }
    }
    var checksSpelling: Bool {
        get { composer.checksSpelling }
        set { composer.checksSpelling = newValue }
    }
    /// Show the active word as marked text in this client.
    var prefersMarkedText = false
    /// Called when a client proves unable to take direct text: it ignores
    /// `replacementRange`, or its reported caret never follows the text.
    var onDirectTextUnsupported: (() -> Void)?

    var isComposing: Bool { !composer.isEmpty }

    // Direct mode: where the active word starts in the document (UTF-16
    // units) and what the document holds for it.
    private var start = NSNotFound
    private var written = ""
    /// Where the caret has been after each edit since the client last
    /// reported it, oldest first.  The last entry is where it is now; an empty
    /// trail means VKey does not know and goes by the client's report.
    private var trail: [Int] = []
    private var markedActive = false

    /// Returns true when the key was consumed.
    func handle(_ key: KeyStroke, client: TextClient) -> Bool {
        let selection = client.selectedRange()
        synchronize(with: selection)

        if key.hasShortcutModifier {
            finish(with: composer.committedText, client: client, selection: selection)
            trail = []
            return false
        }
        if key.keyCode == KeyStroke.escape, isComposing {
            // Escape takes back a conversion.  With nothing converted it
            // belongs to the application (close a dialog, leave Vim insert mode).
            let converted = composer.text != composer.raw
            finish(with: composer.raw, client: client, selection: selection)
            if !converted { trail = [] }
            return converted
        }
        if key.keyCode == KeyStroke.backspace, isComposing {
            return backspace(client: client, selection: selection)
        }
        guard let character = composingCharacter(for: key) else {
            finish(with: composer.committedText, client: client, selection: selection)
            passedThrough(key, selection: selection)
            return false
        }
        if composer.raw.count >= Composer.maximumRawLength {
            finish(with: composer.committedText, client: client, selection: selection)
        }

        if composer.isEmpty {
            markedActive = prefersMarkedText || selection.location == NSNotFound
            if markedActive {
                trail = []
            } else {
                start = trail.last ?? selection.location
                if trail.isEmpty { trail = [start] }
            }
        }
        let before = composer.text
        composer.append(character)
        if markedActive {
            showMarked(composer.text, client: client)
            return true
        }
        if composer.text == before + String(character) {
            // The key adds only itself: the application types it.
            moved(to: composer.text)
            return false
        }
        replaceDirect(with: composer.text, client: client, selection: selection)
        return true
    }

    /// End the active word where no key is being handled (focus change, mouse
    /// click, mode switch).  The caret may no longer be at the word, so direct
    /// text is left exactly as it is.
    func commit(client: TextClient) {
        if markedActive {
            client.insertText(composer.committedText, replacementRange: Self.noRange)
        }
        reset()
        trail = []
    }

    /// Forget the active word without touching the client.
    func reset() {
        composer.reset()
        start = NSNotFound
        written = ""
        markedActive = false
    }

    private func composingCharacter(for key: KeyStroke) -> Character? {
        guard let input = key.characters, input.count == 1, let c = input.first, c.isASCII else { return nil }
        if c.isLetter { return c }
        switch mode {
        case .telex: return "[]".contains(c) ? c : nil
        // Keypad digits are numbers, not tone keys.
        case .vni: return c.isNumber && !key.isNumericPad ? c : nil
        }
    }

    /// Backspace removes one character of the active word.
    private func backspace(client: TextClient, selection: NSRange) -> Bool {
        if markedActive {
            composer.backspace()
            showMarked(composer.text, client: client)
            return true
        }
        if selection.location != NSNotFound, selection.length > 0 {
            // Deleting a selection (or an inline completion) is the
            // application's business and ends the word.
            reset()
            trail = []
            return false
        }
        let before = composer.text
        composer.backspace()
        let after = composer.text
        if before.hasPrefix(after), before.utf16.count == after.utf16.count + 1 {
            // Only the last character goes: the application deletes it, which
            // keeps key repeat and undo exactly as they are without VKey.
            moved(to: after)
            if composer.isEmpty { reset() }
            return false
        }
        // The engine also moved a mark ("cuản" → "của").
        replaceDirect(with: after, client: client, selection: selection)
        return true
    }

    /// The application handled a key that is not part of a word.  Text keys
    /// (space, punctuation, digits) move the caret by what they type; after
    /// anything else VKey no longer knows where the caret is.
    private func passedThrough(_ key: KeyStroke, selection: NSRange) {
        if key.keyCode == KeyStroke.backspace, !prefersMarkedText, let caret = trail.last {
            // One character goes, or the completion selected after the caret.
            let completion = selection.location == caret && selection.length > 0
            trail.append(completion ? caret : max(caret - 1, 0))
            return
        }
        // Control characters (Return, Tab, Delete) and the function-key range
        // AppKit uses for arrows and the like do not type anything known.
        guard !prefersMarkedText, let typed = key.characters, !typed.isEmpty,
              typed.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value != 0x7F && !(0xF700...0xF8FF).contains($0.value) }),
              let caret = trail.last ?? (selection.location == NSNotFound ? nil : selection.location) else {
            trail = []
            return
        }
        if trail.isEmpty { trail = [caret] }
        trail.append(caret + typed.utf16.count)
    }

    /// Leave `text` in the document as the finished word and clear the state.
    private func finish(with text: String, client: TextClient, selection: NSRange) {
        guard isComposing else { return }
        if markedActive {
            client.insertText(text, replacementRange: Self.noRange)
        } else if text != written {
            replaceDirect(with: text, client: client, selection: selection)
        }
        reset()
    }

    private func showMarked(_ text: String, client: TextClient) {
        client.setMarkedText(text,
                             selectionRange: NSRange(location: text.utf16.count, length: 0),
                             replacementRange: Self.noMarkedRange)
        if text.isEmpty { markedActive = false }
    }

    /// The document now holds `text` for the active word, the caret after it.
    private func moved(to text: String) {
        written = text
        trail.append(start + text.utf16.count)
    }

    /// Make the document hold `text` for the active word, rewriting only from
    /// the first character that differs.
    private func replaceDirect(with text: String, client: TextClient, selection: NSRange) {
        let old = Array(written.utf16), new = Array(text.utf16)
        guard !old.isEmpty else {
            // The word's first key was itself converted ("w" → "ư").
            client.insertText(text, replacementRange: Self.noRange)
            moved(to: text)
            return
        }

        var kept = 0
        while kept < old.count, kept < new.count, old[kept] == new[kept] { kept += 1 }
        let inserted = String(utf16CodeUnits: Array(new[kept...]), count: new.count - kept)
        // Text selected right after the word is an inline completion offered
        // by the host (address bars); it is replaced together with the word.
        let completion = selection.location == start + old.count ? selection.length : 0
        let range = NSRange(location: start + kept, length: old.count - kept + completion)
        client.insertText(inserted, replacementRange: range.length > 0 ? range : Self.noRange)
        moved(to: text)

        // A client that ignores the range appends instead of replacing, which
        // leaves the caret further along than the replaced text allows.  A
        // late report is never that far along.
        let appended = start + old.count + (new.count - kept)
        if kept < old.count, !new.isEmpty, client.selectedRange().location == appended {
            onDirectTextUnsupported?()
            prefersMarkedText = true
            reset()
            trail = []
        }
    }

    /// Match the reported caret against the trail.  A caret VKey did not put
    /// there means the user clicked, selected or the application changed the
    /// text: the word is already in the document, so only VKey's state goes.
    private func synchronize(with selection: NSRange) {
        guard !markedActive, !trail.isEmpty else { return }
        guard selection.location != NSNotFound, let seen = trail.firstIndex(of: selection.location) else {
            reset()
            trail = []
            return
        }
        trail.removeFirst(seen)
        if trail.count > Self.maximumUnconfirmedEdits {
            // The reported caret does not follow the text at all.  The word
            // in progress stays direct; later words use marked text.
            trail.removeFirst(trail.count - Self.maximumUnconfirmedEdits)
            if !prefersMarkedText {
                prefersMarkedText = true
                onDirectTextUnsupported?()
            }
        }
    }
}
