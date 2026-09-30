import Foundation

enum TypingMode: String { case telex, vni }

/// A short-lived XKey engine reconstructs only the current marked word.
/// No engine instance, history or text survives a conversion or committed word.
struct Composer {
    static let maximumRawLength = 28 // Stay below XKey's 32-entry buffer capacity.
    private(set) var raw = ""
    var mode: TypingMode = .telex
    var text: String { Self.convert(raw, mode: mode) }
    mutating func reset() { raw = "" }
    mutating func append(_ character: Character) { raw.append(character) }
    mutating func backspace() { if !raw.isEmpty { raw.removeLast() } }

    private static let keyCodes = Dictionary(uniqueKeysWithValues:
        VietnameseData.keyCodeToCharacterMap.map { ($0.value, $0.key) })

    static func convert(_ raw: String, mode: TypingMode) -> String {
        // The host controller limits an active word to this size. Keep the
        // adapter safe if a future caller bypasses that controller or a test
        // supplies an oversized string; the upstream buffer is finite.
        guard raw.count <= maximumRawLength else { return raw }
        let engine = VNEngine()
        engine.vInputType = mode == .telex ? 0 : 1
        engine.vCodeTable = 0
        engine.vCheckSpelling = 0
        engine.useSpellCheckingBefore = false
        engine.vRestoreIfWrongSpelling = 0
        engine.vQuickTelex = 0
        engine.vUseMacro = 0
        engine.vUseSmartSwitchKey = 0
        engine.vUpperCaseFirstChar = 0
        engine.vUseModernOrthography = 1
        for c in raw {
            guard let lower = c.lowercased().first, let code = keyCodes[lower] else { return raw }
            _ = engine.handleKeyEvent(keyCode: code, character: c, isUppercase: c.isUppercase, hasOtherModifier: false)
        }
        return engine.getCurrentWord().precomposedStringWithCanonicalMapping
    }
}
