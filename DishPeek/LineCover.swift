import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

// How one translated line is drawn over the menu photo so it looks printed there,
// the way Google Translate's camera does it: a patch of the menu with the original
// words wiped off, and the ink colour to write the translation in. Lines on a photo
// taken at an angle (or handwriting) are tilted, so the strip and the text are too.
nonisolated struct LineCover: @unchecked Sendable {
    nonisolated enum Alignment: Sendable {
        case leading, center, trailing
    }

    var box: [Double]           // the patch: x, y, width, height from 0 to 1 of the photo
    var paper: UIImage          // the photo under the patch, words removed
    var ink: UIColor
    var alignment: Alignment

    // The tilted strip the translation is written in, inside the patch.
    // Sizes are shares of the patch width, so they scale with the photo on screen.
    var center: CGPoint         // 0 to 1 of the patch's width and height
    var angle: Double           // radians, clockwise
    var length: Double
    var thickness: Double
    var fontSize: Double
}

extension Dish {
    // What is written over its line: the translation, plus the price if it was printed on the same line.
    var coverText: String {
        if let lineText, !priceText.isEmpty, lineText.contains(priceText), !lineTranslation.contains(priceText) {
            return "\(lineTranslation)  \(priceText)"
        }
        return lineTranslation
    }
}

// One line to cover: plain values, so the work can run off the main thread.
nonisolated struct LineJob: Sendable {
    var id: String
    var box: [Double]
    var quad: [Double]?
    var text: String
}

nonisolated enum LineCovers {
    static let context = CIContext()

    static func make(photo: UIImage, lines: [LineJob]) -> [String: LineCover] {
        guard let cgImage = photo.cgImage else { return [:] }
        let pixels = Pixels(cgImage)
        var covers: [String: LineCover] = [:]
        for line in lines where line.box.count == 4 {
            if let cover = cover(for: line, in: cgImage, pixels: pixels) {
                covers[line.id] = cover
            }
        }
        return covers
    }

    static func cover(for job: LineJob, in image: CGImage, pixels: Pixels) -> LineCover? {
        let width = Double(image.width)
        let height = Double(image.height)
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        let box = CGRect(x: job.box[0] * width, y: job.box[1] * height, width: job.box[2] * width, height: job.box[3] * height)
            .intersection(bounds)
        guard box.width > 4, box.height > 4 else { return nil }

        // 1. The line itself: centre, length, letter height and tilt, from its corners when we have them.
        var center = CGPoint(x: box.midX, y: box.midY)
        var length = box.width
        var letters = box.height
        var angle = 0.0
        if let q = job.quad, q.count == 8 {
            let corners = stride(from: 0, to: 8, by: 2).map { CGPoint(x: q[$0] * width, y: q[$0 + 1] * height) }
            let (topLeft, topRight, bottomRight, bottomLeft) = (corners[0], corners[1], corners[2], corners[3])
            center = CGPoint(x: corners.map(\.x).reduce(0, +) / 4, y: corners.map(\.y).reduce(0, +) / 4)
            length = (topLeft.distance(to: topRight) + bottomLeft.distance(to: bottomRight)) / 2
            letters = (topLeft.distance(to: bottomLeft) + topRight.distance(to: bottomRight)) / 2
            angle = atan2(topRight.y - topLeft.y, topRight.x - topLeft.x)
        }
        guard length > 4, letters > 4 else { return nil }
        let along = CGVector(dx: cos(angle), dy: sin(angle))

        // 2. The paper colour (what the edges of the line mostly are) and the ink (what stands out most).
        guard let (paper, ink) = pixels.paperAndInk(in: box) else { return nil }

        // 3. Room for the translation. Translations are often longer than the original,
        //    so grow the strip along the line into empty paper when needed.
        var fontSize = letters * 0.85
        let font = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
        let padding = letters * 0.5
        let needed = (job.text as NSString).size(withAttributes: [.font: font]).width + padding
        let middle = job.box[0] + job.box[2] / 2
        let alignment: LineCover.Alignment = abs(middle - 0.5) < 0.08 ? .center : (middle < 0.5 ? .leading : .trailing)
        if needed > length {
            let extra = needed - length
            // Which ends grow, and so where the centre moves to.
            let shift = alignment == .center ? 0 : (alignment == .leading ? extra / 2 : -extra / 2)
            let grownCenter = CGPoint(x: center.x + along.dx * shift, y: center.y + along.dy * shift)
            let ends = endStrips(center: center, length: length, grownCenter: grownCenter, grownLength: needed,
                                 thickness: letters, along: along)
            // Only grow over empty paper, never over another line's words.
            if pixels.isBlank(ends.map { $0.intersection(bounds) }, paper: paper) {
                center = grownCenter
                length = needed
            }
        }
        // Still too long for the room it has: a smaller size, the way a sign painter would squeeze it in.
        if needed > length, needed > padding {
            fontSize *= max(0.4, (length - padding) / (needed - padding))
        }

        // 4. The patch: the strip, tilted, with a little margin, and the box around it.
        let strip = CGSize(width: length + letters * 0.3, height: letters * 1.35)
        let patch = rotatedBounds(center: center, size: strip, angle: angle).intersection(bounds).integral
        guard patch.width > 2, patch.height > 2 else { return nil }

        // 5. Wipe the words off: spread the paper over the thin strokes of the letters, then shrink it back
        //    (a morphological "closing"), so the paper keeps its own brightness. Then soften.
        let radius = max(2, letters * 0.25)
        // Core Image measures from the bottom left.
        let flipped = CGRect(x: patch.minX, y: height - patch.maxY, width: patch.width, height: patch.height)
        let source = CIImage(cgImage: image).clampedToExtent()
        let (first, second) = paper.luminance > ink.luminance
            ? ("CIMorphologyMaximum", "CIMorphologyMinimum")
            : ("CIMorphologyMinimum", "CIMorphologyMaximum")
        let soft = source
            .applyingFilter(first, parameters: [kCIInputRadiusKey: radius])
            .applyingFilter(second, parameters: [kCIInputRadiusKey: radius])
            .applyingGaussianBlur(sigma: radius * 0.5)
        // Back in the photo's own colours, so the patch is not lighter or darker than the paper around it.
        let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let wiped = context.createCGImage(soft, from: flipped, format: .RGBA8, colorSpace: colorSpace) else { return nil }

        return LineCover(
            box: [patch.minX / width, patch.minY / height, patch.width / width, patch.height / height],
            paper: UIImage(cgImage: wiped),
            ink: ink.color,
            alignment: alignment,
            center: CGPoint(x: (center.x - patch.minX) / patch.width, y: (center.y - patch.minY) / patch.height),
            angle: angle,
            length: strip.width / patch.width,
            thickness: strip.height / patch.width,
            fontSize: fontSize / patch.width
        )
    }

    // The box around a rectangle turned by an angle.
    static func rotatedBounds(center: CGPoint, size: CGSize, angle: Double) -> CGRect {
        let w = abs(size.width * cos(angle)) + abs(size.height * sin(angle))
        let h = abs(size.width * sin(angle)) + abs(size.height * cos(angle))
        return CGRect(x: center.x - w / 2, y: center.y - h / 2, width: w, height: h)
    }

    // The parts of a grown strip beyond the original line, as boxes to check for other words.
    static func endStrips(center: CGPoint, length: Double, grownCenter: CGPoint, grownLength: Double,
                          thickness: Double, along: CGVector) -> [CGRect] {
        func point(_ c: CGPoint, _ offset: Double) -> CGPoint {
            CGPoint(x: c.x + along.dx * offset, y: c.y + along.dy * offset)
        }
        let oldStart = point(center, -length / 2), oldEnd = point(center, length / 2)
        let newStart = point(grownCenter, -grownLength / 2), newEnd = point(grownCenter, grownLength / 2)
        let angle = atan2(along.dy, along.dx)
        var strips: [CGRect] = []
        for (a, b) in [(newStart, oldStart), (oldEnd, newEnd)] {
            let span = a.distance(to: b)
            guard span > 1 else { continue }
            let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            strips.append(rotatedBounds(center: mid, size: CGSize(width: span, height: thickness), angle: angle))
        }
        return strips
    }
}

// The photo's pixels, read once, for sampling colours.
nonisolated struct Pixels {
    nonisolated struct RGB {
        var r: Double, g: Double, b: Double
        var luminance: Double { 0.299 * r + 0.587 * g + 0.114 * b }
        var color: UIColor { UIColor(red: r, green: g, blue: b, alpha: 1) }
        func distance(_ other: RGB) -> Double {
            ((r - other.r) * (r - other.r) + (g - other.g) * (g - other.g) + (b - other.b) * (b - other.b)).squareRoot()
        }
    }

    let width: Int
    let height: Int
    let bytes: [UInt8]

    init(_ image: CGImage) {
        let w = image.width
        let h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        data.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
            context?.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        width = w
        height = h
        bytes = data
    }

    // x and y are measured from the top left, in pixels.
    func at(_ x: Int, _ y: Int) -> RGB {
        let i = (min(max(y, 0), height - 1) * width + min(max(x, 0), width - 1)) * 4
        return RGB(r: Double(bytes[i]) / 255, g: Double(bytes[i + 1]) / 255, b: Double(bytes[i + 2]) / 255)
    }

    // 40 × 12 evenly spread samples from a rectangle.
    func samples(in rect: CGRect) -> [(x: Double, y: Double, rgb: RGB)] {
        let columns = 40, rows = 12
        var result: [(Double, Double, RGB)] = []
        for row in 0..<rows {
            for column in 0..<columns {
                let fx = (Double(column) + 0.5) / Double(columns)
                let fy = (Double(row) + 0.5) / Double(rows)
                result.append((fx, fy, at(Int(rect.minX + fx * rect.width), Int(rect.minY + fy * rect.height))))
            }
        }
        return result
    }

    func paperAndInk(in rect: CGRect) -> (RGB, RGB)? {
        let all = samples(in: rect)
        guard !all.isEmpty else { return nil }
        // The edge of a line's box is mostly paper.
        let edge = all.filter { $0.x < 0.08 || $0.x > 0.92 || $0.y < 0.12 || $0.y > 0.88 }.map(\.rgb)
        func median(_ values: [Double]) -> Double { values.sorted()[values.count / 2] }
        let paper = RGB(r: median(edge.map(\.r)), g: median(edge.map(\.g)), b: median(edge.map(\.b)))
        // The ink is what differs most from the paper.
        let farthest = all.map(\.rgb).sorted { $0.distance(paper) > $1.distance(paper) }.prefix(max(4, all.count / 10))
        let count = Double(farthest.count)
        var ink = RGB(
            r: farthest.map(\.r).reduce(0, +) / count,
            g: farthest.map(\.g).reduce(0, +) / count,
            b: farthest.map(\.b).reduce(0, +) / count
        )
        // Too little contrast to tell: plain black or white, whichever reads on this paper.
        if ink.distance(paper) < 0.2 {
            ink = paper.luminance > 0.5 ? RGB(r: 0.1, g: 0.1, b: 0.1) : RGB(r: 0.95, g: 0.95, b: 0.95)
        }
        return (paper, ink)
    }

    // True if almost every sample in these rectangles is close to the paper colour.
    func isBlank(_ rects: [CGRect], paper: RGB) -> Bool {
        for rect in rects where rect.width > 1 && rect.height > 1 {
            let found = samples(in: rect)
            let marked = found.filter { $0.rgb.distance(paper) > 0.25 }.count
            if Double(marked) / Double(found.count) > 0.04 { return false }
        }
        return true
    }
}

extension CGPoint {
    nonisolated func distance(to other: CGPoint) -> Double {
        ((x - other.x) * (x - other.x) + (y - other.y) * (y - other.y)).squareRoot()
    }
}
