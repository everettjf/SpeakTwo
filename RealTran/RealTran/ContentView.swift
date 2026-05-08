import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Translate", systemImage: "waveform")
                }

            ArchiveView()
                .tabItem {
                    Label("Archive", systemImage: "tray.full")
                }
        }
    }
}

#Preview {
    ContentView()
        .environment(AppSettings())
        .environment(SessionStore())
        .environment(TranslationCoordinator(settings: AppSettings(), store: SessionStore()))
}
