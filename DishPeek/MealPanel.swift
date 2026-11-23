import SwiftUI

// Screen 7, "Can't decide?": a whole meal for some people and a budget, put together by the AI from this
// menu, each dish with why it's there (Kia, 2026-11-21: the mood filters only listed the Peek's Picks again;
// the real question is how much to order and what goes together).
//
// It lives on the menu screen itself, not in a sheet (Kia, 2026-11-21): the panel rises behind the menu's
// bottom buttons, the bag stays where it is and the lightbulb stretches into "Another one".

// The planned meals. They are kept while the menu screen is open, so opening the panel again shows the same
// meals; only "Another one" asks again (Kia, 2026-11-21). A new menu, other dishes to avoid or another spice
// level plans afresh.
@Observable
final class MealPlanner {
    var people = 2
    // $, $$ or $$$ (shown in the menu's currency). $$$ is no limit.
    var tier = 2
    // Every meal from one request, by people and tier; switching just picks another.
    var meals: [Backend.Meal] = []
    var reasons: [String: String] = [:]
    var loading = false
    var failed = false
    // What the meals were planned from, to notice when that changes.
    var plannedFor = ""
    @ObservationIgnored var request: Task<Void, Never>?

    // Opening the panel: only plans when nothing is planned for this menu yet.
    func open(_ state: AppState) {
        let key = Self.key(state)
        if key != plannedFor {
            meals = []
            reasons = [:]
            load(state, again: false)
        } else if meals.isEmpty && !loading {
            load(state, again: false)
        }
    }

    // Ask for every meal at once; "Another one" sends the last ones so they come back different.
    func load(_ state: AppState, again: Bool) {
        request?.cancel()
        let previous = again ? meals : []
        let dishes = Self.eligible(state)
        plannedFor = Self.key(state)
        guard Backend.isConfigured, !dishes.isEmpty else { failed = true; return }
        loading = true
        failed = false
        let budgets = Self.budgets(state.menu)
        request = Task {
            do {
                let reply = try await Backend.planMeals(dishes, budgets: budgets, currency: state.menu.currency,
                                                        spice: state.spice, previous: previous, into: Languages.user)
                guard !Task.isCancelled else { return }
                meals = reply.meals
                reasons = Dictionary(reply.reasons.map { ($0.id, $0.reason) }, uniquingKeysWith: { first, _ in first })
                failed = reply.meals.isEmpty
            } catch {
                guard !Task.isCancelled else { return }
                failed = true
            }
            loading = false
        }
    }

    // Only dishes this person can eat go to the AI.
    static func eligible(_ state: AppState) -> [Dish] {
        state.menu.dishes.filter { state.hasAvoided($0).isEmpty }
    }

    static func key(_ state: AppState) -> String {
        eligible(state).map { $0.id + $0.originalName }.joined(separator: ",")
            + "|" + (state.spice?.rawValue ?? "") + "|" + Languages.user
    }

    // Budget per person for $ and $$, from this menu's own prices: about one main and a bit, and a fuller
    // meal. $$$ has no limit.
    static func budgets(_ menu: ScannedMenu) -> [Double?] {
        let mains = menu.dishes.filter(\.isMainDish).compactMap(\.price).sorted()
        guard !mains.isEmpty else { return [nil, nil, nil] }
        let typical = mains[mains.count / 2]
        return [typical * 1.4, typical * 2.4, nil]
    }
}

// The panel. The menu's own buttons stay on top of its bottom edge, so it leaves room for them.
struct MealPanel: View {
    @Environment(AppState.self) var state
    var planner: MealPlanner
    // From the panel's bottom edge to just above the menu's buttons.
    var bottomInset: CGFloat
    // The most the whole panel may be, so it stays under the photo/list switch.
    var maxHeight: CGFloat
    var onClose: () -> Void
    var onOpen: (Dish) -> Void

    @State var contentHeight: CGFloat = 400
    @State var drag: CGFloat = 0

    static let headerHeight: CGFloat = 70

    // The meal for the chosen people and budget.
    var plan: [(dish: Dish, reason: String)] {
        let meal = planner.meals.first { $0.people == planner.people && $0.tier == planner.tier }
        return (meal?.dishes ?? []).compactMap { id in
            state.dish(id).map { (dish: $0, reason: planner.reasons[id] ?? "") }
        }
    }

    // The menu's currency sign: "€", "₩", "$". Just the sign: in Chinese, USD's symbol is "US$", which made
    // the budgets read "US$US$US$" (Kia, 2026-11-21); the letters only tell dollars apart, and the menu
    // is right there.
    var sign: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = state.menu.currency
        formatter.locale = Locale(identifier: Languages.user)
        let symbol = formatter.currencySymbol ?? "$"
        let bare = symbol.filter { !$0.isLetter }
        return bare.isEmpty ? symbol : bare
    }

    var body: some View {
        let room = max(120, maxHeight - Self.headerHeight - bottomInset - 8)
        VStack(spacing: 0) {
            header
            ScrollView {
                content
                    .padding(.bottom, contentHeight > room ? 16 : 0)
                    .readHeight($contentHeight)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: min(contentHeight, room))
            // When the meal doesn't fit, its last dish fades out above the buttons instead of being cut off.
            .mask {
                VStack(spacing: 0) {
                    Color.black
                    LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                        .frame(height: contentHeight > room ? 28 : 0)
                }
            }
            Color.clear
                .frame(height: bottomInset)
        }
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 48))
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
        .offset(y: drag)
        .animation(.smooth(duration: 0.3), value: contentHeight)
    }

    // The grabber, close and the title. Dragging it down closes the panel, as with a sheet.
    var header: some View {
        VStack(spacing: 8) {
            Capsule()
                .fill(Color.textSecondary.opacity(0.35))
                .frame(width: 36, height: 5)
            HStack {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                        .frame(width: 44, height: 44)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Close"))
                Spacer()
                Text("Can't decide?")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Color.clear
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.top, 8)
        .padding(.horizontal, 16)
        .frame(height: Self.headerHeight, alignment: .top)
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .onChanged { drag = max(0, $0.translation.height) }
                .onEnded { value in
                    if value.translation.height > 90 || value.predictedEndTranslation.height > 240 {
                        onClose()
                    } else {
                        withAnimation(.smooth(duration: 0.3)) { drag = 0 }
                    }
                }
        )
    }

    var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                label("How many people?")
                HStack(spacing: 8) {
                    ForEach(1...6, id: \.self) { count in
                        Chip(title: count == 6 ? "6+" : "\(count)", isOn: planner.people == count) {
                            planner.people = count
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                label("Budget per person")
                HStack(spacing: 8) {
                    ForEach(1...3, id: \.self) { level in
                        Chip(title: String(repeating: sign, count: level), isOn: planner.tier == level) {
                            planner.tier = level
                        }
                    }
                }
            }

            if planner.loading {
                // The logo loader while the meals are planned (Kia, 2026-11-21), also for "Another one".
                VStack(spacing: 14) {
                    LogoLoader()
                        .frame(height: 56)
                    Text("Putting a meal together…")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 240)
                .transition(.opacity)
            } else if planner.failed && plan.isEmpty {
                Text("Couldn't put a meal together. Check your connection and try again.")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 84)
            } else {
                // The dishes come in one after another from below.
                VStack(spacing: 10) {
                    ForEach(Array(plan.enumerated()), id: \.element.dish.id) { index, item in
                        MealRow(dish: item.dish, reason: item.reason, price: state.menu.money(item.dish),
                                isAdded: state.order.contains(item.dish.id)) {
                            onOpen(item.dish)
                        } onAdd: {
                            withAnimation(.snappy) {
                                state.toggleInOrder(item.dish)
                            }
                        }
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 16))
                                .animation(.smooth(duration: 0.35).delay(Double(index) * 0.06)),
                            removal: .opacity.animation(.easeOut(duration: 0.15))))
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 2)
        .padding(.bottom, 8)
        .animation(.smooth(duration: 0.3), value: plan.map(\.dish.id))
        .animation(.smooth(duration: 0.3), value: planner.loading)
    }

    func label(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Color.textSecondary)
    }
}

// The menu's lightbulb. While the meal panel is open it stretches to the bag into "Another one", in place
// (Kia, 2026-11-21): one glass capsule that only changes width, the icon handing over to the words.
struct DecideButton: View {
    var expanded: Bool
    var busy: Bool
    // Round size, the same as the bag next to it, and the width when stretched.
    var size: CGFloat
    var width: CGFloat
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Image(systemName: "lightbulb")
                    .font(.system(size: 20, weight: .semibold))
                    .opacity(expanded ? 0 : 1)
                    .scaleEffect(expanded ? 0.5 : 1)
                    .blur(radius: expanded ? 4 : 0)
                Text("Another one")
                    .font(.system(size: 17, weight: .medium))
                    .fixedSize()
                    .opacity(expanded ? (busy ? 0.35 : 1) : 0)
                    .scaleEffect(expanded ? 1 : 0.7)
                    .blur(radius: expanded ? 0 : 4)
            }
            .foregroundStyle(Color.textPrimary)
            .frame(width: expanded ? max(size, width) : size, height: size)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .accessibilityLabel(expanded ? Text("Another one") : Text("Can't decide?"))
    }
}
