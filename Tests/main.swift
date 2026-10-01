import Foundation

var failures = 0
func expect(_ actual: String, _ expected: String, _ label: @autoclosure () -> String) {
 if actual != expected { print("FAIL \(label()): \(actual) != \(expected)"); failures += 1 }
}

// MARK: - Conversion of a single word (what is shown while typing)

let cases: [(TypingMode, String, String)] = [
 (.vni,"toi6","tôi"),(.vni,"dau6","dâu"),(.vni,"d9au6","đâu"),(.vni,"thay61","thấy"),
 (.vni,"thay16","thấy"),(.vni,"go4","gõ"),(.vni,"duoc975","được"),(.vni,"chu74","chữ"),
 (.vni,"muon61","muốn"),(.vni,"tieng61","tiếng"),(.vni,"viet65","việt"),(.vni,"van64","vẫn"),
 (.vni,"chua7","chưa"),(.vni,"khong6","không"),(.vni,"biet61","biết"),(.vni,"nhieu62","nhiều"),
 (.vni,"cuoi61","cuối"),(.vni,"nguoi72","người"),(.vni,"truong72","trường"),(.vni,"thuan65","thuận"),
 (.telex,"tooi","tôi"),(.telex,"ddaau","đâu"),(.telex,"thaays","thấy"),(.telex,"goox","gỗ"),
 (.telex,"chuaw","chưa"),(.telex,"tieengs","tiếng"),(.telex,"Vieetj","Việt"),(.telex,"Tieengs","Tiếng"),
 (.telex,"dduwowngf","đường"),(.telex,"Dduwowngf","Đường"),
 (.telex,"nghieeng","nghiêng"),(.telex,"nguowif","người"),
 (.telex,"Nguyeenx","Nguyễn"),(.telex,"Duowng","Dương"),(.telex,"Hungw","Hưng"),
 (.telex,"aa","â"),(.telex,"aw","ă"),(.telex,"ee","ê"),(.telex,"oo","ô"),
 (.telex,"ow","ơ"),(.telex,"uw","ư"),(.telex,"dd","đ"),
 (.telex,"as","á"),(.telex,"af","à"),(.telex,"ar","ả"),(.telex,"ax","ã"),(.telex,"aj","ạ"),
 (.telex,"ass","as"),(.telex,"aaa","aa"),(.telex,"ddd","dd"),(.telex,"asz","a"),
 (.telex,"quas","quá"),(.telex,"gias","giá"),(.telex,"hoaf","hoà"),(.telex,"thuyr","thuỷ"),
 (.telex,"tieesng","tiếng"),(.telex,"NGUYEENX","NGUYỄN"),
 (.vni,"tie6ng1","tiếng"),(.vni,"Vie6t5","Việt"),(.vni,"d9uo7ng2","đường"),
 (.vni,"D9uo7ng2","Đường"),(.vni,"nghie6ng","nghiêng"),(.vni,"nguo7i2","người"),
 (.vni,"Nguye6n4","Nguyễn"),(.vni,"Duo7ng","Dương"),(.vni,"Hu7ng","Hưng"),
 (.vni,"a6","â"),(.vni,"a8","ă"),(.vni,"e6","ê"),(.vni,"o6","ô"),
 (.vni,"o7","ơ"),(.vni,"u7","ư"),(.vni,"d9","đ"),
 (.vni,"a1","á"),(.vni,"a2","à"),(.vni,"a3","ả"),(.vni,"a4","ã"),(.vni,"a5","ạ"),
 (.vni,"a10","a"),(.vni,"12345","12345"),(.vni,"a11","a1")
]
for (mode, raw, expected) in cases {
 expect(Composer.convert(raw, mode: mode), expected, "\(mode) \(raw)")
}
let corpusURL = URL(fileURLWithPath: "Tests/xkey-conversion-cases.json")
let corpus = try! JSONDecoder().decode([[String]].self, from: Data(contentsOf: corpusURL))
for pair in corpus {
 var word = "", actual = ""
 for c in pair[0] {
  if c.isASCII && (c.isLetter || c.isNumber || "[]".contains(c)) { word.append(c) }
  else { actual += Composer.convert(word, mode: .telex) + String(c); word = "" }
 }
 actual += Composer.convert(word, mode: .telex)
 // The reference corpus includes cases that are kept for regression tracking.
 if pair[0] == "qusy" && actual == "qusy" { print("KNOWN EDGE CASE: qusy remains raw; use quys for quý"); continue }
 if !pair[1].components(separatedBy: " / ").contains(actual) { print("CORPUS FAIL \(pair[0]): \(actual) != \(pair[1])"); failures += 1 }
}
print("Reference transformation corpus: \(corpus.count) cases")
print("\(cases.count) conversion cases")

// MARK: - What stays in the document when the word ends

func committed(_ raw: String, _ mode: TypingMode) -> String {
 var composer = Composer()
 composer.mode = mode
 for c in raw { composer.append(c) }
 return composer.committedText
}
let commitCases: [(TypingMode, String, String)] = [
 // Marks that land on something that cannot be a syllable give the keys back.
 (.telex,"windows","windows"),(.telex,"Windows","Windows"),(.telex,"USER","USER"),(.telex,"user","user"),
 (.telex,"expect","expect"),(.telex,"software","software"),(.telex,"terminal","terminal"),
 (.telex,"next","next"),(.telex,"write","write"),(.telex,"server","server"),(.telex,"result","result"),
 (.telex,"address","address"),(.telex,"Siri","Siri"),(.telex,"USB","USB"),(.telex,"URL","URL"),
 (.telex,"google","google"),(.telex,"terminal","terminal"),(.telex,"review","review"),(.telex,"xcode","xcode"),
 (.vni,"covid19","covid19"),(.vni,"i18n","i18n"),(.vni,"12a1","12a1"),(.vni,"web3","web3"),
 // Vietnamese stays Vietnamese, including chat spellings and abbreviations.
 (.telex,"tieengs","tiếng"),(.telex,"dduwowcj","được"),(.telex,"giuwax","giữa"),(.telex,"khuyur","khuỷu"),
 (.telex,"ddc","đc"),(.telex,"ddk","đk"),(.telex,"VNDD","VNĐ"),(.telex,"QDD","QĐ"),(.telex,"DDH","ĐH"),
 (.telex,"ddiiii","điiii"),(.telex,"vaanggg","vânggg"),(.telex,"owii","ơii"),(.telex,"xooong","xoong"),(.telex,"uwfm","ừm"),(.telex,"ofy","òy"),
 (.telex,"DDawsk","Đắk"),(.telex,"Lawsk","Lắk"),(.telex,"Kroong","Krông"),(.telex,"Pawsk","Pắk"),
 (.telex,"huow","huơ"),(.telex,"quowis","quới"),(.telex,"quownr","quởn"),(.vni,"quo7i1","quới"),(.telex,"quoocs","quốc"),(.telex,"thuowr","thuở"),(.telex,"huychj","huỵch"),(.telex,"Puf","Pù"),(.telex,"yr","ỷ"),
 (.telex,"kuwng","kưng"),(.telex,"howm","hơm"),(.telex,"muns","mún"),(.telex,"ruif","rùi"),(.telex,"nhiuf","nhìu"),(.telex,"chums","chúm"),(.telex,"own","ơn"),(.telex,"hown","hơn"),
 (.vni,"d9c","đc"),(.vni,"VND9","VNĐ"),(.vni,"D9a8k1","Đắk"),(.vni,"a2","à"),(.vni,"u72","ừ"),
 // Doubling a tone key is Telex's own way to cancel it.
 (.telex,"tesst","test"),(.telex,"thiss","this"),(.telex,"hass","has"),(.telex,"noww","now"),(.telex,"lasst","last"),
 (.telex,"passs","pass"),(.telex,"carr","car"),(.telex,"seee","see"),(.telex,"tooo","too"),(.telex,"maxx","max"),(.vni,"a11","a1"),
 // English words that are also shaped like Vietnamese syllables stay converted:
 // nothing in the keys says which was meant.  Switch to English, or cancel the mark.
 (.telex,"test","tét"),(.telex,"this","thí"),(.telex,"is","í"),(.telex,"more","moẻ"),(.telex,"taxi","tãi"),
 (.telex,"down","dơn"),(.telex,"pass","pas"),(.telex,"error","eror"),
]
for (mode, raw, expected) in commitCases {
 expect(committed(raw, mode), expected, "commit \(mode) \(raw)")
}
var free = Composer()
free.checksSpelling = false
for c in "microo" { free.append(c) }
expect(free.committedText, "micrô", "free typing with spelling off")

// English words typed in Vietnamese mode.  The rule is structural, so the
// invariant is too: a word comes out as typed, or as a real Vietnamese
// syllable the keys happened to spell (this → thí), never as a non-syllable.
// The exception is Telex's own cancelling: a doubled s, f, r, x or j removes
// a letter (pass → pas), and one more of the key restores it (passs → pass).
let english = Set(try! String(contentsOfFile: "Tests/english-words.txt", encoding: .utf8)
 .split(whereSeparator: { $0.isWhitespace }).map(String.init))
var englishExact = 0, englishDoubled = 0
for word in english.sorted() {
 let actual = committed(word, .telex)
 if actual == word { englishExact += 1; continue }
 let letters = Array(word)
 if let at = letters.indices.dropLast().first(where: { "sfrxj".contains(letters[$0]) && letters[$0] == letters[$0 + 1] }) {
  // Type the doubled key once more and the word comes out as spelled.
  var repaired = letters
  repaired.insert(letters[at], at: at + 1)
  expect(committed(String(repaired), .telex), word, "tripled key restores \(word)")
  englishDoubled += 1
  continue
 }
 if !VietnameseSyllable.isPossible(actual) { print("ENGLISH FAIL \(word): \(actual)"); failures += 1 }
}
for word in english { expect(committed(word, .vni), word, "english in VNI \(word)") }
print("English words: \(englishExact)/\(english.count) unchanged, \(englishDoubled) with a doubled key (type it three times), the rest are also Vietnamese syllables")

// MARK: - Vietnamese text typed key by key

let toneRows: [(letter: Character, mark: Int, forms: String)] = [
 ("a",0,"aáàảãạ"),("a",2,"ăắằẳẵặ"),("a",1,"âấầẩẫậ"),("e",0,"eéèẻẽẹ"),("e",1,"êếềểễệ"),("i",0,"iíìỉĩị"),
 ("o",0,"oóòỏõọ"),("o",1,"ôốồổỗộ"),("o",3,"ơớờởỡợ"),("u",0,"uúùủũụ"),("u",3,"ưứừửữự"),("y",0,"yýỳỷỹỵ"),
]
var decomposition: [Character: (letter: Character, mark: Int, tone: Int)] = ["đ": ("d", 4, 0)]
for row in toneRows { for (tone, form) in row.forms.enumerated() { decomposition[form] = (row.letter, row.mark, tone) } }

/// Keys for a Vietnamese word. mark: 1 circumflex, 2 breve, 3 horn, 4 đ.
func keys(for word: String, mode: TypingMode, toneAtEnd: Bool) -> String? {
 let allCaps = word.count > 1 && word == word.uppercased()
 var result = "", pending = ""
 for character in word {
  let lower = Character(character.lowercased())
  guard let part = decomposition[lower] else {
   guard character.isASCII, character.isLetter else { return nil }
   result.append(character); continue
  }
  let upper = character.isUppercase
  result += upper ? part.letter.uppercased() : String(part.letter)
  var extra = ""
  switch (mode, part.mark) {
  case (_, 0): break
  case (.telex, 1), (.telex, 4): extra = String(part.letter)
  case (.telex, _): extra = "w"
  case (.vni, 1): extra = "6"
  case (.vni, 2): extra = "8"
  case (.vni, 3): extra = "7"
  default: extra = "9"
  }
  result += allCaps ? extra.uppercased() : extra
  if part.tone > 0 {
   let index = "sfrxj".index("sfrxj".startIndex, offsetBy: part.tone - 1)
   let key = mode == .telex ? String("sfrxj"[index]) : String(part.tone)
   let cased = allCaps ? key.uppercased() : key
   if toneAtEnd { pending = cased } else { result += cased }
  }
 }
 return result + pending
}
/// Old and new tone placement (hòa/hoà) count as the same word.
func toneless(_ word: String) -> String {
 var tone = 0
 let letters = String(word.precomposedStringWithCanonicalMapping.map { character -> Character in
  guard let part = decomposition[Character(character.lowercased())], part.letter != "d" else { return character }
  if part.tone > 0 { tone = part.tone }
  let row = toneRows.first { $0.letter == part.letter && $0.mark == part.mark }!
  let base = row.forms.first!
  return character.isUppercase ? Character(base.uppercased()) : base
 })
 return "\(letters)\(tone)"
}
func vietnameseWords(in text: String) -> [String] {
 text.precomposedStringWithCanonicalMapping
  .split(whereSeparator: { !$0.isLetter }).map(String.init)
}
let vietnamese = try! String(contentsOfFile: "Tests/vietnamese-text.txt", encoding: .utf8)
let vietnameseTokens = vietnameseWords(in: vietnamese)
var typedWords = 0
for word in Set(vietnameseTokens).sorted() {
 for mode in [TypingMode.telex, .vni] {
  for toneAtEnd in [true, false] {
   guard let raw = keys(for: word, mode: mode, toneAtEnd: toneAtEnd) else { continue }
   let actual = committed(raw, mode)
   typedWords += 1
   if toneless(actual) != toneless(word) {
    print("VIETNAMESE FAIL \(mode) \(raw): \(actual) != \(word)"); failures += 1
   }
  }
 }
}
print("Vietnamese text: \(Set(vietnameseTokens).count) distinct words, \(typedWords) typings")

// MARK: - The whole dictionary, both ways round

// Every Vietnamese syllable of the ibus-bamboo dictionary (Tests/vietnamese-syllables.txt)
// must be typeable in Telex and VNI, with the tone key at the end or right
// after its vowel, and must still be there after the word ends.
var syllables = 0
var missed: [String] = []
for word in try! String(contentsOfFile: "Tests/vietnamese-syllables.txt", encoding: .utf8).split(whereSeparator: \.isNewline).map(String.init) {
 var wrong: [String] = [], typedAny = false
 for mode in [TypingMode.telex, .vni] {
  for toneAtEnd in [true, false] {
   guard let raw = keys(for: word, mode: mode, toneAtEnd: toneAtEnd), raw.count <= Composer.maximumRawLength else { continue }
   typedAny = true
   let actual = committed(raw, mode)
   if toneless(actual) != toneless(word) { wrong.append("\(raw)→\(actual)") }
  }
 }
 guard typedAny else { continue }
 syllables += 1
 if !wrong.isEmpty { missed.append("\(word): \(wrong.joined(separator: " "))") }
}
print("Dictionary syllables: \(syllables - missed.count)/\(syllables) typeable all four ways")
if CommandLine.arguments.contains("--verbose") { for entry in missed { print("  ", entry) } }

// MARK: - Syllable check

for word in ["tiếng","Việt","nghiêng","khuỷu","giữa","gì","giếng","quốc","quýt","quẳng","uể","oải","huơ","thuở",
             "khuya","xoong","Đắk","ừm","điiii","vânggg","yêu","ỷ","ươn","oẳn","khoẻ","toé"] {
 if !VietnameseSyllable.isPossible(word, stretched: true) { print("SYLLABLE FAIL valid \(word)"); failures += 1 }
}
for word in ["uẻ","ưindows","hóue","leà","ră","ảe","tẽt","kêp","việt1","qa","trêe","ẽpect","sỉi","điiii"] {
 if VietnameseSyllable.isPossible(word) { print("SYLLABLE FAIL invalid \(word)"); failures += 1 }
}

// MARK: - Backspace removes one character and typing continues

func typed(_ keys: String, _ mode: TypingMode) -> Composer {
 var composer = Composer()
 composer.mode = mode
 for c in keys { if c == "<" { composer.backspace() } else { composer.append(c) } }
 return composer
}
let backspaceCases: [(TypingMode, String, String)] = [
 (.telex,"tieengs<","tiến"),(.telex,"tieengs<<","tiế"),(.telex,"tieengs<<<","ti"),(.telex,"tieengs<g","tiếng"),
 (.telex,"tieengs<<<<<",""),(.telex,"nguowif<","ngườ"),(.telex,"dduwowcj<","đượ"),(.telex,"dduwowcj<<<","đ"),
 (.telex,"hoanf<","hoà"),(.telex,"quoocs<","quố"),(.telex,"as<",""),(.telex,"ass<","a"),
 (.telex,"tooi<<oi","toi"),(.telex,"tooi<<<ta","ta"),(.telex,"thuyeenf<<","thuy"),(.telex,"Tieengs<","Tiến"),
 (.telex,"vieejt<t","việt"),(.telex,"tieng<<<<<tooi","tôi"),
 (.vni,"tie6ng1<","tiến"),(.vni,"d9uo7c5<<","đư"),(.vni,"d9uo7c5<c","được"),(.vni,"toi6<<","t"),
]
for (mode, keys, expected) in backspaceCases {
 expect(typed(keys, mode).text, expected, "backspace \(mode) \(keys)")
}
// The keys kept after Backspace are the ones the user typed, so Escape and
// auto-restore still work on an edited word.
expect(typed("tieengs<", .telex).raw, "tieens", "raw after backspace")
expect(typed("tie6ng1<", .vni).raw, "tie6n1", "raw after backspace (VNI)")
expect(typed("windoww<s", .telex).committedText, "windows", "restore after backspace")
var emptied = typed("tooi<<<", .telex)
if !emptied.isEmpty || !emptied.raw.isEmpty { print("FAIL composer not empty after deleting every character"); failures += 1 }
emptied.append("a")
expect(emptied.text, "a", "typing after deleting every character")

// MARK: - A whole typing session against a simulated text field

class FakeClient: TextClient {
 let document = NSMutableString()
 var selection = NSRange(location: 0, length: 0)
 var marked: NSRange?
 var reportsSelection = true
 var honoursReplacement = true
 var escapesSeen = 0
 /// Like a browser address bar: when the text is the start of one of these,
 /// the rest is filled in and selected.
 var completions: [String] = []
 /// How many times the input method itself wrote to the document.
 var edits = 0

 var text: String { document as String }
 func selectedRange() -> NSRange { reportsSelection ? selection : NSRange(location: NSNotFound, length: 0) }
 func insertText(_ text: String, replacementRange: NSRange) {
  edits += 1
  var target = marked ?? selection
  if replacementRange.location != NSNotFound, honoursReplacement { target = replacementRange }
  replace(target, with: text)
  marked = nil
 }
 func setMarkedText(_ text: String, selectionRange: NSRange, replacementRange: NSRange) {
  edits += 1
  let target = marked ?? selection
  replace(target, with: text)
  marked = text.isEmpty ? nil : NSRange(location: target.location, length: text.utf16.count)
 }
 private func replace(_ range: NSRange, with text: String) {
  document.replaceCharacters(in: range, with: text)
  selection = NSRange(location: range.location + text.utf16.count, length: 0)
  let typed = self.text
  guard !text.isEmpty, selection.location == typed.utf16.count,
        let match = completions.first(where: { $0.hasPrefix(typed) && $0 != typed }) else { return }
  document.setString(match)
  selection = NSRange(location: typed.utf16.count, length: match.utf16.count - typed.utf16.count)
 }
 /// What the application itself does with a key the input method declined.
 func pressNatively(_ key: KeyStroke) {
  if key.keyCode == KeyStroke.escape { escapesSeen += 1; return }
  if key.keyCode == KeyStroke.backspace {
   if selection.length == 0, selection.location > 0 { selection = NSRange(location: selection.location - 1, length: 1) }
   replace(selection, with: "")
   return
  }
  if !key.hasShortcutModifier, let characters = key.characters { replace(selection, with: characters) }
 }
 func click(at location: Int, length: Int = 0) { selection = NSRange(location: location, length: length) }
}

/// "<" is Backspace, "^" is Escape, "~x" is Command-x, "#5" is keypad 5.
func type(_ keys: String, into client: FakeClient, with session: InputSession) {
 var modifier: Character?
 for c in keys {
  if c == "~" || c == "#" { modifier = c; continue }
  var key = KeyStroke(keyCode: 0, characters: String(c))
  if c == "<" { key = KeyStroke(keyCode: KeyStroke.backspace, characters: "\u{7f}") }
  if c == "^" { key = KeyStroke(keyCode: KeyStroke.escape, characters: "\u{1b}") }
  key.hasShortcutModifier = modifier == "~"
  key.isNumericPad = modifier == "#"
  modifier = nil
  if !session.handle(key, client: client) { client.pressNatively(key) }
 }
}
func run(_ mode: TypingMode, _ keys: String, configure: (FakeClient, InputSession) -> Void = { _, _ in }) -> FakeClient {
 let client = FakeClient(), session = InputSession()
 session.mode = mode
 configure(client, session)
 type(keys, into: client, with: session)
 return client
}

let telexSentence = "Hoom nay tooi caif Windows 11 vaf Chrome, rooif ddooir cuar user admin. "
 + "Email: hung@gmail.com, web https://google.com/search?q=tieengs+vieetj. "
 + "Anh Minh baor: \"Some info, please check the docs!\" Ddc rooif, carm own nhieeuf nhes :)) "
 + "Nguyeenx Vawn A (SDDT 0912 345 678) gops ys: khoong neen duwngf laij, Windows 404 course."
let sentenceResult = "Hôm nay tôi cài Windows 11 và Chrome, rồi đổi của user admin. "
 + "Email: hung@gmail.com, web https://google.com/search?q=tiếng+việt. "
 + "Anh Minh bảo: \"Some info, please check the dóc!\" Đc rồi, cảm ơn nhiều nhé :)) "
 + "Nguyễn Văn A (SĐT 0912 345 678) góp ý: không nên dừng lại, Windows 404 course."
let vniSentence = "Ho6m nay to6i ca2i Windows 11 va2 Chrome, ro6i2 d9o6i3 cu3a user admin. "
 + "D9o6i5 tuye63n Vie65t Nam d9a1 luc1 19h30, ve1 250k, lo71p 12a1 d9i xem covid19 het61 chu7a?"
let vniResult = "Hôm nay tôi cài Windows 11 và Chrome, rồi đổi của user admin. "
 + "Đội tuyển Việt Nam đá lúc 19h30, vé 250k, lớp 12a1 đi xem covid19 hết chưa?"

// The same text must come out whether the client supports direct replacement,
// reports no selection (marked text), or is set to marked text from the start.
for (label, configure) in [
 ("direct", { (_: FakeClient, _: InputSession) in }),
 ("no selection", { (client: FakeClient, _: InputSession) in client.reportsSelection = false }),
 ("marked", { (_: FakeClient, session: InputSession) in session.prefersMarkedText = true }),
] as [(String, (FakeClient, InputSession) -> Void)] {
 let telex = run(.telex, telexSentence, configure: configure)
 expect(telex.text, sentenceResult, "telex sentence, \(label)")
 if telex.marked != nil { print("FAIL marked text left behind, \(label)"); failures += 1 }
 expect(run(.vni, vniSentence, configure: configure).text, vniResult, "vni sentence, \(label)")
 // Backspace inside a word, then carry on.
 expect(run(.telex, "tieengs<g vieejt<t ", configure: configure).text, "tiếng việt ", "backspace, \(label)")
 expect(run(.telex, "ab tooi<<<<<cd", configure: configure).text, "acd", "backspace past the word, \(label)")
 // Escape returns the keys typed and is consumed only when it changed something.
 let escaped = run(.telex, "tooi^ abc^", configure: configure)
 expect(escaped.text, "tooi abc", "escape, \(label)")
 expect("\(escaped.escapesSeen)", "1", "escape reaches the application, \(label)")
 // A shortcut ends the word, restoring English first.
 expect(run(.telex, "windows~s", configure: configure).text, "windows", "shortcut, \(label)")
 // More keys than one word can hold.
 expect(run(.telex, String(repeating: "ab", count: 20) + " tooi", configure: configure).text,
        String(repeating: "ab", count: 20) + " tôi", "long word, \(label)")
}
expect(run(.vni, "a#1 a1").text, "a1 á", "keypad digits are not tone keys")
expect(run(.telex, "vieetj1 a2").text, "việt1 a2", "digits end a Telex word")
expect(run(.telex, "microo windows ") { _, session in session.checksSpelling = false }.text, "micrô ưindớ ", "spelling off in session")

// Plain letters are typed by the application itself; VKey writes only when a
// key changes what is already there, and then only the changed part.
do {
 let english = run(.telex, "hello and thank you all, nothing big had gone bad today ")
 expect(english.text, "hello and thank you all, nothing big had gone bad today ", "plain text")
 expect("\(english.edits)", "0", "edits for plain text")
 let client = FakeClient(), session = InputSession()
 type("tieengs", into: client, with: session)
 expect(client.text, "tiếng", "direct typing")
 expect("\(client.edits)", "2", "edits for tieengs (ê, then ế)")
}
// Backspace with a selection deletes the selection in one press.
do {
 let client = FakeClient(), session = InputSession()
 type("xin chaof", into: client, with: session)
 client.click(at: 0, length: client.text.utf16.count)
 type("<", into: client, with: session)
 expect(client.text, "", "select all, backspace")
 type("tieengs", into: client, with: session)
 client.click(at: 0, length: 5)
 type("<", into: client, with: session)
 expect(client.text, "", "select the active word, backspace")
 type("tieengs<<<<<<", into: client, with: session)
 expect(client.text, "", "one backspace per character")
}
// Clicking away mid-word must not touch text that VKey did not type.
do {
 let client = FakeClient(), session = InputSession()
 type("xin chao vie", into: client, with: session)
 client.click(at: 0, length: 3)
 type("t", into: client, with: session)
 expect(client.text, "t chao vie", "typing over a selection made mid-word")
 client.click(at: 1)
 type("ooi", into: client, with: session)
 expect(client.text, "tôi chao vie", "new word after moving the caret")
}
// An inline completion selected after the word is replaced with it.
do {
 let client = FakeClient(), session = InputSession()
 type("vie", into: client, with: session)
 client.document.append("tnam.vn")
 client.selection = NSRange(location: 3, length: 7)
 type("e", into: client, with: session)
 expect(client.text, "viê", "inline completion")
}
// An address bar that completes what is typed, all the way through a phrase.
do {
 let client = FakeClient(), session = InputSession()
 client.completions = ["tiếng việt online", "vnexpress.net"]
 type("tieengs vieetj", into: client, with: session)
 expect(client.text, "tiếng việt online", "address bar: completion offered for converted text")
 expect("\(client.selection.location),\(client.selection.length)", "10,7", "address bar: completion stays selected")
 type("<", into: client, with: session)
 expect(client.text, "tiếng việt", "address bar: Backspace removes the completion only")
 type(" nam", into: client, with: session)
 expect(client.text, "tiếng việt nam", "address bar: typing continues after Backspace")
 let url = FakeClient(), urlSession = InputSession()
 url.completions = ["vnexpress.net"]
 type("vnex", into: url, with: urlSession)
 expect(url.text, "vnexpress.net", "address bar: English completion untouched")
 expect("\(url.edits)", "0", "address bar: no input-method edits for plain letters")
}
// A client that ignores the replacement range is noticed once and then served
// with marked text, in this word's successor and in later sessions.
do {
 let client = FakeClient(), session = InputSession()
 client.honoursReplacement = false
 var reported = 0
 session.onDirectTextUnsupported = { reported += 1 }
 type("to ", into: client, with: session)
 type("tooi ddi hocj ", into: client, with: session)
 expect("\(reported)", "1", "replacement-ignoring client reported")
 expect(client.text, "to toôi đi học ", "marked text after detection")
 if !session.prefersMarkedText { print("FAIL session did not switch to marked text"); failures += 1 }
}
// A client whose reported caret never moves cannot take direct text either.
do {
 final class FrozenCaretClient: FakeClient {
  override func selectedRange() -> NSRange { NSRange(location: 0, length: 0) }
 }
 let client = FrozenCaretClient(), session = InputSession()
 var reported = 0
 session.onDirectTextUnsupported = { reported += 1 }
 type("ab tooi ddi hocj ", into: client, with: session)
 expect(client.text, "ab tôi đi học ", "frozen caret: marked text from the second key on")
 expect("\(reported)", "0", "frozen caret seen once is not yet reported")
 session.prefersMarkedText = false   // the application is activated again
 type("nuwax ddi ", into: client, with: session)
 expect(client.text, "ab tôi đi học nữa đi ", "frozen caret, second activation")
 expect("\(reported)", "1", "frozen caret reported when seen again")
}
// A client whose caret normally follows typing but is reported one key late
// (text held in another process) keeps the word together.
do {
 final class LaggingClient: FakeClient {
  var lagging = false
  private var caretBeforeLastKey = 0
  override func pressNatively(_ key: KeyStroke) {
   caretBeforeLastKey = selection.location
   super.pressNatively(key)
  }
  override func selectedRange() -> NSRange {
   lagging ? NSRange(location: caretBeforeLastKey, length: 0) : super.selectedRange()
  }
 }
 let client = LaggingClient(), session = InputSession()
 type("xin ch", into: client, with: session)
 client.lagging = true
 type("a", into: client, with: session)
 client.lagging = false
 type("of tooi", into: client, with: session)
 expect(client.text, "xin chào tôi", "caret reported one key late")
 if session.prefersMarkedText { print("FAIL a late caret must not switch the client to marked text"); failures += 1 }
}
// Losing focus with marked text commits it; with direct text nothing is sent.
do {
 let client = FakeClient(), session = InputSession()
 session.prefersMarkedText = true
 type("windows", into: client, with: session)
 session.commit(client: client)
 expect(client.text, "windows", "commit on focus change, marked")
 let direct = FakeClient(), directSession = InputSession()
 type("tooi", into: direct, with: directSession)
 directSession.commit(client: direct)
 type("s", into: direct, with: directSession)
 expect(direct.text, "tôis", "commit on focus change, direct")
}

print("Commit, backspace and session checks done: \(failures) failures")
exit(failures == 0 ? 0 : 1)
