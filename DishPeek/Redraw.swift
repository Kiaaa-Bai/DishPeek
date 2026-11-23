import UIKit
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins

// The whole menu redrawn by AI in the user's language (always on: the app's core),
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
            let drawn = try await Backend.redrawMenu(photo: jpeg, aspectRatio: aspectRatio(for: size), translations: translations, into: language)
            // Lined up with the photo first, so switching between original and translation only changes the text,
            // and the lines are then read where they will be shown.
            let image = await aligned(drawn, toPhoto: jpeg)
            let lines = try await MenuReader.lines(in: image)
            return RedrawnMenu(image: image, boxes: match(menu.dishes, to: lines))
        } catch {
            #if DEBUG
            print("[scan] redraw failed: \(error)")
            #endif
            return nil
        }
    }

    // The image model doesn't always keep the photo's framing: it can shift, scale or slightly tilt the
    // menu, so switching to the original seemed to move the photo (Kia, 2026-11-19). Vision measures how the
    // redrawn picture sits against the photo (from the board's edges, the food photos, the background),
    // and the picture is warped back onto it. Tested on two redraws: the difference to the photo dropped
    // from 20 to 13 and from 13 to 10 (mean pixel difference, 0 to 255).
    // If the measurement looks wrong (a corner would move more than a fifth of the picture), it is skipped.
    static func aligned(_ drawn: UIImage, toPhoto jpeg: String) async -> UIImage {
        guard let data = Data(base64Encoded: jpeg), let photo = UIImage(data: data) else { return drawn }
        return await Task.detached(priority: .userInitiated) {
            alignNow(drawn, to: photo) ?? drawn
        }.value
    }

    nonisolated private static func alignNow(_ drawn: UIImage, to photo: UIImage) -> UIImage? {
        // The photo comes from the JPEG the app made itself, which is already the right way up.
        guard let reference = photo.cgImage else { return nil }
        let size = CGSize(width: reference.width, height: reference.height)
        // The same pixel size as the photo: it is shown stretched to the photo's shape anyway.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let stretched = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            drawn.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let floating = stretched.cgImage else { return nil }

        let request = VNHomographicImageRegistrationRequest(targetedCGImage: floating)
        guard (try? VNImageRequestHandler(cgImage: reference).perform([request])) != nil,
              let warp = request.results?.first?.warpTransform else { return nil }

        // Where each corner of the redrawn picture belongs on the photo (Core Image counts from the bottom left).
        let corners = [CGPoint(x: 0, y: 0), CGPoint(x: size.width, y: 0), CGPoint(x: 0, y: size.height), CGPoint(x: size.width, y: size.height)]
        let moved = corners.map { point -> CGPoint in
            let v = warp * SIMD3<Float>(Float(point.x), Float(point.y), 1)
            return CGPoint(x: CGFloat(v.x / v.z), y: CGFloat(v.y / v.z))
        }
        let farthest = zip(corners, moved).map { hypot($0.x - $1.x, $0.y - $1.y) }.max() ?? 0
        guard farthest < 0.2 * max(size.width, size.height) else { return nil }

        let filter = CIFilter.perspectiveTransform()
        filter.inputImage = CIImage(cgImage: floating)
        filter.bottomLeft = moved[0]
        filter.bottomRight = moved[1]
        filter.topLeft = moved[2]
        filter.topRight = moved[3]
        // Where the warped picture no longer reaches the edge, the photo shows through, never a gap.
        let photoImage = CIImage(cgImage: reference)
        guard let output = filter.outputImage?.composited(over: photoImage).cropped(to: photoImage.extent),
              let result = CIContext().createCGImage(output, from: photoImage.extent) else { return nil }
        return UIImage(cgImage: result)
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
