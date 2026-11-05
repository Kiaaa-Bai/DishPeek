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
    var style: BadgeStyle
    // Shorter text for tight spots; empty means icon only.
    var short: String? = nil
    var id: String { text }

    var compact: BadgeInfo {
        BadgeInfo(text: short ?? text, icon: icon, style: style)
    }
}

struct Badge: View {
    var info: BadgeInfo

    var body: some View {
        HStack(spacing: 4) {
            if let icon = info.icon {
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
        .padding(.horizontal, 8)
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

    // One row if it fits, otherwise stack the badges so none get cut off.
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) {
                ForEach(badges) { badge in
                    Badge(info: badge)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(badges) { badge in
                    Badge(info: badge)
                }
            }
        }
    }
}

extension AppState {
    // Short badges next to a line on the menu photo.
    func lineBadges(_ dish: Dish) -> [BadgeInfo] {
        var badges: [BadgeInfo] = []
        if dish.knownFor {
            badges.append(BadgeInfo(text: String(localized: "Known for"), icon: "star.fill", style: .top, short: ""))
        }
        if dish.isSpicy {
            badges.append(BadgeInfo(text: String(localized: "Spicy"), icon: "flame.fill", style: .caution, short: ""))
        }
        return badges
    }

    // Why a dish is popular: Google Maps, the menu's own marks, DishPeek orders, and the AI's local classics.
    func popularityBadges(_ dish: Dish) -> [BadgeInfo] {
        var badges: [BadgeInfo] = []
        if dish.knownFor {
            badges.append(BadgeInfo(text: String(localized: "Known for"), icon: "star.fill", style: .top))
        }
        if dish.houseSpecial {
            badges.append(BadgeInfo(text: String(localized: "House special"), icon: "rosette", style: .top))
        }
        if menu.dishPeekRank(dish) == 1 {
            badges.append(BadgeInfo(text: String(localized: "#1 on DishPeek"), icon: "person.2.fill", style: .neutral))
        }
        if dish.localClassic {
            badges.append(BadgeInfo(text: String(localized: "Local classic"), icon: "fork.knife", style: .neutral))
        }
        return badges
    }

    // Popularity, then the warnings that matter to this user.
    func cardBadges(_ dish: Dish) -> [BadgeInfo] {
        popularityBadges(dish) + flagBadges(dish)
    }

    // Only the warnings that matter to this user: what they avoid, and spice.
    func flagBadges(_ dish: Dish) -> [BadgeInfo] {
        var badges: [BadgeInfo] = []
        for item in unsure(dish) {
            badges.append(BadgeInfo(text: String(localized: "\(item.allergen.title): not sure"), icon: "exclamationmark.triangle", style: .caution))
        }
        for allergen in hasAvoided(dish) {
            badges.append(BadgeInfo(text: allergen.warning, icon: "exclamationmark.triangle", style: .caution))
        }
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

    var body: some View {
        if source.hasPrefix("https://") {
            AsyncImage(url: URL(string: source), transaction: Transaction(animation: .easeOut(duration: 0.25))) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.actionSubtle
                }
            }
        } else {
            Image(source)
                .resizable()
                .scaledToFill()
        }
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
struct PopularityCard: View {
    @Environment(AppState.self) var state
    var dish: Dish

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if dish.knownFor {
                row(icon: "star.fill") {
                    Text("Known for this dish here")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                    // Google Maps sources must sit right under what they support, with the name unchanged.
                    if let source = state.place.knownForSources.first, let url = URL(string: source.url) {
                        Link(destination: url) {
                            Text(verbatim: "Google Maps")
                                .underline()
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.textSecondary)
                    } else {
                        Text(verbatim: "Google Maps")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }
            if dish.houseSpecial {
                row(icon: "rosette") {
                    Text("House special")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                    Text("Marked on their menu")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.textSecondary)
                }
            }
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
            if dish.localClassic {
                row(icon: "fork.knife") {
                    Text("Local classic")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                    Text("AI pick: a dish this cuisine is known for")
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
    var message: String
    var icon = "exclamationmark.triangle"

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.caution)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.caution)
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .card(Color.cautionSubtle)
    }
}
