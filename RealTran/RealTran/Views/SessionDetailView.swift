import SwiftUI

struct SessionDetailView: View {
    let session: ChatSession

    var body: some View {
        List {
            Section {
                LabeledContent("Started", value: session.startedAt.formatted(date: .abbreviated, time: .standard))
                if let ended = session.endedAt {
                    LabeledContent("Ended", value: ended.formatted(date: .abbreviated, time: .standard))
                }
                LabeledContent("Duration", value: session.durationDescription)
                LabeledContent("Languages", value: "\(session.primaryLanguageCode.uppercased()) ⇄ \(session.secondaryLanguageCode.uppercased())")
            } header: {
                Text("Session")
            }

            if let chatTurns = session.chatTurns, !chatTurns.isEmpty {
                Section {
                    ForEach(chatTurns) { turn in
                        chatTurnRow(turn)
                    }
                } header: {
                    Text("Conversation")
                }
            }

            Section {
                if session.primaryLines.isEmpty {
                    Text("No transcript")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(session.primaryLines) { line in
                        transcriptRow(line)
                    }
                }
            } header: {
                Text(SupportedLanguages.byCode(session.primaryLanguageCode)?.nativeName
                     ?? session.primaryLanguageCode)
            }

            Section {
                if session.secondaryLines.isEmpty {
                    Text("No transcript")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(session.secondaryLines) { line in
                        transcriptRow(line)
                    }
                }
            } header: {
                Text(SupportedLanguages.byCode(session.secondaryLanguageCode)?.nativeName
                     ?? session.secondaryLanguageCode)
            }
        }
        .navigationTitle(session.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func chatTurnRow(_ turn: ChatTurn) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(turn.sourceLanguageCode.split(separator: "-").first.map(String.init)?.uppercased()
                     ?? "?")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.blue.opacity(0.15), in: .capsule)
                    .foregroundStyle(.blue)
                Text(turn.startedAt.formatted(date: .omitted, time: .standard))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Text(turn.sourceText)
                .font(.body)
            if !turn.translatedText.isEmpty {
                Text("→ \(turn.translatedText)")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func transcriptRow(_ line: TranscriptLine) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(line.text)
                .font(.body)
            Text(line.timestamp.formatted(date: .omitted, time: .standard))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 2)
    }
}
