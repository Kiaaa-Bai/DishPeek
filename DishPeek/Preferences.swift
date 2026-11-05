import SwiftUI

// The food choices: what you avoid (or that you eat everything) and how spicy you like it.
// Used on the first screen and in Settings.
struct PreferencesForm: View {
    @Binding var avoid: Set<Allergen>
    @Binding var eatsEverything: Bool
    @Binding var spice: Spice?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // The quick answer: nothing to avoid. Picking it clears the list, and the reverse.
            Chip(title: String(localized: "I eat everything"), emoji: "🍽️", isOn: eatsEverything) {
                eatsEverything.toggle()
                if eatsEverything {
                    avoid = []
                }
            }

            heading("Allergies")
            FlowLayout {
                ForEach(Allergen.allergies) { avoidChip($0) }
            }

            heading("Diet")
            FlowLayout {
                ForEach(Allergen.diets) { avoidChip($0) }
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

    func avoidChip(_ allergen: Allergen) -> some View {
        Chip(title: allergen.title, emoji: allergen.emoji, isOn: avoid.contains(allergen)) {
            if avoid.contains(allergen) {
                avoid.remove(allergen)
            } else {
                avoid.insert(allergen)
                eatsEverything = false
            }
        }
    }
}

// Spice as five chilies, like a star rating: tap one, or drag across them. More chilies, hotter.
// Dragging to the far left (or tapping the only lit chili) means not spicy. The level's name shows beside it.
struct ChiliScale: View {
    @Binding var spice: Spice?

    let cell: CGFloat = 36
    var level: Int { spice?.chilies ?? 0 }

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 0) {
                ForEach(1...5, id: \.self) { count in
                    Text(verbatim: "🌶️")
                        .font(.system(size: 22))
                        .grayscale(count <= level ? 0 : 1)
                        .opacity(count <= level ? 1 : 0.25)
                        .scaleEffect(count == level ? 1.12 : 1)
                        .frame(width: cell, height: 44)
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
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(spice == nil ? Color.textSecondary : Color.textPrimary)
                .contentTransition(.opacity)
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

// The first screen, before anything else: food choices are required,
// so every menu can flag what this person can't eat.
struct OnboardingView: View {
    @Environment(AppState.self) var state
    @State var avoid: Set<Allergen> = []
    @State var eatsEverything = false
    @State var spice: Spice? = nil

    // Both questions answered: something avoided (or "I eat everything"), and a spice level.
    var isDone: Bool { (eatsEverything || !avoid.isEmpty) && spice != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Image("AppMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 13))
                    .padding(.bottom, 20)

                Text("Anything you don't eat?")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                Text("We'll flag those dishes on every menu. You can change this later.")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
                    .padding(.bottom, 20)

                PreferencesForm(avoid: $avoid, eatsEverything: $eatsEverything, spice: $spice)
            }
            .padding(.horizontal, 24)
            .padding(.top, 32)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaBar(edge: .bottom) {
            ActionButton(title: "Continue", fullWidth: true) {
                state.avoid = avoid
                state.spice = spice
                state.hasSetPreferences = true
            }
            .controlSize(.large)
            .disabled(!isDone)
            .animation(.snappy, value: isDone)
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
        }
        .background(Color.canvas)
    }
}

// Settings: change the food choices.
struct SettingsView: View {
    @Environment(AppState.self) var state
    @Environment(\.dismiss) var dismiss
    @State var eatsEverything = false

    var body: some View {
        @Bindable var state = state

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Anything you don't eat?")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                    PreferencesForm(avoid: $state.avoid, eatsEverything: $eatsEverything, spice: $state.spice)

                    Toggle(isOn: $state.redraws) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Redraw the menu with AI")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Color.textPrimary)
                            Text("The photo comes back as if printed in your language. Takes about half a minute.")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                    .tint(Color.action)
                    .padding(.top, 12)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
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
            eatsEverything = state.avoid.isEmpty
        }
        // Clearing every allergen in Settings means they eat everything again.
        .onChange(of: state.avoid) {
            if state.avoid.isEmpty {
                eatsEverything = true
            }
        }
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
