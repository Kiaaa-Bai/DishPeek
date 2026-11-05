import SwiftUI

// Which sheet is up on the menu screen. Only one at a time.
enum MenuSheet: Identifiable {
    case peek(Dish)
    case cantDecide

    var id: String {
        switch self {
        case .peek(let dish): "peek-" + dish.id
        case .cantDecide: "cantDecide"
        }
    }
}

// Screens 3 and 5: the menu, as the photo or as a list.
// As a photo it fills the screen behind everything and pans and zooms like a map.
struct MenuScreen: View {
    @Environment(AppState.self) var state
    @State var sheet: MenuSheet?
    @State var peekHeight: CGFloat = 300
    @State var zoomActivity = ZoomActivity()

    var isPeeking: Bool {
        if case .peek = sheet { return true }
        return false
    }

    var body: some View {
        @Bindable var state = state

        GeometryReader { geo in
            if state.menuMode == .photo {
                photo(insets: geo.safeAreaInsets)
                    .ignoresSafeArea()
                    .scrollEdgeEffectHidden(true, for: .all)
                    .transition(.opacity)
            } else {
                ScrollView {
                    DishList { dish in
                        state.path.append(.detail(dish.id))
                    }
                }
                .transition(.opacity)
            }
        }
        .background(Color.canvas)
        .safeAreaBar(edge: .top, spacing: 0) {
            // Floats right on the photo: glass controls, no bar behind them.
            PhotoListToggle(mode: $state.menuMode)
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, 8)
        }
        .safeAreaBar(edge: .bottom) {
            VStack(alignment: .trailing, spacing: 12) {
            // On the photo: the translation switch, above Order.
            if state.menuMode == .photo {
                LanguageToggle(
                    original: state.menu.sourceLanguage,
                    target: state.menu.targetLanguage,
                    translated: $state.photoTranslated,
                    peeking: $state.photoPeeking,
                    showsTranslation: state.photoShowsTranslation
                )
                .sensoryFeedback(.selection, trigger: state.photoShowsTranslation)
                .padding(.trailing, 28)
                .transition(.opacity)
            }
            BottomButtons {
                GlassButton(title: "Can't decide?") {
                    sheet = .cantDecide
                }
            } trailing: {
                ActionButton(title: "Order (\(state.order.count))") {
                    state.path.append(.order)
                }
                .contentTransition(.numericText())
                .animation(.snappy, value: state.order.count)
            }
            }
        }
        .navigationTitle(state.place.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // The name, with the Google Maps rating small under it. On the photo it sits on glass,
            // so it reads over any picture.
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text(state.place.name)
                        .font(.system(size: 17, weight: .semibold))
                        .lineLimit(1)
                    if state.place.ratingCount > 0 {
                        Text("\(Image(systemName: "star.fill")) \(state.place.rating, format: .number.precision(.fractionLength(1))) \(Text("on Google Maps · \(state.place.category)"))")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(1)
                    }
                }
                .foregroundStyle(Color.textPrimary)
                .padding(.horizontal, state.menuMode == .photo ? 16 : 0)
                .padding(.vertical, state.menuMode == .photo ? 5 : 0)
                .glassEffect(state.menuMode == .photo ? .regular : .identity, in: .capsule)
            }
            ToolbarItem(placement: .topBarTrailing) {
                SettingsButton(inToolbar: true)
            }
        }
        .sheet(item: $sheet, onDismiss: sheetClosed) { sheet in
            switch sheet {
            case .peek(let dish):
                DishPeekSheet(dish: dish, height: $peekHeight) {
                    self.sheet = nil
                    state.path.append(.detail(dish.id))
                } onAdd: {
                    self.sheet = nil
                    state.add(dish)
                    state.path.append(.order)
                }
            case .cantDecide:
                CantDecideSheet { dishes in
                    self.sheet = nil
                    for dish in dishes {
                        state.add(dish)
                    }
                    state.path.append(.order)
                }
            }
        }
    }

    // The menu photo (the user's own, or the sample) behind the bars, zoomable.
    // While a line is selected it is kept in view above the peek sheet.
    func photo(insets: EdgeInsets) -> some View {
        let selectedBox = state.selectedLine.flatMap { state.dish($0) }.flatMap { state.shownBox($0) }
        let focus = selectedBox.map { CGRect(x: $0[0], y: $0[1], width: $0[2], height: $0[3]) }
        let aspect = state.photo.map { $0.size.height / max(1, $0.size.width) } ?? MenuPhoto.aspect
        return ZoomView(aspect: aspect, insets: insets, focus: state.photo == nil ? nil : focus,
                        bottomCover: isPeeking ? peekHeight : 0, activity: zoomActivity,
                        // Real photos scale their drawn translations with the photo, so they can be drawn larger.
                        detail: state.photo == nil ? 1 : 2) { point, size in
            if let dish = dish(at: point, in: size) {
                peek(dish)
            }
        } content: {
            Group {
                if let image = state.photo {
                    PhotoMenu(image: image, menu: state.menu, selected: state.selectedLine) { _ in }
                } else {
                    MenuPhoto(menu: state.menu, selected: state.selectedLine, badges: state.lineBadges) { _ in }
                }
            }
            // Taps are handled by the zoomable view, so pinches that start on a line still zoom.
            .allowsHitTesting(false)
            .environment(state)
            .fontDesign(.rounded)
        }
    }

    // The dish whose line is under a tap on the photo, if any. Closest line wins where lines overlap.
    func dish(at point: CGPoint, in size: CGSize) -> Dish? {
        var hits: [(dish: Dish, distance: CGFloat)] = []
        for dish in state.menu.dishes {
            let shape: Path
            if state.photo == nil {
                guard let frame = state.sampleLineFrames[dish.id] else { continue }
                shape = Path(frame)
            } else if !state.showsRedrawn, let cover = state.lineCovers[dish.id] {
                let rect = CGRect(x: cover.box[0] * size.width, y: cover.box[1] * size.height,
                                  width: cover.box[2] * size.width, height: cover.box[3] * size.height)
                shape = Strip(center: cover.center, size: CGSize(width: cover.length, height: cover.thickness), angle: cover.angle)
                    .path(in: rect)
            } else if let box = state.shownBox(dish) {
                shape = Path(CGRect(x: box[0] * size.width, y: box[1] * size.height,
                                    width: box[2] * size.width, height: box[3] * size.height).insetBy(dx: -6, dy: -4))
            } else {
                continue
            }
            if shape.contains(point) {
                let middle = CGPoint(x: shape.boundingRect.midX, y: shape.boundingRect.midY)
                hits.append((dish, hypot(point.x - middle.x, point.y - middle.y)))
            }
        }
        return hits.min { $0.distance < $1.distance }?.dish
    }

    func peek(_ dish: Dish) {
        // The end of a pinch or drag over a line is not a tap on it.
        guard !zoomActivity.isBusy else { return }
        withAnimation(.snappy) {
            state.selectedLine = dish.id
        }
        sheet = .peek(dish)
    }

    func sheetClosed() {
        // Tapping another line swaps the sheet; keep that new line selected.
        if sheet == nil {
            withAnimation(.snappy) {
                state.selectedLine = nil
            }
        }
    }
}

// Screen 5. Popular dishes as big photo cards (like Yelp and Google Maps),
// then the whole menu translated, in the printed order, with quick add (like Uber Eats).
struct DishList: View {
    @Environment(AppState.self) var state
    var onOpen: (Dish) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Popular: each card's badge says why (Google Maps, the menu's marks, DishPeek orders, an AI pick).
            let cards = state.menu.popular
            let typicalPhotos = cards.contains { $0.photoSource == .typical }
            let onlyMapsAndOrders = cards.allSatisfy { $0.knownFor || $0.dishPeekOrders > 0 }

            if !cards.isEmpty {
            Text("Popular")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
                .padding(.horizontal, 20)
            if typicalPhotos || onlyMapsAndOrders {
                HStack(spacing: 4) {
                    Image(systemName: typicalPhotos ? "photo" : "person.2")
                        .font(.system(size: 11, weight: .medium))
                    Text(typicalPhotos ? LocalizedStringKey("Typical photos, not from this restaurant") : LocalizedStringKey("From Google Maps and DishPeek orders"))
                        .font(.system(size: 13))
                }
                .foregroundStyle(Color.textSecondary)
                .padding(.horizontal, 20)
                .padding(.top, 4)
            }

            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(cards) { dish in
                        Button {
                            onOpen(dish)
                        } label: {
                            PopularDishCard(dish: dish, price: state.menu.money(dish), badge: state.popularityBadges(dish).first)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .contentMargins(.horizontal, 20, for: .scrollContent)
            .padding(.top, 14)
            }

            Text("Full menu")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
                .padding(.horizontal, 20)
                .padding(.top, 28)
            Text("Everything on their menu, in the same order")
                .font(.system(size: 13))
                .foregroundStyle(Color.textSecondary)
                .padding(.horizontal, 20)
                .padding(.top, 4)

            VStack(spacing: 0) {
                ForEach(Array(state.menu.dishes.enumerated()), id: \.element.id) { index, dish in
                    if index > 0 {
                        Rectangle()
                            .fill(Color.border)
                            .frame(height: 1)
                            .padding(.leading, 16)
                    }
                    MenuRow(dish: dish, price: state.menu.money(dish), badges: state.flagBadges(dish), isAdded: state.order.contains(dish.id)) {
                        onOpen(dish)
                    } onAdd: {
                        withAnimation(.snappy) {
                            state.add(dish)
                        }
                    }
                }
            }
            .card(radius: Radius.medium)
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
        .padding(.top, 16)
        .padding(.bottom, 12)
    }
}

// A big photo card in the Popular row.
struct PopularDishCard: View {
    var dish: Dish
    var price: String
    var badge: BadgeInfo?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DishPhoto(dish: dish, size: 172, height: 128, radius: Radius.medium)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(dish.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                    Spacer(minLength: 4)
                    Text(price)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.textSecondary)
                }
                Text(dish.summary)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }
            if let badge {
                Badge(info: badge)
            }
        }
        .frame(width: 172, alignment: .leading)
        .contentShape(Rectangle())
    }
}

// One line of the translated menu: its photo, name, the original, what it is, price, quick add.
struct MenuRow: View {
    var dish: Dish
    var price: String
    var badges: [BadgeInfo]
    var isAdded: Bool
    var onOpen: () -> Void
    var onAdd: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: onOpen) {
                HStack(alignment: .center, spacing: 12) {
                    DishPhoto(dish: dish, size: 64, radius: Radius.small)
                    VStack(alignment: .leading, spacing: 3) {
                        // Side by side when both fit; with the photo taking room, usually one above the other.
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                rowName
                                rowOriginal
                            }
                            VStack(alignment: .leading, spacing: 1) {
                                rowName
                                rowOriginal
                            }
                        }
                        Text(dish.summary)
                            .font(.system(size: 14))
                            .foregroundStyle(Color.textSecondary)
                        if !badges.isEmpty {
                            BadgeRow(badges: badges)
                                .padding(.top, 4)
                        }
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
                    .frame(width: 32, height: 32)
                    .background(isAdded ? Color.action : Color.border, in: Circle())
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .disabled(isAdded)
            .accessibilityLabel(isAdded ? String(localized: "\(dish.name) is in your order") : String(localized: "Add \(dish.name) to order"))
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .padding(.vertical, 14)
    }

    var rowName: some View {
        Text(dish.name)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Color.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }

    var rowOriginal: some View {
        Text(dish.originalName)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Color.textSecondary)
            .lineLimit(1)
    }
}
