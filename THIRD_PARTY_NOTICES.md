# Third-party notices

This file records the source provenance and license notices for VKey. It is
an attribution record, not a legal opinion.

## XKey

Original project:
https://github.com/xmannv/xkey

License: MIT License

Reference commit audited for the adapted engine subset:
`f0e448d1498ec8429c5dbc4015fe4a6ab5e56839`

This project builds on and includes an adapted subset of XKey. The relevant
files are under `Sources/XKeyEngine/`:

- `TypingBuffer.swift`
- `VNCharacter.swift`
- `VNEngine.swift`
- `VNEngineAdvanced.swift`
- `VNEngineEnglishDetection.swift`
- `VietnameseData.swift`
- `VowelSequenceValidator.swift`

Copyright (c) 2025 XKey. The original MIT copyright and license notice is
preserved in `Resources/Licenses/XKey-MIT.txt` and in the adapted source
headers.

We sincerely thank the XKey authors and contributors for making their work
available to the open-source community.

## OpenKey

Original project:
https://github.com/tuyenvm/OpenKey

Original author: Mai Vu Tuyen (Tuyen Mai)

License: GNU General Public License v3.0

XKey's engine source comments identify the Vietnamese engine as a Swift port
based on the OpenKey C++ engine. In this repository, the OpenKey-derived
provenance is explicitly visible in:

- `Sources/XKeyEngine/VNEngine.swift` (engine port based on OpenKey)
- `Sources/XKeyEngine/VNEngineAdvanced.swift` (advanced logic ported from
  `OpenKey Engine.cpp`)
- `Sources/XKeyEngine/VietnameseData.swift` (language data ported from
  `OpenKey Vietnamese.cpp`)
- OpenKey rule references in `VowelSequenceValidator.swift` and
  `VNEngine.swift`

Within the scope of this audit, no OpenKey C++ source file was found copied
into this repository; the current code is a modified Swift subset obtained
through XKey. The OpenKey GPL-3.0 text is retained in
`Resources/Licenses/OpenKey-GPL-3.0.txt`.

For portions with OpenKey provenance, the applicable copyright and license
terms are retained. In view of that provenance, this repository does not
present the adapted engine as an MIT-only component.

## Test data

`Tests/vietnamese-syllables.txt` is the syllable list of the Vietnamese
spell-check dictionary of ibus-bamboo (https://github.com/BambooEngine/ibus-bamboo,
`data/vietnamese.cm.dict`, GPL-3.0). It is used only by `scripts/test.sh` to
check that every listed syllable can be typed; it is not compiled into or
shipped with the app. Its own notice, which names the Free Vietnamese
Dictionary Project of Hồ Ngọc Đức (GPL), Vietnamese Wiktionary (CC BY-SA) and
the abbreviation list of Ngô Quốc Hưng as sources, is kept in
`Tests/vietnamese-syllables.LICENSE.txt`.

## Modifications and project-specific work

This project contains modifications and additional work made on top of the
existing open-source sources, including:

- an InputMethodKit host and VKey preferences/menu integration;
- a bounded `Composer` adapter that keeps an engine for the active word only;
- removal of XKey host/event-tap, logging, dictionary, macro, translation,
  updater, and application-inspection integrations;
- removal of persistent word/history behavior from the active conversion path;
- two corrections in the adapted engine, marked `VKey:` in the source: the
  rhyme "uych" accepts a tone key after its final (huỵch), and "quơ" followed
  by i or n stays "quơi"/"quơn" (Quới, quởn);
- the word-end rule that gives typed keys back when the marks cannot form a
  Vietnamese syllable (`VietnameseSyllable`);
- tests, build/package scripts, documentation, and the VKey app metadata.

VKey is a separate project and should be understood as an independent release,
rather than as a release issued or endorsed by XKey or OpenKey. Upstream
authors and contributors retain credit for their work; VKey claims authorship
only for its own integration and modifications.

## License structure and audit limitation

The repository-root `LICENSE` is the complete GNU GPL-3.0 text and has been
left unchanged. The combined VKey source and binaries are distributed under
GPL-3.0, while the XKey MIT notice remains preserved for the XKey portions.
Accordingly, the adapted engine is documented here with both upstream
notices rather than being presented as MIT-only.

The audit found clear source-level evidence of OpenKey ancestry through XKey,
while the repository does not currently provide enough information to fully
reconstruct the licensing history of every XKey Swift line. This document does
not attempt to resolve that question as a legal matter. The repository
therefore follows a cautious approach by retaining GPL-3.0 and all upstream
notices instead of presenting the project as MIT-only.

## Other third-party material

- `Tests/xkey-conversion-cases.json` is identified by the project as an
  upstream XKey transformation corpus and is kept with that attribution.
- No Swift package, third-party binary library, embedded framework, downloaded
  runtime, or other dependency with a separate license was found in the
  current source tree. Apple frameworks are system dependencies.
- No separate author or license metadata was found for `Resources/VKeyIcon.pdf`;
  its provenance can be documented separately if the artwork is not original
  project material.
