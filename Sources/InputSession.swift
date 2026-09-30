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
/// changed.  This is the direct transport of XKey's IMKit mode.  It needs a
/// client that reports its selection and honours `replacementRange`.  Clients
/// that cannot (terminals, some cross-platform toolkits) get the standard
/// IMKit marked text instead, which every client supports.
final class InputSession {
    private static let noRange = NSRange(location: NSNotFound, length: 0)
    private static let noMarkedRange = NSRange(location: NSNotFound, length: NSNotFound)

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
    /// `replacementRange`, or its selection does not follow what is typed.
    var onDirectTextUnsupported: (() -> Void)?

    var isComposing: Bool { !composer.isEmpty }

    // Direct mode: where the active word starts in the document (UTF-16
    // units) and what the document holds for it.
    private var directStart = NSNotFound
    private var directText = ""
    /// The caret as reported before the last key the application typed itself.
    private var caretBeforeTypedKey = NSNotFound
    /// This client's caret has been seen to move with a typed letter.
    private var caretFollowsTyping = false
    private var frozenCaretSightings = 0
    private var markedActive = false

    /// Returns true when the key was consumed.
    func handle(_ key: KeyStroke, client: TextClient) -> Bool {
        var selection = synchronize(with: client)

        if key.hasShortcutModifier {
            finish(with: composer.committedText, client: client, selection: selection)
            return false
        }
        if key.keyCode == KeyStroke.escape, isComposing {
            // Escape takes back a conversion.  With nothing converted it
            // belongs to the application (close a dialog, leave Vim insert mode).
            let converted = composer.text != composer.raw
            finish(with: composer.raw, client: client, selection: selection)
            return converted
        }
        if key.keyCode == KeyStroke.backspace, isComposing {
            return backspace(client: client, selection: selection)
        }
        guard let character = composingCharacter(for: key) else {
            finish(with: composer.committedText, client: client, selection: selection)
            return false
        }
        if composer.raw.count >= Composer.maximumRawLength {
            finish(with: composer.committedText, client: client, selection: selection)
            selection = client.selectedRange()
        }

        if composer.isEmpty {
            markedActive = prefersMarkedText || selection.location == NSNotFound
        }
        let before = composer.text
        composer.append(character)
        if markedActive {
            showMarked(composer.text, client: client)
            return true
        }
        if composer.text == before + String(character) {
            // The key adds only itself: the application types it.
            if before.isEmpty { directStart = selection.location }
            caretBeforeTypedKey = selection.length == 0 ? directStart + before.utf16.count : NSNotFound
            directText = composer.text
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
    }

    /// Forget the active word without touching the client.
    func reset() {
        composer.reset()
        clearDirect()
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
            return false
        }
        let before = composer.text
        composer.backspace()
        let after = composer.text
        if before.hasPrefix(after), before.utf16.count == after.utf16.count + 1 {
            // Only the last character goes: the application deletes it, which
            // keeps key repeat and undo exactly as they are without VKey.
            directText = after
            if after.isEmpty { clearDirect() }
            return false
        }
        // The engine also moved a mark ("cuản" → "của").
        replaceDirect(with: after, client: client, selection: selection)
        return true
    }

    /// Leave `text` in the document as the finished word and clear the state.
    private func finish(with text: String, client: TextClient, selection: NSRange) {
        guard isComposing else { return }
        if markedActive {
            client.insertText(text, replacementRange: Self.noRange)
        } else if text != directText {
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

    /// Make the document hold `text` for the active word, rewriting only from
    /// the first character that differs.
    private func replaceDirect(with text: String, client: TextClient, selection: NSRange) {
        let old = Array(directText.utf16), new = Array(text.utf16)
        guard !old.isEmpty else {
            // The word's first key was itself converted ("w" → "ư").
            directStart = selection.location
            client.insertText(text, replacementRange: Self.noRange)
            directText = text
            return
        }

        var kept = 0
        while kept < old.count, kept < new.count, old[kept] == new[kept] { kept += 1 }
        let inserted = String(utf16CodeUnits: Array(new[kept...]), count: new.count - kept)
        // Text selected right after the word is an inline completion offered
        // by the host (address bars); it is replaced together with the word.
        let completion = selection.location == directStart + old.count ? selection.length : 0
        let range = NSRange(location: directStart + kept, length: old.count - kept + completion)
        client.insertText(inserted, replacementRange: range.length > 0 ? range : Self.noRange)
        directText = text

        // A client that ignores the range appends instead of replacing, which
        // leaves the caret further along than the replaced text allows.
        let appended = directStart + old.count + (new.count - kept)
        if kept < old.count, !new.isEmpty, client.selectedRange().location == appended {
            useMarkedText(report: true)
        }
    }

    private func useMarkedText(report: Bool) {
        prefersMarkedText = true
        if report { onDirectTextUnsupported?() }
        reset()
    }

    private func clearDirect() {
        directStart = NSNotFound
        directText = ""
        caretBeforeTypedKey = NSNotFound
    }

    /// Drop the active word if the caret is no longer right after it.
    private func synchronize(with client: TextClient) -> NSRange {
        let selection = client.selectedRange()
        guard !markedActive, !directText.isEmpty, selection.location != NSNotFound else { return selection }
        let typedKeyCaret = caretBeforeTypedKey
        caretBeforeTypedKey = NSNotFound
        if selection.location == directStart + directText.utf16.count {
            if typedKeyCaret != NSNotFound { caretFollowsTyping = true }
            return selection
        }
        if selection.location == typedKeyCaret {
            // The application typed a letter and its caret has not moved.  A
            // client whose caret is known to follow typing is just one key
            // behind (its text lives in another process); the word's own
            // position record stays valid.
            if caretFollowsTyping { return selection }
            // Otherwise the selection it reports cannot be used to place
            // replacements.  A click just before that letter looks the same
            // once, so the application is only reported when it happens again.
            frozenCaretSightings += 1
            useMarkedText(report: frozenCaretSightings == 2)
        } else {
            // The user clicked or selected elsewhere.  The text is already
            // in the document, so only VKey's word state is discarded.
            reset()
        }
        return selection
    }
}
