# VKey 0.3.9 — Security and privacy

Network: Does this app access the Internet? **NO application network features or requests.**
Keystroke storage: Does this app save keystrokes? **NO persistent storage.**
Analytics: NO. Telemetry: NO. Third-party tracking: NO. Cloud: NO. Auto update: NO.

## Input and permissions

VKey uses Apple's InputMethodKit. macOS sends input to the selected input method for the active text client. The app temporarily keeps the active word's raw input and converted text in RAM to compose Unicode, restore the keys typed and handle Backspace. Raw input normally holds at most 28 characters, including tone and modifier keys. When continuing a word whose first keys reached the application before VKey activated, or a word that Backspace has led back to, it reads the word right before the caret from the document (up to 28 characters) and appends the current key, temporarily reaching 29. Nothing about a finished word is kept; only what the document shows is read back. This is a composition-buffer limit, not a limit on the length of text the user can type.

It asks the text client for its selection range (where the caret is). It also reads nearby text to continue missed input or verify and relocate the active word before changing it. Continuing missed input reads at most 28 UTF-16 units before the caret. Verification reads the active word; relocation also reads one preceding UTF-16 unit to check the word boundary, for at most 30 UTF-16 units in the 29-character case. An adopted word is held in the active composition; other text read for these checks is not retained after the check.

From macOS it learns only the time at which an application became active, not which one. It does not use the clipboard. It clears its own active composition on commit, deactivation, activation and a Secure Input event. This is ordinary Swift memory release, not guaranteed cryptographic memory erasure; operating-system memory management, swap and system crash diagnostics are outside the app's control.

No Accessibility, Input Monitoring, screen recording, full disk access or administrator access is required by the app. Users drag VKey.app to Applications and open it once; VKey copies and registers its own bundle in the user's `~/Library/Input Methods`, then the user selects it in macOS Keyboard settings. There are no event taps, global keyboard monitors, synthetic backspaces, password-field workarounds, background helper processes or launch agents.

`IsSecureEventInputEnabled()` is checked before handling events. If enabled, the app ends the active word and returns events without conversion; the menu-bar item shows a lock and its menu names the application holding Secure Input (read from `CGSessionCopyCurrentDictionary`). The normal macOS input-method security rules remain in force. Chrome local password field was tested with dummy a1: two masked characters remained, and ordinary text conversion resumed after leaving the field. This is a limited smoke test, not comprehensive secure-field certification.

## Data storage

The application-written preferences are `TypingMode` (telex/vni), `VietnameseEnabled` (Boolean), and `MarkedTextApplications`: the bundle identifiers of applications found unable to take direct text. All are in the `local.vkey.inputmethod` UserDefaults domain. AppKit may manage its own normal system preferences. No typed content is written to preferences, files, logs or pasteboard. No dictionaries, input histories or accounts exist. Composition is delivered only to the requesting local text client. That client application remains responsible for its own storage and network behavior.

## Verification and limits

- `scripts/audit.sh` checks production source for networking, logging, clipboard, process launching and event-tap API patterns, and records linked libraries, undefined symbols and signing information.
- Binary links only Apple system frameworks and Swift runtimes. The adapted Vietnamese conversion source is compiled into the binary; no embedded third-party binary frameworks or packages. See THIRD_PARTY_NOTICES.md for provenance and license information.
- The release build output `dist/VKey.app` (0.3.9, build 19) uses the Developer ID Application certificate with hardened runtime and no entitlements. The build script selects `VKEY_CODESIGN_IDENTITY` or the first available Developer ID Application identity. Apple Notary Service accepted submission `b02482ac-7983-43ca-8aae-1ac6c4180116` for the 0.3.9 DMG, its ticket was stapled and validated, and local `spctl` reported `accepted` with source `Notarized Developer ID`. The installed input-method copy is updated only when the new app is opened. **Not App Sandbox enabled:** absence of network entitlements alone does not prohibit network access for a non-sandboxed app. The offline conclusion is based on the small source implementation and symbol inspection, not a claim of an OS-enforced network firewall.
- Launched successfully on the build Mac; `lsof -nP -a -c VKey -i` found no Internet sockets at the observation time. This snapshot is not proof of all future behavior.
- Engine tests pass locally and also under a test-only deny-network sandbox (see test report when available). Full app typing with the Mac physically disconnected has not been tested.
- No security settings, TCC database, SIP, or Gatekeeper settings were changed.

Development used local source references and Apple documentation. Development-only material is not part of VKey and is not shipped inside the app.

## Changes in 0.3.0

- One engine instance now lives for the active word (created on its first key, released when the word ends) instead of being rebuilt on every key. No engine instance, history or text survives a word.
- When a word ends, a structural rule (`VietnameseSyllable`) decides whether the converted text can be a Vietnamese syllable, and gives the keys back if not. There is no dictionary, spell-check service or network.
- Only the copy in `~/Library/Input Methods` runs as the input method. Any other copy installs itself there, restarts the running input method through `NSRunningApplication`/`NSWorkspace`, and exits.
- `scripts/live-test.sh` builds a separate test tool that posts key events and therefore needs the Accessibility permission. It is not part of VKey.app, which still requests no permission.

## Engine isolation in 0.2.0

The custom conversion algorithm was replaced by a bounded local conversion engine. The production path has no logging callbacks, dictionary-backed instant restoration or app-inspection hooks. It never feeds committed words or word-break history into persistent storage. Any conversion history exists only for the active word and is released with that word. Only local character maps and vowel rules are used. No user dictionary, spell-check service, macro manager or network manager is compiled. The production scan now recursively covers the conversion-engine sources as well.
