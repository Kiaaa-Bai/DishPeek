import SwiftUI
import UIKit

// The user's own menu photo, with every dish line made tappable where it sits on the paper.
// Translated, each line's words are wiped off and the translation is written in the same ink,
// so it reads as if printed on the menu (like Google Translate's camera). No boxes: only the
// line being looked at is highlighted.
// The language switch sits in the bar above, so it stays in reach on a long menu.
// With the AI redraw on, the translated side is the redrawn picture instead, stretched to the photo's
// shape, and its lines are tappable where Vision found them on it.
struct PhotoMenu: View {
    @Environment(AppState.self) var state
    var image: UIImage
    var menu: ScannedMenu
    var selected: String?
    var onTap: (Dish) -> Void

    var showsTranslation: Bool { state.photoShowsTranslation }

    var body: some View {
        Image(uiImage: state.showsRedrawn ? state.redrawn!.image : image)
            .resizable()
            .aspectRatio(image.size, contentMode: .fit)
            .overlay {
                GeometryReader { geo in
                    ForEach(menu.dishes.filter { state.shownBox($0) != nil }) { dish in
                        // The redrawn picture already has the translation in it: no cover.
                        let cover = state.showsRedrawn ? nil : state.lineCovers[dish.id]
                        let frame = frame(for: dish, cover: cover, in: geo.size)
                        Button {
                            onTap(dish)
                        } label: {
                            PhotoLine(dish: dish, cover: cover, isSelected: selected == dish.id, translated: showsTranslation && !state.showsRedrawn, height: frame.height)
                        }
                        .buttonStyle(LineButtonStyle())
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                        .id(dish.id)
                        .accessibilityLabel("\(dish.name), \(dish.originalName), \(menu.money(dish))")
                    }
                }
            }
            .animation(.snappy(duration: 0.2), value: showsTranslation)
            .sensoryFeedback(.selection, trigger: showsTranslation)
    }

    // Where a line sits on screen. A cover must line up with the photo exactly;
    // otherwise the line gets a little extra room so it is easy to tap.
    func frame(for dish: Dish, cover: LineCover?, in size: CGSize) -> CGRect {
        let box = cover?.box ?? state.shownBox(dish)!
        let rect = CGRect(x: box[0] * size.width, y: box[1] * size.height, width: box[2] * size.width, height: box[3] * size.height)
        if cover != nil { return rect }
        if showsTranslation && !state.showsRedrawn {
            // No cover yet (still being made): a plain label with room for the longer translation.
            let width = min(max(rect.width, 170), size.width - 8)
            let x = min(max(4, rect.midX - width / 2), size.width - 4 - width)
            return CGRect(x: x, y: rect.minY - 4, width: width, height: rect.height + 8)
        }
        return rect.insetBy(dx: -6, dy: -4)
    }
}

// Pressing a line tints it, so people see the tap land.
struct LineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay {
                if configuration.isPressed {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.action.opacity(0.3))
                }
            }
    }
}

// One dish line on the photo.
struct PhotoLine: View {
    var dish: Dish
    var cover: LineCover?
    var isSelected: Bool
    var translated: Bool
    var height: CGFloat

    var body: some View {
        ZStack {
            if let cover {
                printed(cover)
            } else if translated {
                // No cover yet (still being made): a plain label.
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.surface.opacity(0.96))
                highlight
                Text(verbatim: dish.coverText)
                    .font(.system(size: min(22, max(11, height * 0.6)), weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, 6)
                    .overlay(alignment: .bottom) { underline }
            } else {
                highlight
                    .overlay(alignment: .bottom) { underline }
            }
        }
        .overlay(alignment: .topTrailing) {
            if dish.knownFor {
                Image(systemName: "star.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.textOnAction)
                    .frame(width: 15, height: 15)
                    .background(Color.action, in: Circle())
                    .offset(x: 5, y: -6)
            }
        }
        .animation(.snappy(duration: 0.25), value: isSelected)
        // Taps count only on the line itself, so tilted lines that overlap don't steal each other's taps.
        .contentShape(tapShape)
    }

    var tapShape: AnyShape {
        if let cover {
            AnyShape(Strip(center: cover.center, size: CGSize(width: cover.length, height: cover.thickness), angle: cover.angle))
        } else {
            AnyShape(Rectangle())
        }
    }

    // The translation written into the wiped strip, tilted like the printed line was.
    // In the original language only the highlight shows, along the same tilted strip.
    func printed(_ cover: LineCover) -> some View {
        GeometryReader { geo in
            let scale = geo.size.width
            let strip = CGSize(width: cover.length * scale, height: cover.thickness * scale)
            let center = CGPoint(x: cover.center.x * geo.size.width, y: cover.center.y * geo.size.height)
            ZStack {
                if translated {
                    // The wiped paper, only along the line, its edges softened into the photo.
                    Image(uiImage: cover.paper)
                        .resizable()
                        .mask {
                            RoundedRectangle(cornerRadius: strip.height * 0.3)
                                .frame(width: strip.width, height: strip.height)
                                .blur(radius: 1.5)
                                .rotationEffect(.radians(cover.angle))
                                .position(center)
                        }
                }
                ZStack {
                    highlight
                    if translated {
                        Text(verbatim: dish.coverText)
                            .font(.system(size: cover.fontSize * scale, weight: .semibold))
                            .foregroundStyle(Color(uiColor: cover.ink))
                            .lineLimit(1)
                            .minimumScaleFactor(0.3)
                            .padding(.horizontal, strip.height * 0.2)
                            .frame(width: strip.width, alignment: cover.alignment.frameAlignment)
                    }
                }
                .frame(width: strip.width, height: strip.height)
                .overlay(alignment: .bottom) { underline }
                .rotationEffect(.radians(cover.angle))
                .position(center)
            }
        }
    }

    // Only the selected line shows anything over the photo: a soft wash of the accent colour.
    @ViewBuilder var highlight: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.action.opacity(0.28))
        }
    }

    // The line being looked at also gets an underline in the accent colour.
    @ViewBuilder var underline: some View {
        if isSelected {
            Capsule()
                .fill(Color.action)
                .frame(height: 3)
                .padding(.horizontal, 2)
                .offset(y: 2)
        }
    }
}

// A tilted strip inside a rectangle: centre as 0 to 1 of the rectangle, size as shares of its width.
struct Strip: Shape {
    var center: CGPoint
    var size: CGSize
    var angle: Double

    func path(in rect: CGRect) -> Path {
        let width = size.width * rect.width
        let height = size.height * rect.width
        let middle = CGPoint(x: rect.minX + center.x * rect.width, y: rect.minY + center.y * rect.height)
        return Path(CGRect(x: -width / 2, y: -height / 2, width: width, height: height))
            .applying(CGAffineTransform(rotationAngle: angle))
            .applying(CGAffineTransform(translationX: middle.x, y: middle.y))
    }
}

extension LineCover.Alignment {
    var frameAlignment: Alignment {
        switch self {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }
}
