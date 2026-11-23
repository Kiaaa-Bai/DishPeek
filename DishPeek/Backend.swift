import UIKit
import FirebaseCore
import FirebaseFunctions

// Talks to DishPeek's Cloud Functions, which hold the Gemini and Google Maps keys.
// Without GoogleService-Info.plist in the app, Firebase stays off and the app runs on the sample menu.
enum Backend {
    static func configure() {
        if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
            FirebaseApp.configure()
        }
    }

    static var isConfigured: Bool {
        FirebaseApp.app() != nil
    }

    static var functions: Functions {
        Functions.functions(region: "us-central1")
    }

    // Wakes the scan functions up when the camera opens, so the first scan doesn't wait for them
    // to start (a cold start takes a few seconds). Each answers at once and does no work.
    static func warmUp() {
        guard isConfigured else { return }
        for name in ["scanMenu", "explainDishes", "redrawMenu", "dishPhotos", "planMeal"] {
            Task.detached(priority: .utility) {
                _ = try? await functions.httpsCallable(name).call(["warmup": true])
            }
        }
    }

    // MARK: Read a menu

    nonisolated struct ScanRequest: Encodable {
        var lines: [MenuText]
        var targetLanguage: String
        var photo: String?          // the menu photo as base64 JPEG, so Gemini can fix what the reader missed
    }

    static func scanMenu(_ lines: [MenuText], photo: String?, into language: String) async throws -> ScannedMenu {
        var call = functions.httpsCallable("scanMenu", requestAs: ScanRequest.self, responseAs: ScannedMenu.self)
        call.timeoutInterval = 60
        return try await call(ScanRequest(lines: lines, targetLanguage: language, photo: photo))
    }

    // MARK: Explain each dish

    // scanMenu only returns what the screens show first. This asks for the rest of each dish
    // once the menu is on screen: same lines and photo, plus the dishes it found.
    nonisolated struct DishToExplain: Encodable {
        var id: String
        var originalName: String
        var name: String
        var box: [Double]?
        var contains: [Allergen]
    }

    nonisolated struct ExplainRequest: Encodable {
        var lines: [MenuText]
        var targetLanguage: String
        var photo: String?
        var dishes: [DishToExplain]
    }

    struct DishDetails: Decodable {
        var pronunciation: String?
        // Moved here from scanMenu on 2026-11-19, so the menu (and its redraw) can start sooner.
        // Optional, so details from an older server still decode.
        var summary: String?
        var isSpicy: Bool?
        var contains: [Allergen]?
        var isMainDish: Bool?
        var whatItIs: String
        var details: String
        var spiceTip: String?
        var isCold: Bool
        var unsure: [UnsureAllergen]
        var amount: Bilingual
        var question: Bilingual?
        var houseSpecial: Bool
        var localClassic: Bool
        var wikiTitle: String?
    }

    struct Explained: Decodable {
        var footer: Bilingual?
        var dishes: [String: DishDetails]   // by dish id
    }

    static func explainDishes(_ dishes: [Dish], lines: [MenuText], photo: String?, into language: String) async throws -> Explained {
        var call = functions.httpsCallable("explainDishes", requestAs: ExplainRequest.self, responseAs: Explained.self)
        call.timeoutInterval = 120
        let list = dishes.map { DishToExplain(id: $0.id, originalName: $0.originalName, name: $0.name, box: $0.box, contains: $0.contains) }
        return try await call(ExplainRequest(lines: lines, targetLanguage: language, photo: photo, dishes: list))
    }

    // MARK: Plan a meal ("Can't decide?")

    nonisolated struct MealDish: Encodable {
        var id: String
        var name: String
        var originalName: String
        var price: Double?
        var contains: [Allergen]
        var isCold: Bool
        var isSpicy: Bool
        var isMainDish: Bool
        var peekPick: Bool
        var summary: String
    }

    nonisolated struct Meal: Codable {
        var people: Int
        var tier: Int
        var dishes: [String]
    }

    nonisolated struct MealRequest: Encodable {
        var dishes: [MealDish]
        var budgets: [Double?]          // per person for tiers 1, 2, 3; nil = no limit
        var currency: String
        var targetLanguage: String
        var spice: String?
        var previous: [Meal]
    }

    nonisolated struct MealPlans: Decodable {
        struct Reason: Decodable {
            var id: String
            var reason: String
        }
        var reasons: [Reason]
        var meals: [Meal]
    }

    // Every meal at once, for 1 to 6 people and three budget tiers, each dish with why, picked by Gemini from
    // these dishes. About 5 s and $0.0016; switching people or budget afterwards is instant and free.
    // `previous` asks for different meals than last time.
    static func planMeals(_ dishes: [Dish], budgets: [Double?], currency: String, spice: Spice?,
                          previous: [Meal], into language: String) async throws -> MealPlans {
        var call = functions.httpsCallable("planMeal", requestAs: MealRequest.self, responseAs: MealPlans.self)
        call.timeoutInterval = 60
        let list = dishes.map {
            MealDish(id: $0.id, name: $0.name, originalName: $0.originalName, price: $0.price, contains: $0.contains,
                     isCold: $0.isCold, isSpicy: $0.isSpicy, isMainDish: $0.isMainDish, peekPick: $0.peekPick, summary: $0.summary)
        }
        return try await call(MealRequest(dishes: list, budgets: budgets, currency: currency, targetLanguage: language,
                                          spice: spice?.rawValue, previous: previous))
    }

    // MARK: Redraw the menu

    nonisolated struct RedrawRequest: Encodable {
        var photo: String
        var targetLanguage: String
        var aspectRatio: String
        var translations: [Bilingual]   // printed line → what to write in its place
    }

    struct Redrawn: Decodable {
        var image: String               // base64
    }

    // The menu photo redrawn by an image model with its text in the user's language. About 10 s
    // (Flash-Lite); up to about a minute when Flash-Lite is busy and Pro draws it instead.
    static func redrawMenu(photo: String, aspectRatio: String, translations: [Bilingual], into language: String) async throws -> UIImage {
        var call = functions.httpsCallable("redrawMenu", requestAs: RedrawRequest.self, responseAs: Redrawn.self)
        call.timeoutInterval = 120
        let reply = try await call(RedrawRequest(photo: photo, targetLanguage: language, aspectRatio: aspectRatio, translations: translations))
        guard let data = Data(base64Encoded: reply.image), let image = UIImage(data: data) else {
            throw URLError(.cannotDecodeContentData)
        }
        return image
    }

    // MARK: Dish photos

    nonisolated struct PhotoQuery: Encodable {
        var id: String
        var originalName: String
        var name: String
        var wikiTitle: String?
    }

    nonisolated struct PhotosRequest: Encodable {
        var dishes: [PhotoQuery]
        var quick: Bool             // only Wikipedia and photos already found for other users: no web search
    }

    struct Picture: Decodable {
        var url: String
        var credit: String
        var link: String
    }

    struct PhotosResponse: Decodable {
        var photos: [String: Picture]
    }

    // A typical photo of each dish, by dish id. Dishes with none found are left out.
    static func dishPhotos(_ dishes: [Dish], quick: Bool) async throws -> [String: Picture] {
        var call = functions.httpsCallable("dishPhotos", requestAs: PhotosRequest.self, responseAs: PhotosResponse.self)
        call.timeoutInterval = 70
        let queries = dishes.map { PhotoQuery(id: $0.id, originalName: $0.originalName, name: $0.name, wikiTitle: $0.wikiTitle) }
        return try await call(PhotosRequest(dishes: queries, quick: quick)).photos
    }

    // MARK: Find the restaurant

    nonisolated struct PlaceRequest: Encodable {
        var latitude: Double
        var longitude: Double
        var languageCode: String
        var nameHint: String?
    }

    struct PlaceResponse: Decodable {
        var place: Place?
    }

    static func nearbyPlace(latitude: Double, longitude: Double, language: String, nameHint: String?) async throws -> Place? {
        let call = functions.httpsCallable("nearbyPlace", requestAs: PlaceRequest.self, responseAs: PlaceResponse.self)
        let request = PlaceRequest(latitude: latitude, longitude: longitude, languageCode: language, nameHint: nameHint)
        return try await call(request).place
    }

    // MARK: What's popular there

    nonisolated struct DishRef: Encodable {
        var id: String
        var originalName: String
        var name: String
    }

    nonisolated struct PopularityRequest: Encodable {
        var placeId: String
        var placeName: String
        var latitude: Double
        var longitude: Double
        var dishes: [DishRef]
    }

    struct Popularity: Decodable {
        var knownFor: [String]
        var sources: [Place.Source]
        var orders: [String: Int]
    }

    static func popularity(at place: Place, latitude: Double, longitude: Double, dishes: [Dish]) async throws -> Popularity {
        var call = functions.httpsCallable("placePopularity", requestAs: PopularityRequest.self, responseAs: Popularity.self)
        call.timeoutInterval = 60
        let refs = dishes.map { DishRef(id: $0.id, originalName: $0.originalName, name: $0.name) }
        return try await call(PopularityRequest(placeId: place.id, placeName: place.name, latitude: latitude, longitude: longitude, dishes: refs))
    }

    // MARK: Count an order

    nonisolated struct OrderRequest: Encodable {
        var placeId: String
        var dishIds: [String]
    }

    struct OK: Decodable {
        var ok: Bool
    }

    static func recordOrder(placeId: String, dishIds: [String]) async throws {
        let call = functions.httpsCallable("recordOrder", requestAs: OrderRequest.self, responseAs: OK.self)
        _ = try await call(OrderRequest(placeId: placeId, dishIds: dishIds))
    }
}

extension Dish {
    // Fills in what explainDishes found out about this dish.
    mutating func add(_ more: Backend.DishDetails) {
        pronunciation = more.pronunciation
        if let summary = more.summary { self.summary = summary }
        if let isSpicy = more.isSpicy { self.isSpicy = isSpicy }
        if let contains = more.contains { self.contains = contains }
        if let isMainDish = more.isMainDish { self.isMainDish = isMainDish }
        whatItIs = more.whatItIs
        details = more.details
        spiceTip = more.spiceTip
        isCold = more.isCold
        unsure = more.unsure
        amount = more.amount
        question = more.question
        houseSpecial = more.houseSpecial
        localClassic = more.localClassic
        wikiTitle = more.wikiTitle
    }
}
