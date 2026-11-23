import SwiftUI

// MARK: - Badges (Known for, #1 on DishPeek, Spicy, Shellfish: not sure)

enum BadgeStyle {
    case top
    case neutral
    case caution
}

struct BadgeInfo: Identifiable {
    var text: String
    var icon: String? = nil
    // The Peek's Pick mark instead of a symbol.
    var peekMark = false
    // An emoji instead of a symbol: ingredients use the same emoji as the food choices in Settings.
    var emoji: String? = nil
    var style: BadgeStyle
    // Shorter text for tight spots; empty means icon only.
    var short: String? = nil
    var id: String { text }

    var compact: BadgeInfo {
        BadgeInfo(text: short ?? text, icon: icon, peekMark: peekMark, emoji: emoji, style: style)
    }
}

struct Badge: View {
    var info: BadgeInfo

    var body: some View {
        HStack(spacing: 4) {
            if let emoji = info.emoji {
                Text(verbatim: emoji)
                    .font(.system(size: 12))
            } else if info.peekMark {
                PeekMark(height: 13)
            } else if let icon = info.icon {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
            }
            if !info.text.isEmpty {
                Text(info.text)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(foreground)
        // A little tighter before the Peek mark: the gap looked too big (Kia, 2026-11-21).
        .padding(.leading, info.peekMark ? 6 : 8)
        .padding(.trailing, 8)
        .frame(height: 22)
        .background(background, in: Capsule())
    }

    var foreground: Color {
        switch info.style {
        case .top: Color.textOnAction
        case .neutral: Color.textPrimary
        case .caution: Color.caution
        }
    }

    var background: Color {
        switch info.style {
        case .top: Color.action
        case .neutral: Color.border
        case .caution: Color.cautionSubtle
        }
    }
}

struct BadgeRow: View {
    var badges: [BadgeInfo]

    // As many on a line as fit, then the next line, so none get cut off.
    var body: some View {
        FlowLayout(spacing: 4) {
            ForEach(badges) { badge in
                Badge(info: badge)
            }
        }
    }
}

extension AppState {
    // Short badges next to a line on the menu photo.
    func lineBadges(_ dish: Dish) -> [BadgeInfo] {
        var badges: [BadgeInfo] = []
        if dish.isSpicy {
            badges.append(BadgeInfo(text: String(localized: "Spicy"), icon: "flame.fill", style: .caution, short: ""))
        }
        return badges
    }

    // Why a dish is popular: Google Maps, the menu's own marks, DishPeek orders, and the AI's local classics.
    func popularityBadges(_ dish: Dish) -> [BadgeInfo] {
        var badges: [BadgeInfo] = []
        if menu.dishPeekRank(dish) == 1 {
            badges.append(BadgeInfo(text: String(localized: "#1 on DishPeek"), icon: "person.2.fill", style: .neutral))
        }
        if dish.peekPick {
            // One label for the AI's picks and the menu's own specials (Kia, 2026-11-20: no separate
            // "House special"). Renamed from "DishPick", which read as generic.
            badges.insert(BadgeInfo(text: String(localized: "Peek's Pick"), peekMark: true, style: .neutral), at: 0)
        }
        return badges
    }

    // Popularity, then the warnings that matter to this user.
    func cardBadges(_ dish: Dish) -> [BadgeInfo] {
        popularityBadges(dish) + flagBadges(dish)
    }

    // What the dish contains, as the same emoji pills as the food choices in Settings (Kia, 2026-11-19).
    // Everything it contains is shown; what this user avoids comes first and stands out. Then the
    // "not sure" ones that matter to them. No warning icons: the pill says it.
    // The list and the peek show only what this user avoids; the dish page shows everything (Kia, 2026-11-19).
    func ingredientBadges(_ dish: Dish, onlyAvoided: Bool = false) -> [BadgeInfo] {
        let avoided = Set(avoid.flatMap { $0.tags })
        var tags: [Allergen] = []
        for tag in dish.contains where !tags.contains(tag) {
            // "Meat" next to "Pork" or "Beef" says nothing new.
            if tag == .meat && (dish.contains.contains(.pork) || dish.contains.contains(.beef)) { continue }
            if onlyAvoided && !avoided.contains(tag) { continue }
            tags.append(tag)
        }
        tags.sort { avoided.contains($0) && !avoided.contains($1) }
        var badges = tags.map { tag in
            BadgeInfo(text: tag.title, emoji: tag.emoji, style: avoided.contains(tag) ? .caution : .neutral)
        }
        for item in unsure(dish) {
            badges.append(BadgeInfo(text: String(localized: "\(item.allergen.title): not sure"), emoji: item.allergen.emoji, style: .caution))
        }
        return badges
    }

    // Under a dish in the list and the peek: its ingredients, and spice.
    func flagBadges(_ dish: Dish) -> [BadgeInfo] {
        // Allergens arrive with the details. Until then say so, so a missing warning never reads as safe.
        if isExplaining(dish) && !avoid.isEmpty {
            return [BadgeInfo(text: String(localized: "Checking allergens…"), icon: "hourglass", style: .caution)]
        }
        var badges = ingredientBadges(dish, onlyAvoided: true)
        if let note = spiceNote(dish) {
            badges.append(BadgeInfo(text: note, icon: "flame.fill", style: .caution))
        }
        return badges
    }
}

// MARK: - Chip (shows a checkmark when selected)

struct Chip: View {
    var title: String
    var emoji: String? = nil        // shown instead of the checkmark; the fill shows it's on
    var isOn: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let emoji {
                    Text(verbatim: emoji)
                        .font(.system(size: 16))
                } else if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                }
                Text(title)
                    .font(.system(size: 15, weight: .medium))
            }
            // Always as wide as its words: "✓ 2" was cut off when the meal panel first rose (2026-11-21).
            .fixedSize()
            .foregroundStyle(isOn ? Color.textOnAction : Color.textPrimary)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(isOn ? Color.action : Color.surface, in: Capsule())
            .overlay {
                Capsule().strokeBorder(isOn ? Color.clear : Color.border)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isOn)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

// Lays chips out in rows, starting a new row when the next one doesn't fit.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map { $0.height }.reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map { $0.width }.max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.items {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    struct Row {
        var items: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    func rows(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].items.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > width, !rows[rows.count - 1].items.isEmpty {
                rows.append(Row())
            }
            let last = rows.count - 1
            rows[last].width += (rows[last].items.isEmpty ? 0 : spacing) + size.width
            rows[last].height = max(rows[last].height, size.height)
            rows[last].items.append(index)
        }
        return rows
    }
}

// MARK: - Photo / List toggle

struct PhotoListToggle: View {
    @Binding var mode: MenuMode
    @Namespace var pill

    var body: some View {
        HStack(spacing: 0) {
            segment(.photo, title: String(localized: "Photo"), icon: "photo")
            segment(.list, title: String(localized: "List"), icon: "list.bullet")
        }
        .padding(4)
        .glassEffect(.regular, in: .capsule)
    }

    func segment(_ value: MenuMode, title: String, icon: String) -> some View {
        let isOn = mode == value
        return Button {
            withAnimation(.snappy(duration: 0.25)) {
                mode = value
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                Text(title)
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(isOn ? Color.textPrimary : Color.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background {
                if isOn {
                    Capsule()
                        .fill(Color.surface)
                        .shadow(color: .black.opacity(0.08), radius: 4, y: 1)
                        .matchedGeometryEffect(id: "pill", in: pill)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isOn)
    }
}

// MARK: - Buttons

// Green Liquid Glass button for the main action on a screen.
struct ActionButton: View {
    var title: LocalizedStringKey
    var fullWidth = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.textOnAction)
                .padding(.horizontal, 6)
                .frame(maxWidth: fullWidth ? .infinity : nil)
        }
        .buttonStyle(.glassProminent)
        .tint(Color.action)
        .controlSize(.large)
    }
}

// Clear Liquid Glass button for the second action.
struct GlassButton: View {
    var title: LocalizedStringKey
    var fullWidth = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.textPrimary)
                .padding(.horizontal, 6)
                .frame(maxWidth: fullWidth ? .infinity : nil)
        }
        .buttonStyle(.glass)
        .controlSize(.large)
    }
}

// A round glass button with an icon, and the count inside it when there is one. The menu's Order and
// Can't decide are these (Kia, 2026-11-21: an icon and a number instead of words).
struct IconButton: View {
    var systemName: String
    var label: LocalizedStringKey
    var prominent = false
    var count = 0
    var action: () -> Void

    var body: some View {
        Group {
            if prominent {
                Button(action: action) { icon.foregroundStyle(Color.textOnAction) }
                    .buttonStyle(.glassProminent)
                    .tint(Color.action)
            } else {
                Button(action: action) { icon.foregroundStyle(Color.textPrimary) }
                    .buttonStyle(.glass)
            }
        }
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .animation(.snappy, value: count)
        .accessibilityLabel(Text(label))
    }

    // The icon, with the count written inside it (Kia, 2026-11-21: inside the bag, not on its corner).
    var icon: some View {
        ZStack {
            Image(systemName: systemName)
                .font(.system(size: count > 0 ? 24 : 20, weight: .semibold))
            if count > 0 {
                Text(verbatim: "\(count)")
                    .font(.system(size: 12, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(prominent ? Color.action : Color.surface)
                    .contentTransition(.numericText())
                    .offset(y: 2.5)
            }
        }
        .frame(width: 32, height: 32)
    }
}

// Two buttons pinned to the bottom of a screen.
struct BottomButtons<Leading: View, Trailing: View>: View {
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        GlassEffectContainer {
            HStack {
                leading
                Spacer()
                trailing
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 4)
    }
}

// MARK: - Dish photo

struct DishPhoto: View {
    var dish: Dish
    var size: CGFloat
    var height: CGFloat? = nil
    var radius: CGFloat = Radius.small

    var body: some View {
        Color.actionSubtle
            .frame(width: size, height: height ?? size)
            .overlay {
                if let photo = dish.photos.first {
                    DishImage(source: photo)
                } else {
                    Image(systemName: "fork.knife")
                        .font(.system(size: size * 0.3))
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: radius))
    }
}

// One dish picture: a photo that ships with the app, or one found on the web.
struct DishImage: View {
    var source: String
    // Fit shows the whole photo (the full-screen viewer); fill crops it to the frame.
    var fit = false

    var body: some View {
        if source.hasPrefix("https://"), let url = URL(string: source) {
            WebPhoto(url: url, fit: fit)
        } else {
            Image(source)
                .resizable()
                .aspectRatio(contentMode: fit ? .fit : .fill)
        }
    }
}

// Photos already downloaded, kept in memory. AsyncImage downloads again every time a photo appears,
// so the full-screen viewer opened black and the photo popped in late (Kia, 2026-11-19).
enum PhotoCache {
    nonisolated(unsafe) static let images = NSCache<NSURL, UIImage>()
}

// A photo from the web: shown at once if it was downloaded before, otherwise faded in when it arrives.
struct WebPhoto: View {
    var url: URL
    var fit: Bool
    @State var image: UIImage?

    init(url: URL, fit: Bool) {
        self.url = url
        self.fit = fit
        _image = State(initialValue: PhotoCache.images.object(forKey: url as NSURL))
    }

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: fit ? .fit : .fill)
            } else {
                fit ? Color.clear : Color.actionSubtle
            }
        }
        .task(id: url) {
            if image != nil { return }
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let downloaded = await UIImage(data: data)?.byPreparingForDisplay() else { return }
            PhotoCache.images.setObject(downloaded, forKey: url as NSURL)
            withAnimation(.easeOut(duration: 0.25)) {
                image = downloaded
            }
        }
    }
}

// The DishPeek logo exactly as designed: the two shapes from the brand file
// (dishpeek-mark.svg, a 99 × 55 view box). The holes (the open eye in
// the "d", the wink in the "p") are cut out, so whatever is behind shows through, like the real mark.
// It replaces a version drawn by eye that got the wink wrong (Kia, 2026-11-21).
enum DishPeekLogo {
    static let size = CGSize(width: 99, height: 55)

    // The "d": a ring and its stem. Its hole is a circle, the open eye.
    static let d = svgPath("M49.747 0.179131C51.1314 -0.186759 52.6049 0.0127604 53.8427 0.732842C55.0804 1.453 55.9814 2.63559 56.3476 4.01995C56.7135 5.40433 56.5148 6.87789 55.7948 8.11565L38.5956 37.6762L38.3202 38.1352C32.4501 47.6604 20.0198 50.8179 10.2929 45.1586C0.411748 39.4093 -2.9377 26.7382 2.81143 16.8569C8.56072 6.97573 21.2318 3.62543 31.1132 9.37444C34.2127 11.1778 36.6692 13.663 38.4042 16.5287L46.4599 2.68499C47.1801 1.44729 48.3625 0.545138 49.747 0.179131ZM20.703 16.8666C14.9593 16.8666 10.3027 21.5233 10.3026 27.267C10.3026 33.0108 14.9593 37.6674 20.703 37.6674C26.4466 37.6672 31.1024 33.0107 31.1024 27.267C31.1024 21.5234 26.4466 16.8668 20.703 16.8666Z")
    // The "p": a bowl and its stem, with the wink (a closed eye, "◠") cut out of the bowl.
    static let p = svgPath("M60.08 16.8569C65.8293 6.97573 78.5004 3.62543 88.3817 9.37444C98.2629 15.1235 101.613 27.7948 95.8642 37.6762C90.1149 47.5577 77.4429 50.9078 67.5614 45.1586C64.4615 43.3549 62.0044 40.8697 60.2694 38.0033L52.2157 51.8491C51.4956 53.0867 50.3129 53.9878 48.9286 54.3539C47.544 54.72 46.0698 54.5205 44.8319 53.8002C43.5943 53.08 42.693 51.8975 42.327 50.5131C41.9612 49.1287 42.1606 47.6551 42.8808 46.4174L60.08 16.8569ZM77.9706 17.766C74.3438 17.7661 70.8487 19.1254 68.1747 21.5756C65.5007 24.0261 63.8422 27.3901 63.5263 31.0033C63.3099 33.4791 65.1413 35.6619 67.6171 35.8783C70.0927 36.0945 72.2747 34.2622 72.4911 31.7866C72.611 30.4162 73.2407 29.1407 74.2548 28.2114C75.269 27.2819 76.5949 26.7661 77.9706 26.766C79.3463 26.7661 80.6722 27.2819 81.6864 28.2114C82.7005 29.1407 83.3302 30.4163 83.4501 31.7866C83.6666 34.2624 85.8493 36.0948 88.3251 35.8783C90.8005 35.6616 92.6322 33.4789 92.4159 31.0033C92.1 27.3902 90.4414 24.0261 87.7675 21.5756C85.0935 19.1252 81.5975 17.7661 77.9706 17.766Z")
    // The open eye in the "d", for drawing a pupil or a lid in it.
    static let eyeCenter = CGPoint(x: 20.703, y: 27.267)
    static let eyeRadius: CGFloat = 10.4

    // A path written with absolute M, L, C and Z commands, as the brand file uses.
    static func svgPath(_ text: String) -> Path {
        var numbers: [CGFloat] = []
        var command: Character = "M"
        var path = Path()
        func flush() {
            switch command {
            case "M" where numbers.count == 2:
                path.move(to: CGPoint(x: numbers[0], y: numbers[1]))
            case "L" where numbers.count == 2:
                path.addLine(to: CGPoint(x: numbers[0], y: numbers[1]))
            case "C" where numbers.count == 6:
                path.addCurve(to: CGPoint(x: numbers[4], y: numbers[5]),
                              control1: CGPoint(x: numbers[0], y: numbers[1]),
                              control2: CGPoint(x: numbers[2], y: numbers[3]))
            default:
                return
            }
            numbers = []
        }
        var token = ""
        func endNumber() {
            if let value = Double(token) { numbers.append(CGFloat(value)) }
            token = ""
            flush()
        }
        for character in text {
            if "MLCZ".contains(character) {
                endNumber()
                if character == "Z" {
                    path.closeSubpath()
                } else {
                    command = character
                }
            } else if character == "-" {
                endNumber()
                token = "-"
            } else if character == " " || character == "," {
                endNumber()
            } else {
                token.append(character)
            }
        }
        endNumber()
        return path
    }

    // The logo scaled to fit a height, its top left at a point.
    static func transform(height: CGFloat, origin: CGPoint = .zero) -> CGAffineTransform {
        let s = height / size.height
        return CGAffineTransform(translationX: origin.x, y: origin.y).scaledBy(x: s, y: s)
    }
}

// The Peek's Pick mark: the DishPeek logo (the "d" and "p" read as an open eye and a winking one)
// with two sparkles at the top right for "picked by AI" (Kia, 2026-11-21). The "p" eye alone read as a
// cave or a house. Laid out in the logo's own 99 × 55 units, widened to make room for the sparkles.
struct PeekMark: View {
    var height: CGFloat
    var color = Color.action        // the letters
    var ink = Color.textOnAction    // the sparkles

    static let box = CGSize(width: 116, height: 55)
    static let bigSparkle = (center: CGPoint(x: 107, y: 7), radius: CGFloat(7))
    static let smallSparkle = (center: CGPoint(x: 112, y: 19), radius: CGFloat(3.6))

    var body: some View {
        Canvas { context, canvas in
            let t = DishPeekLogo.transform(height: canvas.height)
            let fill = FillStyle(eoFill: true)
            context.fill(DishPeekLogo.d.applying(t), with: .color(color), style: fill)
            context.fill(DishPeekLogo.p.applying(t), with: .color(color), style: fill)
            let s = canvas.height / Self.box.height
            for spark in [Self.bigSparkle, Self.smallSparkle] {
                context.fill(Self.sparkle(center: CGPoint(x: spark.center.x * s, y: spark.center.y * s), radius: spark.radius * s), with: .color(ink))
            }
        }
        .frame(width: height * Self.box.width / Self.box.height, height: height)
        .accessibilityHidden(true)
    }

    // A four-pointed star whose sides curve in toward the middle.
    static func sparkle(center c: CGPoint, radius r: CGFloat) -> Path {
        let points = [CGPoint(x: c.x, y: c.y - r), CGPoint(x: c.x + r, y: c.y), CGPoint(x: c.x, y: c.y + r), CGPoint(x: c.x - r, y: c.y)]
        var path = Path()
        path.move(to: points[0])
        for index in 0..<4 {
            let from = points[index]
            let to = points[(index + 1) % 4]
            // Pulled 20% of the way from the middle toward the side, so the star is plump, not spiky.
            let control = CGPoint(x: c.x + ((from.x + to.x) / 2 - c.x) * 0.2, y: c.y + ((from.y + to.y) / 2 - c.y) * 0.2)
            path.addQuadCurve(to: to, control: control)
        }
        path.closeSubpath()
        return path
    }
}

// Peek's Pick on the dish photo, like a sticker, instead of a card under it (Kia, 2026-11-20).
// Peek's Pick on a dish photo: the logo and the words on a green pill (Kia, 2026-11-21: the round sticker
// is for the menu photo; cards and the dish page keep the pill).
struct PeekPickSticker: View {
    var body: some View {
        HStack(spacing: 6) {
            PeekMark(height: 18, color: .white)
            Text("Peek's Pick")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.textOnAction)
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(Color.action, in: Capsule())
    }
}

// Peek's Pick on the menu photo: a round sticker, the logo with its sparkles on brand green with a white
// edge, stuck on a little crooked (Kia, 2026-11-21, in place of a plain green sparkle).
struct PeekRoundSticker: View {
    var size: CGFloat

    var body: some View {
        PeekMark(height: size * 0.29, color: .white, ink: Color.textOnAction)
            .offset(x: size * 0.02)
            .frame(width: size, height: size)
            .background(Color.action, in: Circle())
            .overlay {
                Circle().strokeBorder(.white, lineWidth: max(1.5, size * 0.06))
            }
            .rotationEffect(.degrees(-8))
            .shadow(color: .black.opacity(0.25), radius: size * 0.1, y: size * 0.04)
            .accessibilityElement()
            .accessibilityLabel(Text("Peek's Pick"))
    }
}

extension View {
    // Writes this view's height into a binding, so a sheet can be exactly as tall as its content.
    func readHeight(_ height: Binding<CGFloat>) -> some View {
        onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { newHeight in
            height.wrappedValue = newHeight
        }
    }
}

// MARK: - Cards

extension View {
    func card(_ color: Color = Color.surface, radius: CGFloat = Radius.large) -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color, in: RoundedRectangle(cornerRadius: radius))
    }
}

// Why a dish is popular here, with where each fact comes from (Google Maps, the menu, DishPeek, the AI).
// "From Google Maps reviews", linked to the place's page, under a pick that came from there.
struct GoogleMapsSource: View {
    @Environment(AppState.self) var state

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "star.fill")
                .font(.system(size: 11, weight: .semibold))
            Text("From reviews on")
            if let source = state.place.knownForSources.first, let url = URL(string: source.url) {
                Link(destination: url) {
                    Text(verbatim: "Google Maps").underline()
                }
            } else {
                Text(verbatim: "Google Maps")
            }
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(Color.textSecondary)
    }
}

struct PopularityCard: View {
    @Environment(AppState.self) var state
    var dish: Dish

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let rank = state.menu.dishPeekRank(dish) {
                row(icon: "person.2") {
                    Text(rank == 1 ? String(localized: "#1 on DishPeek here") : String(localized: "Ordered on DishPeek here"))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                    Text("\(dish.dishPeekOrders) orders from DishPeek users")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .padding(16)
        .card()
    }

    func row<Content: View>(icon: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
                .frame(width: 40, height: 40)
                .background(Color.actionSubtle, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// "Shellfish: not sure"
struct FlagCard: View {
    var title: String
    // Only when it says something the title doesn't (why it's "not sure", the heat). Nil: the title alone.
    var message: String? = nil
    var icon = "exclamationmark.triangle"

    var body: some View {
        HStack(alignment: message == nil ? .center : .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.caution)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.caution)
                if let message {
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .card(Color.cautionSubtle)
    }
}

