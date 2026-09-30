# Historical 0.1 reference review — superseded by 0.2 integration

See ../THIRD_PARTY.md and ../SECURITY.md for current reused-source inventory and audit decisions. The text below records the initial no-reuse decision, which was changed at the user’s request.

# XKey reference review

Repository: https://github.com/xmannv/xkey
Commit: f0e448d1498ec8429c5dbc4015fe4a6ab5e56839
Reviewed 2026-09-30. Root LICENSE: MIT, copyright 2025 XKey. MIT permits reuse with its notice. Engine headers identify ports from OpenKey; their provenance would need separate review before reuse. **No upstream engine/source/assets are reused.**

A repository-wide text scan produced `xkey-api-inventory.txt` (1,367 matching lines), covering the requested network, process, storage, keyboard and permission terms. This is a broad API inventory plus focused manual inspection of input controller, engine structure, network providers and logger, not a line-by-line independent security certification of XKey.

| Classification | Area | Finding / VKey decision |
| --- | --- | --- |
| SAFE for intended use | InputMethodKit marked-text APIs | Apple local text-client composition is appropriate. VKey has its own small controller. |
| SAFE with minimization | UserDefaults | Keep only mode and enabled state in the new app. Do not import upstream settings manager. |
| NEEDS REVIEW | VNEngine, VietnameseData, TypingBuffer, VNWordBuffer | Roughly 10,000 lines across engine files; history, spell checking, macros and dictionary coupling; headers mention OpenKey ancestry. Do not reuse. |
| NEEDS REVIEW / OMIT | CGEvent, CGEventTap, Accessibility, Input Monitoring, secure-input monitors | Useful for upstream compatibility, but broad input access is unnecessary for this minimal IMK design. |
| REMOVE / OMIT | Translation providers and TranslationNetworkManager | URLSession sends requested translation text to providers. GoogleTranslateProvider places text in the `q` query parameter. This is an explicit outgoing text path, not evidence of covert exfiltration of every keystroke. |
| REMOVE / OMIT | VNDictionaryManager | Downloads dictionary via URLSession. |
| REMOVE / OMIT | Sparkle / AppDelegate updater | Network updater not required. |
| REMOVE / OMIT | Cloud/sync/backup features | Outside scope. |
| REMOVE / OMIT | DebugLogger and DebugViewModel | FileHandle-based diagnostic persistence; unacceptable surface for this minimal keyboard app. |
| REMOVE / OMIT | NSPasteboard / Clipboard features | Translation, conversion, debug export and event injection use clipboard; not needed. |
| REMOVE / OMIT | Process/NSTask/shell helpers | Installer/update/process management not part of the new app. |
| NEEDS REVIEW / OMIT | Keychain/socket/HTTP references | Entire related feature families excluded; none is imported into VKey. |

“REMOVE / OMIT” means excluded from the new independent app; the downloaded reference checkout was not modified. The audit found explicit networking and text transmission features in XKey, so it would be inaccurate to describe the full upstream app as offline-only.

VKey architecture: IMKServer → one IMKInputController per client session → bounded in-memory Composer → setMarkedText / insertText. No global tap or fallback injection. Backspace recomputes only the current word; Escape restores its raw spelling. Committed words have no restoration history. Browser compatibility is entrusted to official marked-text support and remains a runtime test requirement.

Apple references:
- https://developer.apple.com/documentation/inputmethodkit
- https://developer.apple.com/documentation/inputmethodkit/imkserver/init(name:bundleidentifier:)
