import SwiftUI

@main
struct DishPeekApp: App {
    @State var state = AppState()

    init() {
        Backend.configure()
        // Navigation bar titles in SF Pro Rounded too.
        let base = UIFont.systemFont(ofSize: 17, weight: .semibold)
        if let rounded = base.fontDescriptor.withDesign(.rounded) {
            UINavigationBar.appearance().titleTextAttributes = [.font: UIFont(descriptor: rounded, size: 17)]
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(state)
                .fontDesign(.rounded)
                .preferredColorScheme(.light)
        }
    }
}

struct RootView: View {
    @Environment(AppState.self) var state

    var body: some View {
        @Bindable var state = state

        NavigationStack(path: $state.path) {
            ScanView()
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .menu:
                        MenuScreen()
                    case .detail(let id):
                        if let dish = state.dish(id) {
                            DishDetailView(dish: dish)
                        }
                    case .order:
                        OrderView()
                    }
                }
        }
        // Load the voice for the menu's language early, so Play aloud starts right away.
        .task(id: state.menu.sourceLanguage) {
            Speaker.shared.warmUp(state.menu.sourceLanguage)
        }
        // A success tap whenever a dish lands in the order.
        .sensoryFeedback(.success, trigger: state.order.count) { old, new in new > old }
        // The first screen: food choices are required before anything else.
        .fullScreenCover(isPresented: Binding(get: { !state.hasSetPreferences }, set: { _ in })) {
            OnboardingView()
        }
        #if DEBUG
        // Testing only: launch with -scanPhoto <file> to read that menu photo straight away,
        // and -translated YES to open it already translated.
        .task {
            let defaults = UserDefaults.standard
            guard let file = defaults.string(forKey: "scanPhoto"), let image = UIImage(contentsOfFile: file) else { return }
            await state.scanPhoto(image)
            guard state.scan == .done else { return }
            state.scan = .idle
            state.photoTranslated = defaults.bool(forKey: "translated")
            state.path = [.menu]
        }
        #endif
    }
}
