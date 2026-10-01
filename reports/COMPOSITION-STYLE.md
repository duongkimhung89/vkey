# Composition styling investigation (2026-09-30)

User requested no highlight/underline while typing.

1. Sent NSAttributedString with underlineStyle=0, underlineColor=clear, backgroundColor=clear, and an empty selection at the end. TextEdit still displayed composition decoration in the tested macOS environment.
2. Tested direct IMK insertText replacement scoped to the current word, validating selectedRange and clearing context on cursor movement. TextEdit displayed and converted gõ normally without underline. Chrome local textarea produced misordered input (g4o), so this approach was rejected.
3. Tested setMarkedText with explicit range followed by immediate insertText commit. Chrome duplicated prefixes (ggo), even with individual, separated key actions. Rejected.

The production transport now uses direct IMK replacement with tracked word length and start location. The active word is ordinary host text, so the IMK marked-text underline/background is not requested. The implementation also clears the tracked word when the caret moves, and commits by clearing VKey state rather than inserting the word a second time. TextEdit individual-key smoke testing produced `tiếng Việt` without marked-text decoration; conversion and engine tests remain green. Browser-specific behavior still requires separate manual acceptance because clients can expose different selection-range semantics.

VKey's commands are supplied through its own status item; `IMKInputController.menu()` returns nil, so the macOS input-source menu only selects the source.

## 0.3.0

The direct transport now leaves a key that only adds its own letter to the host application and writes through IMKit only when a key changes letters already present, replacing from the first changed character. Plain typing therefore reaches the host exactly as it does without an input method, which removes the per-key rewrite of the whole word (visible as flicker in address bars that fill in completions). A client that reports no selection, whose caret does not follow typed letters, or that ignores the replacement range is given standard marked text with a faint underline. This has unit coverage against simulated clients only; see README for what has not been run live.

## Fast typing (0.3.4)

Browsers and Electron apps report the caret a few edits late when keys arrive quickly. 0.3.2 accepted a report at most one key late, and only after the client had been seen to follow typing; anything later discarded the active word, so the next tone key was typed as a plain letter (`tooi` stayed `tooi`). A simulated client whose reports trail by 0–4 edits lost words in 29 of 150 sessions.

The session now keeps a trail of the caret positions its own edits and the application's typed keys lead to. A report matching any of them is a late report; only a caret elsewhere ends the word. Word starts after a space, punctuation or Backspace take their position from the trail as well. A reported caret that never follows the text (over 32 unconfirmed edits) switches later words to marked text. Clicks that the client passes to the input method end the word at once. The simulated late client now matches the never-late client in every session, up to 8 edits of lag.
