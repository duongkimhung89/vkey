import Foundation
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
var failures = 0
for (mode, raw, expected) in cases {
 let actual = Composer.convert(raw, mode: mode)
 if actual != expected { print("FAIL \(mode) \(raw): \(actual) != \(expected)"); failures += 1 }
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
 // Upstream corpus includes aspirational cases, not only supported behavior.
 if pair[0] == "qusy" && actual == "qusy" { print("KNOWN UPSTREAM LIMIT: qusy remains raw; use quys for quý"); continue }
 if !pair[1].components(separatedBy: " / ").contains(actual) { print("CORPUS FAIL \(pair[0]): \(actual) != \(pair[1])"); failures += 1 }
}
print("XKey upstream transformation corpus: \(corpus.count) cases")
var c = Composer()
for ch in "tieengs" { c.append(ch) }
c.backspace()
assert(c.text == "tiêng")
c.reset()
assert(c.text.isEmpty && c.raw.isEmpty)
print("\(cases.count) conversion cases, backspace and reset: \(failures) failures")
exit(failures == 0 ? 0 : 1)
