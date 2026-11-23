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
    @State var hintStart = Date()

    // How bright a line at height y (0 top to 1 bottom) is at time t: a wave runs down the menu twice,
    // starting after a short pause, then stays dark.
    static func wave(_ t: Double, y: Double) -> Double {
        let start = 0.6, pass = 1.6
        var best = 0.0
        for run in 0..<2 {
            let front = (t - start - Double(run) * (pass + 0.5)) / pass   // 0 at the top, 1 at the bottom
            let distance = abs(front - y) / 0.18
            best = max(best, max(0, 1 - distance * distance))
        }
        return best
    }

    var body: some View {
        // Read the menu from the state, not the copy passed in: this view lives in ZoomView's own hosting
        // controller, and the copy went stale when details (like Peek's Pick) arrived after the menu was shown.
        let menu = state.menu
        return Image(uiImage: state.showsRedrawn ? state.redrawn!.image : image)
            .resizable()
            .aspectRatio(image.size, contentMode: .fit)
            // Until the first tap: the dish lines light up in a wave from the top, twice, the way they did
            // during the scan, to show they can be tapped.
            .overlay {
                if !state.hasTappedDish {
                    GeometryReader { geo in
                        TimelineView(.animation) { context in
                            let t = context.date.timeIntervalSince(hintStart)
                            ZStack {
                                ForEach(menu.dishes.filter { state.shownBox($0) != nil }) { dish in
                                    let cover = state.showsRedrawn ? nil : state.lineCovers[dish.id]
                                    let frame = frame(for: dish, cover: cover, in: geo.size)
                                    let glow = Self.wave(t, y: frame.midY / max(1, geo.size.height))
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.white.opacity(0.18 * glow))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white.opacity(0.6 * glow), lineWidth: 1.2)
                                        }
                                        .shadow(color: .white.opacity(0.7 * glow), radius: 8 * glow)
                                        .frame(width: frame.width, height: frame.height)
                                        .position(x: frame.midX, y: frame.midY)
                                }
                            }
                        }
                    }
                    .allowsHitTesting(false)
                    .onAppear { hintStart = Date() }
                }
            }
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
                        // Peek's Pick: a pin just before the line, sized to its text, so it covers no words
                        // (Kia, 2026-11-21).
                        .overlay(alignment: .leading) {
                            if dish.peekPick {
                                // Bigger than the line's letters, so the logo in it can be made out.
                                let size = min(60, max(26, frame.height * 1.7))
                                PeekPin(size: size)
                                    .offset(x: -size * 0.9)
                            }
                        }
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

// Peek's Pick on the menu photo: the round logo sticker just before the line (Kia, 2026-11-21).
struct PeekPin: View {
    var size: CGFloat

    var body: some View {
        PeekRoundSticker(size: size)
            .accessibilityHidden(true)
    }
}

// The four-pointed sparkle from the Peek's Pick mark, filling its frame.
struct SparkleShape: Shape {
    func path(in rect: CGRect) -> Path {
        PeekMark.sparkle(center: CGPoint(x: rect.midX, y: rect.midY), radius: min(rect.width, rect.height) / 2)
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
    @State var glowing = false

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
        .animation(.snappy(duration: 0.25), value: isSelected)
        // Taps count only on the line itself, so tilted lines that overlap don't steal each other's taps.
        .contentShape(tapShape)
        .onChange(of: isSelected, initial: true) {
            guard isSelected else { glowing = false; return }
            glowing = false
            withAnimation(.easeOut(duration: 0.35)) {
                glowing = true
            } completion: {
                withAnimation(.easeIn(duration: 0.6)) {
                    glowing = false
                }
            }
        }
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
    // It glows once when it is picked, so it can be found at a glance: after "Show on the menu" the menu
    // opens on it (Kia, 2026-11-21: once, not five times).
    @ViewBuilder var highlight: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.action.opacity(0.28))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.action, lineWidth: 2)
                        .opacity(glowing ? 1 : 0.35)
                }
                .shadow(color: Color.action.opacity(glowing ? 0.9 : 0), radius: glowing ? 10 : 0)
                .scaleEffect(glowing ? 1.05 : 1)
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
