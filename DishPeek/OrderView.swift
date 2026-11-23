import SwiftUI

// Screens 8a and 8b: big names in the menu's language to show the server.
struct OrderView: View {
    @Environment(AppState.self) var state
    @State var askAbout = false
    // The order card's text width, so long names can be sized to fit it.
    @State var lineWidth: CGFloat = 0

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
            // Icons, like the menu's own buttons (Kia, 2026-11-21).
            BottomButtons {
                IconButton(systemName: "speaker.wave.2.fill", label: "Play aloud") {
                    Speaker.shared.say(spokenOrder, in: menu.sourceLanguage)
                }
            } trailing: {
                IconButton(systemName: "checkmark", label: "Done", prominent: true) {
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
                // A short amount ("×1", "1개") stays with the last word when a long name wraps.
                let glue = dish.amount.original.contains(" ") ? " " : "\u{00A0}"
                bigLine(
                    original: "\(dish.originalName)\(glue)\(dish.amount.original)",
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
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { lineWidth = $0 }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .card()
    }

    func bigLine(original: String, translated: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            // Big enough for a server to read from across the table, and always whole: a long name wraps
            // onto more lines instead of ending in "…" (Kia, 2026-11-21: "SOUTHWEST LOADED…"). A word too
            // wide for the line makes the text smaller, so lines break between words, never inside one
            // ("Knusperschni-tzel").
            Text(original)
                .font(.system(size: Self.bigSize(original, width: lineWidth), weight: .bold))
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(translated)
                .font(.system(size: 16))
                .foregroundStyle(Color.textSecondary)
        }
    }

    // 48 pt, or smaller until the widest word fits the line.
    static func bigSize(_ text: String, width: CGFloat) -> CGFloat {
        guard width > 0 else { return 48 }
        let font = UIFont.systemFont(ofSize: 48, weight: .bold)
        let widest = text.split(separator: " ")
            .map { (String($0) as NSString).size(withAttributes: [.font: font]).width }
            .max() ?? 0
        guard widest > width else { return 48 }
        return max(22, (48 * width / widest).rounded(.down))
    }

    var divider: some View {
        Rectangle()
            .fill(Color.border)
            .frame(height: 1)
            .padding(.vertical, 14)
    }

    // Every ordered dish's line as printed, to point at on their menu. It used to show one line at a
    // time behind an arrow, which read as if only the first dish was there (2026-11-05).
    var pointCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "hand.point.up.left")
                    .font(.system(size: 15, weight: .medium))
                Text("Or point at this line on their menu")
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(Color.textPrimary)

            ForEach(dishes) { dish in
                // The line cut out of their own menu photo, so the server sees exactly what is printed
                // (Kia, 2026-11-21: the typed-out line was often blank). The sample menu has no photo.
                if let strip = state.printedLine(dish) {
                    Image(uiImage: strip)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 90)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.small))
                        .overlay {
                            RoundedRectangle(cornerRadius: Radius.small).strokeBorder(Color.border)
                        }
                } else {
                    typedLine(dish)
                }
            }
        }
        .padding(16)
        .card()
    }

    // When no line can be cut out (the sample menu, or a dish the phone didn't read), the name and price as
    // printed, typed out, so the row is never just a price (Kia, 2026-11-21).
    func typedLine(_ dish: Dish) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(dish.printed.isEmpty ? dish.originalName : dish.printed)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Text(dish.priceText)
        }
        .font(.system(size: 19, weight: .bold))
        .fontDesign(.default)
        .foregroundStyle(Color.textPrimary)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.canvas, in: RoundedRectangle(cornerRadius: Radius.small))
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

    // Said as one sentence: "I would like to order 1 crab dip, 1 southwest loaded fries and 1 zucchini fries."
    // "×1" was read out as "x one" (Kia, 2026-11-21), so a "×" amount becomes the number before the name,
    // which the voice says the way the language does ("one", "ein", "un"). Amounts already written in the
    // language ("1개", "1つ") stay after the name, where they belong.
    var spokenOrder: String {
        let items = dishes.map { dish -> String in
            let amount = dish.amount.original.trimmingCharacters(in: .whitespaces)
            if let sign = amount.firstIndex(where: { $0 == "×" || $0 == "x" || $0 == "X" }) {
                let count = amount[amount.index(after: sign)...].trimmingCharacters(in: .whitespaces)
                if !count.isEmpty, count.allSatisfy(\.isNumber) {
                    return "\(count) \(dish.originalName)"
                }
            }
            return "\(dish.originalName) \(amount)"
        }
        let list = ListFormatter()
        list.locale = Locale(identifier: menu.sourceLanguage)
        let joined = list.string(from: items) ?? items.joined(separator: ", ")
        var text = menu.orderPhrase.original + " " + joined + "."
        if askAbout, let question = unsureQuestion {
            text += " " + question.original
        }
        return text
    }
}
