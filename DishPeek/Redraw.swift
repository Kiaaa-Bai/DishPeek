import UIKit

// The whole menu redrawn by AI in the user's language (Settings → Redraw the menu with AI),
// and where each dish's line is on the new picture. The image model can move lines around,
// so the app reads the new picture with Vision and matches each line to the dish whose
// translation it shows.
struct RedrawnMenu {
    var image: UIImage
    var boxes: [String: [Double]]   // dish id → x, y, width, height from 0 to 1 on the picture
}

enum Redraw {
    // The image model only draws these shapes (width:height).
    static let ratios: [(name: String, value: CGFloat)] = [
        ("1:1", 1), ("2:3", 2.0 / 3), ("3:2", 3.0 / 2), ("3:4", 3.0 / 4), ("4:3", 4.0 / 3),
        ("4:5", 4.0 / 5), ("5:4", 5.0 / 4), ("9:16", 9.0 / 16), ("16:9", 16.0 / 9),
    ]

    // The shape closest to the photo's. The picture is stretched back to the photo's shape on screen,
    // which changes it by a few percent at most.
    static func aspectRatio(for size: CGSize) -> String {
        let value = size.width / max(1, size.height)
        return ratios.min { abs($0.value - value) < abs($1.value - value) }!.name
    }

    // Redraw the menu with the translations scanMenu already made, then find each dish on it.
    // Nil if anything fails: the app then writes the translation over each line instead.
    static func menu(photo jpeg: String, size: CGSize, menu: ScannedMenu, into language: String) async -> RedrawnMenu? {
        let translations = menu.dishes.compactMap { dish in
            dish.lineText.map { Bilingual(original: $0, translated: dish.coverText) }
        }
        do {
            let image = try await Backend.redrawMenu(photo: jpeg, aspectRatio: aspectRatio(for: size), translations: translations, into: language)
            let lines = try await MenuReader.lines(in: image)
            return RedrawnMenu(image: image, boxes: match(menu.dishes, to: lines))
        } catch {
            #if DEBUG
            print("[scan] redraw failed: \(error)")
            #endif
            return nil
        }
    }

    // Each dish gets the line that reads most like its translation. The best matches are taken first,
    // and a line belongs to one dish only. A dish with no line that reads at least half like it gets none.
    static func match(_ dishes: [Dish], to lines: [MenuText]) -> [String: [Double]] {
        let read = lines.map { pairs($0.text) }
        var candidates: [(dish: String, line: Int, score: Double)] = []
        for dish in dishes {
            let wanted = [dish.coverText, dish.lineTranslation, dish.name].map { pairs($0) }
            for (index, have) in read.enumerated() {
                let score = wanted.map { similarity($0, have) }.max() ?? 0
                if score >= 0.5 {
                    candidates.append((dish.id, index, score))
                }
            }
        }
        var boxes: [String: [Double]] = [:]
        var taken = Set<Int>()
        for candidate in candidates.sorted(by: { $0.score > $1.score }) {
            guard boxes[candidate.dish] == nil, !taken.contains(candidate.line) else { continue }
            boxes[candidate.dish] = lines[candidate.line].box
            taken.insert(candidate.line)
        }
        return boxes
    }

    // Neighbouring letter pairs, lowercased, without spaces or punctuation: "Beef w." → be, ee, ef, fw.
    // Comparing pairs instead of whole words still works when the reader gets a letter wrong.
    static func pairs(_ text: String) -> [String] {
        let letters = Array(text.lowercased().filter { $0.isLetter || $0.isNumber })
        guard letters.count > 1 else { return letters.map(String.init) }
        return (0..<letters.count - 1).map { String(letters[$0...$0 + 1]) }
    }

    // How alike two texts are, from 0 to 1: the share of letter pairs they have in common.
    static func similarity(_ a: [String], _ b: [String]) -> Double {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        var left: [String: Int] = [:]
        for pair in b {
            left[pair, default: 0] += 1
        }
        var shared = 0
        for pair in a where left[pair, default: 0] > 0 {
            shared += 1
            left[pair]! -= 1
        }
        return 2 * Double(shared) / Double(a.count + b.count)
    }
}
