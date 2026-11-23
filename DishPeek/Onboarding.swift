import SwiftUI

// The first launch (Kia, 2026-11-21, after references from seven real apps and two HTML prototypes):
// three pages that show what the app does on one drawn menu, a tap each; then the language menus are
// translated into, four short questions one per screen, and last the camera, asked for only when it's
// about to be used. Food choices are still required before anything else.
//
// The top (the logo, or back and progress) and the button at the bottom stay put; only what's between
// them changes from screen to screen (Kia, 2026-11-21: they flashed with every change).
struct OnboardingView: View {
    @Environment(AppState.self) var state
    @AppStorage(Languages.translationKey) var translationLanguage = ""

    enum Step: Int { case features, language, diet, dislikes, allergies, spice, camera }
    @State var step = Step.features
    @State var featurePage = 0
    @State var forward = true
    // The answers, saved together at the end.
    @State var language = ""                // empty: the phone's language
    @State var diet: Allergen? = nil
    @State var dietChosen = false
    @State var dislikes: Set<Allergen> = []
    @State var allergies: Set<Allergen> = []
    @State var spice: Spice? = nil

    // The page's own words are the title, big, so people notice them change (Kia, 2026-11-21); "Read any
    // menu" sits small by the logo.
    // Short enough for one line (Kia, 2026-11-22: they were too long).
    static let captions: [LocalizedStringKey] = [
        "One photo, in your language",
        "See every dish",
        "AI picks, flags what you avoid",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .frame(height: 44)
            Group {
                content
            }
            .id(step)
            // The content fades in place and slides a little, the way it moves forward or back.
            .transition(.asymmetric(insertion: .offset(x: forward ? 28 : -28).combined(with: .opacity),
                                    removal: .offset(x: forward ? -28 : 28).combined(with: .opacity)))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            ActionButton(title: buttonTitle, fullWidth: true, action: next)
                .controlSize(.large)
                .disabled(!canContinue)
                .padding(.top, 12)
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background {
            ZStack {
                Color.canvas
                if step == .camera {
                    CameraBackdrop()
                        .transition(.opacity)
                }
            }
            .ignoresSafeArea()
            .animation(.smooth(duration: 0.35), value: step == .camera)
        }
        // White status bar over the dark camera page; light everywhere else, like the app.
        .preferredColorScheme(step == .camera ? .dark : .light)
    }

    // MARK: Top and bottom

    var header: some View {
        ZStack(alignment: .leading) {
            if step == .features {
                HStack(spacing: 10) {
                    PeekMark(height: 24, color: .action, ink: .action)
                    Text("Read any menu")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.textSecondary)
                }
                .transition(.opacity)
            } else {
                HStack(spacing: 14) {
                    Button(action: back) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(step == .camera ? Color.white : Color.textPrimary)
                            .frame(width: 44, height: 44)
                            .glassEffect(.regular.interactive(), in: .circle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Back"))
                    if step != .camera {
                        HStack(spacing: 6) {
                            ForEach(1...5, id: \.self) { index in
                                Capsule()
                                    .fill(index <= progress ? Color.action : Color.textPrimary.opacity(0.1))
                                    .frame(height: 5)
                            }
                        }
                        .animation(.smooth(duration: 0.3), value: progress)
                        .transition(.opacity)
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.3), value: step == .features)
        .animation(.smooth(duration: 0.3), value: step == .camera)
    }

    var progress: Int {
        switch step {
        case .language: 1
        case .diet: 2
        case .dislikes: 3
        case .allergies: 4
        case .spice: 5
        default: 0
        }
    }

    var buttonTitle: LocalizedStringKey {
        switch step {
        case .features: "Next"
        case .dislikes: dislikes.isEmpty ? "I eat it all, continue" : "Continue"
        case .allergies: allergies.isEmpty ? "No allergies, continue" : "Continue"
        case .camera: "Get started"
        default: "Continue"
        }
    }

    var canContinue: Bool {
        switch step {
        case .diet: dietChosen
        case .spice: spice != nil
        default: true
        }
    }

    func next() {
        switch step {
        case .features:
            if featurePage < Self.captions.count - 1 {
                withAnimation(.smooth(duration: 0.55)) { featurePage += 1 }
            } else {
                go(.language)
            }
        case .language: go(.diet)
        case .diet: go(.dislikes)
        case .dislikes: go(.allergies)
        case .allergies: go(.spice)
        case .spice: go(.camera)
        case .camera: finish()
        }
    }

    func back() {
        switch step {
        case .language: go(.features)
        case .diet: go(.language)
        case .dislikes: go(.diet)
        case .allergies: go(.dislikes)
        case .spice: go(.allergies)
        case .camera: go(.spice)
        case .features: break
        }
    }

    func go(_ next: Step) {
        forward = next.rawValue > step.rawValue
        // The direction has to be in place before the screens swap, for the slide to go the right way.
        DispatchQueue.main.async {
            withAnimation(.smooth(duration: 0.3)) { step = next }
        }
    }

    func finish() {
        var avoid = dislikes.union(allergies)
        if let diet { avoid.insert(diet) }
        state.avoid = avoid
        state.spice = spice
        translationLanguage = language
        state.hasSetPreferences = true
    }

    // MARK: What changes

    @ViewBuilder var content: some View {
        switch step {
        case .features: features
        case .language: languageScreen
        case .diet: dietScreen
        case .dislikes: dislikesScreen
        case .allergies: allergiesScreen
        case .spice: spiceScreen
        case .camera: cameraScreen
        }
    }

    var features: some View {
        let pair = DemoMenu.pair(for: Languages.user)
        return VStack(alignment: .leading, spacing: 0) {
            FeatureScene(page: featurePage, printed: pair.printed, redrawn: pair.redrawn)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(spacing: 6) {
                ForEach(0..<Self.captions.count, id: \.self) { index in
                    Capsule()
                        .fill(index <= featurePage ? Color.action : Color.textPrimary.opacity(0.1))
                        .frame(height: 4)
                }
            }
            .animation(.smooth(duration: 0.3), value: featurePage)
            ZStack(alignment: .topLeading) {
                Text(Self.captions[featurePage])
                    .id(featurePage)
                    .transition(.blurReplace)
            }
            .font(.system(size: 28, weight: .bold))
            .foregroundStyle(Color.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
            .padding(.top, 16)
            .animation(.smooth(duration: 0.35), value: featurePage)
        }
    }

    func question<Content: View>(_ title: LocalizedStringKey, @ViewBuilder _ answers: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Color.textPrimary)
                .padding(.top, 22)
            ScrollView {
                answers()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 22)
                    .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    // Every language, the phone's first and ticked (Kia, 2026-11-21).
    var languageScreen: some View {
        let phone = Languages.translationChoices.first { Languages.user.hasPrefix($0) } ?? "en"
        return question("Translate menus into") {
            VStack(alignment: .leading, spacing: 10) {
                ChoiceRow(title: Languages.ownName(phone), detail: String(localized: "Your phone's language"),
                          isOn: language.isEmpty || language == phone) { language = "" }
                ForEach(Languages.translationChoices.filter { $0 != phone }, id: \.self) { code in
                    ChoiceRow(title: Languages.ownName(code), detail: Languages.name(code), isOn: language == code) { language = code }
                }
                Text("You can change this in Settings.")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.textSecondary)
                    .padding(.top, 4)
            }
        }
    }

    var dietScreen: some View {
        question("Any eating habits?") {
            VStack(spacing: 10) {
                ChoiceRow(title: String(localized: "No, I eat everything"), emoji: "🍽️", isOn: dietChosen && diet == nil) {
                    diet = nil
                    dietChosen = true
                }
                ForEach(Allergen.diets) { choice in
                    ChoiceRow(title: choice.title, emoji: choice.emoji, isOn: diet == choice) {
                        diet = choice
                        dietChosen = true
                    }
                }
            }
        }
    }

    var dislikesScreen: some View {
        question("Anything you don't eat?") {
            FlowLayout {
                ForEach(Allergen.dislikes) { item in
                    Chip(title: item.title, emoji: item.emoji, isOn: dislikes.contains(item)) { toggle(item, in: &dislikes) }
                }
            }
        }
    }

    var allergiesScreen: some View {
        question("Any allergies?") {
            FlowLayout {
                ForEach(Allergen.allergies) { item in
                    Chip(title: item.title, emoji: item.emoji, isOn: allergies.contains(item)) { toggle(item, in: &allergies) }
                }
            }
        }
    }

    var spiceScreen: some View {
        question("How spicy can you go?") {
            VStack(spacing: 18) {
                SpiceFace(level: spice?.chilies ?? -1)
                ChiliScale(spice: $spice, stacked: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
        }
    }

    var cameraScreen: some View {
        VStack(spacing: 8) {
            Spacer()
            Text("Point at a menu")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)
            Text("Take a photo and read it in your language.")
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 14)
    }

    func toggle(_ item: Allergen, in set: inout Set<Allergen>) {
        if set.contains(item) { set.remove(item) } else { set.insert(item) }
    }
}

// Behind the last page: the sample menu, dark and soft, as if the camera were already looking at one,
// with the scan corners breathing. In an overlay, so the picture fills the screen without widening it.
struct CameraBackdrop: View {
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State var breathe = false

    var body: some View {
        Color.black
            .overlay {
                Image("example-menu")
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 3)
                    .overlay(Color.black.opacity(0.55))
            }
            .clipped()
            .overlay {
                ScanBrackets()
                    .stroke(.white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .padding(.horizontal, 34)
                    .padding(.top, 150)
                    .padding(.bottom, 290)
                    .scaleEffect(breathe ? 0.965 : 1)
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { breathe = true }
            }
    }
}

// One answer of a single-choice question: a full-width card, green with a check when chosen.
struct ChoiceRow: View {
    var title: String
    var detail: String? = nil
    var emoji: String? = nil
    var isOn: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let emoji {
                    Text(verbatim: emoji)
                        .font(.system(size: 22))
                        .frame(width: 28)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: title)
                        .font(.system(size: 17, weight: .medium))
                    if let detail {
                        Text(verbatim: detail)
                            .font(.system(size: 13))
                            .foregroundStyle(isOn ? Color.textOnAction.opacity(0.7) : Color.textSecondary)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .bold))
                    .opacity(isOn ? 1 : 0)
                    .scaleEffect(isOn ? 1 : 0.6)
            }
            .foregroundStyle(isOn ? Color.textOnAction : Color.textPrimary)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .frame(minHeight: 58)
            .background(isOn ? Color.action : Color.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18).strokeBorder(isOn ? Color.clear : Color.border)
            }
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isOn)
        .animation(.snappy(duration: 0.2), value: isOn)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
