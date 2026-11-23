import Foundation

// Language codes are BCP 47: "ko", "en", "zh-Hans", "ja".
enum Languages {
    // The user's language: the one the interface is showing in right now.
    // Menus can be in any language Vision and Gemini read.
    static var user: String {
        Bundle.main.preferredLocalizations.first ?? "en"
    }

    // A language's name in the user's language: "Korean", "韩语".
    static func name(_ code: String) -> String {
        Locale(identifier: user).localizedString(forIdentifier: code) ?? code
    }

    // The language menus are translated into. Settings can pick one (Kia, 2026-11-21); empty means
    // the app's own language. The app's words stay in the app's language either way.
    static let translationKey = "translationLanguage"
    static var menu: String {
        let picked = UserDefaults.standard.string(forKey: translationKey) ?? ""
        return picked.isEmpty ? user : picked
    }

    // What Settings offers: the languages the app itself speaks.
    static let translationChoices = ["zh-Hans", "zh-Hant", "en", "ja", "ko", "es", "fr", "de", "th", "vi"]

    // A language's name in that language, so people find their own: "日本語", "Español".
    static func ownName(_ code: String) -> String {
        let locale = Locale(identifier: code)
        return locale.localizedString(forIdentifier: code)?.capitalized(with: locale) ?? code
    }
}

// Two kinds in one list. What a dish contains (the server tags dishes with these), and what a person picks
// (Kia, 2026-11-21: three groups, so a choice can't read two ways). "I am…" is a diet, one at most,
// made of the tags it rules out. "I don't eat" and "I'm allergic" are tags to avoid, any number.
enum Allergen: String, CaseIterable, Identifiable, Codable {
    // Allergens: the EU's 14 that menus must declare, which include the US's 9. "shellfish" is crustaceans.
    case shellfish, molluscs, fish, peanuts, treeNuts, dairy, eggs, gluten, soy, sesame
    case mustard, celery, lupin, sulphites
    // What people often don't eat when travelling.
    case pork, beef, lamb, poultry, offal, alcohol, alliums, cilantro, mushrooms, raw
    case meat, honey                   // only tags: any meat or poultry, and honey, for the diets
    // Diets: only choices.
    case vegetarian, vegan, pescatarian, halal, kosher, jain

    var id: String { rawValue }

    static let allergies: [Allergen] = [.shellfish, .molluscs, .fish, .peanuts, .treeNuts, .dairy, .eggs, .gluten, .soy, .sesame, .mustard, .celery, .lupin, .sulphites]
    static let dislikes: [Allergen] = [.pork, .beef, .lamb, .poultry, .offal, .alcohol, .alliums, .cilantro, .mushrooms, .raw]
    static let diets: [Allergen] = [.vegetarian, .vegan, .pescatarian, .halal, .kosher, .jain]
    static let choices = diets + dislikes + allergies

    var isDiet: Bool { Self.diets.contains(self) }
    var isAllergy: Bool { Self.allergies.contains(self) }

    // The tags that break this choice. Pork, beef, lamb and poultry count as meat even if a dish only has
    // the narrower tag.
    var tags: Set<Allergen> {
        let meats: Set<Allergen> = [.meat, .pork, .beef, .lamb, .poultry, .offal]
        switch self {
        case .vegetarian: return meats.union([.fish, .shellfish, .molluscs])
        case .vegan: return meats.union([.fish, .shellfish, .molluscs, .dairy, .eggs, .honey])
        case .pescatarian: return meats
        case .halal: return [.pork, .alcohol]
        case .kosher: return [.pork, .shellfish, .molluscs]
        case .jain: return meats.union([.fish, .shellfish, .molluscs, .eggs, .alliums, .honey])
        case .meat: return meats
        default: return [self]
        }
    }

    var title: String {
        switch self {
        case .shellfish: String(localized: "Crustaceans")
        case .molluscs: String(localized: "Molluscs")
        case .fish: String(localized: "Fish")
        case .peanuts: String(localized: "Peanuts")
        case .treeNuts: String(localized: "Tree nuts")
        case .dairy: String(localized: "Dairy")
        case .eggs: String(localized: "Eggs")
        case .gluten: String(localized: "Gluten")
        case .soy: String(localized: "Soy")
        case .sesame: String(localized: "Sesame")
        case .mustard: String(localized: "Mustard")
        case .celery: String(localized: "Celery")
        case .lupin: String(localized: "Lupin")
        case .sulphites: String(localized: "Sulphites")
        case .pork: String(localized: "Pork")
        case .beef: String(localized: "Beef")
        case .lamb: String(localized: "Lamb")
        case .poultry: String(localized: "Poultry")
        case .offal: String(localized: "Offal")
        case .alcohol: String(localized: "Alcohol")
        case .alliums: String(localized: "Onion & garlic")
        case .cilantro: String(localized: "Cilantro")
        case .mushrooms: String(localized: "Mushrooms")
        case .raw: String(localized: "Raw food")
        case .meat: String(localized: "Meat")
        case .honey: String(localized: "Honey")
        case .vegetarian: String(localized: "Vegetarian")
        case .vegan: String(localized: "Vegan")
        case .pescatarian: String(localized: "Pescatarian")
        case .halal: String(localized: "Halal")
        case .kosher: String(localized: "Kosher")
        case .jain: String(localized: "Jain")
        }
    }

    // On a dish's warning: "Has Pork", but "Not vegetarian" for a diet.
    var warning: String {
        switch self {
        case .vegetarian: String(localized: "Not vegetarian")
        case .vegan: String(localized: "Not vegan")
        case .pescatarian: String(localized: "Not pescatarian")
        case .halal: String(localized: "Not halal")
        case .kosher: String(localized: "Not kosher")
        case .jain: String(localized: "Not Jain")
        default: String(localized: "Has \(title)")
        }
    }

    var emoji: String {
        switch self {
        case .shellfish: "🦐"
        case .molluscs: "🦪"
        case .fish: "🐟"
        case .peanuts: "🥜"
        case .treeNuts: "🌰"
        case .dairy: "🥛"
        case .eggs: "🥚"
        case .gluten: "🌾"
        case .soy: "🫘"
        case .sesame: "🥯"
        case .mustard: "🌭"
        case .celery: "🥬"
        case .lupin: "🫛"
        case .sulphites: "🍇"
        case .pork: "🐷"
        case .beef: "🐮"
        case .lamb: "🐑"
        case .poultry: "🐔"
        case .offal: "🫀"
        case .alcohol: "🍷"
        case .alliums: "🧄"
        case .cilantro: "🌿"
        case .mushrooms: "🍄"
        case .raw: "🍣"
        case .meat: "🍗"
        case .honey: "🍯"
        case .vegetarian: "🥗"
        case .vegan: "🌱"
        case .pescatarian: "🐠"
        case .halal: "☪️"
        case .kosher: "✡️"
        case .jain: "🕉️"
        }
    }
}

enum Spice: String, CaseIterable, Identifiable, Codable {
    case none, mild, medium, spicy, hot, veryHot

    var id: String { rawValue }

    // How many of the five chilies stand for this level, from none 0 to very hot 5.
    var chilies: Int {
        switch self {
        case .none: 0
        case .mild: 1
        case .medium: 2
        case .spicy: 3
        case .hot: 4
        case .veryHot: 5
        }
    }

    var title: String {
        switch self {
        case .none: String(localized: "None", comment: "Spice level")
        case .mild: String(localized: "Mild", comment: "Spice level")
        case .medium: String(localized: "Medium", comment: "Spice level")
        case .spicy: String(localized: "Spicy", comment: "Spice level")
        case .hot: String(localized: "Hot", comment: "Spice level")
        case .veryHot: String(localized: "Very hot", comment: "Spice level")
        }
    }
}

// The same words in two languages: as printed on the menu, and in the user's language.
struct Bilingual: Codable, Hashable {
    var original: String
    var translated: String
}

// An allergen the dish might have, with the reason we are not sure.
struct UnsureAllergen: Codable, Hashable {
    var allergen: Allergen
    var why: String
}

// Where a dish photo comes from, so people know how much to trust it.
enum PhotoSource: Codable, Hashable {
    case restaurant(count: Int)   // diners' photos at this restaurant
    case typical                  // what the dish usually looks like elsewhere
}

struct Dish: Identifiable, Codable, Hashable {
    var id: String

    // Read off the menu photo, in the menu's language.
    var printed: String             // the line as printed: "콩국수 (여름)"
    var originalName: String        // just the dish: "콩국수"
    var pronunciation: String?      // for scripts the user may not read: "kong-guk-su"
    var priceText: String           // as printed: "12,000"
    var price: Double?
    var box: [Double]? = nil        // where the line is on the photo: x, y, width, height from 0 to 1
    var lineText: String? = nil     // that line exactly as the phone read it, price included

    // In the user's language.
    var name: String                // "Kongguksu"
    var lineTranslation: String     // what the printed line says: "Soy milk noodles (summer)"
    var summary: String             // "Cold soy milk noodles"
    var whatItIs: String            // "Summer only, nutty and plain"
    var details: String
    var spiceTip: String? = nil     // "Sweet chili sauce. Ask for less if you like."
    var isSpicy = false
    var isCold = false
    var contains: [Allergen] = []
    var unsure: [UnsureAllergen] = []
    var amount: Bilingual           // how to order one: "1개" / "×1"
    var question: Bilingual? = nil  // the useful thing to ask the server about it

    // Not on the menu: photos and how popular it is.
    var photos: [String] = []       // names of photos in the app, or web addresses
    var photoSource: PhotoSource? = nil
    var photoCredit: String? = nil  // who took a web photo and its license, shown with it
    var photoLink: String? = nil    // where that photo and its license live
    var wikiTitle: String? = nil    // the dish's English Wikipedia article, for finding a photo
    var knownFor = false            // Google Maps says this place is known for it
    var dishPeekOrders = 0          // how many times DishPeek users ordered it here
    var houseSpecial = false        // the menu itself marks it: a star, a circle, "house special"
    var localClassic = false        // the AI's pick: a well-known classic of this place or cuisine
    var isMainDish = true           // false for sides like rice or extra noodles
    // Shown as "Peek's Pick": the AI's picks and the menu's own specials share one label.
    // Google Maps' "known for" too: still looked up, but shown as the same pick (Kia, 2026-11-21).
    var peekPick: Bool { houseSpecial || localClassic || knownFor }

    static func == (a: Dish, b: Dish) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// One menu, read from a photo and translated into the user's language.
struct ScannedMenu: Codable {
    var sourceLanguage: String      // the menu's language: "ko"
    var targetLanguage: String      // the user's language: "en"
    var currency: String            // ISO 4217: "KRW"
    var title: Bilingual            // the restaurant name as printed on the menu
    var footer: Bilingual? = nil
    var orderPhrase: Bilingual      // "주문할게요" / "I'd like to order"
    var totalWord: Bilingual        // "합계" / "Total"
    var defaultQuestion: Bilingual  // "뭐 들어가요?" / "What's in it?"
    var dishes: [Dish]

    func dish(_ id: String) -> Dish? {
        dishes.first { $0.id == id }
    }

    // Whole amounts without cents (₩11,000, €10), others with both digits (€8.80, not €8.8).
    func money(_ value: Double) -> String {
        let digits = value.rounded() == value ? 0 : 2
        return value.formatted(.currency(code: currency).precision(.fractionLength(digits)).locale(Locale(identifier: Languages.user)))
    }

    func money(_ dish: Dish) -> String {
        if let price = dish.price {
            return money(price)
        }
        return dish.priceText
    }

    // Dishes worth a look, most solid reason first: Google Maps says the place is known for them,
    // the menu marks them as house specials, DishPeek users ordered them, or the AI calls them local classics.
    var popular: [Dish] {
        dishes
            .filter { $0.knownFor || $0.houseSpecial || $0.dishPeekOrders > 0 || ($0.localClassic && $0.isMainDish) }
            .sorted { a, b in
                if a.knownFor != b.knownFor { return a.knownFor }
                if a.houseSpecial != b.houseSpecial { return a.houseSpecial }
                if a.dishPeekOrders != b.dishPeekOrders { return a.dishPeekOrders > b.dishPeekOrders }
                return false
            }
    }

    // 1 for the most ordered dish on DishPeek here, if anyone has ordered at all.
    func dishPeekRank(_ dish: Dish) -> Int? {
        guard dish.dishPeekOrders > 0 else { return nil }
        let higher = dishes.filter { $0.dishPeekOrders > dish.dishPeekOrders }.count
        return higher + 1
    }
}

// The restaurant, from Google Maps.
struct Place: Codable {
    var id: String                  // Google place ID
    var name: String                // in the user's language
    var area: String                // neighborhood: "Myeong-dong"
    var category: String            // "Korean noodles"
    var distanceMeters: Double
    var rating: Double
    var ratingCount: Int
    var mapsURL: String? = nil
    var knownForSources: [Source] = []  // Google Maps pages behind "Known for"

    struct Source: Codable, Hashable {
        var title: String
        var url: String
    }

    var distanceText: String {
        Measurement(value: distanceMeters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road).locale(Locale(identifier: Languages.user)))
    }
}
