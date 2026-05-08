import SwiftUI

/// Side-by-side chat layout: phone lays flat between two people, both reading
/// the same screen. Each utterance becomes a card with the source on top and
/// the translation below.
struct ChatView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(TranslationCoordinator.self) private var coordinator

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if coordinator.chatTurns.isEmpty && coordinator.openTurn == nil {
                        ContentUnavailableView(
                            placeholderTitle,
                            systemImage: "bubble.left.and.bubble.right",
                            description: Text(placeholderDescription)
                        )
                        .padding(.top, 60)
                    } else {
                        ForEach(coordinator.chatTurns) { turn in
                            ChatTurnBubble(
                                turn: turn,
                                primaryLanguageCode: coordinator.primaryLanguageCode,
                                secondaryLanguageCode: coordinator.secondaryLanguageCode
                            )
                            .id(turn.id)
                        }
                        if let openTurn = coordinator.openTurn {
                            ChatTurnBubble(
                                turn: openTurn,
                                primaryLanguageCode: coordinator.primaryLanguageCode,
                                secondaryLanguageCode: coordinator.secondaryLanguageCode,
                                isLive: true
                            )
                            .id("open")
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .onChange(of: coordinator.chatTurns.count) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: coordinator.openTurn?.sourceText) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: coordinator.openTurn?.translatedText) { _, _ in
                scrollToBottom(proxy)
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.15)) {
            if coordinator.openTurn != nil {
                proxy.scrollTo("open", anchor: .bottom)
            } else if let last = coordinator.chatTurns.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    private var placeholderTitle: String {
        coordinator.status == .running ? "Listening…" : "Side-by-side chat"
    }

    private var placeholderDescription: String {
        coordinator.status == .running
            ? "Speak in either language and the translation will appear here."
            : "Tap Start to begin. Each utterance shows what was said and its translation."
    }
}

private struct ChatTurnBubble: View {
    let turn: ChatTurn
    let primaryLanguageCode: String
    let secondaryLanguageCode: String
    var isLive: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if alignsRight { Spacer(minLength: 40) }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(sourceTag)
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(accent.opacity(0.18), in: .capsule)
                        .foregroundStyle(accent)
                    Text(turn.startedAt.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    if isLive {
                        Circle().fill(.red).frame(width: 5, height: 5)
                    }
                }

                Text(turn.sourceText.isEmpty ? "…" : turn.sourceText)
                    .font(.body)
                    .foregroundStyle(.primary)

                if !turn.translatedText.isEmpty || isLive {
                    Divider().padding(.vertical, 2)
                    HStack(spacing: 6) {
                        Text(translationTag)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
                    Text(turn.translatedText.isEmpty ? "…" : turn.translatedText)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(accent.opacity(0.10), in: .rect(cornerRadius: 14))
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(accent)
                    .frame(width: 3)
                    .clipShape(.rect(cornerRadii: .init(topLeading: 14, bottomLeading: 14)))
            }
            .frame(maxWidth: .infinity, alignment: alignsRight ? .trailing : .leading)

            if !alignsRight { Spacer(minLength: 40) }
        }
    }

    private var detectedNormalized: String {
        String(turn.sourceLanguageCode.split(separator: "-").first ?? Substring(turn.sourceLanguageCode))
    }

    private var alignsRight: Bool {
        detectedNormalized == primaryLanguageCode
    }

    private var accent: Color {
        alignsRight ? .green : .blue
    }

    private var sourceTag: String {
        if turn.sourceLanguageCode == "auto" || turn.sourceLanguageCode.isEmpty {
            return "?"
        }
        return detectedNormalized.uppercased()
    }

    private var translationTag: String {
        guard !turn.translatedLanguageCode.isEmpty else { return "" }
        let langName = SupportedLanguages.byCode(turn.translatedLanguageCode)?.nativeName
            ?? turn.translatedLanguageCode.uppercased()
        return "→ \(langName)"
    }
}
