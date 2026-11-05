import SwiftUI

// Screen 6: the photo says where it is from, then what the dish is.
struct DishDetailView: View {
    @Environment(AppState.self) var state
    // The dish as it was when the page opened.
    var opened: Dish
    @State var asking = false
    @State var page = 0

    init(dish: Dish) {
        opened = dish
    }

    // The dish as it is now: its description, warnings and photo can arrive while the page is open.
    var dish: Dish {
        state.dish(opened.id) ?? opened
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero

                VStack(alignment: .leading, spacing: 12) {
                    // A photo from the web is shown with its author and license.
                    if let credit = dish.photoCredit {
                        photoCredit(credit)
                    }

                    Text(originalLine(dish))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.textSecondary)

                    HStack(alignment: .firstTextBaseline) {
                        Text(dish.name)
                            .font(.system(size: 32, weight: .bold))
                        Spacer()
                        Text(state.menu.money(dish))
                            .font(.system(size: 20, weight: .semibold))
                    }
                    .foregroundStyle(Color.textPrimary)

                    if state.isExplaining(dish) {
                        DetailsPlaceholder()
                    } else {
                        Text(dish.details.isEmpty ? dish.summary : dish.details)
                            .font(.system(size: 16))
                            .foregroundStyle(Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button {
                        state.showOnMenu(dish)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "hand.point.up.left")
                                .font(.system(size: 14, weight: .medium))
                            Text("Show on the menu")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundStyle(Color.textPrimary)
                        .padding(.horizontal, 13)
                        .frame(height: 36)
                        .background(Color.surface, in: Capsule())
                        .overlay {
                            Capsule().strokeBorder(Color.border)
                        }
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    if dish.knownFor || dish.houseSpecial || dish.localClassic || state.menu.dishPeekRank(dish) != nil {
                        PopularityCard(dish: dish)
                    }

                    // The "not sure" warnings come with the details, so say they are still coming.
                    if state.isExplaining(dish) && !state.avoid.isEmpty {
                        CheckingAllergens()
                    }
                    ForEach(state.unsure(dish), id: \.allergen) { item in
                        FlagCard(title: String(localized: "\(item.allergen.title): not sure"), message: item.why)
                    }
                    ForEach(state.hasAvoided(dish)) { allergen in
                        FlagCard(
                            title: allergen.warning,
                            message: allergen.isDiet
                                ? String(localized: "Something in it doesn't fit your diet.")
                                : String(localized: "Listed in this dish. You said you don't eat it.")
                        )
                    }
                    if let note = state.spiceNote(dish) {
                        FlagCard(title: note, message: dish.spiceTip ?? String(localized: "Ask how spicy it is."), icon: "flame")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.canvas, in: UnevenRoundedRectangle(topLeadingRadius: Radius.large, topTrailingRadius: Radius.large))
                .padding(.top, -24)
            }
        }
        .ignoresSafeArea(edges: .top)
        .background(Color.canvas)
        .safeAreaBar(edge: .bottom) {
            BottomButtons {
                GlassButton(title: "Ask about it") {
                    asking = true
                }
            } trailing: {
                ActionButton(title: "Add to order") {
                    state.add(dish)
                    state.path.append(.order)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .alert(Text(verbatim: question.original), isPresented: $asking) {
            Button("Play aloud") {
                Speaker.shared.say(question.original, in: state.menu.sourceLanguage)
            }
            Button("Done", role: .cancel) {
            }
        } message: {
            Text("\(question.translated) Show this to your server.")
        }
    }

    // What to ask the server about this dish, in their language and the user's.
    var question: Bilingual {
        dish.question ?? state.menu.defaultQuestion
    }

    func photoCredit(_ credit: String) -> some View {
        let label = HStack(spacing: 4) {
            Image(systemName: "camera")
            Text(verbatim: credit)
                .lineLimit(1)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(Color.textSecondary)

        return Group {
            if let link = dish.photoLink, let url = URL(string: link) {
                Link(destination: url) { label }
            } else {
                label
            }
        }
    }

    var photoSourceText: String? {
        switch dish.photoSource {
        case .restaurant(let count):
            String(localized: "This restaurant · \(count) diner photos")
        case .typical:
            // Short, so "not from this restaurant" is never cut off by a long dish name.
            String(localized: "Typical photo, not from this restaurant")
        case nil:
            nil
        }
    }

    // Swipeable photos. Pulling the screen down stretches the photo instead of showing a gap.
    var hero: some View {
        Color.actionSubtle
            .frame(height: 340)
            .overlay {
                if dish.photos.isEmpty {
                    Image(systemName: "fork.knife")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.textSecondary)
                } else {
                    TabView(selection: $page) {
                        ForEach(Array(dish.photos.enumerated()), id: \.offset) { index, photo in
                            Color.clear
                                .overlay {
                                    DishImage(source: photo)
                                }
                                .clipped()
                                .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                }
            }
            .clipped()
            .overlay(alignment: .bottomTrailing) {
                if dish.photos.count > 1 {
                    Text("\(page + 1) / \(dish.photos.count)")
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.textPrimary)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .glassEffect(.regular, in: .capsule)
                        .padding(.trailing, 20)
                        .padding(.bottom, 38)
                }
            }
            .visualEffect { content, proxy in
                let pull = max(0, proxy.frame(in: .scrollView).minY)
                return content.scaleEffect(1 + pull / 340, anchor: .bottom)
            }
            .overlay(alignment: .bottomLeading) {
                if let photoSourceText {
                    HStack(spacing: 4) {
                        Image(systemName: "camera")
                            .font(.system(size: 12, weight: .semibold))
                        Text(photoSourceText)
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(Color.textPrimary)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.leading, 20)
                    .padding(.bottom, 38)
                }
            }
    }
}

// Gray bars where the description will be, while it is still on its way. They pulse gently.
struct DetailsPlaceholder: View {
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State var dim = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            // Three lines of text, the last one shorter.
            ForEach([0, 16, 110], id: \.self) { shorter in
                Capsule()
                    .fill(Color.border)
                    .frame(height: 12)
                    .padding(.trailing, CGFloat(shorter))
            }
        }
        .padding(.vertical, 4)
        .opacity(dim ? 0.45 : 1)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever()) {
                dim = true
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text("Loading details…"))
    }
}

// Says the "not sure" allergen warnings are still coming, so no warning doesn't read as safe.
struct CheckingAllergens: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Checking allergens…")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.textSecondary)
        }
    }
}
