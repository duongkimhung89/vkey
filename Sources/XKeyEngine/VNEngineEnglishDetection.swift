// Adapted from XKey, copyright (c) 2025 XKey (MIT). See Resources/Licenses and THIRD_PARTY_NOTICES.md.
// Modified 2026-09-30: no logging callbacks; engine core only, no host integration.
//
//  VNEngineEnglishDetection.swift
//  XKey
//
//  English word detection for spell checking optimization
//

import Foundation

// MARK: - Fast English Detection (for spell check optimization)

extension String {
    
    // ============================================
    // MARK: - Static Lookup Tables for Performance
    // ============================================
    
    /// Characters that NEVER start a Vietnamese word
    /// Vietnamese alphabet does not include: f, j, w, z
    /// Any word starting with these is 100% NOT Vietnamese
    private static let impossibleStartingChars: Set<Character> = ["f", "j", "w", "z"]
    
    // ============================================
    // MARK: - Valid Vietnamese Input Sequences (Telex & VNI)
    // ============================================
    // These patterns are VALID input sequences that produce Vietnamese characters
    // They should NOT be flagged as "impossible" patterns
    //
    // TELEX INPUT METHOD:
    // ┌─────────┬─────────┬────────────────────────────────────┐
    // │ Input   │ Output  │ Notes                              │
    // ├─────────┼─────────┼────────────────────────────────────┤
    // │ dd      │ đ       │ Valid at word start (đi, đến, đã)  │
    // │ aa      │ â       │ Vowel modifier (cân, tâm)          │
    // │ ee      │ ê       │ Vowel modifier (kê, đê)            │
    // │ oo      │ ô       │ Vowel modifier (cô, hô)            │
    // │ aw      │ ă       │ Vowel modifier (bắt, ăn)           │
    // │ ow      │ ơ       │ Vowel modifier (cơ, mơ)            │
    // │ uw      │ ư       │ Vowel modifier (cư, tư)            │
    // │ w       │ ư       │ Standalone ư                       │
    // │ [       │ ơ       │ Bracket for ơ                      │
    // │ ]       │ ư       │ Bracket for ư                      │
    // └─────────┴─────────┴────────────────────────────────────┘
    //
    // VNI INPUT METHOD:
    // ┌─────────┬─────────┬────────────────────────────────────┐
    // │ Input   │ Output  │ Notes                              │
    // ├─────────┼─────────┼────────────────────────────────────┤
    // │ d9      │ đ       │ Valid at word start (đi, đến, đã)  │
    // │ a6      │ â       │ Vowel + 6 = circumflex (^)         │
    // │ e6      │ ê       │ Vowel + 6 = circumflex (^)         │
    // │ o6      │ ô       │ Vowel + 6 = circumflex (^)         │
    // │ a8      │ ă       │ Vowel + 8 = breve (˘)              │
    // │ o7      │ ơ       │ Vowel + 7 = horn (ơ, ư)            │
    // │ u7      │ ư       │ Vowel + 7 = horn (ơ, ư)            │
    // │ 1-5     │ tones   │ Tone marks after vowels            │
    // └─────────┴─────────┴────────────────────────────────────┘
    //
    // QUICK TELEX (when vQuickTelex = 1):
    // ┌─────────┬─────────┬────────────────────────────────────┐
    // │ Input   │ Output  │ Notes                              │
    // ├─────────┼─────────┼────────────────────────────────────┤
    // │ cc      │ ch      │ Quick consonant (chào, chính)      │
    // │ gg      │ gi      │ Quick consonant (giá, giúp)        │
    // │ kk      │ kh      │ Quick consonant (không, khác)      │
    // │ nn      │ ng      │ Quick consonant (người, ngày)      │
    // │ qq      │ qu      │ Quick consonant (quá, quên)        │
    // │ pp      │ ph      │ Quick consonant (phải, phong)      │
    // │ tt      │ th      │ Quick consonant (thì, thế)         │
    // └─────────┴─────────┴────────────────────────────────────┘
    //
    // IMPORTANT: "dd", "d9", and Quick Telex patterns are VALID starting sequences!
    // They should be EXCLUDED from impossible patterns.
    
    /// Valid 2-letter starting patterns for TELEX input method
    /// These produce valid Vietnamese characters and should NOT be blocked
    /// Includes: dd → đ, and Quick Telex patterns (cc, gg, kk, nn, qq, pp, tt)
    private static let validTelexStartingPatterns: Set<String> = [
        // Standard Telex
        "dd",  // dd → đ (đi, đến, đã, đây, đó, đang, được, đầu, đề)
        
        // Quick Telex (double consonants at word start)
        "cc",  // cc → ch (chào, chính, cho, chúng)
        "gg",  // gg → gi (giá, giúp, gì, giờ)
        "kk",  // kk → kh (không, khác, khi, khó)
        "nn",  // nn → ng (người, ngày, nghĩ, nghe)
        "qq",  // qq → qu (quá, quên, quốc, quen)
        "pp",  // pp → ph (phải, phong, phố, phim)
        "tt",  // tt → th (thì, thế, thành, theo)
    ]
    
    /// Valid 2-letter starting patterns for VNI input method
    /// These produce valid Vietnamese characters and should NOT be blocked
    private static let validVNIStartingPatterns: Set<String> = [
        "d9",  // d9 → đ (đi, đến, đã, đây, đó, đang, được, đầu, đề)
    ]
    
    /// Combined valid starting patterns for any input method
    /// Use this when input type is unknown or to be safe
    private static let allValidInputStartingPatterns: Set<String> = [
        // Telex patterns
        "dd",  // đ
        "cc",  // ch (Quick Telex)
        "gg",  // gi (Quick Telex)
        "kk",  // kh (Quick Telex)
        "nn",  // ng (Quick Telex)
        "qq",  // qu (Quick Telex)
        "pp",  // ph (Quick Telex)
        "tt",  // th (Quick Telex)
        // VNI patterns
        "d9",  // đ
    ]
    
    /// Set of 2-letter initial clusters that are IMPOSSIBLE in Vietnamese
    /// Vietnamese valid initials: b, c, ch, d, đ, g, gh, gi, h, k, kh, l, m, n,
    ///                           ng, ngh, nh, p, ph, qu, r, s, t, th, tr, v, x
    private static let impossible2LetterPrefixes: Set<String> = [
        // ========================================
        // L-clusters (consonant + L) - Vietnamese NEVER has these
        // ========================================
        "bl", "cl", "dl", "fl", "gl", "hl", "jl", "kl", "ml", "nl",
        "pl", "rl", "sl", "tl", "vl", "wl", "xl", "yl", "zl",
        
        // ========================================
        // R-clusters (consonant + R) - Vietnamese only has "tr", exclude it
        // NOTE: "yr" is EXCLUDED because 'y' is a vowel in Vietnamese, not a consonant
        // NOTE: "kr" is EXCLUDED for ethnic-minority place names (Krông Ana/Búk/Pắc)
        // ========================================
        "br", "cr", "dr", "fr", "gr", "hr", "jr", "lr", "mr", "nr",
        "pr", "rr", "sr", "vr", "wr", "xr", "zr",
        
        // ========================================
        // S-clusters - Vietnamese doesn't start with S + consonant
        // ========================================
        "sb", "sc", "sd", "sf", "sg", "sh", "sj", "sk", "sl", "sm",
        "sn", "sp", "sq", "sr", "ss", "st", "sv", "sw", "sx", "sz",
        
        // ========================================
        // W-clusters - ALL w + letter (Vietnamese NEVER uses 'w')
        // ========================================
        "wa", "wb", "wc", "wd", "we", "wf", "wg", "wh", "wi", "wj",
        "wk", "wl", "wm", "wn", "wo", "wp", "wq", "wr", "ws", "wt",
        "wu", "wv", "ww", "wx", "wy", "wz",
        
        // ========================================
        // F-clusters - ALL f + letter (Vietnamese NEVER uses 'f')
        // ========================================
        "fa", "fb", "fc", "fd", "fe", "ff", "fg", "fh", "fi", "fj",
        "fk", "fl", "fm", "fn", "fo", "fp", "fq", "fr", "fs", "ft",
        "fu", "fv", "fw", "fx", "fy", "fz",
        
        // ========================================
        // J-clusters - ALL j + letter (Vietnamese NEVER uses 'j')
        // ========================================
        "ja", "jb", "jc", "jd", "je", "jf", "jg", "jh", "ji", "jj",
        "jk", "jl", "jm", "jn", "jo", "jp", "jq", "jr", "js", "jt",
        "ju", "jv", "jw", "jx", "jy", "jz",
        
        // ========================================
        // Z-clusters - ALL z + letter (Vietnamese NEVER uses 'z')
        // ========================================
        "za", "zb", "zc", "zd", "ze", "zf", "zg", "zh", "zi", "zj",
        "zk", "zl", "zm", "zn", "zo", "zp", "zq", "zr", "zs", "zt",
        "zu", "zv", "zw", "zx", "zy", "zz",
        
        // ========================================
        // Other consonant + W clusters (except valid qu)
        // NOTE: In Telex/Simple Telex, consonant + w CAN produce valid "Xư" patterns
        //       (e.g., "hw" → "hư", "bw" → "bư", etc.)
        //       These patterns are SKIPPED when inputType is Telex (0, 2, 3)
        //       See consonantWClusters set below for the skip logic.
        // ========================================
        "bw", "cw", "dw", "gw", "hw", "kw", "lw", "mw", "nw", "pw",
        "rw", "sw", "tw", "vw", "xw", "yw",

        
        // ========================================
        // Silent letter patterns and other impossible starts
        // ========================================
        "gn", "kn", "pn", "ps", "pt", "pf", "ks", "ts", "tz",
        
        // ========================================
        // Double consonants at start (Vietnamese never has)
        // EXCEPT: The following are EXCLUDED because they are valid Telex input:
        // - "dd" → đ (standard Telex)
        // - "cc" → ch, "gg" → gi, "kk" → kh, "nn" → ng, "pp" → ph, "tt" → th (Quick Telex)
        // - "qq" → qu (Quick Telex)
        // These are now in validTelexStartingPatterns and handled by isValidVietnameseInputSequence
        // ========================================
        "bb", "ff", "hh", "jj",
        "ll", "mm", "rr", "ss", "vv", "ww", "xx", "zz",
        
        // ========================================
        // Other invalid consonant combinations
        // ========================================
        // B + consonant (except bl, br which are above)
        "bc", "bd", "bf", "bg", "bh", "bj", "bk", "bm", "bn", "bp", "bq", "bs", "bt", "bv", "bx", "by", "bz",
        // C + consonant (except ch, cl, cr - ch is valid Vietnamese, cl/cr are above)
        "cb", "cd", "cf", "cg", "cj", "ck", "cm", "cn", "cp", "cq", "cs", "ct", "cv", "cx", "cy", "cz",
        // D + consonant (except dr, dw which are above)
        "db", "dc", "df", "dg", "dh", "dj", "dk", "dm", "dn", "dp", "dq", "ds", "dt", "dv", "dx", "dy", "dz",
        // G + consonant (except gh, gi, gl, gr - gh/gi are valid Vietnamese, gl/gr are above)
        "gb", "gc", "gd", "gf", "gj", "gk", "gm", "gp", "gq", "gs", "gt", "gv", "gx", "gy", "gz",
        // H + consonant, hỷ
        "hb", "hc", "hd", "hf", "hg", "hj", "hk", "hl", "hm", "hn", "hp", "hq", "hr", "hs", "ht", "hv", "hx", "hz",
        // K + consonant (except kh - kh is valid Vietnamese)
        // NOTE: "ky" is EXCLUDED because 'y' is a vowel in Vietnamese (e.g., "ký")
        "kb", "kc", "kd", "kf", "kg", "kj", "kk", "kl", "km", "kp", "kq", "ks", "kt", "kv", "kx", "kz",
        // L + consonant
        // NOTE: "ly" is EXCLUDED because 'y' is a vowel in Vietnamese (e.g., "lý")
        "lb", "lc", "ld", "lf", "lg", "lh", "lj", "lk", "lm", "ln", "lp", "lq", "lr", "ls", "lt", "lv", "lx", "lz",
        // M + consonant
        // NOTE: "my" is EXCLUDED because 'y' is a vowel in Vietnamese (e.g., "mỹ")
        "mb", "mc", "md", "mf", "mg", "mh", "mj", "mk", "ml", "mn", "mp", "mq", "mr", "ms", "mt", "mv", "mx", "mz",
        // N + consonant (except ng, nh - these are valid Vietnamese)
        // NOTE: "ny" is EXCLUDED because 'y' is a vowel in Vietnamese
        "nb", "nc", "nd", "nf", "nj", "nk", "nl", "nm", "np", "nq", "nr", "ns", "nt", "nv", "nx", "nz",
        // P + consonant (except ph, pl, pr - ph is valid Vietnamese, pl/pr are above)
        "pb", "pc", "pd", "pg", "pj", "pk", "pm", "pp", "pq", "pv", "px", "py", "pz",
        // R + consonant
        "rb", "rc", "rd", "rf", "rg", "rh", "rj", "rk", "rl", "rm", "rn", "rp", "rq", "rs", "rt", "rv", "rx", "rz",
        // T + consonant (except th, tr - these are valid Vietnamese)
        // NOTE: "ty" is EXCLUDED because 'y' is a vowel in Vietnamese (e.g., "tỷ")
        "tb", "tc", "td", "tf", "tg", "tj", "tk", "tl", "tm", "tn", "tp", "tq", "ts", "tv", "tx", "tz",
        // V + consonant
        // NOTE: "vy" is EXCLUDED because 'y' is a vowel in Vietnamese
        "vb", "vc", "vd", "vf", "vg", "vh", "vj", "vk", "vl", "vm", "vn", "vp", "vq", "vs", "vt", "vv", "vx", "vz",
        // X + consonant
        // NOTE: "xy" is EXCLUDED because 'y' is a vowel in Vietnamese
        "xb", "xc", "xd", "xf", "xg", "xh", "xj", "xk", "xl", "xm", "xn", "xp", "xq", "xs", "xt", "xv", "xx", "xz",
        
        // ========================================
        // VOWEL PATTERNS - Impossible in Vietnamese
        // These catch common English words like year, you, your, our, ear
        // Vietnamese 'y' only combines with 'ê' (yêu, yên, yếm, yểng)
        // ========================================
        // Y + vowel (except yê which is valid Vietnamese)
        "yo",  // you, your, yolk, yoga → Vietnamese has NO "yo-" words
        "ya",  // yard, yank, yarn, yang → Vietnamese has NO "ya-" words
        "yi",  // yield, yikes, yin → Vietnamese has NO "yi-" words
        "yu",  // yummy, yurt, yuan → Vietnamese has NO "yu-" words
        // O + u (English "ou" sound) → Vietnamese has NO "ou-" words
        "ou",  // our, out, ounce, outer
        // E + a (English "ea" sound) → Vietnamese has NO "ea-" words
        "ea",  // ear, each, eat, easy, earn, earth
    ]
    
    /// Consonant + W clusters that are valid in Telex/Simple Telex 2 for standalone "ư"
    /// These patterns should be SKIPPED when inputType is Telex (0) or Simple Telex 2 (3)
    /// In VNI (1) and Simple Telex 1 (2), 'w' has no special meaning, so these patterns indicate English
    private static let consonantWClusters: Set<String> = [
        "bw", "cw", "dw", "gw", "hw", "kw", "lw", "mw", "nw", "pw",
        "qw", "rw", "sw", "tw", "vw", "xw", "yw"
    ]
    
    /// Digraph + W clusters that are valid in Telex/Simple Telex 2.
    /// These represent valid Vietnamese consonant digraphs followed by 'w' for 'ư'.
    /// Examples: thw → thư, chw → chư, khw → khư, phw → phư, trw → trư, etc.
    /// Note: "nghw" and "ghw" are NOT included because "ngh" and "gh" only appear before i, e, ê (not ư).
    private static let digraphWClusters: Set<String> = [
        "thw", "chw", "khw", "phw", "trw", "nhw", "ngw"
    ]

    
    /// Set of 3-letter initial clusters that are IMPOSSIBLE in Vietnamese
    private static let impossible3LetterPrefixes: Set<String> = [
        // STR family
        "str", "spr", "spl", "scr", "shr", "squ", "stw", "swr",
        // SCH/SHR family
        "sch", "scl", "skr", "skw", "sph", "sth",
        // THR family
        // NOTE: "thw" is EXCLUDED - it's valid in Telex/Simple Telex 2 (thw → thư)
        "thr",
        // CHR/SHR family
        "chr", "shr", "phr",
        // Other 3-letter clusters
        "dge", "dgi", "kni", "pne", "psy", "gho", "ghu", "wri", "wro", "wra",
        "ght", "ghr", "ghl", "ghw",
        "ntr", "mpr", "xtr",
        // GR/GL/GW extended
        "gra", "gre", "gri", "gro", "gru", "gry",
        "gla", "gle", "gli", "glo", "glu", "gly",
        // BR/BL extended
        "bra", "bre", "bri", "bro", "bru", "bry",
        "bla", "ble", "bli", "blo", "blu", "bly",
        // DR extended
        "dra", "dre", "dri", "dro", "dru", "dry",
        // CR/CL extended
        "cra", "cre", "cri", "cro", "cru", "cry",
        "cla", "cle", "cli", "clo", "clu", "cly",
        // PR/PL extended
        "pra", "pre", "pri", "pro", "pru", "pry",
        "pla", "ple", "pli", "plo", "plu", "ply",
        // FR/FL extended
        "fra", "fre", "fri", "fro", "fru", "fry",
        "fla", "fle", "fli", "flo", "flu", "fly",
        // WR extended
        "wra", "wre", "wri", "wro", "wru",
        // YEA pattern - English words like year, yeah, yeast
        // Vietnamese 'y' only combines with 'ê' (yê-), never with 'ea'
        "yea",
    ]
    
    /// Set of 4-letter initial clusters that are IMPOSSIBLE in Vietnamese
    private static let impossible4LetterPrefixes: Set<String> = [
        // SCHR/SCHT/SCHW family (German loanwords)
        "schr", "schw", "schn", "schm", "schl",
        // STRI/STRA/STRO family
        "stra", "stre", "stri", "stro", "stru", "stry",
        // SPRI/SPRA family  
        "spra", "spre", "spri", "spro", "spru", "spry",
        // SCRA/SCRE/SCRI family
        "scra", "scre", "scri", "scro", "scru", "scry",
        // SPLA/SPLE family
        "spla", "sple", "spli", "splo", "splu",
        // SQUA/SQUE/SQUI family
        "squa", "sque", "squi", "squo",
        // THRO/THRA family
        "thra", "thre", "thri", "thro", "thru", "thry",
        // CHRO/CHRA family
        "chra", "chre", "chri", "chro", "chru",
        // PHRA/PHRE family
        "phra", "phre", "phri", "phro",
        // SHRA/SHRE family
        "shra", "shre", "shri", "shro", "shru",
        // Other
        "psyc", "pneu", "ghri",
        // THEI pattern - English words like their, they
        // Vietnamese "th" + "e" is valid (thế, thể) but "thei" is NOT
        "thei",
    ]
    
    // ============================================
    // MARK: - Main Detection Properties
    // ============================================
    
    /// Ultra-fast detection: Does this word START with a pattern that is
    /// 100% IMPOSSIBLE in Vietnamese?
    /// 
    /// This is the most reliable rule because:
    /// 1. Vietnamese has a closed set of valid initial consonants/clusters
    /// 2. Uses Set lookup for O(1) performance
    /// 3. False positive rate is 0% (these patterns NEVER occur in Vietnamese)
    ///
    /// Valid Vietnamese initials: b, c, ch, d, đ, g, gh, gi, h, k, kh, l, m, n,
    ///                           ng, ngh, nh, p, ph, qu, r, s, t, th, tr, v, x
    ///
    /// - Parameter customConsonants: Set of custom consonant characters to allow (e.g., z, f, w, j, k)
    /// Examples detected: "winner", "water", "food", "fast", "jazz", "zero",
    ///                    "street", "spring", "chrome", "psychology", "knight"
    func startsWithImpossibleVietnameseCluster(customConsonants: Set<Character> = []) -> Bool {
        let word = self.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !word.isEmpty else { return false }
        
        // ============================================
        // RULE 0 (FASTEST): Check if word starts with letters that
        // NEVER exist in Vietnamese alphabet: f, j, w, z
        // ============================================
        // This catches: winner, water, food, fast, jazz, jungle, zero, zone, etc.
        // Vietnamese NEVER uses these letters at the start of words
        // This is the fastest check - O(1) Set lookup on a single character
        // EXCEPTION: If the starting char is in customConsonants, skip this check
        if let firstChar = word.first, Self.impossibleStartingChars.contains(firstChar) && !customConsonants.contains(firstChar) {
            return true
        }
        
        // For single character words, we've already checked impossible chars above
        guard word.count >= 2 else { return false }
        
        // Check 2-letter prefixes (most common case - check first for efficiency)
        let prefix2 = String(word.prefix(2))
        // Skip prefix check if it starts with a custom consonant character
        let skipPrefix = prefix2.first.map { customConsonants.contains($0) } ?? false
        if !skipPrefix && Self.impossible2LetterPrefixes.contains(prefix2) {
            return true
        }
        
        // Check 3-letter prefixes
        if word.count >= 3 {
            let prefix3 = String(word.prefix(3))
            let skipPrefix3 = prefix3.first.map { customConsonants.contains($0) } ?? false
            if !skipPrefix3 && Self.impossible3LetterPrefixes.contains(prefix3) {
                return true
            }
        }
        
        // Check 4-letter prefixes (most specific)
        if word.count >= 4 {
            let prefix4 = String(word.prefix(4))
            let skipPrefix4 = prefix4.first.map { customConsonants.contains($0) } ?? false
            if !skipPrefix4 && Self.impossible4LetterPrefixes.contains(prefix4) {
                return true
            }
        }
        
        return false
    }
    
    /// Check if this RAW INPUT string starts with a valid Vietnamese input sequence
    /// This is used to EXCLUDE valid typing patterns from being flagged as "impossible"
    ///
    /// For example:
    /// - "dd" in Telex → produces "đ" → should NOT be blocked
    /// - "d9" in VNI → produces "đ" → should NOT be blocked
    /// - "str" → NOT a valid sequence → should be blocked
    ///
    /// - Parameter inputType: 0 = Telex, 1 = VNI, 2 = Simple Telex, 3 = VIQR
    /// - Returns: true if starts with valid Vietnamese input sequence
    func isValidVietnameseInputSequence(inputType: Int = 0) -> Bool {
        let input = self.lowercased()
        
        guard input.count >= 2 else { return false }
        
        let prefix2 = String(input.prefix(2))
        
        switch inputType {
        case 0, 2, 3: // Telex, Simple Telex, VIQR
            return Self.validTelexStartingPatterns.contains(prefix2)
        case 1: // VNI
            return Self.validVNIStartingPatterns.contains(prefix2)
        default:
            // Unknown input type - check all patterns to be safe
            return Self.allValidInputStartingPatterns.contains(prefix2)
        }
    }
    
    /// Check if RAW INPUT starts with a pattern that is DEFINITELY NOT Vietnamese
    /// This considers valid input sequences like "dd" (Telex) or "d9" (VNI)
    ///
    /// - Parameter inputType: 0 = Telex, 1 = VNI, 2 = Simple Telex 1, 3 = Simple Telex 2
    /// - Parameter customConsonants: Set of custom consonant characters to allow
    /// - Returns: true if raw input starts with impossible pattern (excluding valid input sequences)
    func startsWithImpossiblePatternForRawInput(inputType: Int = 0, customConsonants: Set<Character> = []) -> Bool {
        // First, check if this is a valid Vietnamese input sequence
        // If so, it's NOT impossible - return false early
        if isValidVietnameseInputSequence(inputType: inputType) {
            return false
        }
        
        let word = self.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // For Telex (0) and Simple Telex 2 (3), 'w' is a vowel modifier
        // that can create valid Vietnamese patterns:
        // - Standalone "w" → "ư" (at word start)
        // - Consonant + "w" → "Xư" (e.g., "hw" → "hư", "bw" → "bư")
        // For VNI (1) and Simple Telex 1 (2), 'w' has no special meaning, so these patterns indicate English
        let supportsStandaloneW = (inputType == 0 || inputType == 3)
        
        if supportsStandaloneW {
            // When standalone W is supported (Telex/Simple Telex 2), 'w' at word start
            // represents 'ư' — a valid Vietnamese vowel that combines freely with consonants:
            // wn → ưn (ưng, ứng, ừng...), wt → ưt (ướt), wc → ưc (ước), etc.
            // Allow ALL w-starting words through; invalid combos are caught by spell check.
            if word.hasPrefix("w") {
                return false
            }
            
            // Allow consonant + w patterns (hw → hư, bw → bư, etc.)
            if word.count >= 2 {
                let prefix2 = String(word.prefix(2))
                if Self.consonantWClusters.contains(prefix2) {
                    // This is a valid Telex pattern (consonant + w → Xư), not English
                    return false
                }
            }
            
            // Allow digraph + w patterns (thw → thư, chw → chư, khw → khư, etc.)
            if word.count >= 3 {
                let prefix3 = String(word.prefix(3))
                if Self.digraphWClusters.contains(prefix3) {
                    // This is a valid Telex pattern (digraph + w → Xư), not English
                    return false
                }
            }
        }
        
        // Otherwise, check against impossible patterns
        return startsWithImpossibleVietnameseCluster(customConsonants: customConsonants)
    }
    
    /// Check if RAW INPUT is definitely NOT Vietnamese based on START patterns only.
    /// 
    /// This is a conservative check that ONLY looks at the beginning of the word.
    /// Middle and end patterns are NOT checked here because:
    /// 1. Telex uses 'w' as a vowel modifier (ư, ơ, ă) which could create false clusters
    /// 2. Free Mark allows adding tone at the end of word
    /// 3. Complex patterns could interfere with valid Vietnamese input sequences
    ///
    /// Cases like "micros" (where middle/end patterns indicate English) are handled by:
    /// - Spell checking after word is complete
    /// - Instant restore feature (if enabled)
    ///
    /// - Parameter inputType: 0 = Telex, 1 = VNI, 2 = Simple Telex, 3 = VIQR
    /// - Parameter customConsonants: Set of custom consonant characters to allow
    /// - Returns: true if raw input STARTS with impossible Vietnamese pattern
    func isDefinitelyNotVietnameseForRawInput(inputType: Int = 0, customConsonants: Set<Character> = []) -> Bool {
        // Simply delegate to the start pattern check
        // This already handles:
        // 1. Valid Vietnamese input sequences (dd, cc, gg, etc.)
        // 2. Impossible starting characters (f, j, w, z) - unless they are in customConsonants
        // 3. Impossible 2/3/4-letter prefixes (str, bl, gr, etc.)
        return startsWithImpossiblePatternForRawInput(inputType: inputType, customConsonants: customConsonants)
    }
    
}

// MARK: - VNEngine Helper Extensions

extension VNEngine {

    /// Get raw input keys as a String for ENGLISH DETECTION purposes
    /// This EXCLUDES overflow entries to avoid false positives after restore.
    ///
    /// Problem: After restoreLastTypingState(), overflow may contain old word data.
    /// When user types new characters, getRawInputString() returns overflow + entries,
    /// which can cause false English pattern detection.
    ///
    /// Example scenario:
    /// 1. User types "thật" + space → saved to history
    /// 2. User types "lo", then backspaces to empty → restore "thật" into buffer
    /// 3. Buffer: overflow=['t'], entries=['h','ậ','t'] (simplified)
    /// 4. User types 'l' → entries now has 'l' at some position
    /// 5. getRawInputString() = "t..." + "l" → may detect "tl" as English pattern!
    /// 6. User cannot type Vietnamese anymore due to false detection
    ///
    /// Solution: For English detection, only check entries (current typing),
    /// not overflow (old data from restored words).
    func getRawInputStringForEnglishDetection() -> String {
        buffer.getRawInputStringFromEntries { keyCode in
            Self.keyCodeToChar(keyCode)
        }
    }

}
