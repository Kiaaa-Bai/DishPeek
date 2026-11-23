import SwiftUI
import AVFoundation
import CoreLocation
import CoreImage.CIFilterBuiltins

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
// Only the food choices are saved on the phone (UserDefaults);
// the menu and the order reset when the app quits.
@Observable
class AppState {
    var path: [Route] = []

    var menu: ScannedMenu = SampleMenu.menu
    var place: Place = SampleMenu.place
    // The real menu photo, once the user has scanned one. Nil shows the sample menu.
    var photo: UIImage? = nil
    var hasPlace = true
    // Ask on the menu whether the restaurant we found is the right one.
    var askPlace = false
    var scan: ScanStatus = .idle
    // True while the rest of each dish is on its way, after the menu is already on screen.
    var detailsLoading = false
    // What the scan is doing, and when each step began. The scan screen plays it on the photo itself
    // (Kia, 2026-11-21): the lines light up where they are, the dishes turn green, and the redrawn menu
    // is wiped in over the photo. No progress popup.
    var scanStep: ScanStep = .reading
    var scanStepTimes: [ScanStep: Date] = [:]

    nonisolated enum ScanStep: Hashable {
        case reading       // finding the text on the photo (on the phone, about a second)
        case translating   // scanMenu reads and translates the dishes
        case redrawing     // the image model redraws the menu
        case revealing     // the redrawn menu wipes in over the photo
    }
    // The photo being scanned, the lines found on it, which of them are dishes, and the redrawn picture.
    var scanImage: UIImage?
    // The whole photo as taken, shown until the menu part is cut out of it.
    var scanFullImage: UIImage?
    var scanLines: [MenuText] = []
    var scanDishBoxes: Set<[Double]> = []
    // The dishes' translated names, shown one after another in the scan pill while the menu is redrawn,
    // so the long wait shows the translation is real (Kia, 2026-11-21).
    var scanDishNames: [String] = []
    var scanRedrawn: UIImage?

    // The redrawn menu wipes in over the photo from the top (Kia, 2026-11-21: line by line was tried on the
    // phone and dropped; the whole menu turning together reads better), then the menu opens.
    static let wipeSeconds = 1.6
    static let revealSeconds = 2.2

    func enterScanStep(_ step: ScanStep) {
        scanStep = step
        scanStepTimes[step] = Date()
    }

    // Redraw the whole menu in the user's language with AI. It is the app's core, so it is always on
    // (the Settings switch was removed 2026-11-19). If a redraw fails, the translation is written
    // over each line instead.
    let redraws = true
    // The redrawn menu and where each dish is on it. Nil when the redraw failed.
    var redrawn: RedrawnMenu? = nil

    enum ScanStatus: Equatable {
        case idle
        case reading
        case done
        case failed(String)
    }

    // The user's food choices, from the first screen. Saved on the phone; changed in Settings.
    // Whether this person has ever tapped a dish on the menu photo. Until then the dishes glow in a wave
    // and a hint says they can be tapped (Kia, 2026-11-21: in usability tests many didn't know).
    var hasTappedDish = UserDefaults.standard.bool(forKey: "hasTappedDish") {
        didSet { UserDefaults.standard.set(hasTappedDish, forKey: "hasTappedDish") }
    }
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
        // Only where the dish was found on the redrawn picture: its layout can differ from the photo's, so the
        // photo's place would put pins and taps on the wrong line.
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

    // In the order if it wasn't, out of it if it was.
    func toggleInOrder(_ dish: Dish) {
        if let index = order.firstIndex(of: dish.id) {
            order.remove(at: index)
        } else {
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
        // The line glows once so it can be found, then lets go, so it doesn't stay in the way of tapping the
        // other dishes (Kia, 2026-11-21).
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            if selectedLine == dish.id {
                withAnimation(.smooth(duration: 0.5)) {
                    selectedLine = nil
                }
            }
        }
    }

    // MARK: Scanning a real menu

    // Read the photo on the phone, have the backend explain it, and find the restaurant.
    func scanPhoto(_ image: UIImage) async {
        scanStepTimes = [:]
        scanFullImage = image.upright()
        scanImage = nil
        scanLines = []
        scanDishBoxes = []
        scanDishNames = []
        scanRedrawn = nil
        enterScanStep(.reading)
        scan = .reading
        let started = Date()
        var marks: [String: Double] = [:]
        func mark(_ step: String) {
            #if DEBUG
            marks[step.components(separatedBy: ",").first ?? step] = Date().timeIntervalSince(started)
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
            // The photo stays as it was taken: no cutting it down to the text (Kia, 2026-11-21).
            let (menuPhoto, lines) = (upright, found)
            // Every line lights up where it is on the photo.
            scanImage = menuPhoto
            scanLines = lines
            enterScanStep(.translating)
            let jpeg = menuPhoto.smallJPEG()
            // Only what the photo and the list show, so the menu is on screen in seconds.
            let newMenu = try await Backend.scanMenu(lines, photo: jpeg, into: Languages.menu)
            mark("scanMenu")
            // The whole menu redrawn with these translations, while the details and the restaurant are found.
            var redrawing: Task<RedrawnMenu?, Never>? = nil
            // The dishes among those lines turn green.
            scanDishBoxes = Set(newMenu.dishes.compactMap(\.box))
            scanDishNames = newMenu.dishes.map(\.name).filter { !$0.isEmpty }
            enterScanStep(.redrawing)
            if redraws, let jpeg {
                redrawing = Task {
                    await Redraw.menu(photo: jpeg, size: menuPhoto.size, menu: newMenu, into: Languages.menu)
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
                   language: Languages.menu,
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
            #if DEBUG
            // -dumpScan YES: save what the scan saw, for prototyping the scan animation in HTML.
            if UserDefaults.standard.bool(forKey: "dumpScan") {
                dumpScan(marks: marks)
            }
            #endif
            // The redrawn menu wipes in over the photo, then the menu opens. Without one the lines just fade.
            scanRedrawn = redrawn?.image
            enterScanStep(.revealing)
            try? await Task.sleep(for: .seconds(redrawn == nil ? 0.6 : Self.revealSeconds))
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
                explained = try await Backend.explainDishes(menu.dishes, lines: lines, photo: jpeg, into: Languages.menu)
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
        // First what is ready at once (Wikipedia, and photos found for other users), then a web search
        // for the rest, so the ready ones don't wait for the search (2026-11-19).
        for quick in [true, false] {
            let dishes = menu.dishes.filter { $0.photos.isEmpty }
            guard !dishes.isEmpty, let found = try? await Backend.dishPhotos(dishes, quick: quick) else { continue }
            withAnimation(.snappy) {
                for index in menu.dishes.indices {
                    // Only if this is still the same menu and the dish still has no photo.
                    guard let picture = found[menu.dishes[index].id], menu.dishes[index].photos.isEmpty else { continue }
                    menu.dishes[index].photos = [picture.url]
                    menu.dishes[index].photoSource = .typical
                    // Web photos come without a credit or link (Kia, 2026-11-19): show none rather than an empty label.
                    menu.dishes[index].photoCredit = picture.credit.isEmpty ? nil : picture.credit
                    menu.dishes[index].photoLink = picture.link.isEmpty ? nil : picture.link
                }
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

#if DEBUG
extension AppState {
    // Writes the menu photo, the redrawn picture, the lines read off the photo and the timings
    // into the app's Documents folder.
    func dumpScan(marks: [String: Double]) {
        guard let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        try? photo?.jpegData(compressionQuality: 0.85)?.write(to: folder.appending(path: "scan-photo.jpg"))
        try? redrawn?.image.jpegData(compressionQuality: 0.85)?.write(to: folder.appending(path: "scan-redrawn.jpg"))
        struct Dump: Codable {
            var lines: [MenuText]
            var dishes: [[String: String]]
            var dishBoxes: [String: [Double]]
            var marks: [String: Double]
        }
        let dump = Dump(
            lines: readLines,
            dishes: menu.dishes.map { ["id": $0.id, "name": $0.name, "original": $0.originalName, "pick": $0.peekPick ? "1" : "0"] },
            dishBoxes: Dictionary(uniqueKeysWithValues: menu.dishes.compactMap { dish in dish.box.map { (dish.id, $0) } }),
            marks: marks
        )
        try? JSONEncoder().encode(dump).write(to: folder.appending(path: "scan.json"))
        print("[scan] dumped to \(folder.path)")
    }
}
#endif

extension AppState {
    // A dish's line as printed, cut out of the menu photo along its own slant and straightened: the name
    // and, if it sits on the same row, the price after it (Kia, 2026-11-21, for pointing at on their menu).
    // Nil without a photo or a place on it.
    // The read line a dish came from: the one the server pointed to, or else the line whose words are the
    // dish's name. The server sometimes finds a dish without its line (Kia's 2026-11-21 test: two of three
    // dishes had none, so the order page showed only their prices).
    func readLine(of dish: Dish) -> MenuText? {
        if let box = dish.box, box.count == 4 {
            let key = box.map { String(format: "%.4f", $0) }
            if let line = readLines.first(where: { $0.box.map { String(format: "%.4f", $0) } == key }) {
                return line
            }
        }
        func plain(_ text: String) -> String {
            text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).filter { $0.isLetter || $0.isNumber }
        }
        let name = plain(dish.originalName)
        guard name.count >= 3 else { return nil }
        // A line that holds the whole name, or most of it; the closest in length wins.
        return readLines
            .filter { line in
                let text = plain(line.text)
                return text.contains(name) || (text.count >= max(3, name.count * 2 / 3) && name.contains(text))
            }
            .min { abs(plain($0.text).count - name.count) < abs(plain($1.text).count - name.count) }
    }

    func printedLine(_ dish: Dish) -> UIImage? {
        guard let photo, let cgImage = photo.cgImage, let line = readLine(of: dish) else { return nil }
        let box = line.box
        let q = line.quad ?? [box[0], box[1], box[0] + box[2], box[1], box[0] + box[2], box[1] + box[3], box[0], box[1] + box[3]]
        var topLeft = CGPoint(x: q[0], y: q[1]), topRight = CGPoint(x: q[2], y: q[3])
        var bottomRight = CGPoint(x: q[4], y: q[5]), bottomLeft = CGPoint(x: q[6], y: q[7])

        // The price: the nearest line to its right, about level with it, with a digit in it.
        let slope = (topRight.y - topLeft.y) / max(0.001, topRight.x - topLeft.x)
        let middleY = (topLeft.y + bottomLeft.y) / 2
        let thickness = abs(bottomLeft.y - topLeft.y)
        // Where the dish's line would be at a price's left edge, and how far that price is from it.
        func offset(_ other: MenuText) -> Double {
            let expected = middleY + slope * (other.box[0] - topLeft.x)
            return abs(other.box[1] + other.box[3] / 2 - expected)
        }
        // Prices sit close together on a handwritten board: the most level one wins, not the first.
        let price = readLines
            .filter { other in
                other != line && other.text.contains(where: \.isNumber) && other.box[0] > topRight.x - 0.01
                    && offset(other) < thickness * 0.6
            }
            .min { offset($0) < offset($1) }
        if let price, let pq = price.quad {
            topRight = CGPoint(x: pq[2], y: pq[3])
            bottomRight = CGPoint(x: pq[4], y: pq[5])
        } else if let price {
            topRight = CGPoint(x: price.box[0] + price.box[2], y: price.box[1])
            bottomRight = CGPoint(x: price.box[0] + price.box[2], y: price.box[1] + price.box[3])
        }

        // A little room around the words: up and down along the line's own slant, and at both ends.
        func moved(_ p: CGPoint, toward q: CGPoint, by share: Double) -> CGPoint {
            CGPoint(x: p.x + (p.x - q.x) * share, y: p.y + (p.y - q.y) * share)
        }
        let (tl, bl) = (moved(topLeft, toward: bottomLeft, by: 0.3), moved(bottomLeft, toward: topLeft, by: 0.3))
        let (tr, br) = (moved(topRight, toward: bottomRight, by: 0.3), moved(bottomRight, toward: topRight, by: 0.3))
        let ends = 0.015
        let (tl2, bl2) = (moved(tl, toward: tr, by: ends / max(0.01, tr.x - tl.x)), moved(bl, toward: br, by: ends / max(0.01, br.x - bl.x)))
        let (tr2, br2) = (moved(tr, toward: tl, by: ends / max(0.01, tr.x - tl.x)), moved(br, toward: bl, by: ends / max(0.01, br.x - bl.x)))

        // Core Image measures from the bottom left, in pixels.
        let width = Double(cgImage.width), height = Double(cgImage.height)
        func pixel(_ p: CGPoint) -> CGPoint { CGPoint(x: min(1, max(0, p.x)) * width, y: (1 - min(1, max(0, p.y))) * height) }
        let filter = CIFilter.perspectiveCorrection()
        filter.inputImage = CIImage(cgImage: cgImage)
        filter.topLeft = pixel(tl2)
        filter.topRight = pixel(tr2)
        filter.bottomRight = pixel(br2)
        filter.bottomLeft = pixel(bl2)
        guard let output = filter.outputImage,
              let strip = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: strip)
    }
}
