import UIKit
import Vision
import CoreLocation

// One line of text on the menu photo, and where it is:
// x, y, width, height from 0 to 1, measured from the photo's top left corner.
// quad is the line's four corners (top left, top right, bottom right, bottom left; x and y each),
// which also says how the line is tilted on a photo taken at an angle.
struct MenuText: Codable, Hashable {
    var text: String
    var box: [Double]
    var quad: [Double]? = nil
}

// Reads the text on a menu photo on the phone itself, with Apple Vision.
// No network and no wait, and it knows exactly where each line is.
enum MenuReader {
    static func lines(in image: UIImage) async throws -> [MenuText] {
        guard let cgImage = image.cgImage else { return [] }

        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        // Menus can be in any language, so let Vision work it out.
        request.automaticallyDetectsLanguage = true
        request.usesLanguageCorrection = true

        let observations = try await request.perform(on: cgImage, orientation: image.cgImageOrientation)

        let lines = observations.compactMap { observation -> MenuText? in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            // Vision measures from the bottom left; flip to top left like the screen.
            let r = observation.boundingBox.cgRect
            let box = [r.minX, 1 - r.maxY, r.width, r.height].map { Double($0) }
            let corners = [observation.topLeft, observation.topRight, observation.bottomRight, observation.bottomLeft]
            let quad = corners.flatMap { [Double($0.x), Double(1 - $0.y)] }
            return MenuText(text: text, box: box, quad: quad)
        }

        // Top to bottom, then left to right, the way people read a menu.
        return lines.sorted { a, b in
            if abs(a.box[1] - b.box[1]) > 0.01 { return a.box[1] < b.box[1] }
            return a.box[0] < b.box[0]
        }
    }
}

// Cuts the photo down to the part with the menu on it, so the lines are big enough to read.
// A menu photographed from across the table can fill a tenth of the picture.
enum MenuCrop {
    static func toText(_ image: UIImage, lines: [MenuText]) -> (image: UIImage, lines: [MenuText]) {
        // With only a line or two read, they are as likely a sign or a logo as the menu: keep the whole photo.
        guard let cgImage = image.cgImage, lines.count >= 3 else { return (image, lines) }

        // The smallest box around every line, plus a margin.
        var left = lines.map { $0.box[0] }.min()!
        var top = lines.map { $0.box[1] }.min()!
        var right = lines.map { $0.box[0] + $0.box[2] }.max()!
        var bottom = lines.map { $0.box[1] + $0.box[3] }.max()!
        let margin = 0.04
        left -= margin
        right += margin
        top -= margin
        bottom += margin

        // A narrow strip of paper would be very tall on screen: widen it to at least half its height.
        let imageWidth = Double(cgImage.width)
        let imageHeight = Double(cgImage.height)
        let minWidth = (bottom - top) * imageHeight * 0.55 / imageWidth
        if right - left < minWidth {
            let middle = (left + right) / 2
            left = middle - minWidth / 2
            right = middle + minWidth / 2
        }

        left = max(0, left)
        top = max(0, top)
        right = min(1, right)
        bottom = min(1, bottom)

        // Already mostly menu: keep the whole photo.
        if (right - left) * (bottom - top) > 0.8 { return (image, lines) }

        let pixels = CGRect(
            x: left * imageWidth,
            y: top * imageHeight,
            width: (right - left) * imageWidth,
            height: (bottom - top) * imageHeight
        ).integral
        guard let cropped = cgImage.cropping(to: pixels) else { return (image, lines) }

        // Measure each line again, now inside the cut-out.
        let width = right - left
        let height = bottom - top
        let moved = lines.map { line in
            MenuText(
                text: line.text,
                box: [
                    (line.box[0] - left) / width,
                    (line.box[1] - top) / height,
                    line.box[2] / width,
                    line.box[3] / height,
                ],
                quad: line.quad.map { quad in
                    quad.enumerated().map { index, value in
                        index.isMultiple(of: 2) ? (value - left) / width : (value - top) / height
                    }
                }
            )
        }
        return (UIImage(cgImage: cropped, scale: image.scale, orientation: .up), moved)
    }
}

extension UIImage {
    // A small JPEG as base64 text, for sending the menu photo to the server.
    func smallJPEG(longSide: CGFloat = 1600) -> String? {
        let scale = min(1, longSide / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let small = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
        return small.jpegData(compressionQuality: 0.7)?.base64EncodedString()
    }

    // The same photo, turned the right way up, so pixel positions match what people see.
    func upright() -> UIImage {
        if imageOrientation == .up { return self }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    // A photo from the camera is often stored sideways with a note saying which way is up.
    var cgImageOrientation: CGImagePropertyOrientation {
        switch imageOrientation {
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        case .upMirrored: .upMirrored
        case .downMirrored: .downMirrored
        case .leftMirrored: .leftMirrored
        case .rightMirrored: .rightMirrored
        @unknown default: .up
        }
    }
}

// Where the user is, once, to find the restaurant they are in.
enum Locator {
    static func current() async -> CLLocationCoordinate2D? {
        // Give up after a few seconds: the menu matters more than the rating.
        return await withTaskGroup(of: CLLocationCoordinate2D?.self) { group in
            group.addTask {
                // Holding a session asks for permission the first time and keeps it while we look.
                let session = CLServiceSession(authorization: .whenInUse)
                defer { withExtendedLifetime(session) {} }
                do {
                    for try await update in CLLocationUpdate.liveUpdates() {
                        if let location = update.location {
                            return location.coordinate
                        }
                        if update.authorizationDenied || update.authorizationDeniedGlobally {
                            return nil
                        }
                    }
                } catch {}
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(6))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
