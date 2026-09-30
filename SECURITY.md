# VKey 0.2.0 — Security and privacy

Network: Does this app access the Internet? **NO application network features or requests.**
Keystroke storage: Does this app save keystrokes? **NO persistent storage.**
Analytics: NO. Telemetry: NO. Third-party tracking: NO. Cloud: NO. Auto update: NO.

## Input and permissions

VKey uses Apple's InputMethodKit. macOS sends input to the selected input method for the active text client. The app keeps at most 28 raw characters of the active word in memory to compose Unicode and undo a typing key. It does not request surrounding document contents or clipboard contents. It clears its own active composition on commit, deactivation, activation and a Secure Input event. This is ordinary Swift memory release, not guaranteed cryptographic memory erasure; operating-system memory management, swap and system crash diagnostics are outside the app's control.

No Accessibility, Input Monitoring, screen recording, full disk access or administrator access is required by the app. Users drag VKey.app to Applications and open it once; VKey copies and registers its own bundle in the user's `~/Library/Input Methods`, then the user selects it in macOS Keyboard settings. There are no event taps, global keyboard monitors, synthetic backspaces, password-field workarounds, background helper processes or launch agents.

`IsSecureEventInputEnabled()` is checked before handling events and committing composition. If enabled, the app clears its buffer and returns events without conversion. The normal macOS input-method security rules remain in force. Chrome local password field was tested with dummy a1: two masked characters remained, and ordinary text conversion resumed after leaving the field. This is a limited smoke test, not comprehensive secure-field certification.

## Data storage

The only application-written preferences are `TypingMode` (telex/vni) and `VietnameseEnabled` (Boolean), in the `local.vkey.inputmethod` UserDefaults domain. AppKit may manage its own normal system preferences. No typed content is written to preferences, files, logs or pasteboard. No dictionaries, input histories or accounts exist. Composition is delivered only to the requesting local text client. That client application remains responsible for its own storage and network behavior.

## Verification and limits

- `scripts/audit.sh` checks production source for networking, logging, clipboard, process launching and event-tap API patterns, and records linked libraries, undefined symbols and signing information.
- Binary links only Apple system frameworks and Swift runtimes. Adapted XKey/OpenKey-derived engine SOURCE is compiled into the binary; no embedded third-party binary frameworks or packages. See THIRD_PARTY_NOTICES.md.
- The current build output `dist/VKey.app` uses the Developer ID Application certificate with hardened runtime and no entitlements. The build script selects `VKEY_CODESIGN_IDENTITY` or the first available Developer ID Application identity. Build 6 was accepted by Apple Notary Service, and the app plus DMG have stapled tickets; local `spctl` reports `accepted` with source `Notarized Developer ID`. An older installed input-method copy may remain ad-hoc until the build-number-6 app is opened and updates it. **Not App Sandbox enabled:** absence of network entitlements alone does not prohibit network access for a non-sandboxed app. The offline conclusion is based on the small source implementation and symbol inspection, not a claim of an OS-enforced network firewall.
- Launched successfully on the build Mac; `lsof -nP -a -c VKey -i` found no Internet sockets at the observation time. This snapshot is not proof of all future behavior.
- Engine tests pass locally and also under a test-only deny-network sandbox (see test report when available). Full app typing with the Mac physically disconnected has not been tested.
- No security settings, TCC database, SIP, or Gatekeeper settings were changed.

Development downloaded XKey for reference and consulted Apple documentation. Those developer tools are not part of VKey and are not shipped inside the app.

## Engine isolation in 0.2.0

The custom conversion algorithm was replaced by the XKey core. All logging callbacks, dictionary-backed instant restoration and app-inspection hooks were removed. The adapter creates a fresh engine per active-word conversion; it never feeds committed words or word-break history into a persistent engine. Any upstream history structures are confined to that temporary engine lifetime. Only local character maps and vowel rules are used. No user dictionary, spell-check service, macro manager or network manager is compiled. The production scan now recursively covers Sources/XKeyEngine as well.
