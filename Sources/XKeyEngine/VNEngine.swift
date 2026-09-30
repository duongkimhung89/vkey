// Adapted from XKey, copyright (c) 2025 XKey (MIT). See Resources/Licenses and THIRD_PARTY_NOTICES.md.
// Modified 2026-09-30: no logging callbacks; engine core only, no host integration.
// XKey identifies this engine as a Swift port based on the GPL-3.0 OpenKey engine.
// OpenKey provenance: Copyright © 2019 Tuyen Mai / Mai Vu Tuyen; GPL-3.0.
//
//  VNEngine.swift
//  XKey
//
//  Vietnamese Input Engine - Complete rewrite based on OpenKey Engine
//  Ported from OpenKey C++ engine to Swift with full feature parity
//

import Foundation
import Cocoa

/// Main Vietnamese typing engine - Direct port from OpenKey
class VNEngine {
    
    // MARK: - Constants (from DataType.h)
    // Note: Using internal access for extension support
    
    static let MAX_BUFF = 32
    
    // Masks for internal data structure
    static let CAPS_MASK: UInt32           = 0x10000
    static let TONE_MASK: UInt32           = 0x20000
    static let TONEW_MASK: UInt32          = 0x40000
    static let MARK1_MASK: UInt32          = 0x80000    // Sắc
    static let MARK2_MASK: UInt32          = 0x100000   // Huyền
    static let MARK3_MASK: UInt32          = 0x200000   // Hỏi
    static let MARK4_MASK: UInt32          = 0x400000   // Ngã
    static let MARK5_MASK: UInt32          = 0x800000   // Nặng
    static let MARK_MASK: UInt32           = 0xF80000
    static let CHAR_MASK: UInt32           = 0xFFFF
    static let STANDALONE_MASK: UInt32     = 0x1000000
    static let CHAR_CODE_MASK: UInt32      = 0x2000000
    // Note: END_CONSONANT_MASK and CONSONANT_ALLOW_MASK are defined in VietnameseData (as UInt16)
    // and are the canonical source used throughout the codebase.
    
    /// Convert macOS virtual key code to printable character for logging.
    /// Indexes into the canonical static map to avoid rebuilding a dictionary on every call
    /// (this runs per keystroke, per buffer char via getRawInputString/getCurrentWordString).
    static func keyCodeToChar(_ keyCode: UInt16) -> Character? {
        return VietnameseData.keyCodeToCharacterMap[keyCode]
    }
    
    // MARK: - Settings (from Engine.h)
    
    var vInputType = 0             // 0: Telex, 1: VNI
    var vAdaptiveEnabled = false   // Adaptive: accept BOTH Telex & VNI keys, decided per keystroke
    var vCodeTable = 0             // 0: Unicode, 1: TCVN3, 2: VNI-Windows
    var vCheckSpelling = 1         // 0: No, 1: Yes
    var vUseModernOrthography = 1  // 0: òa/úy, 1: oà/uý
    var vQuickTelex = 1            // 0: No, 1: Yes (cc=ch, gg=gi, etc.)
    var vRestoreIfWrongSpelling = 1 // 0: No, 1: Yes
    var vUseMacro = 0              // 0: No, 1: Yes
    var vUseSmartSwitchKey = 0     // 0: No, 1: Yes
    var vUpperCaseFirstChar = 0    // 0: No, 1: Yes
    var vUpperCaseRequireSpace = 1 // 0: cap right after . ? ! even with no space; 1: require a space after . ? ! (newline always caps)
    var vTempOffSpelling = 0       // 0: No, 1: Yes (temp off spell check via toolbar)
    var vTempOffEngine = 0         // 0: No, 1: Yes (temp off engine via toolbar)
    var vCustomConsonants: Set<UInt16> = [] { // Custom consonants allowed (e.g., Z, F, W, J, K)
        didSet {
            // Cache the Character form so the per-keystroke English-detection path
            // doesn't rebuild this Set on every key.
            customConsonantChars = Set(vCustomConsonants.compactMap { VietnameseData.char(for: $0) })
        }
    }
    /// Character form of `vCustomConsonants`, recomputed only when that set changes.
    /// `private(set)` so tests can verify the cache stays in sync without allowing writes.
    private(set) var customConsonantChars: Set<Character> = []
    var vQuickStartConsonant = 0   // 0: No, 1: Yes (f->ph, j->gi, w->qu)
    var vQuickEndConsonant = 0     // 0: No, 1: Yes (g->ng, h->nh, k->ch)
    
    // MARK: - Unified Buffer System
    //
    // Single source of truth for typing state.
    // Each CharacterEntry contains both raw keystrokes and processed output.

    /// Primary typing buffer
    let buffer = TypingBuffer()

    /// History of typed words for restore functionality
    let history = TypingHistory()

    // MARK: - Buffer Accessors
    //
    // Wrapper types provide array-like access to buffer while using
    // unified buffer as single source of truth.

    /// Wrapper for accessing processed character data with array syntax
    struct ProcessedDataAccessor {
        let buffer: TypingBuffer

        subscript(i: Int) -> UInt32 {
            get {
                guard i >= 0 && i < buffer.count else { return 0 }
                return buffer[i].processedData
            }
            nonmutating set {
                guard i >= 0 && i < buffer.count else { return }
                buffer[i].processedData = newValue
            }
        }

        var count: Int { buffer.count }
    }

    /// Wrapper for accessing raw keystrokes with array syntax
    struct RawKeystrokeAccessor {
        let buffer: TypingBuffer

        subscript(i: Int) -> UInt32 {
            get {
                // Use direct access instead of creating array each time
                guard let keystroke = buffer.getRawKeystroke(at: i) else { return 0 }
                return keystroke.asUInt32
            }
            nonmutating set {
                // Raw keystrokes are managed through buffer operations
            }
        }

        var count: Int { buffer.totalKeystrokeCount }
    }

    /// Access to processed data (typingWord replacement)
    var typingWord: ProcessedDataAccessor {
        ProcessedDataAccessor(buffer: buffer)
    }

    /// Access to raw keystrokes (keyStates replacement)
    var keyStates: RawKeystrokeAccessor {
        RawKeystrokeAccessor(buffer: buffer)
    }

    /// Number of characters in buffer
    var index: UInt8 {
        UInt8(min(buffer.count, Int(UInt8.max)))
    }

    /// Get key code at index
    func chr(_ idx: Int) -> UInt16 {
        buffer.keyCode(at: idx)
    }

    // MARK: - Engine State

    var tempDisableKey = false
    var spaceCount = 0
    var hasHandledMacro = false
    var upperCaseStatus: UInt8 = 0
    var specialChar = [UInt32]()
    var useSpellCheckingBefore = false
    var hasHandleQuickConsonant = false
    var willTempOffEngine = false

    /// Flag to track when cursor was moved by mouse click or arrow keys
    /// When true, restore logic is skipped because engine doesn't have full context
    /// of the word being edited (user may be editing middle of an existing word)
    var cursorMovedSinceReset = false

    /// Flag to track when focus change occurred during typing session
    /// This can happen when suggestion popups appear, causing keystrokes to go to popup
    /// instead of target input, causing buffer desync. When true, restore is skipped
    /// at word break/backspace to avoid incorrect output.
    var focusChangedDuringTyping = false

    /// Flag to track when buffer-screen desync was detected
    /// When true, spelling check and restore are disabled until new session starts.
    /// This prevents incorrect restore when engine doesn't have full context (e.g., user
    /// clicked mid-word and continued typing, or backspaced across word boundary).
    var bufferDesyncDetected = false

    
    // MARK: - Logging

    /// Logging callback

    // MARK: - Hook State (result to send back)
    
    struct HookState {
        var code: UInt8 = 0           // 0: DoNothing, 1: Process, 2: WordBreak, 3: Restore, 4: ReplaceMacro
        var backspaceCount: Int = 0   // Changed from UInt8 to Int to support longer macros
        var newCharCount: Int = 0     // Changed from UInt8 to Int to support longer macros
        var extCode: UInt8 = 0        // 1: WordBreak, 2: Delete, 3: Normal, 4: ShouldNotSendEmpty, 5: InstantRestore
        var charData = [UInt32](repeating: 0, count: MAX_BUFF)
        var macroKey = [UInt32]()
    }
    
    var hookState = HookState()
    
    // Hook codes - internal for extension access
    let vDoNothing = 0
    let vWillProcess = 1
    let vRestore = 3
    let vReplaceMacro = 4
    let vRestoreAndStartNewSession = 5
    
    // MARK: - Vietnamese Data Tables
    
    let vietnameseData: VietnameseData
    
    // MARK: - Initialization
    
    init() {
        vietnameseData = VietnameseData()
        useSpellCheckingBefore = (vCheckSpelling == 1)
    }
    
    // MARK: - Main Entry Point
    
    /// Main entry point for processing key events
    /// - Parameters:
    ///   - keyCode: The key code
    ///   - character: The character
    ///   - isUppercase: Whether Shift or CapsLock is active
    ///   - hasOtherModifier: Whether Ctrl/Cmd/Option is pressed
    /// - Returns: HookState with processing result
    func handleKeyEvent(keyCode: UInt16, character: Character, isUppercase: Bool, hasOtherModifier: Bool) -> HookState {
        // Debug: Log Space key
        if keyCode == VietnameseData.KEY_SPACE {
        }
        
        // Save macroKey before reset (it accumulates across key events)
        let savedMacroKey = hookState.macroKey
        
        // Reset hook state
        hookState = HookState()
        
        // Restore macroKey
        hookState.macroKey = savedMacroKey
        
        let isCaps = isUppercase

        // Adaptive input method: choose the effective input type for THIS keystroke
        // (boundary translation). Digits route to VNI logic; every other key routes
        // to Telex. Telex/VNI trigger keys are disjoint, so each keystroke maps to
        // exactly one method. Downstream code keeps reading a concrete vInputType
        // (0/1) and never sees the adaptive sentinel (4).
        if vAdaptiveEnabled {
            vInputType = vietnameseData.isNumberKey(keyCode) ? 1 : 0
        }

        // Check if number key with shift or has other modifier
        if (vietnameseData.isNumberKey(keyCode) && isUppercase) || hasOtherModifier || isWordBreak(keyCode: keyCode) {
            handleWordBreak(keyCode: keyCode, character: character, isCaps: isCaps)
            return hookState
        }
        
        // NOTE: Space is handled by processWordBreak() which is called directly by handlers
        
        // Handle delete/backspace
        if keyCode == VietnameseData.KEY_DELETE {
            handleDelete()
            return hookState
        }
        
        // Handle normal key
        handleNormalKey(keyCode: keyCode, character: character, isCaps: isCaps)
        
        return hookState
    }
    
    // MARK: - Word Break Handling
    
    private func isWordBreak(keyCode: UInt16) -> Bool {
        return vietnameseData.breakCode.contains(keyCode)
    }
    
    private func isMacroBreakCode(keyCode: UInt16) -> Bool {
        return vietnameseData.macroBreakCode.contains(keyCode)
    }

    private func isMacroBreakCode(keyCode: UInt16, isCaps: Bool) -> Bool {
        // Check if it's in the standard macro break code list
        if vietnameseData.macroBreakCode.contains(keyCode) {
            return true
        }

        // Special case: number keys with Shift produce special characters (@, !, #, etc.)
        // and should also trigger macro replacement
        if isCaps && vietnameseData.isNumberKey(keyCode) {
            return true
        }

        return false
    }

    private func handleWordBreak(keyCode: UInt16, character: Character, isCaps: Bool) {
        hookState.code = UInt8(vDoNothing)
        hookState.backspaceCount = 0
        hookState.newCharCount = 0
        hookState.extCode = 1 // word break

        // For special characters that can be part of a macro (like @, !, #, ~),
        // just add them to macroKey WITHOUT triggering macro replacement.
        // Macro replacement should only happen when user presses SPACE.
        let isCharKeyCode = vietnameseData.charKeyCode.contains(keyCode)
        if false && isMacroBreakCode(keyCode: keyCode, isCaps: isCaps) && !hasHandledMacro {
            if isCharKeyCode {
                // Add character to macroKey for building macros like "you@" or "!bb"
                hookState.macroKey.append(UInt32(keyCode) | (isCaps ? VNEngine.CAPS_MASK : 0))
            }
            // NOTE: Do NOT call findAndReplaceMacro() here
            // Macro replacement only happens on SPACE (in processWordBreak)
        }
        
        // Check quick consonant
        if (vQuickStartConsonant == 1 || vQuickEndConsonant == 1) && !tempDisableKey && isMacroBreakCode(keyCode: keyCode, isCaps: isCaps) {
            checkQuickConsonant()
        }
        
        // Check restore if wrong spelling
        // IMPORTANT: Skip restore if cursor was moved (editing mid-word)
        // Also skip if spelling is temporarily off via toolbar
        if vRestoreIfWrongSpelling == 1 && vTempOffSpelling == 0 && isWordBreak(keyCode: keyCode) && !cursorMovedSinceReset {
            if !tempDisableKey && vCheckSpelling == 1 {
                checkSpelling(forceCheckVowel: true)
            }
            if tempDisableKey {
                checkRestoreIfWrongSpelling(handleCode: vRestoreAndStartNewSession)
            }
        } else if cursorMovedSinceReset && isWordBreak(keyCode: keyCode) {
        }
        
        // Handle special char saving
        if !isCharKeyCode {
            specialChar.removeAll()
            history.clear()
        } else {
            if spaceCount > 0 {
                saveWord(keyCode: VietnameseData.KEY_SPACE, count: spaceCount)
                spaceCount = 0
            } else {
                saveWord()
            }
            specialChar.append(UInt32(keyCode) | (isCaps ? VNEngine.CAPS_MASK : 0))
            hookState.extCode = 3 // normal word
        }
        
        // Handle session management
        // For special characters (charKeyCode), preserve macroKey to allow building macros
        if hookState.code == UInt8(vDoNothing) {
            if isCharKeyCode {
                // Save and restore macroKey around startNewSession
                let savedMacroKey = hookState.macroKey
                startNewSession()
                hookState.macroKey = savedMacroKey
            } else {
                // For non-char word breaks, clear macroKey
                startNewSession()
            }
            vCheckSpelling = useSpellCheckingBefore ? 1 : 0
            willTempOffEngine = false
        } else if hookState.code == UInt8(vReplaceMacro) || hasHandleQuickConsonant {
            buffer.clear()
        }
        
        // IMPORTANT: Reset cursorMovedSinceReset after word break
        // This allows backspace to restore words from history even if user clicked before typing
        // The user has now typed a complete word (saved to history), so backspace should work
        // Same logic as processWordBreak() at the end
        cursorMovedSinceReset = false
        
        // Upper case first char — delegate to updateUpperCaseStatus()
        // which is the single source of truth for status transitions.
        // Use the character parameter directly — it already contains the correct
        // character ("\n" for Enter, "." for period, " " for space, etc.)
        updateUpperCaseStatus(character: character)
    }
    
    
    // MARK: - Delete Handling

    /// Handle delete/backspace key
    private func handleDelete() {


        hookState.code = UInt8(vDoNothing)
        hookState.extCode = 2

        if !specialChar.isEmpty {
            specialChar.removeLast()
            if specialChar.isEmpty {
                // Skip restore if cursor was moved or focus changed (potential desync)
                // This is safer than trying to verify via slow AX calls
                if cursorMovedSinceReset || focusChangedDuringTyping {
                    clearWithoutRestore()
                } else {
                    restoreLastTypingState()
                }
            }
        } else if spaceCount > 0 {
            spaceCount -= 1
            if spaceCount == 0 {
                // Skip restore if cursor was moved or focus changed (potential desync)
                // This is safer than trying to verify via slow AX calls
                if cursorMovedSinceReset || focusChangedDuringTyping {
                    clearWithoutRestore()
                } else {
                    restoreLastTypingState()
                }
            }
        } else {
            if !buffer.isEmpty {
                buffer.removeLast()

                // CRITICAL FIX: Reset tempDisableKey when user backspaces
                // This fixes bug where Vietnamese processing is skipped after:
                // 1. User types mark key twice to undo (e.g., "nhầm" + "f" → "nhâmf")
                //    → tempDisableKey = true is set during undo
                // 2. User backspaces to remove the raw key (e.g., "nhâmf" → "nhâm")
                // 3. User types mark key again (e.g., "f")
                //    → Without this fix, tempDisableKey is still true
                //    → Vietnamese processing is skipped, resulting in "nhâmf" instead of "nhầm"
                tempDisableKey = false

                if vCheckSpelling == 1 {
                    checkSpelling()
                }
            }

            if vUseMacro == 1 && !hookState.macroKey.isEmpty {
                hookState.macroKey.removeLast()
            }

            hookState.backspaceCount = 0
            hookState.newCharCount = 0
            hookState.extCode = 2

            if buffer.isEmpty {
                startNewSession()
                specialChar.removeAll()

                // Skip restore if cursor was moved or focus changed (potential desync)
                // This is safer than trying to verify via slow AX calls
                if cursorMovedSinceReset || focusChangedDuringTyping {
                    history.clear()
                    bufferDesyncDetected = true
                } else {
                    // Normal backspace - trust history without AX verify
                    // REASON: AX query has race condition - it may return stale data
                    // because we process backspace event BEFORE OS updates the screen.
                    // When user is backspacing continuously without focus/cursor change,
                    // history is reliable and we should restore directly.
                    restoreLastTypingState()
                }
            } else {
                checkGrammar(deltaBackSpace: 1)
            }
        }
    }

    /// Clear session without restoring from history
    /// Used when desync is detected to prevent incorrect text insertion
    private func clearWithoutRestore() {
        startNewSession()
        history.clear()
        specialChar.removeAll()
        spaceCount = 0
        // Set desync flag to disable spellcheck/restore until new session
        bufferDesyncDetected = true
    }
    

    // MARK: - Normal Key Handling
    
    private func handleNormalKey(keyCode: UInt16, character: Character, isCaps: Bool) {

        if willTempOffEngine {
            hookState.code = UInt8(vDoNothing)
            hookState.extCode = 3
            return
        }

        // Temp off engine via toolbar - just insert key without Vietnamese processing
        if vTempOffEngine == 1 {
            hookState.code = UInt8(vDoNothing)
            hookState.backspaceCount = 0
            hookState.newCharCount = 0
            hookState.extCode = 3
            insertKey(keyCode: keyCode, isCaps: isCaps)
            return
        }

        if spaceCount > 0 {
            // Save macroKey before reset - it may contain special chars like "!" for macro matching
            let savedMacroKey = hookState.macroKey
            
            hookState.backspaceCount = 0
            hookState.newCharCount = 0
            hookState.extCode = 0
            startNewSession()
            saveWord(keyCode: VietnameseData.KEY_SPACE, count: spaceCount)
            spaceCount = 0
            
            // Restore macroKey if it had content (allows macros like "!bb" to work)
            if !savedMacroKey.isEmpty {
                hookState.macroKey = savedMacroKey
            }
        } else if !specialChar.isEmpty {
            saveSpecialChar()
        }

        // NOTE: Removed unconditional insertState() call here.
        // insertState was adding EVERY keystroke as a modifier to the last entry,
        // causing getRawInputString() to return duplicate keystrokes (e.g., "ly" → "lyy").
        // This led to false English pattern detection (e.g., "ltyyyyys" instead of "lys")
        // and prevented Vietnamese typing like "lý".
        // 
        // If modifier tracking is needed for Telex sequences (aa→â, dd→đ, etc.),
        // it should be added in the specific handlers (insertAOE, insertD, handleMarkKey)
        // ONLY when a key actually modifies an existing entry.
        
        let isSpecial = isSpecialKey(keyCode: keyCode)
        
        // Bracket keys [/] are EXPLICIT Vietnamese standalone input (ơ/ư).
        // They should bypass tempDisableKey because:
        // 1. They are different from the key that triggered the undo
        // 2. The user intentionally pressed them for Vietnamese input
        // 3. checkForStandaloneChar already validates the context
        let isBracketStandaloneKey = (keyCode == VietnameseData.KEY_LEFT_BRACKET || keyCode == VietnameseData.KEY_RIGHT_BRACKET)
        
        if !isSpecial || (tempDisableKey && !isBracketStandaloneKey) {
            if vQuickTelex == 1 && isQuickTelexKey(keyCode: keyCode) {
                handleQuickTelex(keyCode: keyCode, isCaps: isCaps)
                return
            } else {
                hookState.code = UInt8(vDoNothing)
                hookState.backspaceCount = 0
                hookState.newCharCount = 0
                hookState.extCode = 3
                insertKey(keyCode: keyCode, isCaps: isCaps)
            }
        } else {
            // Reset tempDisableKey when bracket key passes through
            // This allows subsequent Vietnamese processing to continue
            if tempDisableKey && isBracketStandaloneKey {
                tempDisableKey = false
            }
            hookState.code = UInt8(vDoNothing)
            hookState.extCode = 3
            handleMainKey(keyCode: keyCode, isCaps: isCaps)
        }
        
        // Always check for vowel auto-fix (ưo → ươ)
        // This is important for correct Vietnamese typing
        // Skip if instant restore has occurred (extCode == 5) - word is being discarded
        if !isKeyD(keyCode: keyCode, inputType: vInputType) && hookState.extCode != 5 {
            let deltaBS = hookState.code == UInt8(vDoNothing) ? -1 : 0
            checkVowelAutoFix(deltaBackSpace: deltaBS)
        }
        
        // Check mark position - ALWAYS check when typing end consonant or adding vowel to marked word
        // Vietnamese spelling rule: with end consonant, tone must be on the vowel closest to it
        // Example: "hoạt" - tone on 'a', not 'o'; "hiện" - tone on 'ê', not 'i'
        // Additional rule: when adding vowels after a mark, position may need adjustment
        // Example: "ngò" + "a" → "ngoà" (mark moves from 'o' to 'a')
        // Skip if instant restore has occurred (extCode == 5) - word is being discarded
        if !isKeyD(keyCode: keyCode, inputType: vInputType) && hookState.extCode != 5 {
            // Check if this key is an end consonant
            let isEndConsonant = vietnameseData.isConsonant(keyCode) && index > 1
            
            // Check if this key is a vowel and the word already has a mark
            var isVowelWithExistingMark = false
            if !vietnameseData.isConsonant(keyCode) && index > 1 {
                // Check if any existing vowel has a mark
                for i in 0..<Int(index) - 1 {
                    if (typingWord[i] & VNEngine.MARK_MASK) != 0 {
                        isVowelWithExistingMark = true
                        break
                    }
                }
            }
            
            // Always check mark position when:
            // 1. This is an end consonant (Vietnamese spelling rule), OR
            // 2. This is a vowel added to a word with existing mark (mark position may need adjustment)
            if isEndConsonant || isVowelWithExistingMark {
                // IMPORTANT: Determine deltaBackSpace correctly
                // If checkVowelAutoFix has run (extCode=4), the last character hasn't been
                // sent to screen yet, so we need deltaBackSpace=-1 even if hookState.code != vDoNothing
                let deltaBS: Int
                if hookState.code == UInt8(vDoNothing) {
                    deltaBS = -1
                } else if hookState.extCode == 4 {
                    // checkVowelAutoFix has run, last char not on screen yet
                    deltaBS = -1
                } else {
                    deltaBS = 0
                }
                checkMarkPosition(deltaBackSpace: deltaBS)
            }
        }
        
        // Note: extCode == 5 means instant restore - key is already included in restored keystrokes
        // so we should NOT insert it again. Only insert key for normal restore (undo mark).
        if hookState.code == UInt8(vRestore) && hookState.extCode != 5 {
            insertKey(keyCode: keyCode, isCaps: isCaps)
            // NOTE: We do NOT remove modifier here because raw keystrokes should reflect
            // what user actually typed. E.g., "ass" should have raw keystrokes ["a", "s", "s"]
            // The modifier "s" on entry "á" represents the first "s", and the new entry "s"
            // from insertKey represents the second "s" that triggered restore.
            // The dd undo in insertD is the exception: see the comment there.
        }
        
        // Insert or replace key for macro
        if vUseMacro == 1 {
            if hookState.code == UInt8(vDoNothing) {
                hookState.macroKey.append(UInt32(keyCode) | (isCaps ? VNEngine.CAPS_MASK : 0))
            } else if hookState.code == UInt8(vWillProcess) || hookState.code == UInt8(vRestore) {
                for _ in 0..<hookState.backspaceCount {
                    if !hookState.macroKey.isEmpty {
                        hookState.macroKey.removeLast()
                    }
                }
                let startIdx = Int(index) - hookState.backspaceCount
                for i in startIdx..<(hookState.newCharCount + startIdx) {
                    if i >= 0 && i < Int(index) {
                        hookState.macroKey.append(typingWord[i])
                    }
                }
            }
        }
        
        // Upper case first char
        // Status 1 = after . ? ! (no space yet), 2 = after newline, 3 = after . ? ! + space.
        // When vUpperCaseRequireSpace == 1 (default): only status 2 or 3 capitalize, so
        // "google.com"/"3.14"/"file.txt" stay untouched but "Hello. world" and newlines
        // still capitalize. When 0 (legacy): any status >= 1 capitalizes (cap even with no
        // space after punctuation).
        // Skip in browser address bars — "." is a domain separator, not a sentence end
        // (e.g. "google.com" must not become "google.Com").
        if vUpperCaseFirstChar == 1 {
            let pendingCapitalize = vUpperCaseRequireSpace == 1
                ? (upperCaseStatus == 2 || upperCaseStatus == 3)
                : (upperCaseStatus >= 1)
            if index == 1 && pendingCapitalize {
                upperCaseFirstCharacter()
            }
            upperCaseStatus = 0
        }
        

        
        // Handle bracket keys
        if isBracketKey(keyCode: keyCode) && (isBracketKey(hookState.charData[0]) || vInputType == 2 || vInputType == 3) {
            let effectiveCount = buffer.count - (hookState.code == UInt8(vWillProcess) ? hookState.backspaceCount : 0)
            if effectiveCount > 0 {
                buffer.removeLast()
                saveWord()
            }
            buffer.clear()
            tempDisableKey = false
            hookState.extCode = 3
            specialChar.append(UInt32(keyCode) | (isCaps ? VNEngine.CAPS_MASK : 0))
        }
    }
    
    // MARK: - Main Key Processing
    
    private func handleMainKey(keyCode: UInt16, isCaps: Bool) {
        // Handle Z key - remove mark
        if isKeyZ(keyCode: keyCode, inputType: vInputType) {
            removeMark()
            if !isChanged {
                insertKey(keyCode: keyCode, isCaps: isCaps)
            }
            return
        }
        
        // Handle [ key - standalone ơ
        if keyCode == VietnameseData.KEY_LEFT_BRACKET {
            checkForStandaloneChar(data: keyCode, isCaps: isCaps, keyWillReverse: VietnameseData.KEY_O)
            return
        }
        
        // Handle ] key - standalone ư
        if keyCode == VietnameseData.KEY_RIGHT_BRACKET {
            checkForStandaloneChar(data: keyCode, isCaps: isCaps, keyWillReverse: VietnameseData.KEY_U)
            return
        }
        
        // Handle D key
        if isKeyD(keyCode: keyCode, inputType: vInputType) {
            var isCorrect = false
            var isChanged = false
            var k = Int(index)
            
            for i in 0..<vietnameseData.consonantDTable.count {
                if Int(index) < vietnameseData.consonantDTable[i].count {
                    continue
                }
                isCorrect = true
                k = Int(index)
                
                // Check if matches consonant D pattern
                for j in stride(from: vietnameseData.consonantDTable[i].count - 1, through: 0, by: -1) {
                    let endMask: UInt16 = vQuickEndConsonant == 1 ? 0x4000 : 0
                    if (vietnameseData.consonantDTable[i][j] & ~endMask) != chr(k - 1) {
                        isCorrect = false
                        break
                    }
                    k -= 1
                    if k < 0 {
                        break
                    }
                }
                
                // Allow d after consonant
                if !isCorrect && Int(index) >= 2 && chr(Int(index) - 1) == VietnameseData.KEY_D &&
                   vietnameseData.isConsonant(chr(Int(index) - 2)) {
                    isCorrect = true
                }
                
                if isCorrect {
                    isChanged = true
                    insertD(keyCode: keyCode, isCaps: isCaps)
                    break
                }
            }
            
            if !isChanged {
                insertKey(keyCode: keyCode, isCaps: isCaps)
            }
            return
        }
        
        // ============================================
        // EARLY ENGLISH DETECTION: Skip Vietnamese processing for words that
        // are definitely NOT Vietnamese
        // ============================================
        // Uses comprehensive detection that checks:
        // 1. Start pattern - impossible prefixes like "str", "bl", "gr"
        // 2. End pattern - Vietnamese NEVER ends with 's', 'b', 'd', etc.
        // 3. Middle pattern - impossible consonant clusters like "cr", "br"
        //
        // This excludes valid Vietnamese input sequences like:
        // - "dd" → đ, "cc" → ch, "gg" → gi (Telex/Quick Telex)
        // - "d9" → đ (VNI)
        //
        // Examples caught:
        // - "street" (starts with "str")
        // - "micros" (ends with "s")
        // - "micro" (has "cr" in middle)
        // NOTE: Use getRawInputStringForEnglishDetection() which EXCLUDES overflow entries
        // to avoid false positives after restoreLastTypingState()
        let rawInput = getRawInputStringForEnglishDetection()
        // Adaptive accepts both Telex and VNI in one buffer, so vInputType reflects only
        // the LAST keystroke. Validating the whole raw buffer against that single type would
        // misjudge mixed sequences (e.g. a VNI "d9..." checked against Telex tables). Treat
        // the buffer as English only when it is impossible under BOTH interpretations.
        let isDefinitelyNotVietnamese: Bool
        if vAdaptiveEnabled {
            isDefinitelyNotVietnamese =
                rawInput.isDefinitelyNotVietnameseForRawInput(inputType: 0, customConsonants: customConsonantChars)
                && rawInput.isDefinitelyNotVietnameseForRawInput(inputType: 1, customConsonants: customConsonantChars)
        } else {
            isDefinitelyNotVietnamese =
                rawInput.isDefinitelyNotVietnameseForRawInput(inputType: vInputType, customConsonants: customConsonantChars)
        }
        if isDefinitelyNotVietnamese {
            // ENHANCED LOGGING: Log full context when English pattern is detected
            // This helps debug buffer desync issues

            
            insertKey(keyCode: keyCode, isCaps: isCaps)
            
            // Set tempDisableKey so subsequent keys don't get processed as Vietnamese
            // until word break occurs
            tempDisableKey = true
            return
        }
        
        // Handle mark keys (S, F, R, X, J or 1-5 for VNI)
        if isMarkKey(keyCode: keyCode, inputType: vInputType) {
            handleMarkKey(keyCode: keyCode, isCaps: isCaps)
            return
        }
        
        // Handle vowel keys
        handleVowelKey(keyCode: keyCode, isCaps: isCaps)
    }
    
    private func handleMarkKey(keyCode: UInt16, isCaps: Bool) {
        var isCorrect = false
        var isChanged = false

        
        // Ignore "qu" case - OpenKey: checkCorrectVowel
        if index >= 2 && chr(Int(index) - 1) == VietnameseData.KEY_U && chr(Int(index) - 2) == VietnameseData.KEY_Q {
            insertKey(keyCode: keyCode, isCaps: isCaps)
            return
        }
        
        for (_, charsets) in vietnameseData.vowelForMarkTable {
            for charset in charsets {
                if Int(index) < charset.count {
                    continue
                }
                isCorrect = true
                var k = Int(index)
                
                // Check if matches vowel pattern
                for j in stride(from: charset.count - 1, through: 0, by: -1) {
                    let endMask: UInt16 = vQuickEndConsonant == 1 ? 0x4000 : 0
                    let charsetChar = charset[j] & ~endMask
                    let bufferChar = chr(k - 1)
                    if charsetChar != bufferChar {
                        isCorrect = false
                        break
                    }
                    k -= 1
                    if k < 0 {
                        break
                    }
                }
                
                // Limit mark for end consonant: "C", "T", "P" - OpenKey: checkCorrectVowel
                // Cannot use huyền (F), hỏi (R), ngã (X) with end consonant C, T, K or P
                if isCorrect && charset.count > 1 {
                    let isMarkFRX = (vInputType != 1) ? 
                        (keyCode == VietnameseData.KEY_F || keyCode == VietnameseData.KEY_R || keyCode == VietnameseData.KEY_X) :
                        (keyCode == VietnameseData.KEY_2 || keyCode == VietnameseData.KEY_3 || keyCode == VietnameseData.KEY_4)
                    
                    if isMarkFRX {
                        if charset[1] == VietnameseData.KEY_C || charset[1] == VietnameseData.KEY_T ||
                           charset[1] == VietnameseData.KEY_K || charset[1] == VietnameseData.KEY_P {
                            isCorrect = false
                        } else if charset.count > 2 && charset[2] == VietnameseData.KEY_T {
                            isCorrect = false
                        }
                    }
                }
                
                // Check duplicate consonant - OpenKey: checkCorrectVowel
                // IMPORTANT: Only check if k+1 is within current buffer (k+1 < index)
                // This fixes a bug where stale data in typingWord could cause false positives
                if isCorrect && k >= 0 && k + 1 < Int(index) {
                    if chr(k) == chr(k + 1) {
                        isCorrect = false
                    }
                }
                
                if isCorrect {
                    isChanged = true
                    
                    // Determine which mark to insert based on key
                    var markMask: UInt32 = 0
                    if vInputType != 1 { // Not VNI
                        if keyCode == VietnameseData.KEY_S {
                            markMask = VNEngine.MARK1_MASK
                        } else if keyCode == VietnameseData.KEY_F {
                            markMask = VNEngine.MARK2_MASK
                        } else if keyCode == VietnameseData.KEY_R {
                            markMask = VNEngine.MARK3_MASK
                        } else if keyCode == VietnameseData.KEY_X {
                            markMask = VNEngine.MARK4_MASK
                        } else if keyCode == VietnameseData.KEY_J {
                            markMask = VNEngine.MARK5_MASK
                        }
                    } else { // VNI
                        if keyCode == VietnameseData.KEY_1 {
                            markMask = VNEngine.MARK1_MASK
                        } else if keyCode == VietnameseData.KEY_2 {
                            markMask = VNEngine.MARK2_MASK
                        } else if keyCode == VietnameseData.KEY_3 {
                            markMask = VNEngine.MARK3_MASK
                        } else if keyCode == VietnameseData.KEY_4 {
                            markMask = VNEngine.MARK4_MASK
                        } else if keyCode == VietnameseData.KEY_5 {
                            markMask = VNEngine.MARK5_MASK
                        }
                    }
                    
                    // Save state before attempting mark insertion
                    // typingWord is backed by TypingBuffer (reference type), so save processedData manually
                    let savedHookState = hookState
                    var savedProcessedData: [Int: UInt32] = [:]
                    for i in 0..<Int(index) {
                        savedProcessedData[i] = typingWord[i]
                    }
                    
                    insertMarkInternal(markMask: markMask, canModifyFlag: true, deltaBackSpace: 0)
                    
                    // Check 1: insertMarkInternal returned vDoNothing (e.g., vowelCount=0 with
                    // multi-char consonant like "ng" — no valid vowel target for the mark).
                    // Restore state and let the key be inserted as a regular character.
                    if hookState.code == UInt8(vDoNothing) {
                        hookState = savedHookState
                        for (i, data) in savedProcessedData {
                            typingWord[i] = data
                        }
                        isChanged = false
                        break
                    }
                    
                    // Check 2: getCharacterCode validation — if the mark landed on a consonant
                    // that has no entry in the code table, restore state (safety net)
                    if hookState.code != UInt8(vRestore) {
                        let markedCharCode = getCharacterCode(typingWord[vowelWillSetMark])
                        let hasMarkOnChar = (typingWord[vowelWillSetMark] & VNEngine.MARK_MASK) != 0
                        if hasMarkOnChar && (markedCharCode & VNEngine.CHAR_CODE_MASK) == 0 {
                            hookState = savedHookState
                            for (i, data) in savedProcessedData {
                                typingWord[i] = data
                            }
                            hookState.code = UInt8(vDoNothing)
                            isChanged = false
                            break
                        }
                    }
                    
                    // Track modifier keystroke for restore functionality
                    // Only add if not a restore operation (duplicate mark key)
                    // Add to the ACTUAL modified vowel (vowelWillSetMark), not the last entry
                    if hookState.code != UInt8(vRestore) {
                        insertStateAt(index: vowelWillSetMark, keyCode: keyCode, isCaps: isCaps)
                    }
                    break
                }
            }
            
            if isCorrect {
                break
            }
        }
        
        if !isChanged {
            
            // VNI fallback: For keys 1-5, if pattern didn't match but we have vowels,
            // try to apply tone anyway.
            if vInputType == 1 && (keyCode == VietnameseData.KEY_1 || keyCode == VietnameseData.KEY_2 ||
                                   keyCode == VietnameseData.KEY_3 || keyCode == VietnameseData.KEY_4 ||
                                   keyCode == VietnameseData.KEY_5) {
                findAndCalculateVowel()
                
                if vowelCount > 0 {
                    
                    // Determine which mark to insert
                    var markMask: UInt32 = 0
                    switch keyCode {
                    case VietnameseData.KEY_1: markMask = VNEngine.MARK1_MASK  // Sắc
                    case VietnameseData.KEY_2: markMask = VNEngine.MARK2_MASK  // Huyền
                    case VietnameseData.KEY_3: markMask = VNEngine.MARK3_MASK  // Hỏi
                    case VietnameseData.KEY_4: markMask = VNEngine.MARK4_MASK  // Ngã
                    case VietnameseData.KEY_5: markMask = VNEngine.MARK5_MASK  // Nặng
                    default: break
                    }
                    
                    if markMask != 0 {
                        insertMarkInternal(markMask: markMask, canModifyFlag: true, deltaBackSpace: 0)
                        
                        // Track modifier keystroke for restore functionality
                        // Add to the ACTUAL modified vowel (vowelWillSetMark), not the last entry
                        if hookState.code != UInt8(vRestore) {
                            insertStateAt(index: vowelWillSetMark, keyCode: keyCode, isCaps: isCaps)
                        }
                        return
                    }
                }
            }
            
            insertKey(keyCode: keyCode, isCaps: isCaps)
        }
    }
    
    private func handleVowelKey(keyCode: UInt16, isCaps: Bool) {

        
        // Ignore "qu" case - OpenKey: checkCorrectVowel
        // NOTE: Must exclude standalone ư (from w→ư conversion). When user types "q+w",
        // chr() returns KEY_U from processedData, but it's standalone ư, not plain u.
        // Without this check, "qww" fails because engine treats "qư" as "qu" and
        // skips the standalone undo path.
        if index >= 2 && chr(Int(index) - 1) == VietnameseData.KEY_U && chr(Int(index) - 2) == VietnameseData.KEY_Q
            && (typingWord[Int(index) - 1] & VNEngine.STANDALONE_MASK) == 0 {
            insertKey(keyCode: keyCode, isCaps: isCaps)
            return
        }
        
        // Handle VNI: for keys 6, 7, 8 find the correct vowel to modify circumflex/horn
        // VEI = -1 means no valid vowel (a, e, o) was found
        var VEI = -1
        if vInputType == 1 { // VNI
            for i in stride(from: Int(index) - 1, through: 0, by: -1) {
                let key = chr(i)
                if key == VietnameseData.KEY_O || key == VietnameseData.KEY_A || key == VietnameseData.KEY_E {
                    VEI = i
                    break
                }
            }
        }

        let keyForAEO: UInt16
        if vInputType != 1 {
            keyForAEO = keyCode
        } else {
            if keyCode == VietnameseData.KEY_7 || keyCode == VietnameseData.KEY_8 {
                keyForAEO = VietnameseData.KEY_W
            } else if keyCode == VietnameseData.KEY_6 {
                // For VNI key 6: apply circumflex to found vowel (a->â, e->ê, o->ô)
                // If no vowel found (VEI == -1), keyForAEO will be 0 and won't match any pattern
                keyForAEO = VEI >= 0 ? chr(VEI) : 0
            } else {
                keyForAEO = keyCode
            }
        }
        
        
        guard let charsets = vietnameseData.vowelTable[keyForAEO] else {
            if keyCode == VietnameseData.KEY_W && vInputType != 2 {
                checkForStandaloneChar(data: keyCode, isCaps: isCaps, keyWillReverse: VietnameseData.KEY_U)
            } else {
                insertKey(keyCode: keyCode, isCaps: isCaps)
            }
            return
        }
        
        var isCorrect = false
        var isChanged = false

        for charset in charsets {
            if Int(index) < charset.count {
                continue
            }
            isCorrect = true
            var k = Int(index)
            
            // Check if matches vowel pattern
            for j in stride(from: charset.count - 1, through: 0, by: -1) {
                let endMask: UInt16 = vQuickEndConsonant == 1 ? 0x4000 : 0
                if (charset[j] & ~endMask) != chr(k - 1) {
                    isCorrect = false
                    break
                }
                k -= 1
                if k < 0 {
                    break
                }
            }
            
            // NOTE: Duplicate consonant check is NOT applied for vowel keys (A, O, E, W)
            // It's only for mark keys (S, F, R, X, J) - see handleMarkKey
            
            if isCorrect {
                isChanged = true
                
                // Check if it's double letter (A, O, E) or W
                // For VNI: key 6 adds circumflex (^) to a, e, o -> â, ê, ô
                // We check keyCode (original key pressed) for VNI, not keyForAEO (which is already converted to vowel)
                let isKeyDouble = (vInputType != 1 && (keyForAEO == VietnameseData.KEY_A ||
                                                       keyForAEO == VietnameseData.KEY_O ||
                                                       keyForAEO == VietnameseData.KEY_E)) ||
                                 (vInputType == 1 && keyCode == VietnameseData.KEY_6)
                
                let isKeyW = isKeyW(keyCode: keyCode, inputType: vInputType)
                
                if isKeyDouble {
                    insertAOE(keyCode: keyForAEO, isCaps: isCaps)
                } else if isKeyW {
                    // VNI special validation for key 7 and key 8:
                    // Key 7: horn (móc) for 'o' → 'ơ' and 'u' → 'ư'  
                    // Key 8: breve (trăng) only for 'a' → 'ă'
                    var shouldProcess = true
                    if vInputType == 1 {
                        // First, find the vowel range in the word (like Telex does)
                        findAndCalculateVowel()
                        
                        if keyCode == VietnameseData.KEY_7 {
                            // Key 7: horn (móc) - search for ANY 'o' or 'u' in the VOWEL group
                            // This matches Telex behavior where insertW() handles vowel combinations
                            // like "ua" → "ưa", "uo" → "ươ" intelligently
                            var hasValidVowel = false
                            if vowelCount > 0 {
                                for i in vowelStartIndex...vowelEndIndex {
                                    let key = chr(i)
                                    if key == VietnameseData.KEY_O || key == VietnameseData.KEY_U {
                                        hasValidVowel = true
                                        break
                                    }
                                }
                            }
                            shouldProcess = hasValidVowel
                        } else if keyCode == VietnameseData.KEY_8 {
                            // Key 8: breve (trăng) only for 'a' → 'ă'
                            // Search for 'a' in the VOWEL group
                            var hasValidVowel = false
                            if vowelCount > 0 {
                                for i in vowelStartIndex...vowelEndIndex {
                                    let key = chr(i)
                                    if key == VietnameseData.KEY_A {
                                        hasValidVowel = true
                                        break
                                    }
                                }
                            }
                            shouldProcess = hasValidVowel
                        }
                    }
                    if shouldProcess {
                        insertW(keyCode: keyForAEO, isCaps: isCaps)
                    } else {
                        // Not a valid VNI combination - will be handled in the outer "if !isChanged" block
                        isChanged = false
                    }
                }
                break
            }
        }
        
        if !isChanged {
            
            // VNI fallback: For key 7/8, if pattern didn't match but we have valid vowels,
            // try to apply horn/breve anyway (free-mark style like Telex)
            if vInputType == 1 && (keyCode == VietnameseData.KEY_7 || keyCode == VietnameseData.KEY_8) {
                findAndCalculateVowel()
                var hasValidVowel = false
                
                if vowelCount > 0 {
                    for i in vowelStartIndex...vowelEndIndex {
                        let key = chr(i)
                        if keyCode == VietnameseData.KEY_7 {
                            // Key 7: horn - need 'o' or 'u'
                            if key == VietnameseData.KEY_O || key == VietnameseData.KEY_U {
                                hasValidVowel = true
                                break
                            }
                        } else if keyCode == VietnameseData.KEY_8 {
                            // Key 8: breve - need 'a'
                            if key == VietnameseData.KEY_A {
                                hasValidVowel = true
                                break
                            }
                        }
                    }
                }
                
                if hasValidVowel {
                    insertW(keyCode: VietnameseData.KEY_W, isCaps: isCaps)
                    return
                }
            }
            
            if keyCode == VietnameseData.KEY_W && vInputType != 2 {
                checkForStandaloneChar(data: keyCode, isCaps: isCaps, keyWillReverse: VietnameseData.KEY_U)
            } else {
                insertKey(keyCode: keyCode, isCaps: isCaps)
            }
        } else {
        }
    }
    
    // MARK: - Key Checking Functions
    
    private func isSpecialKey(keyCode: UInt16) -> Bool {
        if vInputType == 0 { // Telex
            return keyCode == VietnameseData.KEY_W || keyCode == VietnameseData.KEY_E ||
                   keyCode == VietnameseData.KEY_R || keyCode == VietnameseData.KEY_O ||
                   keyCode == VietnameseData.KEY_LEFT_BRACKET || keyCode == VietnameseData.KEY_RIGHT_BRACKET ||
                   keyCode == VietnameseData.KEY_A || keyCode == VietnameseData.KEY_S ||
                   keyCode == VietnameseData.KEY_D || keyCode == VietnameseData.KEY_F ||
                   keyCode == VietnameseData.KEY_J || keyCode == VietnameseData.KEY_Z ||
                   keyCode == VietnameseData.KEY_X
        } else if vInputType == 1 { // VNI
            return keyCode == VietnameseData.KEY_1 || keyCode == VietnameseData.KEY_2 ||
                   keyCode == VietnameseData.KEY_3 || keyCode == VietnameseData.KEY_4 ||
                   keyCode == VietnameseData.KEY_5 || keyCode == VietnameseData.KEY_6 ||
                   keyCode == VietnameseData.KEY_7 || keyCode == VietnameseData.KEY_8 ||
                   keyCode == VietnameseData.KEY_9 || keyCode == VietnameseData.KEY_0
        } else if vInputType == 2 || vInputType == 3 { // Simple Telex 1 & 2
            // Same as Telex but WITHOUT bracket keys [ and ]
            return keyCode == VietnameseData.KEY_W || keyCode == VietnameseData.KEY_E ||
                   keyCode == VietnameseData.KEY_R || keyCode == VietnameseData.KEY_O ||
                   keyCode == VietnameseData.KEY_A || keyCode == VietnameseData.KEY_S ||
                   keyCode == VietnameseData.KEY_D || keyCode == VietnameseData.KEY_F ||
                   keyCode == VietnameseData.KEY_J || keyCode == VietnameseData.KEY_Z ||
                   keyCode == VietnameseData.KEY_X
        }
        return false
    }
    
    private func isQuickTelexKey(keyCode: UInt16) -> Bool {
        if index <= 0 {
            return false
        }
        let prevKey = UInt16(typingWord[Int(index) - 1] & VNEngine.CHAR_MASK)
        
        // Quick Telex only applies when:
        // 1. Current key is one of C, G, K, N, Q, P, T
        // 2. Previous key is the same (double letter)
        // 3. The double letter is at the beginning of the word (index == 1)
        //    This prevents "app" from becoming "aph"
        //    Quick Telex is meant for quickly typing consonant clusters at word start:
        //    pp → ph, cc → ch, gg → gi, nn → ng, kk → kh, qq → qu, tt → th
        let isQuickTelexChar = (keyCode == VietnameseData.KEY_C || keyCode == VietnameseData.KEY_G ||
                                keyCode == VietnameseData.KEY_K || keyCode == VietnameseData.KEY_N ||
                                keyCode == VietnameseData.KEY_Q || keyCode == VietnameseData.KEY_P ||
                                keyCode == VietnameseData.KEY_T)
        
        // Only apply at word start to avoid bugs like "app" → "aph"
        return isQuickTelexChar && prevKey == keyCode && index == 1
    }
    
    private func isKeyZ(keyCode: UInt16, inputType: Int) -> Bool {
        return vietnameseData.processingChar[inputType][10] == keyCode
    }
    
    private func isKeyD(keyCode: UInt16, inputType: Int) -> Bool {
        return vietnameseData.processingChar[inputType][9] == keyCode
    }
    
    private func isKeyW(keyCode: UInt16, inputType: Int) -> Bool {
        if inputType != 1 {
            return vietnameseData.processingChar[inputType][8] == keyCode
        } else {
            return vietnameseData.processingChar[inputType][8] == keyCode ||
                   vietnameseData.processingChar[inputType][7] == keyCode
        }
    }
    
    private func isMarkKey(keyCode: UInt16, inputType: Int) -> Bool {
        if inputType != 1 { // Not VNI
            return keyCode == VietnameseData.KEY_S || keyCode == VietnameseData.KEY_F ||
                   keyCode == VietnameseData.KEY_R || keyCode == VietnameseData.KEY_J ||
                   keyCode == VietnameseData.KEY_X
        } else { // VNI
            return keyCode == VietnameseData.KEY_1 || keyCode == VietnameseData.KEY_2 ||
                   keyCode == VietnameseData.KEY_3 || keyCode == VietnameseData.KEY_5 ||
                   keyCode == VietnameseData.KEY_4
        }
    }
    
    private func isBracketKey(keyCode: UInt16) -> Bool {
        return keyCode == VietnameseData.KEY_LEFT_BRACKET || keyCode == VietnameseData.KEY_RIGHT_BRACKET
    }
    
    private func isBracketKey(_ data: UInt32) -> Bool {
        let keyCode = UInt16(data & VNEngine.CHAR_MASK)
        return isBracketKey(keyCode: keyCode)
    }
    
    // MARK: - Insert Functions

    /// Insert a new character into the buffer
    func insertKey(keyCode: UInt16, isCaps: Bool, isCheckSpelling: Bool = true) {


        buffer.append(keyCode: keyCode, isCaps: isCaps)
        
        // Record keystroke in actual typing order (for restore at word break)
        buffer.recordKeystroke(RawKeystroke(keyCode: keyCode, isCaps: isCaps))


        if vCheckSpelling == 1 && isCheckSpelling {
            checkSpelling()
        }

        // Allow d after consonant
        if keyCode == VietnameseData.KEY_D && buffer.count >= 2 {
            let prevKey = buffer.keyCode(at: buffer.count - 2)
            if vietnameseData.isConsonant(prevKey) {
                tempDisableKey = false
            }
        }
    }

    /// Record a raw keystroke as modifier (for Telex sequences like aa→â).
    /// Adds to the LAST entry in buffer and records the *stamped* keystroke into
    /// `keystrokeSequence` so the sequence can be correlated back to its entry by id.
    func insertState(keyCode: UInt16, isCaps: Bool) {
        let stamped = buffer.addModifierToLast(RawKeystroke(keyCode: keyCode, isCaps: isCaps))
        buffer.recordKeystroke(stamped)
    }

    /// Record a raw keystroke as modifier at a specific buffer index.
    /// Use this when the modified entry is NOT the last one (e.g., mark on first vowel
    /// of "ưa"). Records the stamped keystroke so removal by `entryId` works even
    /// though `recordKeystroke`'s auto-stamping would otherwise pin this to the last
    /// entry, not entries[index].
    func insertStateAt(index: Int, keyCode: UInt16, isCaps: Bool) {
        let stamped = buffer.addModifier(at: index, keystroke: RawKeystroke(keyCode: keyCode, isCaps: isCaps))
        buffer.recordKeystroke(stamped)
    }

    
    private var isChanged = false
    
    private func insertD(keyCode: UInt16, isCaps: Bool) {
        hookState.code = UInt8(vWillProcess)
        hookState.backspaceCount = 0
        
        for i in stride(from: Int(index) - 1, through: 0, by: -1) {
            hookState.backspaceCount += 1
            if chr(i) == VietnameseData.KEY_D {
                // Reverse unicode char
                if (typingWord[i] & VNEngine.TONE_MASK) != 0 {
                    // Restore and disable temporary
                    hookState.code = UInt8(vRestore)
                    typingWord[i] &= ~VNEngine.TONE_MASK
                    // Use getCharacterCode to convert to proper character (not raw key code)
                    hookState.charData[Int(index) - 1 - i] = getCharacterCode(typingWord[i])
                    // Drop the 'd' that made 'đ': the screen is back to "dd" and the key
                    // that undid it is recorded as its own entry by the vRestore branch of
                    // processKey. Keeping the modifier too would make restore-on-wrong-spelling
                    // replay "dddos" for "ddó" instead of "ddos".
                    buffer.removeModifier(at: i, keyCode: keyCode)
                    tempDisableKey = true
                    break
                } else {
                    typingWord[i] |= VNEngine.TONE_MASK
                    hookState.charData[Int(index) - 1 - i] = getCharacterCode(typingWord[i])
                    
                    // Track modifier keystroke for restore functionality (dd→đ)
                    // Add to the ACTUAL modified 'D' (index i), not the last entry
                    insertStateAt(index: i, keyCode: keyCode, isCaps: isCaps)
                }
                break
            } else {
                // Present old char
                hookState.charData[Int(index) - 1 - i] = getCharacterCode(typingWord[i])
            }
        }
        hookState.newCharCount = hookState.backspaceCount
    }
    
    private func insertAOE(keyCode: UInt16, isCaps: Bool) {
        findAndCalculateVowel()


        // Whether the vowel that will receive the circumflex currently carries a horn/breve.
        // Stripping horn from the whole cluster is only correct when we are breaking a horn
        // diphthong, i.e. the circumflex target itself is horned (e.g. "cươi" + "o" → "cuôi").
        // When the target is a plain vowel sitting next to a horned vowel (e.g. "ưa" + "a"),
        // the neighbour's horn must be preserved; otherwise "ừa" → "uầ" silently drops the horn.
        var circumflexTargetHasHorn = false
        if vowelCount >= 1 {
            for i in stride(from: vowelEndIndex, through: vowelStartIndex, by: -1) {
                if chr(i) == keyCode {
                    circumflexTargetHasHorn = (typingWord[i] & VNEngine.TONEW_MASK) != 0
                    break
                }
            }
        }

        // Check if vowel sequence is valid before adding circumflex
        // Invalid sequences like "ee", "eee", "aa", "aaa" should NOT get circumflex added
        // This prevents "nhée" + "e" from becoming "nhéê" (should stay as "nhéee")
        if vowelCount >= 2 {
            let vowelSequence = getCurrentVowelSequence()
            if !VowelSequenceValidator.isValid(vowelSequence) {
                insertKey(keyCode: keyCode, isCaps: isCaps)
                return
            }
            
            // POST-TRANSFORM VALIDATION: Simulate adding circumflex to the target vowel
            // and check if the resulting vowel sequence would be valid.
            // Example: "caot" + "o" → target is 'o' at index 2 in vowel group [a, o]
            //   After transform: [a, ô] → NOT valid Vietnamese → fallback to insertKey
            // Example: "to" + "o" → target is 'o' at index 1 in vowel group [o] (single)
            //   → skip this check (only applies to multi-vowel groups)
            // Example: "tho" + "o" → single vowel, becomes "thô" → valid
            // Find which vowel in the group would receive the circumflex
            for i in stride(from: vowelEndIndex, through: vowelStartIndex, by: -1) {
                if chr(i) == keyCode {
                    // This vowel would get circumflex - simulate post-transform sequence
                    var predictedSequence: [VNVowel] = []
                    for j in vowelStartIndex...vowelEndIndex {
                        if j == i {
                            // Apply circumflex to this vowel
                            switch keyCode {
                            case VietnameseData.KEY_A: predictedSequence.append(.aCircumflex)
                            case VietnameseData.KEY_E: predictedSequence.append(.eCircumflex)
                            case VietnameseData.KEY_O: predictedSequence.append(.oCircumflex)
                            default: break
                            }
                        } else if let vowel = convertToVNVowel(at: j) {
                            // Mirror insertAOE: horn is only stripped from neighbours when the
                            // circumflex target is itself horned (breaking a horn diphthong).
                            // For a plain target (e.g. "ưa" + "a") the neighbour keeps its horn,
                            // so the prediction must too — making "ưâ" correctly fail validation
                            // and fall back to inserting the literal vowel instead of "uâ".
                            if circumflexTargetHasHorn {
                                switch vowel {
                                case .oHorn: predictedSequence.append(.o)
                                case .uHorn: predictedSequence.append(.u)
                                case .aBreve: predictedSequence.append(.a)
                                default: predictedSequence.append(vowel)
                                }
                            } else {
                                predictedSequence.append(vowel)
                            }
                        }
                    }
                    
                    if !predictedSequence.isEmpty && !VowelSequenceValidator.isValid(predictedSequence) {
                        insertKey(keyCode: keyCode, isCaps: isCaps)
                        return
                    }
                    break
                }
            }
        }

        // Track which vowels had TONEW_MASK removed (e.g., ư → u, ơ → o)
        // This is needed to update the output for ALL affected vowels, not just the one getting ^
        // Example: "cươi" + "o" → need to update both ư→u AND ơ→ô
        var earliestAffectedIndex = Int(index)  // Start with no affected vowels

        // Remove W tone from all vowels and track the earliest affected vowel.
        // Only when breaking a horn diphthong (circumflex target itself horned). A plain
        // circumflex target must not strip a neighbour's horn (e.g. "ưa" + "a" keeps ư).
        if circumflexTargetHasHorn {
            for i in vowelStartIndex...vowelEndIndex {
                if (typingWord[i] & VNEngine.TONEW_MASK) != 0 {
                    typingWord[i] &= ~VNEngine.TONEW_MASK
                    if i < earliestAffectedIndex {
                        earliestAffectedIndex = i
                    }
                }
            }
        }
        
        hookState.code = UInt8(vWillProcess)

        hookState.backspaceCount = 0
        
        // Check if we need to move mark from previous vowel to this one
        // This handles case: h-i-e-j-e → hịe → hiệ (mark moves from i to ê)
        var shouldMoveMark = false
        var markToMove: UInt32 = 0
        var markSourceIndex = -1
        
        // Track the index where we found the target vowel (a, o, or e)
        var targetVowelIndex = -1
        
        for i in stride(from: Int(index) - 1, through: 0, by: -1) {
            hookState.backspaceCount += 1
            if chr(i) == keyCode {
                targetVowelIndex = i
                
                // Reverse unicode char
                if (typingWord[i] & VNEngine.TONE_MASK) != 0 {
                    // Restore and disable temporary
                    hookState.code = UInt8(vRestore)
                    typingWord[i] &= ~VNEngine.TONE_MASK
                    // Use getCharacterCode to convert to proper character (not raw key code)
                    hookState.charData[Int(index) - 1 - i] = getCharacterCode(typingWord[i])
                    if keyCode != VietnameseData.KEY_O { // Case thoòng
                        tempDisableKey = true
                    }
                    break
                } else {
                    typingWord[i] |= VNEngine.TONE_MASK
                    if keyCode != VietnameseData.KEY_D {
                        typingWord[i] &= ~VNEngine.TONEW_MASK
                    }
                    
                    // Check if previous vowel has a mark that should move to this vowel
                    // For "iê", "yê" patterns: mark should be on ê, not on i/y
                    if keyCode == VietnameseData.KEY_E && i > 0 {
                        let prevKey = chr(i - 1)
                        if (prevKey == VietnameseData.KEY_I || prevKey == VietnameseData.KEY_Y) &&
                           (typingWord[i - 1] & VNEngine.MARK_MASK) != 0 {
                            // Move mark from i/y to ê
                            markToMove = typingWord[i - 1] & VNEngine.MARK_MASK
                            markSourceIndex = i - 1
                            shouldMoveMark = true
                        }
                    }
                    // For "uô" pattern: mark should be on ô, not on u
                    if keyCode == VietnameseData.KEY_O && i > 0 {
                        let prevKey = chr(i - 1)
                        if prevKey == VietnameseData.KEY_U &&
                           (typingWord[i - 1] & VNEngine.MARK_MASK) != 0 {
                            // Move mark from u to ô
                            markToMove = typingWord[i - 1] & VNEngine.MARK_MASK
                            markSourceIndex = i - 1
                            shouldMoveMark = true
                        }
                    }
                    
                    // Apply mark movement
                    if shouldMoveMark {
                        typingWord[markSourceIndex] &= ~VNEngine.MARK_MASK  // Remove mark from source
                        typingWord[i] |= markToMove  // Add mark to destination (ê/ô)
                        // Need to update backspace count to include the source vowel
                        hookState.backspaceCount = Int(index) - markSourceIndex
                    }
                    
                    hookState.charData[Int(index) - 1 - i] = getCharacterCode(typingWord[i])
                    
                    // Track modifier keystroke for restore functionality (aa→â, oo→ô, ee→ê)
                    // Add to the ACTUAL modified vowel (index i), not the last entry
                    insertStateAt(index: i, keyCode: keyCode, isCaps: isCaps)
                }
                break
            } else {
                // Present old char
                hookState.charData[Int(index) - 1 - i] = getCharacterCode(typingWord[i])
            }
        }
        
        // If mark was moved, we need to regenerate charData for all affected vowels
        if shouldMoveMark && markSourceIndex >= 0 {
            let startIdx = markSourceIndex
            hookState.backspaceCount = Int(index) - startIdx
            for i in startIdx..<Int(index) {
                hookState.charData[Int(index) - 1 - i] = getCharacterCode(typingWord[i])
            }
        }
        
        // FIX: If TONEW_MASK was removed from vowels BEFORE the target vowel,
        // we need to extend backspaceCount and regenerate charData for those vowels too.
        // Example: "cươi" + "o" → target is ơ (index 2), but ư (index 1) also needs update
        // Without this fix, we would output "cưôi" instead of "cuôi"
        if earliestAffectedIndex < targetVowelIndex && targetVowelIndex >= 0 {
            let startIdx = earliestAffectedIndex
            hookState.backspaceCount = Int(index) - startIdx
            hookState.newCharCount = hookState.backspaceCount
            for i in startIdx..<Int(index) {
                hookState.charData[Int(index) - 1 - i] = getCharacterCode(typingWord[i])
            }
            return  // Early return since we've already set newCharCount
        }
        
        hookState.newCharCount = hookState.backspaceCount
    }
    
    private func insertW(keyCode: UInt16, isCaps: Bool) {
        // Note: W restoration is tracked by hookState.code (vRestore/vWillProcess) and tempDisableKey
        
        findAndCalculateVowel()
        
        // Remove ^ tone from all vowels
        for i in vowelStartIndex...vowelEndIndex {
            typingWord[i] &= ~VNEngine.TONE_MASK
        }
        
        if vowelCount > 1 {
            hookState.backspaceCount = Int(index) - vowelStartIndex
            hookState.newCharCount = hookState.backspaceCount
            
            let v1HasToneW = (typingWord[vowelStartIndex] & VNEngine.TONEW_MASK) != 0
            let v2HasToneW = (typingWord[vowelStartIndex + 1] & VNEngine.TONEW_MASK) != 0
            let v1Key = chr(vowelStartIndex)
            let v2Key = chr(vowelStartIndex + 1)
            
            if (v1HasToneW && v2HasToneW) ||
               (v1HasToneW && v2Key == VietnameseData.KEY_I) ||
               (v1HasToneW && v2Key == VietnameseData.KEY_A) ||
               (v2HasToneW && v1Key == VietnameseData.KEY_I) ||  // iơ -> io + w
               (v2HasToneW && v1Key == VietnameseData.KEY_O && v2Key == VietnameseData.KEY_A) ||  // oă -> oa + w
               (v2HasToneW && v1Key == VietnameseData.KEY_U && v2Key == VietnameseData.KEY_O) {  // uơ -> uo + w (for "thuơ" case)
                // Restore and disable temporary
                hookState.code = UInt8(vRestore)
                
                for i in vowelStartIndex..<Int(index) {
                    typingWord[i] &= ~VNEngine.TONEW_MASK
                    hookState.charData[Int(index) - 1 - i] = getCharacterCode(typingWord[i]) & ~VNEngine.STANDALONE_MASK
                }
                // W was restored (tracked by hookState.code = vRestore above)
                tempDisableKey = true
            } else {
                hookState.code = UInt8(vWillProcess)

                
                // Apply W tone based on vowel combination
                if v1Key == VietnameseData.KEY_U && v2Key == VietnameseData.KEY_O {
                    // Special case: thuơn
                    if vowelStartIndex >= 2 && chr(vowelStartIndex - 2) == VietnameseData.KEY_T &&
                       chr(vowelStartIndex - 1) == VietnameseData.KEY_H {
                        typingWord[vowelStartIndex + 1] |= VNEngine.TONEW_MASK
                        if vowelStartIndex + 2 < Int(index) && chr(vowelStartIndex + 2) == VietnameseData.KEY_N {
                            typingWord[vowelStartIndex] |= VNEngine.TONEW_MASK
                        }
                    } else if vowelStartIndex >= 1 && chr(vowelStartIndex - 1) == VietnameseData.KEY_Q {
                        typingWord[vowelStartIndex + 1] |= VNEngine.TONEW_MASK
                    } else {
                        typingWord[vowelStartIndex] |= VNEngine.TONEW_MASK
                        typingWord[vowelStartIndex + 1] |= VNEngine.TONEW_MASK
                    }
                } else if (v1Key == VietnameseData.KEY_U && v2Key == VietnameseData.KEY_A) ||
                          (v1Key == VietnameseData.KEY_U && v2Key == VietnameseData.KEY_I) ||
                          (v1Key == VietnameseData.KEY_U && v2Key == VietnameseData.KEY_U) ||
                          (v1Key == VietnameseData.KEY_O && v2Key == VietnameseData.KEY_I) {
                    typingWord[vowelStartIndex] |= VNEngine.TONEW_MASK
                } else if (v1Key == VietnameseData.KEY_I && v2Key == VietnameseData.KEY_O) ||
                          (v1Key == VietnameseData.KEY_O && v2Key == VietnameseData.KEY_A) {
                    typingWord[vowelStartIndex + 1] |= VNEngine.TONEW_MASK
                } else {
                    // Don't do anything
                    tempDisableKey = true
                    isChanged = false
                    hookState.code = UInt8(vDoNothing)
                }
                
                for i in vowelStartIndex..<Int(index) {
                    hookState.charData[Int(index) - 1 - i] = getCharacterCode(typingWord[i])
                }
                
                // Track modifier keystroke for restore functionality (w→ư/ơ for multi-vowel)
                // Add to the FIRST modified vowel (vowelStartIndex), not the last entry
                if hookState.code != UInt8(vDoNothing) {
                    insertStateAt(index: vowelStartIndex, keyCode: keyCode, isCaps: isCaps)
                }
            }
            
            return
        }
        
        // Single vowel case
        hookState.code = UInt8(vWillProcess)

        hookState.backspaceCount = 0
        
        for i in stride(from: Int(index) - 1, through: 0, by: -1) {
            if i < vowelStartIndex {
                break
            }
            hookState.backspaceCount += 1
            
            let key = chr(i)
            if key == VietnameseData.KEY_A || key == VietnameseData.KEY_U || key == VietnameseData.KEY_O {
                if (typingWord[i] & VNEngine.TONEW_MASK) != 0 {
                    // Restore and disable temporary
                    if (typingWord[i] & VNEngine.STANDALONE_MASK) != 0 {
                        hookState.code = UInt8(vWillProcess)
                        if key == VietnameseData.KEY_U {
                            typingWord[i] = UInt32(VietnameseData.KEY_W) | ((typingWord[i] & VNEngine.CAPS_MASK) != 0 ? VNEngine.CAPS_MASK : 0)
                            // When undoing standalone "ư" → "w", remove the modifier from the ACTUAL entry (index i)
                            // W was restored
                            buffer.removeLastModifier(at: i)
                        } else if key == VietnameseData.KEY_O {
                            hookState.code = UInt8(vRestore)
                            typingWord[i] = UInt32(VietnameseData.KEY_O) | ((typingWord[i] & VNEngine.CAPS_MASK) != 0 ? VNEngine.CAPS_MASK : 0)
                            // W was restored
                        }
                        hookState.charData[Int(index) - 1 - i] = typingWord[i]
                    } else {
                        hookState.code = UInt8(vRestore)
                        typingWord[i] &= ~VNEngine.TONEW_MASK
                        hookState.charData[Int(index) - 1 - i] = typingWord[i]
                        // W was restored
                    }
                    
                    tempDisableKey = true
                } else {
                    typingWord[i] |= VNEngine.TONEW_MASK
                    typingWord[i] &= ~VNEngine.TONE_MASK
                    hookState.charData[Int(index) - 1 - i] = getCharacterCode(typingWord[i])
                    
                    // Track modifier keystroke for restore functionality (w→ư/ơ/ă for single vowel)
                    // Add to the ACTUAL modified vowel (index i), not the last entry
                    insertStateAt(index: i, keyCode: keyCode, isCaps: isCaps)
                }
                break
            } else {
                hookState.charData[Int(index) - 1 - i] = getCharacterCode(typingWord[i])
            }
        }
        hookState.newCharCount = hookState.backspaceCount
    }
    
    private func removeMark() {
        findAndCalculateVowel(forGrammar: true)
        isChanged = false
        
        // A word such as "qu" has its `u` excluded from the vowel span above.
        // That can leave an empty span (start > end); never form a closed range
        // for that case because Swift traps before the engine can treat `z` as
        // a no-op.
        if index > 0 && vowelCount > 0 && vowelStartIndex <= vowelEndIndex {
            for i in vowelStartIndex...vowelEndIndex {
                if typingWord[i] & VNEngine.MARK_MASK != 0 {
                    typingWord[i] &= ~VNEngine.MARK_MASK
                    isChanged = true
                }
            }
        }
        
        if isChanged {
            hookState.code = UInt8(vWillProcess)
            hookState.backspaceCount = 0
            
            for i in stride(from: Int(index) - 1, through: vowelStartIndex, by: -1) {
                hookState.backspaceCount += 1
                hookState.charData[Int(index) - 1 - i] = getCharacterCode(typingWord[i])
            }
            hookState.newCharCount = hookState.backspaceCount
        } else {
            hookState.code = UInt8(vDoNothing)
        }
    }
    
    // MARK: - Vowel Processing
    
    private var vowelCount: UInt8 = 0
    private var vowelStartIndex = 0
    private var vowelEndIndex = 0
    private var vowelWillSetMark = 0
    
    private func findAndCalculateVowel(forGrammar: Bool = false) {
        vowelCount = 0
        vowelStartIndex = 0
        vowelEndIndex = 0
        
        for i in stride(from: Int(index) - 1, through: 0, by: -1) {
            let keyCode = UInt16(typingWord[i] & VNEngine.CHAR_MASK)
            if vietnameseData.isConsonant(keyCode) {
                if vowelCount > 0 {
                    break
                }
            } else {
                if vowelCount == 0 {
                    vowelEndIndex = i
                }
                if !forGrammar {
                    // Check gi, qu
                    if i >= 1 {
                        let prevKey = UInt16(typingWord[i - 1] & VNEngine.CHAR_MASK)
                        if (keyCode == VietnameseData.KEY_I && prevKey == VietnameseData.KEY_G) ||
                           (keyCode == VietnameseData.KEY_U && prevKey == VietnameseData.KEY_Q) {
                            break
                        }
                    }
                }
                vowelStartIndex = i
                vowelCount += 1
            }
        }
        
        // Don't count 'u' at 'qu' as vowel
        if vowelStartIndex >= 1 {
            let keyCode = UInt16(typingWord[vowelStartIndex] & VNEngine.CHAR_MASK)
            let prevKey = UInt16(typingWord[vowelStartIndex - 1] & VNEngine.CHAR_MASK)
            if keyCode == VietnameseData.KEY_U && prevKey == VietnameseData.KEY_Q {
                vowelStartIndex += 1
                vowelCount -= 1
            }
        }
    }

    /// Convert typingWord data at given index to VNVowel
    /// Returns nil if the character is not a vowel or cannot be converted
    private func convertToVNVowel(at index: Int) -> VNVowel? {
        let data = typingWord[index]
        let keyCode = UInt16(data & VNEngine.CHAR_MASK)
        let hasTone = (data & VNEngine.TONE_MASK) != 0      // circumflex (^)
        let hasToneW = (data & VNEngine.TONEW_MASK) != 0    // horn (ơ, ư) or breve (ă)

        switch keyCode {
        case VietnameseData.KEY_A:
            if hasTone { return .aCircumflex }      // â
            if hasToneW { return .aBreve }          // ă
            return .a
        case VietnameseData.KEY_E:
            if hasTone { return .eCircumflex }      // ê
            return .e
        case VietnameseData.KEY_I:
            return .i
        case VietnameseData.KEY_O:
            if hasTone { return .oCircumflex }      // ô
            if hasToneW { return .oHorn }           // ơ
            return .o
        case VietnameseData.KEY_U:
            if hasToneW { return .uHorn }           // ư
            return .u
        case VietnameseData.KEY_Y:
            return .y
        default:
            return nil
        }
    }

    /// Get vowel sequence from current vowelStartIndex to vowelEndIndex
    /// Returns array of VNVowel or empty array if conversion fails
    private func getCurrentVowelSequence() -> [VNVowel] {
        guard vowelCount > 0, vowelStartIndex <= vowelEndIndex else {
            return []
        }

        var vowels: [VNVowel] = []
        for i in vowelStartIndex...vowelEndIndex {
            if let vowel = convertToVNVowel(at: i) {
                vowels.append(vowel)
            }
        }
        return vowels
    }

    // MARK: - Spelling Check
    
    private var spellingOK = false
    private var spellingVowelOK = false
    private var spellingEndIndex: UInt8 = 0
    
    /// Check spelling using phonetic rules (like OpenKey's checkSpelling)
    /// This verifies the word structure matches valid Vietnamese patterns:
    /// 1. First consonant must match consonantTable
    /// 2. After vowel, consonant must match endConsonantTable
    ///
    /// If phonetic check fails, tempDisableKey = true, preventing diacritics
    /// This is how OpenKey handles "micros" - "cr" is not in endConsonantTable
    func checkSpelling(forceCheckVowel: Bool = false) {
        // Defensive check: Respect vCheckSpelling setting
        guard vCheckSpelling == 1 else {
            // When spell check is disabled, don't modify spelling state
            return
        }
        
        // Temporary off spelling via toolbar - skip spell check
        if vTempOffSpelling == 1 {
            tempDisableKey = false
            return
        }
        
        
        // Reset spelling state
        spellingOK = false
        spellingVowelOK = true
        spellingEndIndex = index
        
        // Skip if empty word
        guard index > 0 else {
            tempDisableKey = false
            return
        }
        
        // Handle ] key at end (standalone key)
        if index > 0 && chr(Int(index) - 1) == VietnameseData.KEY_RIGHT_BRACKET {
            spellingEndIndex = index - 1
        }
        
        guard spellingEndIndex > 0 else {
            spellingOK = true
            tempDisableKey = false
            return
        }
        
        var j = 0
        
        // ============================================
        // Check first consonant (with consonantTable)
        // ============================================
        if vietnameseData.isConsonant(chr(0)) {
            var foundMatch = false
            
            for consonantPattern in vietnameseData.consonantTable {
                // Check if word starts with this consonant pattern
                if Int(spellingEndIndex) < consonantPattern.count {
                    continue  // Word too short for this pattern
                }
                
                var matches = true
                for (idx, patternKey) in consonantPattern.enumerated() {
                    let actualKey = chr(idx)
                    // Handle CONSONANT_ALLOW_MASK and END_CONSONANT_MASK
                    // For CONSONANT_ALLOW_MASK: only unmask if this specific consonant is in customConsonants
                    // For END_CONSONANT_MASK: unmask when quick start consonant is enabled
                    let baseKeyForAllowCheck = patternKey & ~(VietnameseData.CONSONANT_ALLOW_MASK | VietnameseData.END_CONSONANT_MASK)
                    let shouldUnmaskAllow = (patternKey & VietnameseData.CONSONANT_ALLOW_MASK) != 0 && vCustomConsonants.contains(baseKeyForAllowCheck)
                    let patternKeyMasked = patternKey & ~(
                        (shouldUnmaskAllow ? VietnameseData.CONSONANT_ALLOW_MASK : 0) |
                        (vQuickStartConsonant == 1 ? VietnameseData.END_CONSONANT_MASK : 0)
                    )
                    
                    if Int(spellingEndIndex) > idx && patternKeyMasked != actualKey {
                        matches = false
                        break
                    }
                    j = idx + 1
                }
                
                if matches {
                    foundMatch = true
                    break
                }
            }
            
            if !foundMatch && index > 0 {
                // If first consonant doesn't match any pattern, mark as invalid
                tempDisableKey = true
                return
            }
        }
        
        // If first char is the whole consonant part (like "d")
        if j == Int(spellingEndIndex) {
            spellingOK = true
        }
        
        // ============================================
        // Check vowel position
        // ============================================
        var k = j
        var vowelStartIdx = k
        
        // Special case: "que't" - u after q is not counted as vowel
        if chr(vowelStartIdx) == VietnameseData.KEY_U &&
           k > 0 && k < Int(spellingEndIndex) - 1 &&
           chr(vowelStartIdx - 1) == VietnameseData.KEY_Q {
            k += 1
            j = k
            vowelStartIdx = k
        }
        // Special case: "gìn" - i after g at start
        else if index >= 2 &&
                chr(0) == VietnameseData.KEY_G &&
                chr(1) == VietnameseData.KEY_I &&
                index >= 3 && vietnameseData.isConsonant(chr(2)) {
            vowelStartIdx = 1
            k = 1
            j = 1
        }
        
        // Count vowels (up to 3)
        for _ in 0..<3 {
            if k < Int(spellingEndIndex) && !vietnameseData.isConsonant(chr(k)) {
                k += 1
            }
        }
        // vowelEndIdx is now at position k
        
        // ============================================
        // Check for repeated identical vowels (≥ 3)
        // e.g. "ooo", "aaa" are not valid Vietnamese
        // Uses raw keystroke sequence instead of buffer entries,
        // because Telex transforms merge entries (e.g. o-o→ô,
        // then 3rd o undoes → oo = only 2 entries for 3 keystrokes)
        // ============================================
        let rawKeystrokes = buffer.getKeystrokeSequence()
        if rawKeystrokes.count >= 3 {
            // Find max run of identical vowel keystrokes
            var maxRun = 1
            var currentRun = 1
            for ri in 1..<rawKeystrokes.count {
                let prevKey = rawKeystrokes[ri - 1].keyCode
                let curKey = rawKeystrokes[ri].keyCode
                if curKey == prevKey && !vietnameseData.isConsonant(curKey) {
                    currentRun += 1
                    if currentRun > maxRun { maxRun = currentRun }
                } else {
                    currentRun = 1
                }
            }
            if maxRun >= 3 {
                spellingOK = false
                spellingVowelOK = false
                tempDisableKey = true
                return
            }
        }
        
        // ============================================
        // Check end consonant (with endConsonantTable)
        // ============================================
        if k > j {
            // Has vowel, now check end consonant
            spellingVowelOK = false
            
            // Check vowel combination if forceCheckVowel
            if k - j > 1 && forceCheckVowel {
                // Complex vowel check (similar to OpenKey's vowel combine check)
                // For now, we assume vowel is OK
                spellingVowelOK = true
            } else if !vietnameseData.isConsonant(chr(j)) {
                spellingVowelOK = true
            }
            
            // Continue check last consonant
            for endPattern in vietnameseData.endConsonantTable {
                var matches = true
                
                for (patternIdx, patternKey) in endPattern.enumerated() {
                    let patternKeyMasked = patternKey & ~(vQuickEndConsonant == 1 ? VietnameseData.END_CONSONANT_MASK : 0)
                    
                    if Int(spellingEndIndex) > k + patternIdx {
                        if patternKeyMasked != chr(k + patternIdx) {
                            matches = false
                            break
                        }
                    }
                }
                
                if !matches {
                    continue
                }
                
                // Check if pattern covers rest of word
                if k + endPattern.count >= Int(spellingEndIndex) {
                    spellingOK = true
                    break
                }
            }
            
            // If there are remaining characters after vowel that don't match any end consonant
            // This is the key check that catches "micros" - "cr" is not in endConsonantTable!
            if !spellingOK && k < Int(spellingEndIndex) {
                // Has characters after vowel that don't match end consonant patterns
                spellingOK = false
            }
            
            // Limit: stop end consonants "ch", "t", "k" cannot use with "~", "`", "?"
            // (stop finals only take sắc/nặng). "k" is the ethnic-minority final
            // (Đắk, Lắk) — same restriction as the standard stop finals.
            if spellingOK {
                if index >= 3 &&
                   chr(Int(index) - 1) == VietnameseData.KEY_H &&
                   chr(Int(index) - 2) == VietnameseData.KEY_C {
                    // Check if vowel before "ch" has invalid mark
                    let vowelData = typingWord[Int(index) - 3]
                    let hasMark1 = (vowelData & VNEngine.MARK1_MASK) != 0
                    let hasMark5 = (vowelData & VNEngine.MARK5_MASK) != 0
                    let hasAnyMark = (vowelData & VNEngine.MARK_MASK) != 0
                    if !hasMark1 && !hasMark5 && hasAnyMark {
                        spellingOK = false
                    }
                } else if index >= 2 &&
                          (chr(Int(index) - 1) == VietnameseData.KEY_T ||
                           chr(Int(index) - 1) == VietnameseData.KEY_K ||
                           chr(Int(index) - 1) == VietnameseData.KEY_C ||
                           chr(Int(index) - 1) == VietnameseData.KEY_P) {
                    let vowelData = typingWord[Int(index) - 2]
                    let hasMark1 = (vowelData & VNEngine.MARK1_MASK) != 0
                    let hasMark5 = (vowelData & VNEngine.MARK5_MASK) != 0
                    let hasAnyMark = (vowelData & VNEngine.MARK_MASK) != 0
                    if !hasMark1 && !hasMark5 && hasAnyMark {
                        spellingOK = false
                    }
                }
            }

            // Ethnic-minority final 'k' (Đắk/Lắk/Búk) only pairs with a plain or
            // breve (ă) vowel, never a circumflex (â/ê/ô). A circumflex vowel
            // before 'k' means a foreign word (cowork→cổk, network→netwổk) → reject
            // so it stays literal / is handled by English detection.
            if spellingOK && index >= 2 && chr(Int(index) - 1) == VietnameseData.KEY_K {
                let vowelData = typingWord[Int(index) - 2]
                if (vowelData & VNEngine.TONE_MASK) != 0 {
                    spellingOK = false
                }
            }
        } else {
            // No vowel yet, only consonant - OK
            spellingOK = true
        }
        
        // Final decision
        tempDisableKey = !(spellingOK && spellingVowelOK)
    }

    // MARK: - Grammar Check

    /// Check and auto-fix vowel combinations like "ưo" → "ươ"
    /// This always runs to ensure correct vowel patterns
    private func checkVowelAutoFix(deltaBackSpace: Int) {

        if index <= 1 || index >= VNEngine.MAX_BUFF {
            return
        }

        findAndCalculateVowel(forGrammar: true)
        
        if vowelCount == 0 {
            return
        }
        
        var isFixed = false
        
        // Check for "thuơn", "ưoi", "ưom", "ưoc" cases - auto-fix "ưo" → "ươ"
        if index >= 3 {
            for i in stride(from: Int(index) - 1, through: 0, by: -1) {
                let key = chr(i)
                if key == VietnameseData.KEY_N || key == VietnameseData.KEY_C ||
                   key == VietnameseData.KEY_I || key == VietnameseData.KEY_M ||
                   key == VietnameseData.KEY_P || key == VietnameseData.KEY_T {
                    if i >= 2 && chr(i - 1) == VietnameseData.KEY_O && chr(i - 2) == VietnameseData.KEY_U {
                        let hasToneW1 = (typingWord[i - 1] & VNEngine.TONEW_MASK) != 0
                        let hasToneW2 = (typingWord[i - 2] & VNEngine.TONEW_MASK) != 0
                        if hasToneW1 != hasToneW2 {
                            typingWord[i - 2] |= VNEngine.TONEW_MASK
                            typingWord[i - 1] |= VNEngine.TONEW_MASK
                            isFixed = true
                            break
                        }
                    }
                }
            }
        }
        
        // Re-arrange data to send back
        if isFixed {
            if hookState.code == UInt8(vDoNothing) {
                hookState.code = UInt8(vWillProcess)
            }
            hookState.backspaceCount = 0
            
            for i in stride(from: Int(index) - 1, through: vowelStartIndex, by: -1) {
                hookState.backspaceCount += 1
                hookState.charData[Int(index) - 1 - i] = getCharacterCode(typingWord[i])
            }
            hookState.newCharCount = hookState.backspaceCount
            
            
            // IMPORTANT: deltaBackSpace handling
            // When deltaBackSpace = -1, it means the last character hasn't been sent to screen yet
            // In this case, we need to delete one less character from the screen
            // Example: Screen has "thuở" (4 chars), we want to send "ưởn" (3 chars)
            // - backspaceCount = 3 (for u, ở, n in buffer)
            // - But 'n' hasn't been sent yet, so screen only has "thuở"
            // - We need to delete "uở" (2 chars) from screen, not 3
            // - So: backspaceCount = 3 + (-1) = 2 ✓
            //
            // When deltaBackSpace = 0, the last character has been sent
            // - backspaceCount already correct, no adjustment needed
            if deltaBackSpace == -1 {
                // Last char not on screen yet, delete one less
                hookState.backspaceCount = hookState.backspaceCount + deltaBackSpace
            }
            // If deltaBackSpace = 0, don't adjust (last char already on screen)
            
            
            hookState.extCode = 4
        }
    }
    
    /// Check and auto-adjust mark position
    /// Ensures tone marks are on the correct vowel according to Vietnamese spelling rules
    private func checkMarkPosition(deltaBackSpace: Int) {
        
        if index <= 1 || index >= VNEngine.MAX_BUFF {
            return
        }
        
        findAndCalculateVowel(forGrammar: true)
        
        if vowelCount == 0 {
            return
        }

        // Check if vowel sequence is valid before attempting to move mark
        // Invalid sequences like "ee", "eee", "aa", "aaa" should NOT cause mark movement
        // This prevents the issue where typing "nheseee" incorrectly becomes "nheế"
        // instead of "nhéee" (mark should stay on first 'e')
        if vowelCount >= 2 {
            let vowelSequence = getCurrentVowelSequence()
            if !VowelSequenceValidator.isValid(vowelSequence) {
                return
            }
        }

        var isAdjusted = false
        
        // IMPORTANT: Save vowelStartIndex before calling insertMarkInternal
        // insertMarkInternal calls findAndCalculateVowel() internally which may
        // return different results (e.g., for "gi" case where forGrammar affects results)
        // We need the original vowelStartIndex for the final loop that sends charData
        let savedVowelStartIndex = vowelStartIndex
        
        // Check mark position
        if index >= 2 {
            // IMPORTANT: Save current hookState before calling insertMarkInternal
            // If mark position doesn't need adjustment (isAdjusted=false), we should
            // preserve the hookState calculated by checkVowelAutoFix
            let savedBackspaceCount = hookState.backspaceCount
            let savedNewCharCount = hookState.newCharCount
            let savedCode = hookState.code
            
            for i in vowelStartIndex...vowelEndIndex {
                if typingWord[i] & VNEngine.MARK_MASK != 0 {
                    let mark = typingWord[i] & VNEngine.MARK_MASK
                    typingWord[i] &= ~VNEngine.MARK_MASK
                    insertMarkInternal(markMask: mark, canModifyFlag: false, deltaBackSpace: deltaBackSpace)
                    if i != vowelWillSetMark {
                        isAdjusted = true
                    } else {
                        // Mark position is correct, restore saved hookState
                        // This prevents insertMarkInternal from overwriting the correct
                        // backspaceCount calculated by checkVowelAutoFix
                        hookState.backspaceCount = savedBackspaceCount
                        hookState.newCharCount = savedNewCharCount
                        hookState.code = savedCode
                    }
                    break
                }
            }
        }
        
        // Re-arrange data to send back
        // IMPORTANT: Use savedVowelStartIndex here because insertMarkInternal may have
        // changed vowelStartIndex (it calls findAndCalculateVowel with forGrammar: false
        // which treats "gi" differently). For "gisup" -> "giúp", we need to include
        // the "i" in "gi" when sending charData to remove the mark that was on it.
        if isAdjusted {
            if hookState.code == UInt8(vDoNothing) {
                hookState.code = UInt8(vWillProcess)
            }
            hookState.backspaceCount = 0
            
            for i in stride(from: Int(index) - 1, through: savedVowelStartIndex, by: -1) {
                hookState.backspaceCount += 1
                hookState.charData[Int(index) - 1 - i] = getCharacterCode(typingWord[i])
            }
            hookState.newCharCount = hookState.backspaceCount
            hookState.backspaceCount = hookState.backspaceCount + deltaBackSpace
            hookState.extCode = 4
        }
    }
    
    /// Legacy function - calls both checkVowelAutoFix and checkMarkPosition
    private func checkGrammar(deltaBackSpace: Int) {
        checkVowelAutoFix(deltaBackSpace: deltaBackSpace)
        // When deleting a character (deltaBackSpace > 0), check mark position
        // because deleting an ending consonant changes the "terminated" status
        // of the vowel sequence, which affects where the tone mark should be placed.
        // Example: "bưãn" (mark on 'a') -> delete 'n' -> "bữa" (mark should move to 'ư')
        if deltaBackSpace > 0 {
            checkMarkPosition(deltaBackSpace: deltaBackSpace)
        }
    }
    
    private func insertMarkInternal(markMask: UInt32, canModifyFlag: Bool, deltaBackSpace: Int) {
        
        vowelCount = 0
        
        if canModifyFlag {
            hookState.code = UInt8(vWillProcess)

        }
        hookState.backspaceCount = 0
        hookState.newCharCount = 0
        
        findAndCalculateVowel()
        vowelWillSetMark = 0
        
        // IMPORTANT: Auto-fix "ưo" → "ươ" case (OpenKey checkGrammar logic)
        // If we have "uo" pattern where one has TONEW_MASK but the other doesn't,
        // add TONEW_MASK to both to make "ươ"
        // BUT: Only apply this when there's an ending consonant (like "thương", "người")
        // Do NOT apply to words without ending consonant (like "thuở")
        if vowelCount >= 2 {
            let v1Key = chr(vowelStartIndex)
            let v2Key = chr(vowelStartIndex + 1)
            let v1HasToneW = (typingWord[vowelStartIndex] & VNEngine.TONEW_MASK) != 0
            let v2HasToneW = (typingWord[vowelStartIndex + 1] & VNEngine.TONEW_MASK) != 0
            
            // Check for "uo" pattern with mismatched TONEW_MASK
            if v1Key == VietnameseData.KEY_U && v2Key == VietnameseData.KEY_O {
                if v1HasToneW != v2HasToneW {
                    // Check if there's an ending consonant after the vowel pair
                    var hasEndConsonant = false
                    if vowelEndIndex + 1 < Int(index) {
                        let nextKey = chr(vowelEndIndex + 1)
                        // Check for common ending consonants: n, c, i, m, p, t
                        if nextKey == VietnameseData.KEY_N || nextKey == VietnameseData.KEY_C ||
                           nextKey == VietnameseData.KEY_I || nextKey == VietnameseData.KEY_M ||
                           nextKey == VietnameseData.KEY_P || nextKey == VietnameseData.KEY_T {
                            hasEndConsonant = true
                        }
                    }
                    
                    // Only auto-fix if there's an ending consonant
                    if hasEndConsonant {
                        // Add TONEW_MASK to both to make "ươ"
                        typingWord[vowelStartIndex] |= VNEngine.TONEW_MASK
                        typingWord[vowelStartIndex + 1] |= VNEngine.TONEW_MASK
                    } else {
                    }
                }
            }
        }
        
        
        // Detect mark position
        if vowelCount == 1 {
            vowelWillSetMark = vowelEndIndex
            hookState.backspaceCount = Int(index) - vowelEndIndex
        } else if vowelCount == 0 && vowelEndIndex > 1 {
            // No valid vowel found, AND the detected 'i' is deep inside the word
            // (vowelEndIndex > 1 means 'i' is preceded by a multi-char consonant like "ng").
            //
            // This catches cases like "ngin" where findAndCalculateVowel treats "gi" as a
            // consonant cluster (vowelCount=0), but the real initial consonant is "ng", not "gi".
            // Applying a mark here would produce invalid words like "ngĩn".
            //
            // When vowelEndIndex <= 1, we ALLOW the mark — this preserves valid words like
            // "gì" (g+i+f) and "gìn" (g+i+n+f) where "gi" IS the initial consonant and
            // handleOldMark's special case correctly places the mark on 'i'.
            //
            // NOTE: We use vowelEndIndex (not vowelStartIndex) because findAndCalculateVowel
            // sets vowelEndIndex BEFORE the "gi" break, but vowelStartIndex is never reached.
            hookState.code = UInt8(vDoNothing)
            return
        } else {
            if vUseModernOrthography == 0 {
                handleOldMark()
            } else {
                handleModernMark()
            }
            
            // Check if last vowel has circumflex (^) or horn (ư/ơ)
            let veiHasTone = (typingWord[vowelEndIndex] & VNEngine.TONE_MASK) != 0
            let veiHasToneW = (typingWord[vowelEndIndex] & VNEngine.TONEW_MASK) != 0
            
            if veiHasTone || veiHasToneW {
                vowelWillSetMark = vowelEndIndex
            }
        }
        
        // Send data
        let kk = Int(index) - 1 - vowelStartIndex
        
        // If duplicate same mark -> restore
        if (typingWord[vowelWillSetMark] & markMask) != 0 {
            typingWord[vowelWillSetMark] &= ~VNEngine.MARK_MASK
            if canModifyFlag {
                hookState.code = UInt8(vRestore)
            }
            var kkVar = kk
            for i in vowelStartIndex..<Int(index) {
                typingWord[i] &= ~VNEngine.MARK_MASK
                hookState.charData[kkVar] = getCharacterCode(typingWord[i])
                kkVar -= 1
            }
            // IMPORTANT: Set backspaceCount correctly for restore case
            // This matches OpenKey behavior where backspaceCount is set from handleModernMark/handleOldMark
            // but we need to ensure it matches the actual charData we're sending
            hookState.backspaceCount = Int(index) - vowelStartIndex
            tempDisableKey = true
        } else {
            // Remove other mark
            typingWord[vowelWillSetMark] &= ~VNEngine.MARK_MASK
            
            // Add mark
            typingWord[vowelWillSetMark] |= markMask
            
            var kkVar = kk
            for i in vowelStartIndex..<Int(index) {
                if i != vowelWillSetMark {
                    typingWord[i] &= ~VNEngine.MARK_MASK
                }
                let charCode = getCharacterCode(typingWord[i])
                hookState.charData[kkVar] = charCode
                kkVar -= 1
            }
            
            hookState.backspaceCount = Int(index) - vowelStartIndex
            // Apply deltaBackSpace adjustment if last char not on screen yet
            if deltaBackSpace == -1 {
                hookState.backspaceCount += deltaBackSpace
            }
        }
        hookState.newCharCount = hookState.backspaceCount

        // VKey: dictionary-backed instant restore omitted (no external services).

    }
    
    // MARK: - Mark Position Rules (Modern Orthography)
    
    private func handleModernMark() {
        // Default
        vowelWillSetMark = vowelEndIndex
        hookState.backspaceCount = Int(index) - vowelEndIndex
        
        // Rule 2: Triple vowel combinations
        // For ALL triple vowel sequences in Vietnamese (oai, oay, oeo, uya, uyu, uây, iêu, ươi, etc.),
        // tone mark ALWAYS goes on the middle vowel (index 1).
        // This matches Vietnamese phonetic rules and VowelSequenceValidator.calculateTonePosition behavior.
        // Rule 3.1 below may further refine for circumflex/horn patterns (iê, yê, uô, ươ).
        if vowelCount == 3 {
            vowelWillSetMark = vowelStartIndex + 1
            hookState.backspaceCount = Int(index) - vowelWillSetMark
        } else if vowelCount == 2 {
            let v1 = chr(vowelStartIndex)
            let v2 = chr(vowelStartIndex + 1)
            
            // oi, ai, ui -> mark on first vowel
            if (v1 == VietnameseData.KEY_O && v2 == VietnameseData.KEY_I) ||
               (v1 == VietnameseData.KEY_A && v2 == VietnameseData.KEY_I) ||
               (v1 == VietnameseData.KEY_U && v2 == VietnameseData.KEY_I) {
                vowelWillSetMark = vowelStartIndex
                hookState.backspaceCount = Int(index) - vowelWillSetMark
            }
            // ay -> mark on 'a'
            else if v1 == VietnameseData.KEY_A && v2 == VietnameseData.KEY_Y {
                vowelWillSetMark = vowelStartIndex
                hookState.backspaceCount = Int(index) - vowelWillSetMark
            }
            // NOTE: "oa", "oe" cases are handled by the general rule below:
            // "If 1st vowel is 'o' or 'u' -> mark on last vowel"
            // This matches OpenKey behavior where "khoa" + r = "khoả" (mark on 'a')
            // The old XKey code incorrectly checked for end consonant, but OpenKey doesn't do that.
            // uo -> mark on 'o'
            else if v1 == VietnameseData.KEY_U && v2 == VietnameseData.KEY_O {
                vowelWillSetMark = vowelStartIndex + 1
                hookState.backspaceCount = Int(index) - vowelWillSetMark
            }
            // uy -> mark on 'y' (modern orthography: tuý, quý, thuý)
            else if v1 == VietnameseData.KEY_U && v2 == VietnameseData.KEY_Y {
                vowelWillSetMark = vowelStartIndex + 1  // Đặt dấu vào 'y' cho kiểu hiện đại
                hookState.backspaceCount = Int(index) - vowelWillSetMark
            }
            // If 2nd vowel is 'o' or 'u' -> mark on 1st vowel
            else if v2 == VietnameseData.KEY_O || v2 == VietnameseData.KEY_U {
                vowelWillSetMark = vowelEndIndex - 1
                hookState.backspaceCount = Int(index) - vowelWillSetMark + 1
            }
            // If 1st vowel is 'o' or 'u' -> mark on last vowel
            else if v1 == VietnameseData.KEY_O || v1 == VietnameseData.KEY_U {
                vowelWillSetMark = vowelEndIndex
                hookState.backspaceCount = Int(index) - vowelEndIndex
            }
        }
        
        // Rule 3.1: Special combinations with circumflex/horn (iê, yê, uô, ươ)
        // NOTE: This rule applies regardless of vowelCount (2 or 3 vowels)
        // OpenKey: rule 3.1 - checks for iê, yê, uô, ươ patterns
        // Example: "nhiều" (nhieu + f) → dấu huyền đặt vào "ê" không phải "u"
        let rule3v1 = chr(vowelStartIndex)
        let rule3v1Data = typingWord[vowelStartIndex]
        let rule3v2Data = vowelStartIndex + 1 < Int(index) ? typingWord[vowelStartIndex + 1] : UInt32(0)
        let rule3v2 = UInt16(rule3v2Data & VNEngine.CHAR_MASK)
        let rule3v2HasTone = (rule3v2Data & VNEngine.TONE_MASK) != 0
        let rule3v1HasToneW = (rule3v1Data & VNEngine.TONEW_MASK) != 0
        let rule3v2HasToneW = (rule3v2Data & VNEngine.TONEW_MASK) != 0
        
        // Check for: iê, yê, uô, ươ patterns
        // iê: i + ê (e with circumflex)
        let isIE = (rule3v1 == VietnameseData.KEY_I && rule3v2 == VietnameseData.KEY_E && rule3v2HasTone)
        // yê: y + ê
        let isYE = (rule3v1 == VietnameseData.KEY_Y && rule3v2 == VietnameseData.KEY_E && rule3v2HasTone)
        // uô: u + ô (o with circumflex)
        let isUO = (rule3v1 == VietnameseData.KEY_U && rule3v2 == VietnameseData.KEY_O && rule3v2HasTone)
        // ươ: ư + ơ (both with horn)
        let isUwOw = (rule3v1 == VietnameseData.KEY_U && rule3v1HasToneW && rule3v2 == VietnameseData.KEY_O && rule3v2HasToneW)
        
        
        if isIE || isYE || isUO || isUwOw {
            if vowelStartIndex + 2 < Int(index) {
                let nextKey = chr(vowelStartIndex + 2)
                // If followed by certain consonants or vowels, mark goes on 2nd vowel
                if nextKey == VietnameseData.KEY_P || nextKey == VietnameseData.KEY_T ||
                   nextKey == VietnameseData.KEY_M || nextKey == VietnameseData.KEY_N ||
                   nextKey == VietnameseData.KEY_O || nextKey == VietnameseData.KEY_U ||
                   nextKey == VietnameseData.KEY_I || nextKey == VietnameseData.KEY_C {
                    vowelWillSetMark = vowelStartIndex + 1
                    hookState.backspaceCount = Int(index) - vowelWillSetMark
                } else {
                    vowelWillSetMark = vowelStartIndex
                    hookState.backspaceCount = Int(index) - vowelWillSetMark
                }
            } else {
                // No character after the vowel pair, mark on 1st vowel
                vowelWillSetMark = vowelStartIndex
                hookState.backspaceCount = Int(index) - vowelWillSetMark
            }
        }
        // Rule 3.2: ia, ya, ua, ưu patterns - mark on 1st vowel
        // IMPORTANT: Only apply for double vowels (vowelCount != 3).
        // For triple vowels (e.g., "uây", "oay"), the mark should stay on the middle vowel
        // as set by Rule 2 above, NOT be overridden to the 1st vowel.
        else if vowelCount != 3 &&
                ((rule3v1 == VietnameseData.KEY_I && chr(vowelStartIndex + 1) == VietnameseData.KEY_A) ||
                 (rule3v1 == VietnameseData.KEY_Y && chr(vowelStartIndex + 1) == VietnameseData.KEY_A) ||
                 (rule3v1 == VietnameseData.KEY_U && chr(vowelStartIndex + 1) == VietnameseData.KEY_A) ||
                 (rule3v1 == VietnameseData.KEY_U && rule3v2Data == (UInt32(VietnameseData.KEY_U) | VNEngine.TONEW_MASK))) {
            vowelWillSetMark = vowelStartIndex
            hookState.backspaceCount = Int(index) - vowelWillSetMark
        }
        
        // Rule 4: Special cases for 2 vowels
        if vowelCount == 2 {
            let v1 = chr(vowelStartIndex)
            let v2 = chr(vowelStartIndex + 1)
            
            // ia, iu, io
            if v1 == VietnameseData.KEY_I && (v2 == VietnameseData.KEY_A || v2 == VietnameseData.KEY_U || v2 == VietnameseData.KEY_O) {
                // Check if there's 'g' before 'i'
                if vowelStartIndex > 0 && chr(vowelStartIndex - 1) == VietnameseData.KEY_G {
                    vowelWillSetMark = vowelStartIndex + 1
                    hookState.backspaceCount = Int(index) - vowelWillSetMark
                } else {
                    vowelWillSetMark = vowelStartIndex
                    hookState.backspaceCount = Int(index) - vowelWillSetMark
                }
            }
            // ua
            else if v1 == VietnameseData.KEY_U && v2 == VietnameseData.KEY_A {
                var hasQ = false
                if vowelStartIndex > 0 && chr(vowelStartIndex - 1) == VietnameseData.KEY_Q {
                    hasQ = true
                }
                
                if !hasQ {
                    if vowelEndIndex + 1 >= Int(index) || !canHasEndConsonant() {
                        vowelWillSetMark = vowelStartIndex
                        hookState.backspaceCount = Int(index) - vowelWillSetMark
                    }
                } else {
                    vowelWillSetMark = vowelStartIndex + 1
                    hookState.backspaceCount = Int(index) - vowelWillSetMark
                }
            }
            // oo -> mark on last vowel
            else if v1 == VietnameseData.KEY_O && v2 == VietnameseData.KEY_O {
                vowelWillSetMark = vowelEndIndex
                hookState.backspaceCount = Int(index) - vowelEndIndex
            }
        }
        
        hookState.newCharCount = hookState.backspaceCount
    }
    
    private func handleOldMark() {
        // Default
        if vowelCount == 0 && chr(vowelEndIndex) == VietnameseData.KEY_I {
            vowelWillSetMark = vowelEndIndex
        } else {
            vowelWillSetMark = vowelStartIndex
        }
        hookState.backspaceCount = Int(index) - vowelWillSetMark
        
        // Rule 2: 3 vowels or has ending consonant
        // For old style: "hòa" (no ending) vs "hoàn" (has ending 'n')
        if vowelCount == 3 || (vowelEndIndex + 1 < Int(index) && vietnameseData.isConsonant(chr(vowelEndIndex + 1)) && canHasEndConsonant()) {
            vowelWillSetMark = vowelStartIndex + 1
            hookState.backspaceCount = Int(index) - vowelWillSetMark
        }
        
        // Rule for "uy" in old style: mark on 'u' (úy)
        // Old style: túy, húy, qúy
        // BUT: If there's an ending consonant (like "huynh"), mark should be on 'y' (huỳnh)
        if vowelCount == 2 {
            let v1 = chr(vowelStartIndex)
            let v2 = chr(vowelStartIndex + 1)
            let hasEndConsonant = vowelEndIndex + 1 < Int(index) &&
                                  vietnameseData.isConsonant(chr(vowelEndIndex + 1)) &&
                                  canHasEndConsonant()

            if v1 == VietnameseData.KEY_U && v2 == VietnameseData.KEY_Y && !hasEndConsonant {
                vowelWillSetMark = vowelStartIndex  // Đặt dấu vào 'u' cho kiểu cũ (chỉ khi KHÔNG có phụ âm cuối)
                hookState.backspaceCount = Int(index) - vowelWillSetMark
            }
        }
        
        // Rule 3: For vowels with circumflex/horn (ê, ơ) - tone goes on that vowel
        // This handles: iê (hiện), yê (yến), ươ (người)
        // IMPORTANT: Only check ê and ơ - NOT ư or ô!
        // For "ươ" pattern (like "người"), the tone goes on "ơ", not "ư"
        // For "uô" pattern (like "uống"), rule 2 already handles it (mark on VSI+1)
        // This matches OpenKey behavior exactly
        for i in vowelStartIndex...vowelEndIndex {
            let key = chr(i)
            let hasTone = (typingWord[i] & VNEngine.TONE_MASK) != 0      // Has circumflex (^)
            let hasToneW = (typingWord[i] & VNEngine.TONEW_MASK) != 0    // Has horn (ơ)
            
            // ê (e with circumflex) or ơ (o with horn)
            // NOTE: Do NOT include ư or ô here!
            // - For "ươ" pattern, tone goes on "ơ", not "ư"
            // - For "uô" pattern, rule 2 handles it (3 vowels or end consonant)
            if (key == VietnameseData.KEY_E && hasTone) ||   // ê
               (key == VietnameseData.KEY_O && hasToneW) {   // ơ
                vowelWillSetMark = i
                hookState.backspaceCount = Int(index) - vowelWillSetMark
                break
            }
        }
        
        hookState.newCharCount = hookState.backspaceCount
    }
    
    private func canHasEndConsonant() -> Bool {
        // TODO: Check vowel combine table
        return true
    }
    
    // MARK: - Standalone Character Handling
    
    private func checkForStandaloneChar(data: UInt16, isCaps: Bool, keyWillReverse: UInt16) {
        if index > 0 {
            let lastKey = chr(Int(index) - 1)
            let hasToneW = (typingWord[Int(index) - 1] & VNEngine.TONEW_MASK) != 0
            
            // Undo standalone/horn conversion: if previous char's base key matches
            // keyWillReverse and has TONEW, reverse it back to the raw key.
            // NOTE: chr() returns processedData base key (via CHAR_MASK), so for
            // standalone ư (processedData = KEY_U | TONEW | STANDALONE), lastKey = KEY_U.
            // This naturally matches keyWillReverse = KEY_U without needing separate checks.
            if lastKey == keyWillReverse && hasToneW {
                hookState.code = UInt8(vWillProcess)
                hookState.backspaceCount = 1
                hookState.newCharCount = 1
                typingWord[Int(index) - 1] = UInt32(data) | (isCaps ? VNEngine.CAPS_MASK : 0)
                hookState.charData[0] = getCharacterCode(typingWord[Int(index) - 1])
                return
            }
            
            // Check standalone w -> ư
            if index > 0 && lastKey == VietnameseData.KEY_U && keyWillReverse == VietnameseData.KEY_O {
                insertKey(keyCode: keyWillReverse, isCaps: isCaps)
                reverseLastStandaloneChar(keyCode: keyWillReverse, isCaps: isCaps)
                return
            }
        }
        
        if index == 0 {
            // Standalone ơ/ư at word start → always allow
            insertKey(keyCode: data, isCaps: isCaps, isCheckSpelling: false)
            reverseLastStandaloneChar(keyCode: keyWillReverse, isCaps: isCaps)
            return
        } else if index == 1 {
            let prevKey = chr(0)
            
            // Always block: vowels that can never precede standalone ơ/ư
            if VietnameseData.standaloneWbadAlways.contains(prevKey) {
                insertKey(keyCode: data, isCaps: isCaps)
                return
            }
            
            // Conditionally block: only block if key is NOT in customConsonants
            if VietnameseData.standaloneWbadConditional.contains(prevKey) && !vCustomConsonants.contains(prevKey) {
                insertKey(keyCode: data, isCaps: isCaps)
                return
            }
            
            // Valid consonant before ơ/ư → allow conversion
            insertKey(keyCode: data, isCaps: isCaps, isCheckSpelling: false)
            reverseLastStandaloneChar(keyCode: keyWillReverse, isCaps: isCaps)
            return
        } else if index == 2 {
            // Check double consonant combinations (kh, th, tr, ch, nh, ng, gh, gi, ph)
            for allowed in vietnameseData.doubleWAllowed {
                if chr(0) == allowed[0] && chr(1) == allowed[1] {
                    insertKey(keyCode: data, isCaps: isCaps, isCheckSpelling: false)
                    reverseLastStandaloneChar(keyCode: keyWillReverse, isCaps: isCaps)
                    return
                }
            }
            insertKey(keyCode: data, isCaps: isCaps)
            return
        }
        
        // index > 2: no valid Vietnamese word has ơ/ư after 3+ consonant chars
        // Examples: "nghư", "nghơ" don't exist → always insert raw
        insertKey(keyCode: data, isCaps: isCaps)
    }
    
    private func reverseLastStandaloneChar(keyCode: UInt16, isCaps: Bool) {
        hookState.code = UInt8(vWillProcess)
        hookState.backspaceCount = 0
        hookState.newCharCount = 1
        hookState.extCode = 4
        typingWord[Int(index) - 1] = UInt32(keyCode) | VNEngine.TONEW_MASK | VNEngine.STANDALONE_MASK | (isCaps ? VNEngine.CAPS_MASK : 0)
        hookState.charData[0] = getCharacterCode(typingWord[Int(index) - 1])
    }
    
    // MARK: - State Management
    
    /// Save current word to history for restore functionality
    /// Save current word to history
    func saveWord() {
        if hookState.code == UInt8(vReplaceMacro) || hookState.code == UInt8(vRestore) {
            return
        }

        guard !buffer.isEmpty else {
            return
        }

        let snapshot = buffer.createSnapshot()
        history.save(snapshot)
    }

    /// Save spaces to history
    func saveWord(keyCode: UInt16, count: Int) {
        history.saveSpaces(count: count, keyCode: keyCode)
    }

    /// Save special characters to history
    private func saveSpecialChar() {
        guard !specialChar.isEmpty else { return }

        var entries: [CharacterEntry] = []
        for data in specialChar {
            entries.append(CharacterEntry(fromLegacy: data))
        }
        // Populate keystrokeSequence with each entry's primary keystroke so restoring
        // this snapshot keeps the buffer invariant intact (sequence in typing order,
        // every keystroke carries its owning entry's id).
        let sequence = entries.map { $0.primaryKeystroke }
        let snapshot = BufferSnapshot(entries: entries, overflow: [], keystrokeSequence: sequence)
        history.save(snapshot)
        specialChar.removeAll()
    }

    /// Restore last word from history
    func restoreLastTypingState() {

        guard let lastSnapshot = history.popLast() else {
            cursorMovedSinceReset = true
            return
        }

        guard !lastSnapshot.entries.isEmpty else {
            return
        }

        let firstKeyCode = lastSnapshot.firstKeyCode ?? 0

        if firstKeyCode == VietnameseData.KEY_SPACE {
            spaceCount = lastSnapshot.count
            buffer.clear()
        } else if vietnameseData.charKeyCode.contains(firstKeyCode) {
            buffer.clear()
            specialChar = lastSnapshot.allProcessedData
            if vCheckSpelling == 1 {
                checkSpelling()
            }
        } else {
            buffer.restore(from: lastSnapshot)
            tempDisableKey = false
        }
    }

    /// Start a new typing session
    func startNewSession() {


        buffer.clear()

        hookState.backspaceCount = 0
        hookState.newCharCount = 0
        hookState.macroKey.removeAll()

        tempDisableKey = false
        hasHandledMacro = false
        hasHandleQuickConsonant = false
        // Reset desync flag on new session - fresh start
        bufferDesyncDetected = false

    }

    // MARK: - Character Code Conversion
    
    /// Convert internal code to actual character code based on code table
    func getCharacterCode(_ data: UInt32) -> UInt32 {
        let capsElem = (data & VNEngine.CAPS_MASK) != 0 ? 0 : 1
        let key = data & VNEngine.CHAR_MASK
        
        // Build lookup key with tone/horn flags
        var lookupKey: UInt32 = key
        if (data & VNEngine.TONE_MASK) != 0 {
            lookupKey |= VNEngine.TONE_MASK
        } else if (data & VNEngine.TONEW_MASK) != 0 {
            lookupKey |= VNEngine.TONEW_MASK
        }
        
        // Get code table
        let codeTable = vietnameseData.codeTables[vCodeTable]
        
        if (data & VNEngine.MARK_MASK) != 0 {
            // Has mark - calculate mark element index
            var markElem = -2
            switch data & VNEngine.MARK_MASK {
            case VNEngine.MARK1_MASK: markElem = 0  // Sắc
            case VNEngine.MARK2_MASK: markElem = 2  // Huyền
            case VNEngine.MARK3_MASK: markElem = 4  // Hỏi
            case VNEngine.MARK4_MASK: markElem = 6  // Ngã
            case VNEngine.MARK5_MASK: markElem = 8  // Nặng
            default: break
            }
            markElem += capsElem
            
            // Determine lookup key and markElem offset based on tone/horn presence
            // Code table structure:
            // - KEY_A | TONE_MASK (0x20000): [Â, â, Ă, ă, Á, á, À, à, Ả, ả, Ã, ã, Ạ, ạ] - 14 elements
            //   For marks on vowels WITH circumflex/breve, markElem needs +4 offset
            // - KEY_A | TONE_MASK | 0x80000: [Ấ, ấ, Ầ, ầ, Ẩ, ẩ, Ẫ, ẫ, Ậ, ậ] - 10 elements
            //   For marks on vowels WITH circumflex/breve AND mark, no offset needed
            // - KEY_O | 0x80000: [Ó, ó, Ò, ò, Ỏ, ỏ, Õ, õ, Ọ, ọ] - 10 elements
            //   For marks on PLAIN vowels (no circumflex/horn), no offset needed
            // keyCode derived from key for potential diagnostic use
            var markLookupKey = lookupKey
            
            if (data & VNEngine.TONE_MASK) != 0 || (data & VNEngine.TONEW_MASK) != 0 {
                // Has circumflex/horn AND mark
                markLookupKey |= VNEngine.MARK1_MASK  // Use MARK1_MASK (0x80000) as base for lookup
                // No offset needed - array has 10 elements for marks only
            } else {
                // Plain vowel with mark (no circumflex/horn) - e.g., "ó", "á", "é", "ú"
                // Lookup key is KEY | MARK1_MASK (0x80000)
                markLookupKey = key | VNEngine.MARK1_MASK
                // No offset needed - array has 10 elements for marks only
            }
            
            
            // Look up in code table
            if let charArray = codeTable[markLookupKey], markElem >= 0 && markElem < charArray.count {
                let result = charArray[markElem]
                return result | VNEngine.CHAR_CODE_MASK
            }
            
            // Not found - return as is
            return data
        } else {
            // No mark
            if (data & VNEngine.TONE_MASK) != 0 || (data & VNEngine.TONEW_MASK) != 0 {
                // Has tone/horn but no mark
                // Code table structure for vowels:
                // - [0]: CAPS with ^ (TONE_MASK)
                // - [1]: lowercase with ^
                // - [2]: CAPS with horn (TONEW_MASK)
                // - [3]: lowercase with horn
                var charIndex = capsElem
                
                // Determine the correct lookup key based on character type
                // For O: both ^ (ô) and horn (ơ) are stored at KEY_O | TONE_MASK
                // For U: horn (ư) is stored at KEY_U | TONEW_MASK
                // For A: both ^ (â) and breve (ă) are stored at KEY_A | TONE_MASK
                let keyCode = UInt16(key)
                var actualLookupKey: UInt32
                
                if (data & VNEngine.TONEW_MASK) != 0 {
                    charIndex += 2  // Use index 2 or 3 for horn/breve characters
                    
                    // For O with horn (ơ): lookup at KEY_O | TONE_MASK, index 2,3
                    // For A with breve (ă): lookup at KEY_A | TONE_MASK, index 2,3
                    if keyCode == VietnameseData.KEY_O || keyCode == VietnameseData.KEY_A {
                        actualLookupKey = UInt32(keyCode) | VNEngine.TONE_MASK
                    } else {
                        // For U with horn (ư): lookup at KEY_U | TONEW_MASK
                        actualLookupKey = lookupKey
                    }
                } else {
                    // TONE_MASK (^): lookup at KEY | TONE_MASK
                    actualLookupKey = lookupKey
                }
                
                if let charArray = codeTable[actualLookupKey], charIndex < charArray.count {
                    return charArray[charIndex] | VNEngine.CHAR_CODE_MASK
                }
            }
            
            // No special character - return as is
            return data
        }
    }
    
    // MARK: - Public API
    
    /// Reset engine to initial state
    func reset() {
        startNewSession()
        history.clear()
        specialChar.removeAll()
        spaceCount = 0
        vCheckSpelling = useSpellCheckingBefore ? 1 : 0
        willTempOffEngine = false
        cursorMovedSinceReset = false
        focusChangedDuringTyping = false
        // NOTE: upperCaseStatus is intentionally NOT cleared here.
        // Soft resets (Tab, Forward Delete, Enter-with-empty-buffer) preserve
        // sentence context — the calling code sets the status around reset()
        // to propagate sentence-end (e.g. "\n") into the next typing session.
        // Hard resets that imply lost context (mouse click, arrow keys, app
        // switch, focus change) go through resetWithCursorMoved() which DOES
        // clear the status.
    }

    /// Reset engine with cursor movement flag set
    /// This indicates that user moved cursor (via mouse/arrow keys) and may be editing
    /// in the middle of an existing word. Restore logic will be skipped in this case.
    /// Also clears any pending auto-capitalize status: a cursor move means the
    /// editing context that produced the status (the sentence-ender) is no longer
    /// where the user is now typing — otherwise the next character at the new
    /// location would silently capitalize (e.g. after paste + click + delete).
    func resetWithCursorMoved() {
        reset()
        cursorMovedSinceReset = true
        upperCaseStatus = 0
    }

    /// Update upperCaseStatus based on the word break character
    /// Called from processWordBreak(), handleWordBreak(), and externally when buffer is empty
    /// to ensure auto-capitalize works regardless of which code path runs.
    ///
    /// Status values:
    ///   0 = no pending capitalize
    ///   1 = after sentence-ending punctuation (., ?, !), no space seen yet
    ///   2 = after newline (\n, \r)
    ///   3 = after sentence-ending punctuation AND at least one space seen
    func updateUpperCaseStatus(character: Character) {
        guard vUpperCaseFirstChar == 1 else { return }
        if character == "." || character == "?" || character == "!" {
            upperCaseStatus = 1
        } else if character == "\n" || character == "\r" {
            upperCaseStatus = 2
        } else if character == " " {
            // A space after sentence-ending punctuation (status 1) upgrades to status 3
            // ("space seen"). Newline (2) and already-space-seen (3) are preserved, so
            // multiple spaces and "punctuation → space" both end up capitalizable.
            // Flow: sentence-end punctuation → space(s) → next char should be capitalized.
            if upperCaseStatus == 1 {
                upperCaseStatus = 3
            }
        } else {
            // Any other character cancels the pending capitalize.
            upperCaseStatus = 0
        }
        // If space: keep/upgrade upperCaseStatus (preserves period/newline status)
    }

    /// Get current typing word as string (for debugging and display)
    func getCurrentWord() -> String {
        var result = ""
        for i in 0..<Int(index) {
            let data = typingWord[i]
            let charCode = getCharacterCode(data)
            let isCaps = (data & VNEngine.CAPS_MASK) != 0

            if (charCode & VNEngine.CHAR_CODE_MASK) != 0 {
                // Unicode character
                let unicodeValue = charCode & 0xFFFF
                if let scalar = UnicodeScalar(unicodeValue) {
                    var char = String(Character(scalar))
                    if isCaps {
                        char = char.uppercased()
                    }
                    result.append(char)
                }
            } else {
                // Key code - convert to character using macOS key code mapping
                let keyCode = UInt16(charCode & VNEngine.CHAR_MASK)
                if let char = keyCodeToCharacter(keyCode) {
                    if isCaps {
                        result.append(Character(String(char).uppercased()))
                    } else {
                        result.append(char)
                    }
                }
            }
        }
        return result
    }
    
    /// Convert macOS key code to character (for debugging)
    /// Delegates to the static keyCodeToChar method to avoid duplicating the mapping.
    private func keyCodeToCharacter(_ keyCode: UInt16) -> Character? {
        return Self.keyCodeToChar(keyCode)
    }
}
