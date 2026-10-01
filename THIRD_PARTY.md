# Third-party source and notices

The canonical repository notice is [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
This file is retained for the existing packaged-app path and mirrors the same
provenance decisions in a shorter form.

VKey includes an adapted offline subset of XKey:
[https://github.com/xmannv/xkey](https://github.com/xmannv/xkey)
Commit `f0e448d1498ec8429c5dbc4015fe4a6ab5e56839`.
Copyright (c) 2025 XKey. MIT license retained in Resources/Licenses/XKey-MIT.txt.

VKey is maintained as a separate project. The upstream authors and contributors retain credit for their work; VKey claims authorship only for its own integration and modifications.

Included under Sources/XKeyEngine:
- VNEngine.swift (core class, host-facing extension omitted)
- VNEngineAdvanced.swift
- VNEngineEnglishDetection.swift
- TypingBuffer.swift
- VietnameseData.swift
- VNCharacter.swift
- VowelSequenceValidator.swift

`Tests/xkey-conversion-cases.json` contains 401 transformation rows retained for regression testing (maximum 28 ASCII input characters). The current test result is recorded in `reports/engine-tests.txt`.

Changes on 2026-09-30: the VKey integration uses a local InputMethodKit host, a bounded active-word adapter and no persistent typing history. No automatic capitalization, quick abbreviations, macro expansion, external spell checker or network integration is enabled. The adapter creates a fresh engine for each bounded active-word conversion and releases it immediately.

Changes in 0.3.0: the adapter keeps one engine for the active word instead of rebuilding it per key; two engine corrections are marked `VKey:` in the source (the "uych" rhyme, and "quơ" before i/n). A syllable list from ibus-bamboo is test data only; see THIRD_PARTY_NOTICES.md.

The upstream engine identifies itself as a Swift port of [OpenKey](https://github.com/tuyenvm/OpenKey).
Copyright © 2019 Tuyen Mai / Mai Vu Tuyen.
OpenKey is GPL-3.0; its license is retained in Resources/Licenses/OpenKey-GPL-3.0.txt. VKey's combined work is supplied under GPL-3.0 with the complete corresponding source and build scripts alongside the binary. The XKey MIT notice is preserved as well; the adapted engine is documented with both upstream notices rather than being presented as MIT-only.

Original VKey integration changes are also supplied under GPL-3.0. No third-party binary, package manager or downloaded runtime is required.
