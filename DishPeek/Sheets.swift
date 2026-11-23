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

    // The tallest the peek may be: about half of an iPhone screen.
    static let maxHeight: CGFloat = 440

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
            // "Checking allergens…" is one of the card badges above while the details load.
            if state.isExplaining(dish) {
                DetailsPlaceholder()
            } else if !dish.details.isEmpty {
                // A peek: at most four lines, the rest is on the dish's page ("More").
                Text(dish.details)
                    .font(.system(size: 16))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                GlassButton(title: "More", fullWidth: true, action: onMore)
                ActionButton(title: state.order.contains(dish.id) ? "Your order" : "Add to order", fullWidth: true, action: onAdd)
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 20)
        .padding(.top, 28)
        .padding(.bottom, 12)
        .readHeight($height)
        .frame(maxHeight: .infinity, alignment: .top)
        // Always a half sheet: it sometimes opened full screen (Kia, 2026-11-19), so the measured
        // height is capped, and the content above is kept short enough to fit.
        .presentationDetents([.height(min(height, Self.maxHeight))])
        .presentationBackgroundInteraction(.enabled(upThrough: .height(min(height, Self.maxHeight))))
        .presentationDragIndicator(.visible)
    }
}

// One dish of the planned meal. The card opens the dish's page; the round button adds it to the order
// and takes it out again, as on the menu (Kia, 2026-11-21).
struct MealRow: View {
    var dish: Dish
    var reason: String
    var price: String
    var isAdded: Bool
    var onOpen: () -> Void
    var onAdd: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpen) {
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
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onAdd) {
                Image(systemName: isAdded ? "checkmark" : "plus")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(isAdded ? Color.textOnAction : Color.textPrimary)
                    .frame(width: 34, height: 34)
                    .background(isAdded ? Color.action : Color.border, in: Circle())
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.selection, trigger: isAdded)
            .accessibilityLabel(isAdded ? String(localized: "\(dish.name) is in your order") : String(localized: "Add \(dish.name) to order"))
        }
        .padding(12)
        .frame(minHeight: 84)
        .card(radius: Radius.medium)
    }
}

// The dish as written on the menu, with how to say it when the script is unfamiliar.
// Menus in Latin letters need no pronunciation: it only repeated the name ("Bratwurstsülze · Bratwurstsülze").
func originalLine(_ dish: Dish) -> String {
    let latin = dish.originalName.unicodeScalars.allSatisfy { !$0.properties.isAlphabetic || $0.value < 0x0250 }
    if let pronunciation = dish.pronunciation, !pronunciation.isEmpty, !latin,
       pronunciation.compare(dish.originalName, options: [.caseInsensitive, .diacriticInsensitive]) != .orderedSame {
        return dish.originalName + " · " + pronunciation
    }
    return dish.originalName
}
