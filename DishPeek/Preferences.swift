import SwiftUI

// The food choices, in three groups so no choice reads two ways (Kia, 2026-11-21: "does picking pork mean I
// don't eat it or only eat it?"). "I am…" is one diet or none; "I don't eat" and "I'm allergic" are things to
// avoid. Then how spicy. Used on the first screen and in Settings.
struct PreferencesForm: View {
    @Binding var avoid: Set<Allergen>
    @Binding var eatsEverything: Bool
    @Binding var spice: Spice?

    var diet: Allergen? { Allergen.diets.first { avoid.contains($0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            heading("I am…")
            FlowLayout {
                // No diet: eats everything. Allergies and dislikes stay as they are.
                Chip(title: String(localized: "I eat everything"), emoji: "🍽️", isOn: diet == nil && eatsEverything) {
                    avoid.subtract(Allergen.diets)
                    eatsEverything = true
                }
                ForEach(Allergen.diets) { dietChip($0) }
            }

            heading("I don't eat")
            FlowLayout {
                ForEach(Allergen.dislikes) { avoidChip($0) }
            }

            heading("I'm allergic to")
            FlowLayout {
                ForEach(Allergen.allergies) { avoidChip($0) }
            }

            heading("Spice")
            ChiliScale(spice: $spice)
        }
    }

    func heading(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Color.textSecondary)
            .padding(.top, 10)
    }

    // One diet at most: picking one replaces the last; picking it again clears it.
    func dietChip(_ choice: Allergen) -> some View {
        Chip(title: choice.title, emoji: choice.emoji, isOn: diet == choice) {
            let wasOn = diet == choice
            avoid.subtract(Allergen.diets)
            if !wasOn {
                avoid.insert(choice)
            }
            eatsEverything = wasOn
        }
    }

    func avoidChip(_ allergen: Allergen) -> some View {
        Chip(title: allergen.title, emoji: allergen.emoji, isOn: avoid.contains(allergen)) {
            if avoid.contains(allergen) {
                avoid.remove(allergen)
            } else {
                avoid.insert(allergen)
            }
        }
    }
}

// Spice as five chilies, like a star rating: tap one, or drag across them. More chilies, hotter.
// Dragging to the far left (or tapping the only lit chili) means not spicy. The level's name shows beside it.
struct ChiliScale: View {
    @Binding var spice: Spice?
    // The level's name under the chilies, centred, instead of beside them: beside, its changing length
    // pushed the chilies around (Kia, 2026-11-21). Bigger too, for the first-launch question.
    var stacked = false

    var cell: CGFloat { stacked ? 50 : 36 }
    var level: Int { spice?.chilies ?? 0 }

    var body: some View {
        let layout = stacked ? AnyLayout(VStackLayout(spacing: 14)) : AnyLayout(HStackLayout(spacing: 10))
        layout {
            HStack(spacing: 0) {
                ForEach(1...5, id: \.self) { count in
                    Text(verbatim: "🌶️")
                        .font(.system(size: stacked ? 32 : 22))
                        .grayscale(count <= level ? 0 : 1)
                        .opacity(count <= level ? 1 : 0.25)
                        .scaleEffect(count == level ? 1.12 : 1)
                        .frame(width: cell, height: stacked ? 56 : 44)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        // Dragging follows the finger; past the left edge is not spicy.
                        if abs(drag.translation.width) > 3 {
                            set(count(at: drag.location.x))
                        }
                    }
                    .onEnded { drag in
                        let tapped = count(at: drag.location.x)
                        if abs(drag.translation.width) <= 3 {
                            // A tap sets that many; tapping the only lit chili turns it off.
                            set(tapped == 1 && level == 1 ? 0 : tapped)
                        } else {
                            set(tapped)
                        }
                    }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Spice"))
            .accessibilityValue(Text(spice?.title ?? ""))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: set(level + 1)
                case .decrement: set(level - 1)
                @unknown default: break
                }
            }

            Text(spice.map { $0 == Spice.none ? String(localized: "Not spicy") : $0.title } ?? String(localized: "Tap or drag"))
                .font(.system(size: stacked ? 20 : 15, weight: stacked && spice != nil ? .semibold : .medium))
                .foregroundStyle(spice == nil ? Color.textSecondary : Color.textPrimary)
                .contentTransition(.opacity)
                .frame(height: stacked ? 26 : nil)
        }
        .animation(.snappy(duration: 0.2), value: level)
        .sensoryFeedback(.selection, trigger: level)
    }

    func count(at x: CGFloat) -> Int {
        Int((x / cell).rounded(.up))
    }

    func set(_ count: Int) {
        let clamped = min(max(count, 0), 5)
        spice = Spice.allCases.first { $0.chilies == clamped }
    }
}

// Settings: the app's language, the language menus are translated into, and the food choices.
struct SettingsView: View {
    @Environment(AppState.self) var state
    @Environment(\.dismiss) var dismiss
    @Environment(\.openURL) var openURL
    @State var eatsEverything = false
    @AppStorage(Languages.translationKey) var translationLanguage = ""

    var body: some View {
        @Bindable var state = state

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    languageRows
                    PreferencesForm(avoid: $state.avoid, eatsEverything: $eatsEverything, spice: $state.spice)
                    // No redraw switch: redrawing the menu is the app's core and always on (Kia, 2026-11-19).

                    // Start over: forget the food choices and show the first-launch pages again, so each
                    // usability-test participant gets a fresh start (lost in the 2026-11-21 Settings rewrite).
                    Button {
                        dismiss()
                        state.startOver()
                    } label: {
                        Text("Start over")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(Color.caution)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.medium))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 24)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Color.canvas)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .close) {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            eatsEverything = !state.avoid.contains(where: \.isDiet)
        }
    }

    // Two languages, two rows, no icons (Kia, 2026-11-21). The app's language is iOS's own per-app setting,
    // so it opens there; the menu's is ours.
    var languageRows: some View {
        VStack(spacing: 0) {
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            } label: {
                HStack {
                    Text("App language")
                    Spacer(minLength: 8)
                    Text(verbatim: Languages.ownName(Languages.user))
                        .foregroundStyle(Color.textSecondary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.textSecondary.opacity(0.6))
                }
                .padding(.horizontal, 16)
                .frame(height: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Rectangle()
                .fill(Color.border)
                .frame(height: 1)
                .padding(.leading, 16)

            HStack {
                Text("Translate menus into")
                Spacer(minLength: 8)
                // A menu with our own label, so the value is the same size as the row above; a menu-style
                // Picker draws its value smaller (Kia, 2026-11-21).
                Menu {
                    Picker(selection: $translationLanguage) {
                        Text("Same as the app").tag("")
                        ForEach(Languages.translationChoices, id: \.self) { code in
                            Text(verbatim: Languages.ownName(code)).tag(code)
                        }
                    } label: {
                        Text("Translate menus into")
                    }
                } label: {
                    HStack(spacing: 6) {
                        Group {
                            if translationLanguage.isEmpty {
                                Text("Same as the app")
                            } else {
                                Text(verbatim: Languages.ownName(translationLanguage))
                            }
                        }
                        .foregroundStyle(Color.textSecondary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.textSecondary.opacity(0.6))
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
        }
        .font(.system(size: 17))
        .foregroundStyle(Color.textPrimary)
        .card(radius: Radius.medium)
    }
}

// The gear that opens Settings, on the camera and on the menu.
// In a toolbar the system already draws the glass circle, so it adds none of its own there.
struct SettingsButton: View {
    var inToolbar = false
    @State var isOpen = false

    var body: some View {
        Group {
            if inToolbar {
                button
            } else {
                button
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
            }
        }
        .accessibilityLabel(Text("Settings"))
        .sheet(isPresented: $isOpen) {
            SettingsView()
        }
    }

    var button: some View {
        Button {
            isOpen = true
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 17, weight: .medium))
                .frame(width: 26, height: 26)
        }
    }
}
