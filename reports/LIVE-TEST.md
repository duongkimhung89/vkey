# VKeyLiveTest verification — 2026-10-01

Environment: macOS 27.0.1 (26A434), Apple Silicon, installed VKey 0.3.4 (build 13).
The existing Accessibility permission was sufficient; no permissions or security settings were changed.

Two test-harness fixes:

- `spin` now retrieves and dispatches queued AppKit events. Previously it only ran `RunLoop`, leaving key events unprocessed and incorrectly reporting that macOS delivered none. Keys still originate as system CGEvents and pass through the installed input method.
- The contenteditable reader uses `innerText` to preserve visible line breaks produced by Enter. `textContent` concatenated the block elements and caused a false failure.

Verification:

- Before fixes: `./scripts/live-test.sh` stopped after the first posted key, with no checks run.
- After event dispatch fix: `LIVE_ONLY='NSTextView' ./scripts/live-test.sh` passed 19/19 checks.
- Full run after event dispatch fix: `./scripts/live-test.sh` passed 101/102 checks, posting 4,145 keys. The remaining failure was the contenteditable line-break reader.
- After fixing that reader: `LIVE_ONLY='WebKit contenteditable' ./scripts/live-test.sh` passed 19/19 checks, posting 725 keys.
- Combined latest results: all 102 distinct checks passed. This combines the full run with the affected target rerun; it is not a claim that a second full run was performed.
- `./scripts/test.sh`: 0 failures, including 200/200 simulated late-caret sessions.

Coverage includes NSTextView, fast NSTextView typing, NSTextField, WebKit textarea/input/contenteditable, Telex/VNI, Backspace, Escape, uppercase, brackets, line breaks, fast sentences, and selection edits. This does not establish separate Safari, Chrome, Terminal, or VS Code application compatibility.

## Full run before the contenteditable reader fix

```text
2026-10-01 10:43:54.014 VKeyLiveTest[2609:39530] error messaging the mach port for IMKCFRunLoopWakeUpReliable
frontmost: local.vkey.livetest, active: true, key window: true, input source: local.inputmethod.VKey, context source: local.inputmethod.VKey
PASS NSTextView / telex / sentence
PASS NSTextView / telex / mixed
PASS NSTextView / telex / names
PASS NSTextView / telex / backspace one character
PASS NSTextView / telex / backspace through word
PASS NSTextView / telex / backspace then retype
PASS NSTextView / telex / escape
PASS NSTextView / telex / double key
PASS NSTextView / telex / brackets
PASS NSTextView / telex / chat
PASS NSTextView / telex / uppercase
PASS NSTextView / telex / newline
PASS NSTextView / vni / sentence
PASS NSTextView / vni / numbers
PASS NSTextView / vni / backspace
PASS NSTextView / telex / fast sentence
PASS NSTextView / vni / fast sentence
PASS NSTextView, fast typing / telex / sentence
PASS NSTextView, fast typing / telex / mixed
PASS NSTextView, fast typing / telex / names
PASS NSTextView, fast typing / telex / backspace one character
PASS NSTextView, fast typing / telex / backspace through word
PASS NSTextView, fast typing / telex / backspace then retype
PASS NSTextView, fast typing / telex / escape
PASS NSTextView, fast typing / telex / double key
PASS NSTextView, fast typing / telex / brackets
PASS NSTextView, fast typing / telex / chat
PASS NSTextView, fast typing / telex / uppercase
PASS NSTextView, fast typing / telex / newline
PASS NSTextView, fast typing / vni / sentence
PASS NSTextView, fast typing / vni / numbers
PASS NSTextView, fast typing / vni / backspace
PASS NSTextView, fast typing / telex / fast sentence
PASS NSTextView, fast typing / vni / fast sentence
PASS NSTextField / telex / sentence
PASS NSTextField / telex / mixed
PASS NSTextField / telex / names
PASS NSTextField / telex / backspace one character
PASS NSTextField / telex / backspace through word
PASS NSTextField / telex / backspace then retype
PASS NSTextField / telex / escape
PASS NSTextField / telex / double key
PASS NSTextField / telex / brackets
PASS NSTextField / telex / chat
PASS NSTextField / telex / uppercase
PASS NSTextField / vni / sentence
PASS NSTextField / vni / numbers
PASS NSTextField / vni / backspace
PASS NSTextField / telex / fast sentence
PASS NSTextField / vni / fast sentence
PASS WebKit textarea / telex / sentence
PASS WebKit textarea / telex / mixed
PASS WebKit textarea / telex / names
PASS WebKit textarea / telex / backspace one character
PASS WebKit textarea / telex / backspace through word
PASS WebKit textarea / telex / backspace then retype
PASS WebKit textarea / telex / escape
PASS WebKit textarea / telex / double key
PASS WebKit textarea / telex / brackets
PASS WebKit textarea / telex / chat
PASS WebKit textarea / telex / uppercase
PASS WebKit textarea / telex / newline
PASS WebKit textarea / vni / sentence
PASS WebKit textarea / vni / numbers
PASS WebKit textarea / vni / backspace
PASS WebKit textarea / telex / fast sentence
PASS WebKit textarea / vni / fast sentence
PASS WebKit input / telex / sentence
PASS WebKit input / telex / mixed
PASS WebKit input / telex / names
PASS WebKit input / telex / backspace one character
PASS WebKit input / telex / backspace through word
PASS WebKit input / telex / backspace then retype
PASS WebKit input / telex / escape
PASS WebKit input / telex / double key
PASS WebKit input / telex / brackets
PASS WebKit input / telex / chat
PASS WebKit input / telex / uppercase
PASS WebKit input / vni / sentence
PASS WebKit input / vni / numbers
PASS WebKit input / vni / backspace
PASS WebKit input / telex / fast sentence
PASS WebKit input / vni / fast sentence
PASS WebKit contenteditable / telex / sentence
PASS WebKit contenteditable / telex / mixed
PASS WebKit contenteditable / telex / names
PASS WebKit contenteditable / telex / backspace one character
PASS WebKit contenteditable / telex / backspace through word
PASS WebKit contenteditable / telex / backspace then retype
PASS WebKit contenteditable / telex / escape
PASS WebKit contenteditable / telex / double key
PASS WebKit contenteditable / telex / brackets
PASS WebKit contenteditable / telex / chat
PASS WebKit contenteditable / telex / uppercase
FAIL WebKit contenteditable / telex / newline
     got: xin chàocác bạn 
  wanted: xin chào
các bạn 
PASS WebKit contenteditable / vni / sentence
PASS WebKit contenteditable / vni / numbers
PASS WebKit contenteditable / vni / backspace
PASS WebKit contenteditable / telex / fast sentence
PASS WebKit contenteditable / vni / fast sentence
PASS NSTextView / select all, one Backspace
PASS NSTextView / type over a selection made mid-word
4145 keys pressed
101/102 live checks passed
```

## Affected target rerun after both fixes

```text
2026-10-01 10:46:55.036 VKeyLiveTest[2767:42126] error messaging the mach port for IMKCFRunLoopWakeUpReliable
frontmost: local.vkey.livetest, active: true, key window: true, input source: local.inputmethod.VKey, context source: local.inputmethod.VKey
PASS WebKit contenteditable / telex / sentence
PASS WebKit contenteditable / telex / mixed
PASS WebKit contenteditable / telex / names
PASS WebKit contenteditable / telex / backspace one character
PASS WebKit contenteditable / telex / backspace through word
PASS WebKit contenteditable / telex / backspace then retype
PASS WebKit contenteditable / telex / escape
PASS WebKit contenteditable / telex / double key
PASS WebKit contenteditable / telex / brackets
PASS WebKit contenteditable / telex / chat
PASS WebKit contenteditable / telex / uppercase
PASS WebKit contenteditable / telex / newline
PASS WebKit contenteditable / vni / sentence
PASS WebKit contenteditable / vni / numbers
PASS WebKit contenteditable / vni / backspace
PASS WebKit contenteditable / telex / fast sentence
PASS WebKit contenteditable / vni / fast sentence
PASS NSTextView / select all, one Backspace
PASS NSTextView / type over a selection made mid-word
725 keys pressed
19/19 live checks passed
```
