import SwiftUI

// Screen 6: the photo says where it is from, then what the dish is.
struct DishDetailView: View {
    @Environment(AppState.self) var state
    // The dish as it was when the page opened.
    var opened: Dish
    @State var asking = false
    @State var page = 0
    // The photo shown full screen: tap it, or pull the page down past the photo.
    @State var viewingPhoto = false
    // The photo grows from where it sits on the page into the full-screen view, and shrinks back.
    @Namespace var photoSpace
    // The screen's height, so the photo takes a share of it.
    @State var pageHeight: CGFloat = 800
    // How tall the card's content is, so the card is only as tall as it needs and the photo takes the rest.
    @State var contentHeight: CGFloat = 300

    init(dish: Dish) {
        opened = dish
    }

    // The dish as it is now: its description, warnings and photo can arrive while the page is open.
    var dish: Dish {
        state.dish(opened.id) ?? opened
    }

    var body: some View {
        ScrollView {
            // The photo leads: it fills the page, and the card sits low on it in frosted glass, so the
            // photo shows through (Kia, 2026-11-21: the photo was a side note and the empty card the star).
            ZStack(alignment: .top) {
                hero

                VStack(alignment: .leading, spacing: 12) {
                    // The name leads; the menu's own words sit to its right, smaller (Kia, 2026-11-19).
                    // Where the photo is from is said in the full-screen viewer, not here.
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            dishName
                            originalName
                            Spacer(minLength: 8)
                            price
                        }
                        // A long name leaves no room beside it: the menu's words go underneath.
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline) {
                                dishName
                                Spacer(minLength: 8)
                                price
                            }
                            originalName
                        }
                    }

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
                        // A glass button on the glass card, instead of a white pill.
                        .glassEffect(.regular.interactive(), in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    if state.menu.dishPeekRank(dish) != nil {
                        PopularityCard(dish: dish)
                    }
                    // A pick that came from Google Maps reviews says so, with the name unchanged and a link
                    // to the source, as Google's terms ask.
                    if dish.knownFor {
                        GoogleMapsSource()
                    }

                    // The "not sure" warnings come with the details, so say they are still coming.
                    if state.isExplaining(dish) && !state.avoid.isEmpty {
                        CheckingAllergens()
                    }
                    // What it contains, as emoji pills; what this user avoids first and highlighted.
                    let ingredients = state.ingredientBadges(dish)
                    if !ingredients.isEmpty {
                        BadgeRow(badges: ingredients)
                    }
                    if let note = state.spiceNote(dish) {
                        FlagCard(title: note, message: dish.spiceTip, icon: "flame")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .readHeight($contentHeight)
                // Room for the buttons floating over the bottom of the card.
                .padding(.bottom, Self.buttonsRoom)
                .frame(maxWidth: .infinity, minHeight: pageHeight - photoShown + Radius.large, alignment: .topLeading)
                // Liquid Glass over the blurred photo (Kia, 2026-11-21: frosted material looked dull). The glass runs
                // on far below the card, so pulling the page up past its end shows more card, not its edge.
                .background(alignment: .top) {
                    GeometryReader { card in
                        Color.clear
                            .frame(width: card.size.width, height: card.size.height + 1200)
                            .glassEffect(.regular, in: UnevenRoundedRectangle(topLeadingRadius: Radius.large, topTrailingRadius: Radius.large))
                    }
                }
                .padding(.top, photoShown - Radius.large)
                // While the photo is full screen, the card slides down out of the way, and back up after.
                .offset(y: viewingPhoto ? 900 : 0)
                .animation(.smooth(duration: 0.4), value: viewingPhoto)
            }
        }
        .ignoresSafeArea(edges: [.top, .bottom])
        // Behind the frosted card: the same photo, blurred into a wash of its colours, so the card takes
        // the dish's colours instead of being a white block.
        .background {
            ZStack {
                Color.canvas
                if let photo = dish.photos.first {
                    DishImage(source: photo)
                        .blur(radius: 50)
                        .opacity(0.85)
                }
            }
            .ignoresSafeArea()
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
        } action: { height in
            pageHeight = height
        }
        .safeAreaBar(edge: .bottom) {
            BottomButtons {
                GlassButton(title: "Ask about it") {
                    asking = true
                }
            } trailing: {
                // Once it is in the order, the button goes to the order instead of saying "Add" again.
                ActionButton(title: state.order.contains(dish.id) ? "Your order" : "Add to order") {
                    state.add(dish)
                    state.path.append(.order)
                }
            }
            .offset(y: viewingPhoto ? 200 : 0)
            .animation(.smooth(duration: 0.4), value: viewingPhoto)
        }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, pulled in
            // Pulled well past the top: open the photo, like stretching it open.
            if pulled < -110 && !dish.photos.isEmpty && !viewingPhoto {
                viewingPhoto = true
            }
        }
        .fullScreenCover(isPresented: $viewingPhoto) {
            PhotoViewer(photos: dish.photos, page: page, note: photoSourceText)
                .navigationTransition(.zoom(sourceID: page, in: photoSpace))
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

    var dishName: some View {
        Text(dish.name)
            .font(.system(size: 32, weight: .bold))
            .foregroundStyle(Color.textPrimary)
            .fixedSize()
    }

    var originalName: some View {
        Text(originalLine(dish))
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(Color.textSecondary)
            .fixedSize()
    }

    var price: some View {
        Text(state.menu.money(dish))
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(Color.textPrimary)
            .fixedSize()
    }

    // What to ask the server about this dish, in their language and the user's.
    var question: Bilingual {
        dish.question ?? state.menu.defaultQuestion
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

    static let buttonsRoom: CGFloat = 104

    // How much of the photo shows above the card: whatever the card's content leaves, so the card sits low
    // with no empty space (Kia, 2026-11-21). At least 55% of the screen; at most two thirds, because web
    // photos are mostly landscape and a taller frame crops into them until they blur.
    var photoShown: CGFloat {
        let left = pageHeight - contentHeight - Self.buttonsRoom + Radius.large
        return min(max(left, pageHeight * 0.55), pageHeight * 0.66).rounded()
    }

    // Swipeable photos. Pulling the screen down stretches the photo instead of showing a gap.
    var hero: some View {
        Color.actionSubtle
            .frame(height: photoShown + Radius.large)
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
                                .matchedTransitionSource(id: index, in: photoSpace)
                                .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                }
            }
            .clipped()
            // The sticker and the page count sit just above the card.
            .overlay(alignment: .top) {
                HStack(alignment: .bottom) {
                    if dish.peekPick {
                        PeekPickSticker()
                    }
                    Spacer()
                    if dish.photos.count > 1 {
                        Text("\(page + 1) / \(dish.photos.count)")
                            .font(.system(size: 13, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(Color.textPrimary)
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .glassEffect(.regular, in: .capsule)
                    }
                }
                .padding(.horizontal, 20)
                .frame(height: photoShown - Radius.large - 12, alignment: .bottom)
                .allowsHitTesting(false)
            }
            .visualEffect { [photoShown] content, proxy in
                let pull = max(0, proxy.frame(in: .scrollView).minY)
                return content.scaleEffect(1 + pull / photoShown, anchor: .bottom)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if !dish.photos.isEmpty { viewingPhoto = true }
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

// A dish photo full screen. It grows out of the photo on the dish page (zoom transition) and goes back
// there when dragged down (the system handles that drag) or tapped. Swipe between photos; pinch or
// double-tap to zoom in.
struct PhotoViewer: View {
    @Environment(\.dismiss) var dismiss
    var photos: [String]
    @State var page: Int
    // Where the photos are from ("Typical photo, not from this restaurant"), under the photo.
    var note: String?
    @State var zoom: CGFloat = 1
    @State var settledZoom: CGFloat = 1

    var body: some View {
        TabView(selection: $page) {
            ForEach(Array(photos.enumerated()), id: \.offset) { index, photo in
                DishImage(source: photo, fit: true)
                    .scaleEffect(index == page ? zoom : 1)
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .automatic : .never))
        .background(Color.black)
        .ignoresSafeArea()
        .overlay(alignment: .bottom) {
            if let note, zoom == 1 {
                HStack(spacing: 4) {
                    Image(systemName: "camera")
                        .font(.system(size: 11, weight: .medium))
                    Text(note)
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(.white.opacity(0.7))
                .padding(.bottom, photos.count > 1 ? 36 : 12)
            }
        }
        .gesture(
            MagnifyGesture()
                .onChanged { zoom = max(1, min(5, settledZoom * $0.magnification)) }
                .onEnded { _ in settledZoom = zoom }
        )
        .onTapGesture(count: 2) {
            withAnimation(.snappy) {
                zoom = zoom > 1 ? 1 : 2.5
                settledZoom = zoom
            }
        }
        .onTapGesture {
            // A single tap goes back to the dish, unless zoomed in.
            if zoom == 1 { dismiss() }
        }
        .onChange(of: page) {
            zoom = 1
            settledZoom = 1
        }
    }
}
