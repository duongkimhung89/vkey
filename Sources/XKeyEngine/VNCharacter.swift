// Adapted from XKey, copyright (c) 2025 XKey (MIT). See Resources/Licenses and THIRD_PARTY_NOTICES.md.
// Modified 2026-09-30: retained only the vowel/consonant types used by the
// offline engine; unused mapping and UI compatibility layers were removed.
//
//  VNCharacter.swift
//  XKey
//
//  Vietnamese vowel and consonant definitions used by the offline engine.
//

import Foundation

enum VNVowel: String, CaseIterable {
    case a, e, i, o, u, y
    case aCircumflex = "â"
    case eCircumflex = "ê"
    case oCircumflex = "ô"
    case aBreve = "ă"
    case oHorn = "ơ"
    case uHorn = "ư"

    var hasCircumflex: Bool {
        switch self {
        case .aCircumflex, .eCircumflex, .oCircumflex: return true
        default: return false
        }
    }

    var hasHorn: Bool {
        self == .oHorn || self == .uHorn
    }
}

enum VNConsonant: String, CaseIterable {
    case b, c, d, g, h, k, l, m, n, p, q, r, s, t, v, x
    case dd = "đ"
    case ch, gh, gi, kh, ng, ngh, nh, ph, qu, th, tr
}
