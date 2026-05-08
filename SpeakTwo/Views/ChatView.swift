import SwiftUI
import UIKit

/// Side-by-side chat layout: phone lays flat between two people, both reading
/// the same screen. Each utterance becomes a card with the source on top and
/// the translation below.
struct ChatView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(TranslationCoordinator.self) private var coordinator
    @Environment(\.horizontalSizeClass) private var hSizeClass

    /// Cap chat column width on iPad / wide layouts so bubbles stay readable
    /// instead of spanning a 1024pt+ screen.
    private var contentMaxWidth: CGFloat {
        hSizeClass == .regular ? 760 : .infinity
    }

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
                        if let drainingTurn = coordinator.drainingTurn {
                            // Input is closed but translation may still be streaming.
                            ChatTurnBubble(
                                turn: drainingTurn,
                                primaryLanguageCode: coordinator.primaryLanguageCode,
                                secondaryLanguageCode: coordinator.secondaryLanguageCode
                            )
                            .id(drainingTurn.id)
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
                .frame(maxWidth: contentMaxWidth)
                .frame(maxWidth: .infinity)
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
            .onChange(of: coordinator.drainingTurn?.translatedText) { _, _ in
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

            bubbleColumn
                .frame(maxWidth: 560, alignment: alignsRight ? .trailing : .leading)

            if !alignsRight { Spacer(minLength: 40) }
        }
    }

    @ViewBuilder
    private var bubbleColumn: some View {
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
                    .foregroundStyle(.primary)
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
        .contextMenu { copyMenu }
    }

    @ViewBuilder
    private var copyMenu: some View {
        if !turn.sourceText.isEmpty {
            Button {
                UIPasteboard.general.string = turn.sourceText
            } label: {
                Label("Copy \(sourceCopyLabel)", systemImage: "doc.on.doc")
            }
        }
        if !turn.translatedText.isEmpty {
            Button {
                UIPasteboard.general.string = turn.translatedText
            } label: {
                Label("Copy \(translatedCopyLabel)", systemImage: "doc.on.doc")
            }
        }
        if !turn.sourceText.isEmpty && !turn.translatedText.isEmpty {
            Divider()
            Button {
                UIPasteboard.general.string = "\(turn.sourceText)\n\n\(turn.translatedText)"
            } label: {
                Label("Copy both", systemImage: "doc.on.doc.fill")
            }
        }
    }

    private func languageDisplayName(forCode code: String) -> String? {
        guard !code.isEmpty, code != "auto" else { return nil }
        let normalized = String(code.split(separator: "-").first ?? Substring(code))
        return SupportedLanguages.byCode(normalized)?.nativeName
            ?? SupportedLanguages.byCode(code)?.nativeName
            ?? normalized.uppercased()
    }

    private var sourceCopyLabel: String {
        languageDisplayName(forCode: turn.sourceLanguageCode) ?? "source"
    }

    private var translatedCopyLabel: String {
        languageDisplayName(forCode: turn.translatedLanguageCode) ?? "translation"
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
