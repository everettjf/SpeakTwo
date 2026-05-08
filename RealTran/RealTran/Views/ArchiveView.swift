import SwiftUI

struct ArchiveView: View {
    @Environment(SessionStore.self) private var store

    var body: some View {
        NavigationStack {
            Group {
                if store.sessions.isEmpty {
                    ContentUnavailableView(
                        "No archived sessions",
                        systemImage: "tray",
                        description: Text("Each chat you finish will appear here.")
                    )
                } else {
                    List {
                        ForEach(store.sessions) { session in
                            NavigationLink(value: session) {
                                row(for: session)
                            }
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .navigationTitle("Archive")
            .navigationDestination(for: ChatSession.self) { session in
                SessionDetailView(session: session)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        store.reload()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func row(for session: ChatSession) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.displayTitle)
                .font(.headline)
            HStack(spacing: 8) {
                Text(SupportedLanguages.byCode(session.primaryLanguageCode)?.nativeName ?? session.primaryLanguageCode)
                Text("⇄")
                    .foregroundStyle(.secondary)
                Text(SupportedLanguages.byCode(session.secondaryLanguageCode)?.nativeName ?? session.secondaryLanguageCode)
                Spacer()
                Text(session.durationDescription)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
    }

    private func delete(at offsets: IndexSet) {
        for idx in offsets {
            store.delete(store.sessions[idx])
        }
    }
}
