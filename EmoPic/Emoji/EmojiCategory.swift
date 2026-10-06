// EmojiCategory.swift
// Categories for organizing emoji in the picker UI.

import Foundation

enum EmojiCategory: String, CaseIterable, Codable, Identifiable {
    case smileys = "smileys"
    case people = "people"
    case animals = "animals"
    case food = "food"
    case activities = "activities"
    case travel = "travel"
    case objects = "objects"
    case symbols = "symbols"
    case flags = "flags"

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

    /// Map an `iamcal/emoji-data` group/category string onto a category.
    static func from(group: String) -> EmojiCategory {
        let g = group.lowercased()
        if g.contains("smile") || g.contains("emotion") { return .smileys }
        if g.contains("people") || g.contains("body") || g.contains("person") { return .people }
        if g.contains("animal") || g.contains("nature") { return .animals }
        if g.contains("food") || g.contains("drink") { return .food }
        if g.contains("activity") || g.contains("activities") { return .activities }
        if g.contains("travel") || g.contains("place") { return .travel }
        if g.contains("object") { return .objects }
        if g.contains("flag") { return .flags }
        return .symbols
    }
}
