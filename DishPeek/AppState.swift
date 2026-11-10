import SwiftUI
import AVFoundation
import CoreLocation

// Screens you can push onto the navigation stack.
enum Route: Hashable {
    case menu
    case detail(String)
    case order
}

enum MenuMode {
    case photo
    case list
}

// Everything the app remembers while it runs.
// Only the food choices and the redraw switch are saved on the phone (UserDefaults);
// the menu and the order reset when the app quits.
@Observable
class AppState {
    var path: [Route] = []

    var menu: ScannedMenu = SampleMenu.menu
    var place: Place = SampleMenu.place
    // The real menu photo, once the user has scanned one. Nil shows the sample menu.
    var photo: UIImage? = nil
    var hasPlace = true
    var scan: ScanStatus = .idle
    // True while the rest of each dish is on its way, after the menu is already on screen.
    var detailsLoading = false
    // What the scan is doing, and since when, for the progress bar on the scan screen.
    var scanStep: ScanStep = .reading
    var scanStepStarted = Date()

    enum ScanStep {
        case reading
        case redrawing
    }

    // Redraw the whole menu in the user's language with AI, instead of writing the translation
    // over each line. On unless switched off in Settings (or launched with -redraw NO).
    var redraws = UserDefaults.standard.object(forKey: "redraw") == nil ? true : UserDefaults.standard.bool(forKey: "redraw") {
        didSet { UserDefaults.standard.set(redraws, forKey: "redraw") }
    }
    // The redrawn menu and where each dish is on it. Nil when it is switched off or failed.
    var redrawn: RedrawnMenu? = nil

    enum ScanStatus: Equatable {
        case idle
        case reading
        case done
        case failed(String)
    }

    // The user's food choices, from the first screen. Saved on the phone; changed in Settings.
    var avoid: Set<Allergen> = Set((UserDefaults.standard.stringArray(forKey: "avoid") ?? []).compactMap(Allergen.init)) {
        didSet { UserDefaults.standard.set(avoid.map(\.rawValue), forKey: "avoid") }
    }
    var spice: Spice? = UserDefaults.standard.string(forKey: "spice").flatMap(Spice.init) {
        didSet { UserDefaults.standard.set(spice?.rawValue, forKey: "spice") }
    }
    // True once the first screen is done. Until then it shows over everything.
    var hasSetPreferences = UserDefaults.standard.bool(forKey: "onboarded") {
        didSet { UserDefaults.standard.set(hasSetPreferences, forKey: "onboarded") }
    }

    // Dish ids in the order they were added. A dish is in the order at most once.
    var order: [String] = []

    var menuMode: MenuMode = .photo
    var selectedLine: String? = nil

    // The language switch on the photo, translated at first. Holding it shows the other language until you let go.
    var photoTranslated = true
    var photoPeeking = false
    var photoShowsTranslation: Bool { photoPeeking ? !photoTranslated : photoTranslated }
    // The redrawn menu shows while the translation is on; the original language shows the user's photo.
    var showsRedrawn: Bool { redrawn != nil && photoShowsTranslation }

    // Where a dish's line is on the picture being shown.
    func shownBox(_ dish: Dish) -> [Double]? {
        showsRedrawn ? redrawn?.boxes[dish.id] : dish.box
    }

    // Patches that make each translation look printed on the photo, by dish id.
    var lineCovers: [String: LineCover] = [:]
    // The text lines read off the current photo, with their corners, for drawing tilted lines.
    var readLines: [MenuText] = []
    // Where each line of the sample menu sits on the zoomable photo, for finding the line under a tap.
    @ObservationIgnored var sampleLineFrames: [String: CGRect] = [:]

    var orderDishes: [Dish] { order.compactMap { menu.dish($0) } }

    func dish(_ id: String) -> Dish? {
        menu.dish(id)
    }

    func add(_ dish: Dish) {
        if !order.contains(dish.id) {
            order.append(dish.id)
        }
    }

    // What this user avoids that the dish might have, with why: one per choice, as the choice
    // ("Vegetarian: not sure" for a dish that may have fish sauce). Choices it surely breaks are left out.
    func unsure(_ dish: Dish) -> [UnsureAllergen] {
        let surely = Set(hasAvoided(dish))
        return Allergen.choices.compactMap { choice in
            guard avoid.contains(choice), !surely.contains(choice),
                  let item = dish.unsure.first(where: { choice.tags.contains($0.allergen) }) else { return nil }
            return UnsureAllergen(allergen: choice, why: item.why)
        }
    }

    // The user's choices this dish surely breaks.
    func hasAvoided(_ dish: Dish) -> [Allergen] {
        Allergen.choices.filter { avoid.contains($0) && !$0.tags.isDisjoint(with: dish.contains) }
    }

    // "Spicier than your Mild" only makes sense if they picked None or Mild.
    func spiceNote(_ dish: Dish) -> String? {
        guard dish.isSpicy else { return nil }
        if let spice, spice == .none || spice == .mild {
            return String(localized: "Spicier than your \(spice.title)")
        }
        return String(localized: "Spicy")
    }

    func showOnMenu(_ dish: Dish) {
        menuMode = .photo
        selectedLine = dish.id
        path = [.menu]
    }

    // MARK: Scanning a real menu

    // Read the photo on the phone, have the backend explain it, and find the restaurant.
    func scanPhoto(_ image: UIImage) async {
        scan = .reading
        scanStep = .reading
        scanStepStarted = Date()
        let started = Date()
        func mark(_ step: String) {
            #if DEBUG
            print("[scan] \(step) \(String(format: "%.2f", Date().timeIntervalSince(started))) s")
            #endif
        }
        // Look for the restaurant while the menu is being read.
        async let located = Locator.current()

        do {
            let upright = image.upright()
            let found = try await MenuReader.lines(in: upright)
            mark("ocr")
            guard !found.isEmpty else {
                scan = .failed(String(localized: "No text found. Try a closer, sharper photo."))
                return
            }
            guard Backend.isConfigured else {
                scan = .failed(String(localized: "DishPeek's server isn't connected yet."))
                return
            }
            // Keep only the menu part of the photo, and measure the lines inside it.
            let (menuPhoto, lines) = MenuCrop.toText(upright, lines: found)
            let jpeg = menuPhoto.smallJPEG()
            // Only what the photo and the list show, so the menu is on screen in seconds.
            let newMenu = try await Backend.scanMenu(lines, photo: jpeg, into: Languages.user)
            mark("scanMenu")
            // The whole menu redrawn with these translations, while the details and the restaurant are found.
            var redrawing: Task<RedrawnMenu?, Never>? = nil
            if redraws, let jpeg {
                scanStep = .redrawing
                scanStepStarted = Date()
                redrawing = Task {
                    await Redraw.menu(photo: jpeg, size: menuPhoto.size, menu: newMenu, into: Languages.user)
                }
            }
            let coordinate = await located
            mark("location")

            photo = menuPhoto
            redrawn = nil
            menu = newMenu
            readLines = lines
            photoTranslated = true
            lineCovers = [:]
            Task {
                await makeCovers()
                mark("covers")
            }
            order = []
            selectedLine = nil
            menuMode = .photo
            hasPlace = false
            place = Place(id: "", name: newMenu.title.translated, area: "", category: "", distanceMeters: 0, rating: 0, ratingCount: 0)
            // The rest of each dish, then its picture, arrive while the menu is already on screen.
            Task {
                await loadDetails(lines: lines, photo: jpeg)
                mark("details")
            }

            // The restaurant is found before the menu shows, so the scan screen can ask "Is this the place?".
            if let coordinate,
               let found = try? await Backend.nearbyPlace(
                   latitude: coordinate.latitude,
                   longitude: coordinate.longitude,
                   language: Languages.user,
                   // A menu with no restaurant name on it falls back to the closest place.
                   nameHint: newMenu.title.original.isEmpty ? nil : newMenu.title.original
               ) {
                place = found
                hasPlace = true
                // Popular dishes can arrive after the menu is already on screen.
                Task { await loadPopularity(at: found, coordinate) }
            }
            mark("place")
            // With the redraw on, the menu shows once the redrawn picture is in. If it failed,
            // the translation is written over each line as before.
            if let redrawing {
                redrawn = await redrawing.value
                mark("redraw, \(redrawn?.boxes.count ?? 0) of \(newMenu.dishes.count) dishes found on it")
            }
            scan = .done
        } catch {
            scan = .failed(String(localized: "Couldn't read this menu. Check your connection and try again."))
        }
    }

    // Wipes each printed line and samples its ink, off the main thread, ready for the translated view.
    func makeCovers() async {
        guard let photo else { return }
        let read = readLines
        let lines = menu.dishes.compactMap { dish -> LineJob? in
            guard let box = dish.box else { return nil }
            // The read line this dish sits on, for its corners.
            let quad = read.first { line in
                zip(line.box, box).allSatisfy { abs($0 - $1) < 0.000_001 }
            }?.quad
            return LineJob(id: dish.id, box: box, quad: quad, text: dish.coverText)
        }
        let covers = await Task.detached(priority: .userInitiated) {
            LineCovers.make(photo: photo, lines: lines)
        }.value
        // Only if the user is still on the same photo.
        if self.photo === photo {
            lineCovers = covers
        }
    }

    // What each dish is, the allergens we can't rule out, how to order it. Pictures wait for this,
    // because it names each dish's Wikipedia article. If it fails, the screens show the summary instead.
    func loadDetails(lines: [MenuText], photo jpeg: String?) async {
        guard let menuPhoto = photo, !menu.dishes.isEmpty else { return }
        detailsLoading = true
        var explained: Backend.Explained?
        // Two tries: a busy model sometimes fails once.
        for _ in 1...2 where explained == nil {
            do {
                explained = try await Backend.explainDishes(menu.dishes, lines: lines, photo: jpeg, into: Languages.user)
            } catch {
                #if DEBUG
                print("[scan] details failed: \(error)")
                #endif
            }
        }
        // Only if the user is still on the same photo.
        guard self.photo === menuPhoto else { return }
        if let explained {
            withAnimation(.snappy) {
                for index in menu.dishes.indices {
                    if let more = explained.dishes[menu.dishes[index].id] {
                        menu.dishes[index].add(more)
                    }
                }
                menu.footer = explained.footer
            }
            #if DEBUG
            print("[scan] explained \(explained.dishes.count) of \(menu.dishes.count) dishes")
            #endif
        }
        detailsLoading = false
        await loadPhotos()
    }

    // True while this dish's description is still on its way.
    func isExplaining(_ dish: Dish) -> Bool {
        detailsLoading && dish.details.isEmpty
    }

    // A typical photo for each dish that has none, labelled as not from this restaurant.
    func loadPhotos() async {
        let dishes = menu.dishes.filter { $0.photos.isEmpty }
        guard !dishes.isEmpty, let found = try? await Backend.dishPhotos(dishes) else { return }
        withAnimation(.snappy) {
            for index in menu.dishes.indices {
                // Only if this is still the same menu and the dish still has no photo.
                guard let picture = found[menu.dishes[index].id], menu.dishes[index].photos.isEmpty else { continue }
                menu.dishes[index].photos = [picture.url]
                menu.dishes[index].photoSource = .typical
                menu.dishes[index].photoCredit = picture.credit
                menu.dishes[index].photoLink = picture.link
            }
        }
    }

    func loadPopularity(at place: Place, _ coordinate: CLLocationCoordinate2D) async {
        guard let result = try? await Backend.popularity(
            at: place,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            dishes: menu.dishes
        ) else { return }
        // Only apply it if the user is still on the same restaurant.
        guard self.place.id == place.id else { return }
        withAnimation(.snappy) {
            for index in menu.dishes.indices {
                let id = menu.dishes[index].id
                menu.dishes[index].knownFor = result.knownFor.contains(id)
                menu.dishes[index].dishPeekOrders = result.orders[id] ?? 0
            }
            self.place.knownForSources = result.sources
        }
    }

    // Settings → Start over: forget the food choices and show the first screen again.
    // Between usability-test participants this gives each one a fresh start.
    func startOver() {
        avoid = []
        spice = nil
        hasSetPreferences = false
        order = []
        selectedLine = nil
        menuMode = .photo
        path = []
        useSample()
    }

    // Back to the built-in sample menu.
    func useSample() {
        photo = nil
        redrawn = nil
        detailsLoading = false
        lineCovers = [:]
        menu = SampleMenu.menu
        place = SampleMenu.place
        hasPlace = true
        order = []
        selectedLine = nil
    }

    // "Somewhere else": keep the menu, drop the restaurant's rating and popularity.
    func forgetPlace() {
        hasPlace = false
        place = Place(id: "", name: menu.title.translated, area: "", category: "", distanceMeters: 0, rating: 0, ratingCount: 0)
        for index in menu.dishes.indices {
            menu.dishes[index].knownFor = false
            menu.dishes[index].dishPeekOrders = 0
        }
    }

    // Count the order for "#1 on DishPeek", once it has been shown to the server.
    func recordOrder() {
        guard hasPlace, !place.id.isEmpty, Backend.isConfigured, !order.isEmpty else { return }
        let placeId = place.id
        let ids = order
        Task {
            try? await Backend.recordOrder(placeId: placeId, dishIds: ids)
        }
    }
}

// Reads text out loud in the menu's language, for showing the server.
// All speech work runs on its own queue: loading a voice can take a long time
// (in the Simulator the Korean voice never loaded), and on the main thread that
// froze every button in the app.
nonisolated final class Speaker: @unchecked Sendable {
    static let shared = Speaker()
    let synth = AVSpeechSynthesizer()
    let queue = DispatchQueue(label: "speaker")
    var voices: [String: AVSpeechSynthesisVoice] = [:]

    // Called once the menu's language is known, so the voice is ready before anyone taps Play aloud.
    func warmUp(_ language: String) {
        queue.async {
            _ = self.voice(language)
        }
    }

    func say(_ text: String, in language: String) {
        queue.async {
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = self.voice(language)
            utterance.rate = 0.45
            self.synth.stopSpeaking(at: .immediate)
            self.synth.speak(utterance)
        }
    }

    func voice(_ language: String) -> AVSpeechSynthesisVoice? {
        if let voice = voices[language] {
            return voice
        }
        let voice = AVSpeechSynthesisVoice(language: language)
        voices[language] = voice
        return voice
    }
}
