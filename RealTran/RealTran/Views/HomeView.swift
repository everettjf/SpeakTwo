import SwiftUI

struct HomeView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(TranslationCoordinator.self) private var coordinator

    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Top panel — rotated 180° for the person sitting opposite.
                TranscriptPanel(
                    title: settings.secondaryLanguage.nativeName,
                    languageCode: coordinator.secondaryLanguageCode,
                    text: coordinator.secondaryTranscript,
                    accent: .blue,
                    isRunning: coordinator.status == .running
                )
                .rotationEffect(.degrees(180))
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                // Center control bar.
                controlBar
                    .padding(.vertical, 12)
                    .background(.thinMaterial)

                Divider()

                // Bottom panel — for the user holding the phone.
                TranscriptPanel(
                    title: settings.primaryLanguage.nativeName,
                    languageCode: coordinator.primaryLanguageCode,
                    text: coordinator.primaryTranscript,
                    accent: .green,
                    isRunning: coordinator.status == .running
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("RealTran")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                NavigationStack {
                    SettingsView()
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") { showingSettings = false }
                            }
                        }
                }
            }
            .alert("Translation error",
                   isPresented: errorBinding,
                   actions: {
                       Button("OK", role: .cancel) {}
                   },
                   message: {
                       if case let .error(msg) = coordinator.status {
                           Text(msg)
                       }
                   })
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: {
                if case .error = coordinator.status { return true }
                return false
            },
            set: { _ in /* dismissed by user */ }
        )
    }

    @ViewBuilder
    private var controlBar: some View {
        HStack(spacing: 16) {
            statusDot
            Spacer()
            actionButton
            Spacer()
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal)
    }

    private var statusDot: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 12, height: 12)
            .frame(width: 80, alignment: .leading)
            .padding(.leading)
    }

    private var statusColor: Color {
        switch coordinator.status {
        case .idle: return .gray
        case .starting, .stopping: return .yellow
        case .running: return .red
        case .error: return .orange
        }
    }

    private var statusText: String {
        switch coordinator.status {
        case .idle: return "Idle"
        case .starting: return "Starting…"
        case .running: return "Live"
        case .stopping: return "Stopping…"
        case .error: return "Error"
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch coordinator.status {
        case .running, .stopping:
            Button {
                coordinator.stop()
            } label: {
                Label("Stop", systemImage: "stop.circle.fill")
                    .font(.title3.weight(.semibold))
                    .fixedSize()
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(.red, in: .capsule)
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(coordinator.status == .stopping)

        case .idle, .starting, .error:
            Button {
                Task { await coordinator.start() }
            } label: {
                Label("Start", systemImage: "mic.circle.fill")
                    .font(.title3.weight(.semibold))
                    .fixedSize()
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(settings.hasAPIKey ? .green : .gray, in: .capsule)
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(!settings.hasAPIKey || coordinator.status == .starting)
        }
    }
}
