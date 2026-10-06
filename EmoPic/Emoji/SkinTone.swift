// SkinTone.swift
// Unicode skin tone modifiers for emoji.

import Foundation

enum SkinTone: String, CaseIterable, Identifiable, CustomStringConvertible {
    case `default` = ""
    case light = "🏻"
    case mediumLight = "🏼"
    case medium = "🏽"
    case mediumDark = "🏾"
    case dark = "🏿"

    var id: String { rawValue }
    var emoji: String { rawValue }
    var description: String {
        switch self {
        case .default: return "Default"
        case .light: return "Light"
        case .mediumLight: return "Medium-Light"
        case .medium: return "Medium"
        case .mediumDark: return "Medium-Dark"
        case .dark: return "Dark"
        }
    }
}
