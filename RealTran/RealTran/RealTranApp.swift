import SwiftUI

@main
struct RealTranApp: App {
    @State private var settings = AppSettings()
    @State private var store = SessionStore()
    @State private var coordinator: TranslationCoordinator

    init() {
        let s = AppSettings()
        let store = SessionStore()
        _settings = State(initialValue: s)
        _store = State(initialValue: store)
        _coordinator = State(initialValue: TranslationCoordinator(settings: s, store: store))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(settings)
                .environment(store)
                .environment(coordinator)
        }
    }
}
