# Build and installation report

Build date: 2026-09-30.

- Host: macOS 27.0.1 (26A434), Apple Silicon arm64.
- Xcode: 27.0 (27A266a).
- Swift: 6.4 (swiftlang-6.4.0.34.1), Swift 5 compatibility mode.
- Deployment target: macOS 13.0, arm64 only. Older macOS versions have not been tested.
- Build: `./scripts/build.sh`
- Tests: `./scripts/test.sh`
- Audit: `./scripts/audit.sh`
- Disk image: `./scripts/package.sh`

Output app: `dist/VKey.app`
Output DMG: `dist/VKey-0.2.0-arm64.dmg`

The compiler succeeds without source warnings. Build 6 is signed with the available Developer ID Application identity using hardened runtime and a secure timestamp; `codesign --verify --deep --strict` passes. Apple Notary Service accepted the DMG, tickets were stapled to the app and DMG, and `spctl --assess` reports `accepted` with source `Notarized Developer ID`. There is no app sandbox or entitlement file. No system security controls were disabled. Build shell scripts are development-only; app runtime launches no subprocesses.

`open` succeeded outside the coding sandbox and the executable process was observed running. The coding sandbox initially returned a LaunchServices error; rerunning with normal desktop access succeeded. UI automation could not attach to this background input-method app. Launch success is not proof of active input-method integration.

81 fixed Telex/VNI cases plus backspace/reset pass; 400/401 upstream transformation rows match, with qusy documented as a known limitation. See reports/engine-tests.txt and reports/INTEGRATION.md for separate actual host-app tests.

## Installation

Open the DMG, drag VKey.app to Applications, then open VKey.app once. The user-launched app copies and registers its IMK bundle in the per-user Input Methods directory automatically. Log out and back in so macOS refreshes the input-source list, then add VKey under System Settings → Keyboard → Text Input → Edit → + → Vietnamese. Select VKey in the macOS input-source menu. If VKey is still missing, restart the Mac. VKey's Vietnamese/English and Telex/VNI commands are provided through the VK menu-bar item.

No Accessibility/Input Monitoring permission required. The user's own input-method directory requires no administrator password. No installer modifies permissions or security settings. Automatic login registration is omitted; macOS starts the selected input method itself.

## Uninstall

1. Open the `VK` menu and choose **Gỡ cài đặt VKey**. This disables the input source and moves both `~/Library/Input Methods/VKey.app` and `/Applications/VKey.app` to Trash.
2. Remove VKey from Keyboard settings if macOS still shows it, then close and reopen System Settings.
3. Optionally remove its two preferences with `defaults delete local.vkey.inputmethod` in Terminal. No launch agents, helper daemons, logs or dictionaries were installed.

## Required manual acceptance checks

Chrome: Telex/VNI text, Backspace, Escape, input-source switching and local dummy-password smoke tests passed. TextEdit: VNI formerly failing words passed on 0.2.0. Safari, Finder, Notes, VS Code/Cursor and the complete shortcut/undo matrix remain untested. Offline physical-network-disconnect typing remains untested; engine is tested in a deny-network sandbox.

Known limits: adapted XKey core with IMK host, no spell checking/dictionary or per-app workarounds; the active word uses direct replacement and is ordinary text without marked-text decoration; Backspace removes a raw typing key while composing; Escape restores the raw active word; after commit, normal host editing/undo applies. Maximum composition is 28 raw characters, then it commits. English text can be transformed in Vietnamese mode; choose English as needed. No Intel build or cross-Mac distribution validation.

## 0.1.1 registration fix

Corrected bundle identifier to `local.inputmethod.VKey` and the matching IMK connection name. Preserved preferences in the existing `local.vkey.inputmethod` domain. Installed the updated bundle and used Apple TISRegisterInputSource: status 0, followed by successful enumeration of `local.inputmethod.VKey`. Previous 0.1.0 returned status 0 but did not appear in enumeration. Conversion tests and signature checks still pass. Full host typing tests remain pending.

## 0.2.0 engine replacement

Replaced the handcrafted Composer algorithm with a bounded adapter to the offline XKey core. The IMKit transport now uses direct replacement for the active word, avoiding marked-text decoration. VKey keeps a separate `VK` status-menu for language and Telex/VNI commands; the macOS input-source menu only selects `ABC` or `VKey`. Preferences remain in the old domain. The corresponding source, tests, build scripts and notices are kept in the repository; the DMG contains the app, a short install guide and an `Applications` shortcut. The app performs the per-user Input Methods copy/register step on its first launch from Applications.

Observed startup limitation: after terminating/replacing the app, Chrome initially passed several synthetic test keys through before the new input session became active. Repeating the sentence after activation succeeded completely; warm ABC/VKey switching also passed. Cold-start readiness is not claimed fully fixed. Do not interpret an installed or selected source alone as successful typing verification.
