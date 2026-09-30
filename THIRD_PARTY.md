# Third-party source and notices

The canonical repository notice is [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
This file is retained for the existing packaged-app path and mirrors the same
provenance decisions in a shorter form.

VKey 0.2.0 includes an adapted offline subset of XKey:
[https://github.com/xmannv/xkey](https://github.com/xmannv/xkey)
Commit `f0e448d1498ec8429c5dbc4015fe4a6ab5e56839`.
Copyright (c) 2025 XKey. MIT license retained in Resources/Licenses/XKey-MIT.txt.

VKey is a separate project and should be understood as an independent release, rather than as a release issued or endorsed by XKey or OpenKey. The upstream authors and contributors retain credit for their work; VKey claims authorship only for its own integration and modifications.

Included under Sources/XKeyEngine:
- VNEngine.swift (core class, host-facing extension omitted)
- VNEngineAdvanced.swift
- VNEngineEnglishDetection.swift
- TypingBuffer.swift
- VietnameseData.swift
- VNCharacter.swift
- VowelSequenceValidator.swift

Tests/xkey-conversion-cases.json contains the 401 transformation rows from the upstream test corpus (maximum 28 ASCII input characters). Other corpus categories require dictionary/English restoration features outside this app's scope. 400/401 transformations pass; qusy is an explicitly recorded upstream behavior limitation, not silently removed.

Changes on 2026-09-30: removed every logging callback and associated diagnostics; removed dictionary-backed instant restore and AppBehaviorDetector access; omitted the entire keyboard-event-host extension, Accessibility debug reader, settings/macros/dictionary/network integrations. No automatic capitalization, quick abbreviations, macro expansion, external spell checker, or history across words is enabled. The adapter creates a fresh engine for each bounded active-word conversion and releases it immediately.

The upstream engine identifies itself as a Swift port of [OpenKey](https://github.com/tuyenvm/OpenKey).
Copyright © 2019 Tuyen Mai / Mai Vu Tuyen.
OpenKey is GPL-3.0; its license is retained in Resources/Licenses/OpenKey-GPL-3.0.txt. VKey's combined work is supplied under GPL-3.0 with the complete corresponding source and build scripts alongside the binary. The XKey MIT notice is preserved as well; the adapted engine is documented with both upstream notices rather than being presented as MIT-only.

Original VKey integration changes are also supplied under GPL-3.0. No third-party binary, package manager or downloaded runtime is required.
