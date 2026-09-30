# Dependencies

No Swift packages, third-party binary libraries, embedded frameworks, updater or downloaded runtime assets. The XKey engine is now a vendored SOURCE dependency, compiled locally; it is necessary for mature Vietnamese typing rules.

Direct Apple frameworks:

| Component | Purpose |
| --- | --- |
| AppKit | Native menu bar, menus, help alert, input event objects |
| InputMethodKit | Official local input-method server and marked-text client interface |
| Carbon | `IsSecureEventInputEnabled`, input-source registration |
| Foundation | Strings, Unicode normalization, local preferences |

The executable also links CoreFoundation, libSystem, libobjc and Apple's Swift runtime/overlay dylibs. `reports/linked-libraries.txt` is the exact build inventory, including compiler-added weak overlays (CoreImage, Darwin, Dispatch, IOKit, Metal, OSLog, ObjectiveC, QuartzCore, Spatial, UniformTypeIdentifiers, XPC, os and simd). Linking these Apple overlays does not mean VKey calls network or logging APIs. All are system-provided; nothing is downloaded at launch.

Build tools: local Xcode/Swift SDK, Python 3 for plist/audit generation, codesign, hdiutil. None is invoked by the application at runtime.

XKey source: commit `f0e448d1498ec8429c5dbc4015fe4a6ab5e56839`. Seven core/model files are adapted under Sources/XKeyEngine. See THIRD_PARTY_NOTICES.md for the exact inventory, modifications and license provenance. Its OpenKey ancestry is preserved; the combined source and binaries are supplied under GPL-3.0 with XKey's MIT notice. No third-party code handles network access, global keyboard monitoring or persistence.
