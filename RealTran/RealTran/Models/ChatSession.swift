import Foundation

struct TranscriptLine: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var timestamp: Date
    var languageCode: String
    var text: String
    /// Whether this line is the source (auto-detected) transcription
    /// from the input mic, or a translated output.
    var kind: Kind

    enum Kind: String, Codable, Sendable {
        case input    // recognized speech in detected source language
        case output   // translated output in the configured target language
    }
}

struct ChatSession: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var startedAt: Date
    var endedAt: Date?
    var primaryLanguageCode: String
    var secondaryLanguageCode: String
    /// Transcript lines for primary panel (translations into primaryLanguage,
    /// plus optional input lines).
    var primaryLines: [TranscriptLine]
    /// Transcript lines for secondary panel (translations into secondaryLanguage).
    var secondaryLines: [TranscriptLine]

    var displayTitle: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: startedAt)
    }

    var durationDescription: String {
        guard let endedAt else { return "—" }
        let elapsed = endedAt.timeIntervalSince(startedAt)
        let mins = Int(elapsed) / 60
        let secs = Int(elapsed) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
