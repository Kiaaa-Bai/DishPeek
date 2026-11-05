import SwiftUI

// Screens 8a and 8b: big names in the menu's language to show the server.
struct OrderView: View {
    @Environment(AppState.self) var state
    @State var askAbout = false
    @State var lineIndex = 0

    var dishes: [Dish] { state.orderDishes }

    var menu: ScannedMenu { state.menu }

    var total: Double {
        var sum = 0.0
        for dish in dishes {
            sum += dish.price ?? 0
        }
        return sum
    }

    // The first dish in the order with an allergen we can't rule out, and what to ask about it.
    var unsureDish: Dish? {
        dishes.first { !state.unsure($0).isEmpty }
    }

    var unsureQuestion: Bilingual? {
        guard let dish = unsureDish else { return nil }
        return dish.question ?? menu.defaultQuestion
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Show this to your server")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Color.textPrimary)

                if dishes.isEmpty {
                    Text("No dishes yet. Tap a line on the menu, then Add to order.")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.textSecondary)
                        .padding(24)
                        .card()
                } else {
                    orderCard
                    pointCard
                    if let question = unsureQuestion {
                        questionCard(question)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .background(Color.canvas)
        .safeAreaBar(edge: .bottom) {
            BottomButtons {
                GlassButton(title: "Play aloud") {
                    Speaker.shared.say(spokenOrder, in: menu.sourceLanguage)
                }
            } trailing: {
                ActionButton(title: "Done") {
                    state.recordOrder()
                    state.path = [.menu]
                }
            }
        }
        .navigationTitle("Your order")
        .navigationBarTitleDisplayMode(.inline)
    }

    var orderCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: "\(menu.orderPhrase.original) · \(menu.orderPhrase.translated)")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.textSecondary)
                .padding(.bottom, 14)

            ForEach(Array(dishes.enumerated()), id: \.element.id) { index, dish in
                if index > 0 {
                    divider
                }
                bigLine(
                    original: "\(dish.originalName) \(dish.amount.original)",
                    translated: "\(dish.name) \(dish.amount.translated)"
                )
            }

            if askAbout, let question = unsureQuestion {
                divider
                bigLine(original: question.original, translated: question.translated)
            }

            divider
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: "\(menu.totalWord.original) · \(menu.totalWord.translated)")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                Text(menu.money(total))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                    .contentTransition(.numericText())
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .card()
    }

    func bigLine(original: String, translated: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            // Big enough for a server to read from across the table.
            Text(original)
                .font(.system(size: 48, weight: .bold))
                .foregroundStyle(Color.textPrimary)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(translated)
                .font(.system(size: 16))
                .foregroundStyle(Color.textSecondary)
        }
    }

    var divider: some View {
        Rectangle()
            .fill(Color.border)
            .frame(height: 1)
            .padding(.vertical, 14)
    }

    // One menu line to point at. The arrow steps through the order.
    var pointCard: some View {
        let dish = dishes[lineIndex % dishes.count]
        return VStack(spacing: 10) {
            Button {
                withAnimation(.snappy) {
                    lineIndex += 1
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "hand.point.up.left")
                        .font(.system(size: 15, weight: .medium))
                    Text("Or point at this line on their menu")
                        .font(.system(size: 14, weight: .medium))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.textSecondary)
                }
                .foregroundStyle(Color.textPrimary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            MenuLine(dish: dish)
                .id(dish.id)
                .transition(.opacity)
        }
        .padding(16)
        .card()
    }

    func questionCard(_ question: Bilingual) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Ask the server too")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                Text(verbatim: "\(question.original) \(question.translated)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
            Toggle("Ask the server too", isOn: $askAbout.animation(.snappy))
                .labelsHidden()
                .tint(Color.action)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .card()
    }

    var spokenOrder: String {
        var text = menu.orderPhrase.original + ". " + dishes.map { "\($0.originalName) \($0.amount.original)" }.joined(separator: ", ") + "."
        if askAbout, let question = unsureQuestion {
            text += " " + question.original
        }
        return text
    }
}
