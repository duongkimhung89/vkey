import Foundation

/// The one rule behind giving typed keys back: a word that carries Vietnamese
/// marks must have a rhyme and a tone that Vietnamese spelling allows.
/// "ưindows", "uẻ" and "sờtware" do not, so those keys were not Vietnamese.
///
/// Initial consonants are not judged here.  With spell checking on, the engine
/// only places marks after an initial it accepts, highland names included
/// (Krông, Đrắk).
enum VietnameseSyllable {
    /// Every vowel form → (toneless base, tone 0...5).
    private static let vowels: [Character: (base: Character, tone: Int)] = {
        var map: [Character: (base: Character, tone: Int)] = [:]
        for forms in ["aáàảãạ", "ăắằẳẵặ", "âấầẩẫậ", "eéèẻẽẹ", "êếềểễệ", "iíìỉĩị",
                      "oóòỏõọ", "ôốồổỗộ", "ơớờởỡợ", "uúùủũụ", "ưứừửữự", "yýỳỷỹỵ"] {
            for (tone, form) in forms.enumerated() { map[form] = (forms.first!, tone) }
        }
        return map
    }()

    private static let rhymes: Set<String> = Set("""
        a e ê i o ô ơ u ư y
        ai ao au ay âu ây eo êu ia iu oa oe oi ôi ơi ua uê ui uy ưa ưi ưu uơ
        iêu yêu oai oay oao oeo uôi ươi ươu uya uyu uây oy ôy ơy
        ac ach am an ang anh ap at
        ăc ăm ăn ăng ăp ăt
        âc âm ân âng âp ât
        ec em en eng ep et
        êch êm ên ênh êp êt
        ich im in inh ip it
        oc om on ong op ot ooc oong
        ôc ôm ôn ông ôp ôt
        ơm ơn ơp ơt
        uc um un ung up ut
        ưc ưm ưn ưng ưt
        iêc iêm iên iêng iêp iêt
        yêm yên yêng yêt
        uôc uôm uôn uông uôt
        ươc ươm ươn ương ươp ươt
        oac oam oan oang oanh oach oap oat
        oăc oăm oăn oăng oăt
        oem oen oeng oet
        uân uât uâng
        uêch uênh
        uyên uyêt uynh uych uyt uyn uyp
        """.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init))

    /// `stretched` accepts a drawn-out ending ("điiii", "vânggg") as the word itself.
    static func isPossible(_ word: String, stretched: Bool = false) -> Bool {
        var letters: [Character] = []
        var tone = 0
        for character in word.lowercased().precomposedStringWithCanonicalMapping {
            guard character.isLetter else { return false }
            guard let vowel = vowels[character] else { letters.append(character); continue }
            if vowel.tone != 0 {
                guard tone == 0 else { return false }
                tone = vowel.tone
            }
            letters.append(vowel.base)
        }
        if stretched {
            while letters.count >= 2, letters[letters.count - 1] == letters[letters.count - 2] { letters.removeLast() }
        }

        // "đc", "đk", "ĐH", "HĐQT": an abbreviation has no vowel to judge by.
        guard let start = letters.firstIndex(where: { vowels[$0] != nil }) else { return true }
        let end = letters[start...].firstIndex(where: { vowels[$0] == nil }) ?? letters.count
        guard letters[end...].allSatisfy({ vowels[$0] == nil }) else { return false }
        let initial = String(letters[..<start]), nucleus = String(letters[start..<end]), final = String(letters[end...])

        // A vowel letter on its own is that letter ("chữ ă").
        if letters.count == 1 { return true }

        // Stop finals carry only sắc or nặng.  "k" is the highland spelling of
        // final "c" (Đắk, Búk) and is also written without a tone (Đăk).
        switch final {
        case "c", "ch", "p", "t": guard tone == 1 || tone == 5 else { return false }
        case "k": guard tone == 0 || tone == 1 || tone == 5 else { return false }
        default: break
        }

        var candidates = [nucleus + final]
        if initial.hasSuffix("q") {
            guard nucleus.hasPrefix("u"), nucleus.count > 1 else { return false }
            candidates.append(String(nucleus.dropFirst()) + final)      // "quá" is qu + a
        } else if initial.hasSuffix("g"), nucleus.hasPrefix("i"), nucleus.count > 1 {
            candidates.append(String(nucleus.dropFirst()) + final)      // "giữa" is gi + ưa
        }
        return candidates.contains { rhymes.contains(final == "k" ? String($0.dropLast()) + "c" : $0) }
    }
}
