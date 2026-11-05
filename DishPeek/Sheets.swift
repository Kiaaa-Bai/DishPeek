import SwiftUI

// Height of a sheet's grabber and toolbar, added on top of the measured content.
let sheetChrome: CGFloat = 88

// Screen 4: a sheet just tall enough for its content, so the tapped line stays in view.
struct DishPeekSheet: View {
    @Environment(AppState.self) var state
    var dish: Dish
    @Binding var height: CGFloat
    var onMore: () -> Void
    var onAdd: () -> Void

    var body: some View {
        // The dish as it is now: its details can arrive while the sheet is open.
        let dish = state.dish(self.dish.id) ?? self.dish

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                DishPhoto(dish: dish, size: 72, radius: Radius.medium)
                VStack(alignment: .leading, spacing: 2) {
                    Text(originalLine(dish))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.textSecondary)
                    Text(dish.name)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                    Text(dish.summary)
                        .font(.system(size: 16))
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer(minLength: 8)
                Text(state.menu.money(dish))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
            }

            let badges = state.cardBadges(dish)
            if !badges.isEmpty {
                BadgeRow(badges: badges)
            }
            if state.isExplaining(dish) && !state.avoid.isEmpty {
                CheckingAllergens()
            }

            if state.isExplaining(dish) {
                DetailsPlaceholder()
            } else if !dish.details.isEmpty {
                Text(dish.details)
                    .font(.system(size: 16))
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                GlassButton(title: "More", fullWidth: true, action: onMore)
                ActionButton(title: "Add to order", fullWidth: true, action: onAdd)
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 20)
        .padding(.top, 28)
        .padding(.bottom, 12)
        .readHeight($height)
        .frame(maxHeight: .infinity, alignment: .top)
        .presentationDetents([.height(height)])
        .presentationBackgroundInteraction(.enabled(upThrough: .height(height)))
        .presentationDragIndicator(.visible)
    }
}

// Screen 7: pick a mood, get up to 3 dishes, check the ones you want.
enum Mood: CaseIterable, Identifiable {
    case popular, mild, budget, cold

    var id: Self { self }

    var title: String {
        switch self {
        case .popular: String(localized: "Local favorite")
        case .mild: String(localized: "Something mild")
        case .budget: String(localized: "Easy on the wallet")
        case .cold: String(localized: "Something cold")
        }
    }

    // Up to 3 main dishes for this mood, each with why it fits.
    func picks(_ menu: ScannedMenu) -> [(dish: Dish, reason: String)] {
        let mains = menu.popular
        var chosen: [Dish]
        switch self {
        case .popular: chosen = mains
        case .mild: chosen = mains.filter { !$0.isSpicy }
        case .budget: chosen = mains.sorted { ($0.price ?? 0) < ($1.price ?? 0) }
        case .cold: chosen = mains.filter { $0.isCold }
        }
        return chosen.prefix(3).map { ($0, reason($0, menu)) }
    }

    func reason(_ dish: Dish, _ menu: ScannedMenu) -> String {
        var parts: [String] = []
        switch self {
        case .popular:
            if dish.knownFor {
                parts.append(String(localized: "Known for it here"))
            }
            if dish.dishPeekOrders > 0 {
                parts.append(String(localized: "\(dish.dishPeekOrders) DishPeek orders"))
            }
        case .mild:
            parts.append(String(localized: "Not spicy"))
        case .budget:
            parts.append(menu.money(dish))
        case .cold:
            parts.append(String(localized: "Served cold"))
        }
        parts.append(dish.summary)
        return parts.prefix(2).joined(separator: ", ")
    }
}

struct CantDecideSheet: View {
    @Environment(\.dismiss) var dismiss
    @Environment(AppState.self) var state
    var onAdd: ([Dish]) -> Void

    @State var mood: Mood = .popular
    @State var checked: [String] = []
    @State var contentHeight: CGFloat = 520

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Pick a mood. We'll suggest up to 3 from what people order here.")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            moodChip(.popular)
                            moodChip(.mild)
                        }
                        HStack(spacing: 8) {
                            moodChip(.budget)
                            moodChip(.cold)
                        }
                    }

                    VStack(spacing: 10) {
                        ForEach(mood.picks(state.menu), id: \.dish.id) { pick in
                            PickRow(dish: pick.dish, reason: pick.reason, price: state.menu.money(pick.dish), isOn: checked.contains(pick.dish.id)) {
                                toggle(pick.dish)
                            }
                        }
                    }

                    ActionButton(title: "Add \(checked.count) to order", fullWidth: true) {
                        onAdd(checked.compactMap { state.dish($0) })
                    }
                    .disabled(checked.isEmpty)
                    .padding(.top, 4)
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 12)
                .readHeight($contentHeight)
                .animation(.snappy, value: mood)
            }
            .scrollBounceBehavior(.basedOnSize)
            .navigationTitle("Can't decide?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.height(contentHeight + sheetChrome)])
        .presentationDragIndicator(.visible)
        .onAppear {
            if checked.isEmpty {
                checked = mood.picks(state.menu).prefix(2).map { $0.dish.id }
            }
        }
    }

    func moodChip(_ value: Mood) -> some View {
        Chip(title: value.title, isOn: mood == value) {
            mood = value
            // New mood: start with its top 2 checked.
            checked = value.picks(state.menu).prefix(2).map { $0.dish.id }
        }
    }

    func toggle(_ dish: Dish) {
        if let index = checked.firstIndex(of: dish.id) {
            checked.remove(at: index)
        } else {
            checked.append(dish.id)
        }
    }
}

struct PickRow: View {
    var dish: Dish
    var reason: String
    var price: String
    var isOn: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                DishPhoto(dish: dish, size: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(dish.name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                    Text(reason)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Text(price)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                checkCircle
            }
            .padding(12)
            .frame(minHeight: 84)
            .card(radius: Radius.medium)
            .overlay {
                RoundedRectangle(cornerRadius: Radius.medium)
                    .strokeBorder(isOn ? Color.action : Color.border, lineWidth: isOn ? 2 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: Radius.medium))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isOn)
    }

    var checkCircle: some View {
        ZStack {
            if isOn {
                Circle().fill(Color.action)
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.textOnAction)
            } else {
                Circle().strokeBorder(Color.textPrimary.opacity(0.2), lineWidth: 1.5)
            }
        }
        .frame(width: 24, height: 24)
    }
}

// The dish as written on the menu, with how to say it when the script is unfamiliar.
func originalLine(_ dish: Dish) -> String {
    if let pronunciation = dish.pronunciation, !pronunciation.isEmpty {
        return dish.originalName + " · " + pronunciation
    }
    return dish.originalName
}
