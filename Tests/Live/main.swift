// Live check of the installed input method.
//
// Opens a window with real AppKit and WebKit text views, selects VKey, and
// presses keys the way a keyboard does: as system key events, which macOS
// routes through the selected input method before the application sees them.
// (Events created inside the application bypass the input method, so they
// cannot test it.)  Posting key events needs the Accessibility permission for
// VKeyLiveTest.app; the first run asks for it.
//
// Keys go to whichever application is frontmost, so every key is sent only
// while this window has keyboard focus, and the run stops if it loses it.
import AppKit
import Carbon
import WebKit

let keyCodes: [Character: UInt16] = [
 "a":0,"s":1,"d":2,"f":3,"h":4,"g":5,"z":6,"x":7,"c":8,"v":9,"b":11,"q":12,"w":13,"e":14,"r":15,"y":16,"t":17,
 "1":18,"2":19,"3":20,"4":21,"6":22,"5":23,"9":25,"7":26,"8":28,"0":29,"o":31,"u":32,"i":34,"p":35,"l":37,"j":38,
 "k":40,",":43,"n":45,"m":46,".":47," ":49,"\n":36,
]

func source(_ id: String) -> TISInputSource? {
 let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
 return (TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource])?.first
}
func spin(_ seconds: TimeInterval) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }

let preferences = UserDefaults(suiteName: "local.vkey.inputmethod")!
let savedPreferences = ["TypingMode", "VietnameseEnabled"].map { ($0, preferences.object(forKey: $0)) }
let savedSource = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
func restore() {
 for (key, value) in savedPreferences { preferences.set(value, forKey: key) }
 preferences.synchronize()
 TISSelectInputSource(savedSource)
}
// Put the user's input source and settings back however the run ends.
atexit { restore() }
for number in [SIGINT, SIGTERM, SIGPIPE, SIGHUP] { signal(number) { _ in exit(3) } }
func setMode(_ mode: String) {
 preferences.set(mode, forKey: "TypingMode")
 preferences.set(true, forKey: "VietnameseEnabled")
 preferences.synchronize()
 spin(1.0)
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 640, height: 420),
                      styleMask: [.titled], backing: .buffered, defer: false)
window.title = "VKey live test — đừng gõ vào đây"
let textView = NSTextView(frame: NSRect(x: 10, y: 250, width: 620, height: 160))
textView.isAutomaticSpellingCorrectionEnabled = false
textView.isAutomaticTextCompletionEnabled = false
textView.isAutomaticQuoteSubstitutionEnabled = false
textView.isAutomaticDashSubstitutionEnabled = false
let field = NSTextField(frame: NSRect(x: 10, y: 210, width: 620, height: 24))
let web = WKWebView(frame: NSRect(x: 10, y: 10, width: 620, height: 190))
window.contentView?.addSubview(textView)
window.contentView?.addSubview(field)
window.contentView?.addSubview(web)
web.loadHTMLString("<textarea id=t rows=4 cols=60></textarea><br><input id=i size=60><div id=e contenteditable style='border:1px solid;min-height:20px'></div>", baseURL: nil)
window.makeKeyAndOrderFront(nil)
app.activate(ignoringOtherApps: true)
spin(1.0)

guard let vkey = source("local.inputmethod.VKey"), TISSelectInputSource(vkey) == noErr else {
 print("VKey is not an enabled input source; add it in System Settings → Keyboard → Text Input.")
 exit(2)
}
spin(1.0)
window.makeFirstResponder(textView)
spin(0.3)
func currentSourceID() -> String {
 let current = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
 guard let pointer = TISGetInputSourceProperty(current, kTISPropertyInputSourceID) else { return "?" }
 return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
}
print("active: \(app.isActive), key window: \(window.isKeyWindow), input source: \(currentSourceID()), "
      + "context source: \(textView.inputContext?.selectedKeyboardInputSource ?? "none")")

guard CGPreflightPostEventAccess() else {
 CGRequestPostEventAccess()
 print("VKeyLiveTest needs permission to press keys: System Settings → Privacy & Security → Accessibility → "
       + "enable VKeyLiveTest (build/VKeyLiveTest.app), then run scripts/live-test.sh again.")
 exit(2)
}

var keysSent = 0
/// "<" is Backspace, "^" is Escape; capitals are typed with Shift.
func type(_ keys: String, pause: TimeInterval) {
 let eventSource = CGEventSource(stateID: .hidSystemState)
 for c in keys {
  var code: UInt16, shift = false
  switch c {
  case "<": code = 51
  case "^": code = 53
  default:
   guard let mapped = keyCodes[Character(c.lowercased())] else { fatalError("no key for \(c)") }
   code = mapped
   shift = c.isUppercase
  }
  guard app.isActive, window.isKeyWindow else {
   print("The test window lost keyboard focus; stopping so that no key reaches another application.")
   exit(4)
  }
  for keyDown in [true, false] {
   guard let event = CGEvent(keyboardEventSource: eventSource, virtualKey: code, keyDown: keyDown) else { continue }
   event.flags = shift ? .maskShift : []
   event.post(tap: .cghidEventTap)
  }
  keysSent += 1
  spin(pause)
 }
}

var failures = 0, checks = 0
func check(_ label: String, _ actual: String, _ expected: String) {
 checks += 1
 if actual == expected { print("PASS \(label)") } else { failures += 1; print("FAIL \(label)\n     got: \(actual)\n  wanted: \(expected)") }
}

func javascript(_ script: String) -> String {
 var result: String?
 web.evaluateJavaScript(script) { value, _ in result = (value as? String) ?? "" }
 while result == nil { spin(0.01) }
 return result!
}

/// One place text can be typed into.
struct Target {
 let name: String
 let focus: () -> Void
 let clear: () -> Void
 let text: () -> String
 let pause: TimeInterval
}
let targets = [
 Target(name: "NSTextView", focus: { window.makeFirstResponder(textView) },
        clear: { textView.string = ""; textView.inputContext?.discardMarkedText() },
        text: { textView.string }, pause: 0.03),
 Target(name: "NSTextView, fast typing", focus: { window.makeFirstResponder(textView) },
        clear: { textView.string = ""; textView.inputContext?.discardMarkedText() },
        text: { textView.string }, pause: 0.012),
 Target(name: "NSTextField", focus: { window.makeFirstResponder(field) },
        clear: { field.stringValue = ""; window.makeFirstResponder(nil); window.makeFirstResponder(field) },
        text: { field.stringValue }, pause: 0.03),
 Target(name: "WebKit textarea", focus: { window.makeFirstResponder(web); _ = javascript("t.focus(); ''") },
        clear: { _ = javascript("t.value = ''; t.focus(); ''") },
        text: { javascript("t.value") }, pause: 0.03),
 Target(name: "WebKit input", focus: { window.makeFirstResponder(web); _ = javascript("i.focus(); ''") },
        clear: { _ = javascript("i.value = ''; i.focus(); ''") },
        text: { javascript("i.value") }, pause: 0.03),
 Target(name: "WebKit contenteditable", focus: { window.makeFirstResponder(web); _ = javascript("e.focus(); ''") },
        clear: { _ = javascript("e.textContent = ''; e.focus(); ''") },
        text: { javascript("e.textContent").replacingOccurrences(of: "\u{a0}", with: " ") }, pause: 0.03),
]

let telex: [(String, String, String)] = [
 ("sentence", "Hoom nay tooi caif Windows 11 vaf Chrome, rooif ddooir password cuar user admin. ",
  "Hôm nay tôi cài Windows 11 và Chrome, rồi đổi password của user admin. "),
 ("mixed", "Tieengs Vieetj raats giauf ddepj, more info is here, down town. ",
  "Tiếng Việt rất giàu đẹp, more info is here, down town. "),
 ("names", "Nguyeenx Vawn Huwng owr Thuaanj Thanhf, Bawcs Ninh. ", "Nguyễn Văn Hưng ở Thuận Thành, Bắc Ninh. "),
 ("backspace one character", "tieengs<g vieejt<t ", "tiếng việt "),
 ("backspace through word", "ab dduwowngf<<<<<<<cd", "acd"),
 ("backspace then retype", "nguowif<<<oi ", "ngoi "),
 ("escape", "tooi^ ", "tooi "),
 ("double key", "tesst pass off error ", "test pass off error "),
 ("chat", "ddc roofi, camr own nhes, ddiiii ", "đc rồi, cảm ơn nhé, điiii "),
 ("uppercase", "VIEETJ NAM, DDAOF TAOJ ", "VIỆT NAM, ĐÀO TẠO "),
 ("newline", "xin chaof\ncacs banj ", "xin chào\ncác bạn "),
]
let vni: [(String, String, String)] = [
 ("sentence", "Ho6m nay to6i ca2i Windows 11 va2 Chrome, ro6i2 d9o6i3 password cu3a user admin. ",
  "Hôm nay tôi cài Windows 11 và Chrome, rồi đổi password của user admin. "),
 ("numbers", "lo71p 12a1 luc1 19h30, ve1 250k, covid19 ", "lớp 12a1 lúc 19h30, vé 250k, covid19 "),
 ("backspace", "tie6ng1<g d9uo7c5<c ", "tiếng được "),
]

if let keys = ProcessInfo.processInfo.environment["LIVE_KEYS"] {
 // Ad-hoc probe in whatever mode is set: type these keys and print the result.
 window.makeFirstResponder(textView)
 type(keys, pause: 0.05)
 spin(0.3)
 print("typed \(keys) → \(textView.string)")
 exit(0)
}
let only = ProcessInfo.processInfo.environment["LIVE_ONLY"]
for target in targets where only == nil || target.name == only {
 target.focus()
 spin(0.3)
 for (mode, cases) in [("telex", telex), ("vni", vni)] {
  setMode(mode)
  for (label, keys, expected) in cases {
   if label == "newline", target.name.contains("Field") || target.name.contains("input") { continue }
   target.clear()
   spin(0.1)
   type(keys, pause: target.pause)
   spin(0.2)
   check("\(target.name) / \(mode) / \(label)", target.text(), expected)
  }
 }
}

// Select everything and press Backspace once.
setMode("telex")
window.makeFirstResponder(textView)
textView.string = ""
type("xin chaof cacs banj", pause: 0.03)
textView.selectAll(nil)
type("<", pause: 0.05)
check("NSTextView / select all, one Backspace", textView.string, "")
// Click in the middle of a word being typed, then carry on typing.
textView.string = ""
type("xin chao vie", pause: 0.03)
textView.setSelectedRange(NSRange(location: 0, length: 3))
type("t", pause: 0.05)
check("NSTextView / type over a selection made mid-word", textView.string, "t chao vie")

restore()
print("\(keysSent) keys pressed")
print("\(checks - failures)/\(checks) live checks passed")
exit(failures == 0 ? 0 : 1)
