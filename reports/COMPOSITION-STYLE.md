# Composition styling investigation (2026-09-30)

User requested no highlight/underline while typing.

1. Sent NSAttributedString with underlineStyle=0, underlineColor=clear, backgroundColor=clear, and an empty selection at the end. TextEdit still displayed composition decoration in the tested macOS environment.
2. Tested direct IMK insertText replacement scoped to the current word, validating selectedRange and clearing context on cursor movement. TextEdit displayed and converted gõ normally without underline. Chrome local textarea produced misordered input (g4o), so this approach was rejected.
3. Tested setMarkedText with explicit range followed by immediate insertText commit. Chrome duplicated prefixes (ggo), even with individual, separated key actions. Rejected.

The production transport now uses direct IMK replacement with tracked word length and start location. The active word is ordinary host text, so the IMK marked-text underline/background is not requested. The implementation also clears the tracked word when the caret moves, and commits by clearing VKey state rather than inserting the word a second time. TextEdit individual-key smoke testing produced `tiếng Việt` without marked-text decoration; the XKey conversion and engine tests remain green. Browser-specific behavior still requires separate manual acceptance because clients can expose different selection-range semantics.

The duplicate VKey status item was also removed. VKey's commands are now supplied through `IMKInputController.menu()`, so the macOS input-source menu is the single VKey menu path.
