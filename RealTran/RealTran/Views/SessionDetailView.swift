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
