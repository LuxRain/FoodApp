import Foundation

public enum FoodCategory: String, CaseIterable, Identifiable, Sendable {
    case produce
    case cannedJarred = "canned_jarred"
    case dryGoodsGrains = "dry_goods_grains"
    case dairyEggs = "dairy_eggs"
    case meatSeafood = "meat_seafood"
    case preparedMeals = "prepared_meals"
    case bakerySnacks = "bakery_snacks"
    case beverages
    case infantFood = "infant_food"
    case other

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .produce: "Produce"
        case .cannedJarred: "Canned & jarred"
        case .dryGoodsGrains: "Dry goods & grains"
        case .dairyEggs: "Dairy & eggs"
        case .meatSeafood: "Meat & seafood"
        case .preparedMeals: "Prepared meals"
        case .bakerySnacks: "Bakery & snacks"
        case .beverages: "Beverages"
        case .infantFood: "Infant food & formula"
        case .other: "Other / unclassified"
        }
    }

    public var symbol: String {
        switch self {
        case .produce: "leaf"
        case .cannedJarred: "archivebox"
        case .dryGoodsGrains: "square.stack"
        case .dairyEggs: "drop"
        case .meatSeafood: "fish"
        case .preparedMeals: "fork.knife"
        case .bakerySnacks: "birthday.cake"
        case .beverages: "cup.and.saucer"
        case .infantFood: "figure.child"
        case .other: "shippingbox"
        }
    }

    public static func from(raw: String?) -> FoodCategory {
        guard let raw, !raw.isEmpty else { return .other }
        if let category = FoodCategory(rawValue: raw) { return category }
        let value = raw.lowercased()
        if contains(value, any: ["infant", "baby", "formula"]) { return .infantFood }
        if contains(value, any: ["canned", "jarred", "tinned"]) { return .cannedJarred }
        if contains(value, any: ["produce", "fruit", "vegetable"]) { return .produce }
        if contains(value, any: ["grain", "rice", "pasta", "cereal", "flour"]) { return .dryGoodsGrains }
        if contains(value, any: ["dairy", "cheese", "yogurt", "egg"]) { return .dairyEggs }
        if contains(value, any: ["meat", "poultry", "seafood", "fish", "salmon", "tuna", "shrimp"]) { return .meatSeafood }
        if contains(value, any: ["meal", "entree", "soup", "prepared"]) { return .preparedMeals }
        if contains(value, any: ["bakery", "bread", "snack", "cookie", "cracker"]) { return .bakerySnacks }
        if contains(value, any: ["beverage", "drink", "juice", "water", "coffee", "tea"]) { return .beverages }
        return .other
    }

    private static func contains(_ value: String, any keywords: [String]) -> Bool {
        keywords.contains { value.contains($0) }
    }
}
