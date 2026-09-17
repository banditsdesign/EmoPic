// EmojiCategory.swift
// Categories for organizing emoji in the picker UI.

import Foundation

enum EmojiCategory: String, CaseIterable, Identifiable {
    case smileys = "smileys"
    people = "people"
    animals = "animals"
    food = "food"
    activities = "activities"
    travel = "travel"
    objects = "objects"
    symbols = "symbols"
    flags = "flags"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .smileys: return "Smileys"
        case .people: return "People"
        case .animals: return "Animals"
        case .food: return "Food"
        case .activities: return "Activities"
        case .travel: return "Travel"
        case .objects: return "Objects"
        case .symbols: return "Symbols"
        case .flags: return "Flags"
        }
    }

    var icon: String {
        switch self {
        case .smileys: return "😊"
        case .people: return "👋"
        case .animals: return "🐾"
        case .food: return "🍔"
        case .activities: return "⚽"
        case .travel: return "✈️"
        case .objects: return "💡"
        case .symbols: return "❤️"
        case .flags: return "🏁"
        }
    }
}
