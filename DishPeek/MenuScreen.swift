import SwiftUI

// Which sheet is up on the menu screen. Only one at a time.
enum MenuSheet: Identifiable {
    case peek(Dish)

    var id: String {
        switch self {
        case .peek(let dish): "peek-" + dish.id
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
    // The photo/list switch's height, so the restaurant check can float just under it.
    @State var toggleHeight: CGFloat = 44
    // "Can't decide?": open or not, and its meals, kept while this screen is open.
    @State var deciding = false
    @State var planner = MealPlanner()
    // Where the switch ends and the bottom buttons start, on screen, so the meal panel fits between them,
    // and the bag's size, which the lightbulb matches.
    @State var toggleBottom: CGFloat = 120
    @State var buttonsFrame: CGRect = .zero
    @State var buttonSize: CGFloat = 52

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
                // No frosted fade under the buttons at the bottom (Kia, 2026-11-21).
                .scrollEdgeEffectHidden(true, for: .bottom)
                .transition(.opacity)
            }
        }
        .background(Color.canvas)
        // The meal panel sits over the menu but under both bars, so the buttons stay on top of it.
        .overlay {
            GeometryReader { geo in
                let screen = geo.frame(in: .global)
                ZStack(alignment: .bottom) {
                    if deciding {
                        Color.black.opacity(0.16)
                            .onTapGesture { closePanel() }
                            .transition(.opacity)
                        MealPanel(planner: planner,
                                  bottomInset: max(0, screen.maxY - 8 - buttonsFrame.minY) + 16,
                                  maxHeight: screen.maxY - toggleBottom - 16,
                                  onClose: closePanel) { dish in
                            state.path.append(.detail(dish.id))
                        }
                        .transition(.move(edge: .bottom))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
            .ignoresSafeArea()
        }
        .safeAreaBar(edge: .top, spacing: 0) {
            // Floats right on the photo: glass controls, no bar behind them.
            PhotoListToggle(mode: $state.menuMode)
                // The restaurant check floats under the switch, over the menu, so the photo doesn't move
                // when it comes and goes.
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { toggleHeight = $0 }
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { toggleBottom = $0 }
                .overlay(alignment: .top) {
                    if state.askPlace {
                        PlaceCheck()
                            .padding(.top, toggleHeight + 8)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .animation(.smooth(duration: 0.4), value: state.askPlace)
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, 8)
        }
        .safeAreaBar(edge: .bottom) {
            VStack(alignment: .trailing, spacing: 12) {
            // Until the first tap on a dish: a hint that the dishes on the photo can be tapped.
            if state.menuMode == .photo && !state.hasTappedDish && !isPeeking && !deciding {
                HStack(spacing: 6) {
                    Image(systemName: "hand.tap")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Tap a dish to see what it is")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundStyle(Color.textPrimary)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .glassEffect(.regular, in: .capsule)
                .frame(maxWidth: .infinity)
                // Leaves fast, so it doesn't hang over the meal panel as that rises.
                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 8)),
                                        removal: .opacity.animation(.easeOut(duration: 0.12))))
            }
            // On the photo: the translation switch, above Order.
            if state.menuMode == .photo && !deciding {
                LanguageToggle(
                    original: state.menu.sourceLanguage,
                    target: state.menu.targetLanguage,
                    translated: $state.photoTranslated,
                    peeking: $state.photoPeeking,
                    showsTranslation: state.photoShowsTranslation
                )
                .sensoryFeedback(.selection, trigger: state.photoShowsTranslation)
                .padding(.trailing, 28)
                .transition(.asymmetric(insertion: .opacity, removal: .opacity.animation(.easeOut(duration: 0.12))))
            }
            BottomButtons {
                // A lightbulb for "give me an idea" (Kia, 2026-11-21: the die didn't say it). With the meal
                // panel open it is "Another one".
                DecideButton(expanded: deciding, busy: planner.loading, size: buttonSize,
                             width: buttonsFrame.width - 56 - buttonSize - 12) {
                    if deciding {
                        if !planner.loading { planner.load(state, again: true) }
                    } else {
                        planner.open(state)
                        withAnimation(.smooth(duration: 0.45)) { deciding = true }
                    }
                }
            } trailing: {
                IconButton(systemName: "bag.fill", label: "Order (\(state.order.count))", prominent: true, count: state.order.count) {
                    state.path.append(.order)
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { buttonSize = $0 }
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { buttonsFrame = $0 }
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
        withAnimation(.smooth(duration: 0.3)) {
            state.hasTappedDish = true
        }
        withAnimation(.snappy) {
            state.selectedLine = dish.id
        }
        sheet = .peek(dish)
    }

    func closePanel() {
        withAnimation(.smooth(duration: 0.4)) { deciding = false }
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
            // No subtitles under the section titles (Kia, 2026-11-19). Where a photo comes from is still
            // said on the dish's own page.
            let cards = state.menu.popular

            if !cards.isEmpty {
            Text("Popular")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
                .padding(.horizontal, 20)

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

            // Two columns of big photos, straight on the page: the white card around a one-column list
            // took room the photos needed (Kia, 2026-11-21).
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12, alignment: .top), GridItem(.flexible(), spacing: 12, alignment: .top)], alignment: .leading, spacing: 20) {
                ForEach(state.menu.dishes) { dish in
                    MenuTile(dish: dish, price: state.menu.money(dish), badges: state.flagBadges(dish), isAdded: state.order.contains(dish.id)) {
                        onOpen(dish)
                    } onAdd: {
                        // Plus adds it; the green check takes it out again.
                        withAnimation(.snappy) {
                            state.toggleInOrder(dish)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
        .padding(.top, 16)
        .padding(.bottom, 12)
    }
}

// Whether the restaurant we found is the one the user is in, asked without stopping them: a glass banner
// under the photo/list switch that stays until answered (Kia, 2026-11-21).
// It matters because Popular and the photos come from that restaurant.
struct PlaceCheck: View {
    @Environment(AppState.self) var state

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(Color.action)
            VStack(alignment: .leading, spacing: 1) {
                Text("Are you at \(state.place.name)?")
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Text(verbatim: [state.place.area, state.place.distanceText].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Not here") {
                state.forgetPlace()
                state.askPlace = false
            }
            .buttonStyle(.glass)
            Button("Yes") {
                state.askPlace = false
            }
            .buttonStyle(.glassProminent)
            .tint(Color.action)
        }
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(Color.textPrimary)
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22))
        // It stays until answered (Kia, 2026-11-21: it went away before people had read it).
    }
}

// A tall card in the Popular row: the photo fills the card, the Peek's Pick sticker sits on top, and the
// name, price, original and two lines of what it is float on a white panel at the bottom
// (Kia, 2026-11-21, option D, after the Kazu Ramen reference). Bigger and more photo-led than the
// grid below it, so the two rows read differently.
struct PopularDishCard: View {
    var dish: Dish
    var price: String
    var badge: BadgeInfo?

    static let size = CGSize(width: 264, height: 352)

    var body: some View {
        DishPhoto(dish: dish, size: Self.size.width, height: Self.size.height, radius: Radius.large)
            .overlay(alignment: .topLeading) {
                if let badge {
                    Group {
                        if badge.peekMark {
                            PeekPickSticker()
                        } else {
                            Badge(info: badge)
                                .background(Color.surface, in: Capsule())
                        }
                    }
                    .padding(10)
                }
            }
            .overlay(alignment: .bottom) {
                info
                    .padding(8)
            }
            .contentShape(RoundedRectangle(cornerRadius: Radius.large))
    }

    var info: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(dish.name)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(price)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
            }
            // Darker than the usual grey: on frosted glass over a dark photo the grey was hard to read.
            Text(dish.originalName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.textPrimary.opacity(0.72))
                .lineLimit(1)
            // Two lines of what it is; the room is kept while it loads, so the cards stay level.
            Text(description)
                .font(.system(size: 13))
                .foregroundStyle(Color.textPrimary.opacity(0.72))
                .lineLimit(2)
                .frame(height: 36, alignment: .topLeading)
                .padding(.top, 2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Liquid Glass, so the photo shows through: a solid white panel was too loud, and frosted
        // material looked flat and grey (Kia, 2026-11-21).
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Radius.large - 8))
    }

    // The longer description, else the short one. The model sometimes sends a stray "," as a
    // description: anything without a few letters counts as none.
    var description: String {
        [dish.details, dish.summary].first { text in
            text.unicodeScalars.filter { $0.properties.isAlphabetic }.count >= 4
        } ?? ""
    }
}

// One dish in the full menu: a square photo with quick add on its corner, then name, the original, price,
// and only the warnings this user cares about.
struct MenuTile: View {
    var dish: Dish
    var price: String
    var badges: [BadgeInfo]
    var isAdded: Bool
    var onOpen: () -> Void
    var onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onOpen) {
                Color.actionSubtle
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        if let photo = dish.photos.first {
                            DishImage(source: photo)
                        } else {
                            Image(systemName: "fork.knife")
                                .font(.system(size: 34))
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Radius.medium))
                    .contentShape(RoundedRectangle(cornerRadius: Radius.medium))
            }
            .buttonStyle(.plain)
            .overlay(alignment: .bottomTrailing) {
                Button(action: onAdd) {
                    Image(systemName: isAdded ? "checkmark" : "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(isAdded ? Color.textOnAction : Color.textPrimary)
                        .frame(width: 34, height: 34)
                        .background(isAdded ? Color.action : Color.surface, in: Circle())
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                // A solid green check once it is in the order, not a faded one (Kia, 2026-11-21); tapping it again
                // takes the dish out.
                .sensoryFeedback(.selection, trigger: isAdded)
                .padding(8)
                .accessibilityLabel(isAdded ? String(localized: "\(dish.name) is in your order") : String(localized: "Add \(dish.name) to order"))
            }

            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(dish.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(dish.originalName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                    Text(price)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                        .padding(.top, 2)
                    if !badges.isEmpty {
                        BadgeRow(badges: badges)
                            .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}
