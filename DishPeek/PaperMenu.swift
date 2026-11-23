import SwiftUI

// One line on the menu photo, made tappable, with its badges. Highlighted only while selected.
// Translated, it shows the user's language laid over the printed line, like a live translation.
struct MenuLine: View {
    var dish: Dish
    var badges: [BadgeInfo] = []
    var isSelected = false
    var translated = false

    var body: some View {
        HStack(spacing: 8) {
            Text(translated ? dish.lineTranslation : dish.printed)
                .font(.system(size: translated ? 15 : 19, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.9)
                .contentTransition(.opacity)
            // Translations run longer, so their badges get short.
            BadgeRow(badges: translated ? badges.map { $0.compact } : badges)
                .fontDesign(.rounded)
                .layoutPriority(1)
            Spacer(minLength: 8)
            Text(dish.priceText)
                .layoutPriority(1)
        }
        .font(.system(size: 19, weight: .bold))
        .foregroundStyle(Color.textPrimary)
        .padding(.horizontal, 13)
        .frame(height: 46)
        // No boxes on the menu: only the line being looked at is highlighted.
        .background(isSelected ? Color.actionSubtle : Color.clear, in: RoundedRectangle(cornerRadius: Radius.small))
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: Radius.small)
                    .strokeBorder(Color.action, lineWidth: 3)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: Radius.small))
        .scaleEffect(isSelected ? 1.02 : 1)
        .animation(.snappy(duration: 0.25), value: isSelected)
        // The menu is a photo of real printed paper, so its text is not rounded.
        .fontDesign(.default)
    }
}

// Stand-in for the photo of the paper menu, drawn from the scanned menu.
struct PaperMenu: View {
    var menu: ScannedMenu
    var showTargets = false
    var selected: String? = nil
    var translated = false
    var badges: (Dish) -> [BadgeInfo] = { _ in [] }
    var onTap: (Dish) -> Void = { _ in }
    // Where each line is, in the "menuPhoto" coordinate space, for finding the line under a tap.
    var onLineFrame: ((String, CGRect) -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            Text(translated ? menu.title.translated : menu.title.original)
                .font(.system(size: translated ? 26 : 30, weight: .black))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(height: 38)
                .contentTransition(.opacity)
                .padding(.top, 20)
            Text(verbatim: "MENU")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.textSecondary)
                .padding(.top, 4)
            Rectangle()
                .fill(Color.border)
                .frame(height: 1)
                .padding(.horizontal, 35)
                .padding(.top, 6)
                .padding(.bottom, 7)

            VStack(spacing: 4) {
                ForEach(menu.dishes) { dish in
                    if showTargets {
                        Button {
                            onTap(dish)
                        } label: {
                            MenuLine(dish: dish, badges: badges(dish), isSelected: selected == dish.id, translated: translated)
                        }
                        .buttonStyle(.plain)
                        .id(dish.id)
                        .onGeometryChange(for: CGRect.self) { proxy in
                            proxy.frame(in: .named("menuPhoto"))
                        } action: { frame in
                            onLineFrame?(dish.id, frame)
                        }
                        .accessibilityLabel("\(dish.name), \(dish.originalName), \(menu.money(dish))")
                        .sensoryFeedback(.selection, trigger: selected == dish.id) { _, isOn in isOn }
                    } else {
                        printedLine(dish)
                    }
                }
            }
            .padding(.horizontal, 8)

            if let footer = menu.footer {
                Text(translated ? footer.translated : footer.original)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
                    .contentTransition(.opacity)
                    .padding(.top, 6)
            }
        }
        .padding(.bottom, 18)
        .foregroundStyle(Color.textPrimary)
        .fontDesign(.default)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.paper)
                .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
        }
    }

    func printedLine(_ dish: Dish) -> some View {
        HStack {
            Text(dish.printed)
            Spacer()
            Text(dish.priceText)
        }
        .font(.system(size: 19, weight: .bold))
        .padding(.horizontal, 12)
        .frame(height: 46)
    }
}

// The sample menu, as the "photo" behind the menu screen: the paper menu on the plain app background.
// The language switch is in the bar above, shared with real photos.
struct MenuPhoto: View {
    @Environment(AppState.self) var state
    var menu: ScannedMenu
    var selected: String?
    var badges: (Dish) -> [BadgeInfo]
    var onTap: (Dish) -> Void

    // Its height for its width, so the zoomable view can lay it out.
    static let aspect: CGFloat = 1.3

    var body: some View {
        PaperMenu(menu: menu, showTargets: true, selected: selected, translated: state.photoShowsTranslation, badges: badges, onTap: onTap) { id, frame in
            state.sampleLineFrames[id] = frame
        }
            .animation(.snappy(duration: 0.2), value: state.photoShowsTranslation)
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color.canvas)
            .coordinateSpace(.named("menuPhoto"))
    }
}

// One round button on the menu photo: green (on) while the translation shows, which is how it starts,
// plain while the original shows. Tap: switch. Press and hold: see the other one, let go to come back.
struct LanguageToggle: View {
    var original: String
    var target: String
    @Binding var translated: Bool
    @Binding var peeking: Bool
    var showsTranslation: Bool
    @State var pressedAt: Date? = nil

    var body: some View {
        Image(systemName: "translate")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(showsTranslation ? Color.textOnAction : Color.textPrimary)
            .frame(width: 56, height: 56)
            .glassEffect(showsTranslation ? .regular.tint(Color.action).interactive() : .regular.interactive(), in: .circle)
            .animation(.snappy, value: showsTranslation)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if pressedAt == nil {
                            pressedAt = .now
                            peeking = true
                        }
                    }
                    .onEnded { _ in
                        let heldFor = Date().timeIntervalSince(pressedAt ?? .now)
                        pressedAt = nil
                        peeking = false
                        // A quick tap keeps the language it just showed.
                        if heldFor < 0.35 {
                            translated.toggle()
                        }
                    }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Menu language"))
            .accessibilityValue(Text(verbatim: Languages.name(showsTranslation ? target : original)))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                translated.toggle()
            }
    }
}
