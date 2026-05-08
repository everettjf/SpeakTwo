import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings

    @State private var apiKeyDraft: String = ""
    @State private var apiKeyVisible: Bool = false
    @State private var saved = false

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                if apiKeyVisible {
                    TextField("sk-…", text: $apiKeyDraft, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .lineLimit(1...4)
                } else {
                    SecureField("sk-…", text: $apiKeyDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                HStack {
                    Toggle("Show key", isOn: $apiKeyVisible)
                    Spacer()
                    Button(saved ? "Saved" : "Save") {
                        settings.apiKey = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        saved = true
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(1.5))
                            saved = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } header: {
                Text("OpenAI API Key")
            } footer: {
                Text("Stored securely in the iOS Keychain on this device. Required for live translation.")
            }

            Section {
                Picker("Primary (your language)", selection: $settings.primaryLanguageCode) {
                    ForEach(SupportedLanguages.outputs) { lang in
                        Text("\(lang.nativeName) · \(lang.name)").tag(lang.code)
                    }
                }
                Picker("Secondary (the other person)", selection: $settings.secondaryLanguageCode) {
                    ForEach(SupportedLanguages.outputs) { lang in
                        Text("\(lang.nativeName) · \(lang.name)").tag(lang.code)
                    }
                }
            } header: {
                Text("Languages")
            } footer: {
                Text("Two simultaneous translation sessions run — one for each language. The model auto-detects who is speaking which language.")
            }

            Section {
                LabeledContent("Model", value: "gpt-realtime-translate")
                LabeledContent("Sample rate", value: "24 kHz PCM16")
                LabeledContent("Pricing (OpenAI)", value: "$0.034 / min × 2 sessions")
            } header: {
                Text("About")
            }
        }
        .navigationTitle("Settings")
        .onAppear { apiKeyDraft = settings.apiKey }
    }
}
