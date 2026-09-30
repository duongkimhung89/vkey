# Actual UI checks, 2026-09-30, VKey 0.2.0

Typed individual key events (not pasted Unicode) with VKey selected. Test text only, local Chrome file page and an unsaved TextEdit scratch document.

PASS Chrome VNI: cha2 toi6 thay61 go4 co1 duoc975 d9au6 chu74 duoc975 chu74 mat61 → chà tôi thấy gõ có được đâu chữ được chữ mất.
PASS Chrome Telex: tooi thaays tieengs Vieetj dduwowngf Nguyeenx → tôi thấy tiếng Việt đường Nguyễn.
PASS TextEdit VNI: toi6 thay61 go4 duoc975 d9au6 → tôi thấy gõ được đâu.
PASS Chrome Backspace: toi6, Backspace, 6 → tôi.
PASS Chrome Escape: toi6, Escape → toi6.
PASS warm ABC/VKey switching, followed immediately by successful VNI composition.
PASS Chrome local dummy password smoke check: a1 produces two masked characters. Leaving the secure field and typing a1 in the ordinary textarea produces á. No real password used.

Initial cold restart after replacing the binary: some keys were passed through before the new input session was ready. A subsequent identical sentence passed. This remains a documented startup limitation.

Not tested on 0.2: Safari, Finder, Notes, VS Code, Cursor, complete Cmd+A/C/V/Z and undo behavior, full forward-delete/navigation matrix, high-speed physical typing, every secure-field implementation, network physically disconnected for GUI typing. No blanket compatibility claim.

Final preference: VNI, Vietnamese enabled. Scratch text is deliberately visible in the test host apps; this is test input placed by the operator, not logging by VKey.
