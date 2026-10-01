# Build and installation report

Build date: 2026-10-01.

- Host: macOS 27.0.1 (26A434), Apple Silicon arm64.
- Xcode: 27.0 (27A266a).
- Swift: 6.4 (swiftlang-6.4.0.34.1), Swift 5 compatibility mode.
- Deployment target: macOS 13.0, arm64 only. Older macOS versions have not been tested.
- Build: `./scripts/build.sh`
- Tests: `./scripts/test.sh`
- Audit: `./scripts/audit.sh`
- Disk image: `./scripts/package.sh`

Output app: `dist/VKey.app`
Output DMG: `dist/VKey-0.3.6-arm64.dmg`

The compiler succeeds without source warnings. Build 16 is signed with the available Developer ID Application identity using hardened runtime and a secure timestamp; `codesign --verify --deep --strict` passes. Apple Notary Service accepted the DMG, tickets were stapled to the app and DMG, and `spctl --assess` reports `accepted` with source `Notarized Developer ID`. There is no app sandbox or entitlement file. No system security controls were disabled. Build shell scripts are development-only; app runtime launches no subprocesses.

`open` succeeded outside the coding sandbox and the executable process was observed running. The coding sandbox initially returned a LaunchServices error; rerunning with normal desktop access succeeded. UI automation could not attach to this background input-method app. Launch success is not proof of active input-method integration.

81 fixed Telex/VNI cases plus backspace/reset pass; 400/401 reference transformation rows match, with `qusy` documented as a known edge case. See reports/engine-tests.txt and reports/INTEGRATION.md for separate actual host-app tests.

## Installation

Open the DMG, drag VKey.app to Applications, then open VKey.app once. The user-launched app copies and registers its IMK bundle in the per-user Input Methods directory automatically. Log out and back in so macOS refreshes the input-source list, then add VKey under System Settings → Keyboard → Text Input → Edit → + → Vietnamese. Select VKey in the macOS input-source menu. If VKey is still missing, restart the Mac. VKey's Vietnamese/English and Telex/VNI commands are provided through the VK menu-bar item.

No Accessibility/Input Monitoring permission required. The user's own input-method directory requires no administrator password. No installer modifies permissions or security settings. Automatic login registration is omitted; macOS starts the selected input method itself.

## Uninstall

1. Open the `VK` menu and choose **Gỡ cài đặt VKey**. This disables the input source and moves both `~/Library/Input Methods/VKey.app` and `/Applications/VKey.app` to Trash.
2. Remove VKey from Keyboard settings if macOS still shows it, then close and reopen System Settings.
3. Optionally remove its two preferences with `defaults delete local.vkey.inputmethod` in Terminal. No launch agents, helper daemons, logs or dictionaries were installed.

## Required manual acceptance checks

Chrome: Telex/VNI text, Backspace, Escape, input-source switching and local dummy-password smoke tests passed. TextEdit: VNI formerly failing words passed on 0.2.0. Safari, Finder, Notes, VS Code/Cursor and the complete shortcut/undo matrix remain untested. Offline physical-network-disconnect typing remains untested; engine is tested in a deny-network sandbox.

Current scope: a local Vietnamese conversion engine with an InputMethodKit host, without spell checking, dictionary data or per-app workarounds. The active word uses direct replacement and is ordinary text without marked-text decoration; Backspace removes a raw typing key while composing; Escape restores the raw active word; after commit, normal host editing/undo applies. Maximum composition is 28 raw characters, then it commits. English text can be transformed in Vietnamese mode; choose English as needed. No Intel build or cross-Mac distribution validation.

## 0.1.1 registration fix

Corrected bundle identifier to `local.inputmethod.VKey` and the matching IMK connection name. Preserved preferences in the existing `local.vkey.inputmethod` domain. Installed the updated bundle and used Apple TISRegisterInputSource: status 0, followed by successful enumeration of `local.inputmethod.VKey`. Previous 0.1.0 returned status 0 but did not appear in enumeration. Conversion tests and signature checks still pass. Full host typing tests remain pending.

## 0.2.0 engine replacement

Replaced the handcrafted Composer algorithm with a bounded adapter to the offline Vietnamese conversion engine. The InputMethodKit transport now uses direct replacement for the active word, avoiding marked-text decoration. VKey keeps a separate `VK` status-menu for language and Telex/VNI commands; the macOS input-source menu only selects `ABC` or `VKey`. Preferences remain in the old domain. The corresponding source, tests, build scripts and notices are kept in the repository; the DMG contains the app, a short install guide and an `Applications` shortcut. The app performs the per-user Input Methods copy/register step on its first launch from Applications.

Observed startup limitation: after terminating/replacing the app, Chrome initially passed several synthetic test keys through before the new input session became active. Repeating the sentence after activation succeeded completely; warm ABC/VKey switching also passed. Cold-start readiness is not claimed fully fixed. Do not interpret an installed or selected source alone as successful typing verification.

## 0.3.6 (build 16)

Keys pressed right after switching to an application could be typed without Vietnamese conversion (`o73` instead of `ở`, `lam2` instead of `làm`), most often in Zalo. macOS activates the input method for an application 10–25 ms after it becomes active, and keys pressed in between reach the application without VKey. The first key VKey then sees now continues the word those keys began, read from the letters right before the caret; see reports/COMPOSITION-STYLE.md. Build 14, which forced marked text in Zalo by bundle identifier, was a local experiment: it did not address this and is not part of the release.

Packaged and released with a Developer ID signature, hardened runtime, and Apple notarization; the DMG ticket was stapled and the app reports `accepted` with source `Notarized Developer ID`. Submission ID: `3c19cb0c-9d83-4278-b87d-505c7c04effa`.

## 0.3.4 (build 13)

Fast typing: the input session tracks the caret positions its edits lead to, so a caret reported a few edits late (browsers, Electron) no longer discards the active word; see reports/COMPOSITION-STYLE.md. Clicks passed to the input method end the word. The status menu splits Hướng dẫn and Giới thiệu, the latter showing the running version; the spelling switch is removed and spell checking is always on.

Telex treats `[` and `]` as punctuation; as shortcuts for ơ/ư, typing `[[` emptied the engine buffer and deleted the word. Switching language or Telex/VNI ends the word as a space does (an English word comes back as typed) while the caret is still at it. Live test expectations follow the current rules and add a fast pass (5 ms between keys); the unit tests fail if dictionary coverage drops below 7,672 syllables.

Builds 11 and 12 were tested locally as 0.3.3, which was never released. At release time, the live test stopped on macOS 27.0.1 claiming that no posted keys were delivered despite Accessibility permission and keyboard focus. Follow-up on 2026-10-01 identified a test-harness bug: `RunLoop.run(until:)` did not dispatch the queued AppKit events. The harness now retrieves those system events with `NSApplication.nextEvent` and dispatches them with `sendEvent`, preserving routing through the installed input method. The full run passed 101/102 checks; correcting the contenteditable reader to preserve visible line breaks then passed all 19 checks in the affected target rerun. All 102 distinct checks have passing results across those runs; see [reports/LIVE-TEST.md](reports/LIVE-TEST.md). Packaged and released with a Developer ID signature, hardened runtime, and Apple notarization; the DMG ticket was stapled and the app reports `accepted` with source `Notarized Developer ID`. Submission ID: `90451695-112e-4256-8102-6f5d7f11c8aa`.

## 0.3.2 (build 10)

Added `VKey.icns` as the Finder application icon, generated by `scripts/make-app-icon.swift`, while keeping `VKeyIcon.pdf` as the separate input-source template icon. Packaged and released with a Developer ID signature, hardened runtime, and Apple notarization; the DMG ticket was stapled and the app reports `accepted` with source `Notarized Developer ID`. Submission ID: `fd28a27e-c603-4140-bec2-1a6b14a7693c`.

## 0.3.1 (build 9)

Input-source icon: `scripts/make-icon.swift` draws a 22×16 pt template badge with "VK" knocked out, bundled as `VKeyIcon.pdf` and named by `tsInputMethodIconFileKey`. The app also carries `VKey.icns` for its Finder icon, generated by `scripts/make-app-icon.swift`. `TISIconLabels` was tried and is read by macOS, but the menu bar does not draw a label badge for a third-party input method. Packaged and released with a Developer ID signature, hardened runtime, and Apple notarization; the DMG ticket was stapled and the app reports `accepted` with source `Notarized Developer ID`. Submission ID: `e61b826a-e077-4826-b285-f7201fb27965`.

## 0.3.0 (build 8)

Released on GitHub and Homebrew without notarization; build 9 (`0.3.1`) was later notarized and stapled.

- `./scripts/dev-install.sh` builds, runs the tests and installs over the running copy without a logout. The built app, started from anywhere outside `~/Library/Input Methods`, copies itself there when the executable or Info.plist differs, registers it, restarts the running input method and exits. `--quiet` suppresses its alert.
- `LSMultipleInstancesProhibited` was removed; the installer copy and the input-method copy must be able to run at the same moment.
- `./scripts/package.sh` reads the version from `Resources/Info.plist`.
- Behaviour changes: Backspace removes one character; word-end rule that gives the typed keys back when the marks cannot form a Vietnamese syllable (README has the table); Escape is consumed only when it changes text; Telex digits and keypad digits end a word; Control + Shift toggles Vietnamese/English; direct text is written only where a key changes existing letters, with marked text as the fallback.

Tests run for 0.3.0: `./scripts/test.sh` (output in reports/engine-tests.txt) and `./scripts/audit.sh`. `./scripts/live-test.sh` exists but has not been run to completion: it needs the Accessibility permission for `build/VKeyLiveTest.app`. No systematic manual check in Safari, Chrome, Terminal or VS Code has been recorded for this build.

macOS App Management protection can refuse command-line writes into `/Applications/VKey.app`; replace that copy with Finder.
