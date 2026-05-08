import Foundation
import Observation

/// Orchestrates the live translation pipeline:
///   - One `AudioCaptureService` reading the mic at 24 kHz PCM16.
///   - Two `RealtimeTranslator` WebSockets, one targeting each language.
///   - Routes deltas into two on-screen transcripts and persists to a session
///     when the user stops.
@Observable
@MainActor
final class TranslationCoordinator {

    enum Status: Sendable, Equatable {
        case idle
        case starting
        case running
        case stopping
        case error(String)
    }

    private(set) var status: Status = .idle

    /// Streaming text for the panel showing translations *into* primary language.
    /// The user reading this panel sees what the other speaker said in their own language.
    private(set) var primaryTranscript: String = ""
    /// Streaming text for the panel showing translations into the secondary language.
    private(set) var secondaryTranscript: String = ""

    /// Last detected source-language transcript (auto-detected by Whisper).
    private(set) var lastInputTranscript: String = ""

    private(set) var primaryLanguageCode: String = "en"
    private(set) var secondaryLanguageCode: String = "zh"

    private let settings: AppSettings
    private let store: SessionStore

    private let audio = AudioCaptureService()
    private var primaryTranslator: RealtimeTranslator?
    private var secondaryTranslator: RealtimeTranslator?

    private var sessionStartedAt: Date?
    private var primaryLines: [TranscriptLine] = []
    private var secondaryLines: [TranscriptLine] = []
    private var inputLines: [TranscriptLine] = []

    init(settings: AppSettings, store: SessionStore) {
        self.settings = settings
        self.store = store
    }

    // MARK: - Public

    func start() async {
        guard status != .running, status != .starting else { return }

        guard !settings.apiKey.isEmpty else {
            status = .error("Add your OpenAI API key in Settings.")
            return
        }

        status = .starting

        // Reset state for a fresh chat.
        primaryTranscript = ""
        secondaryTranscript = ""
        lastInputTranscript = ""
        primaryLines = []
        secondaryLines = []
        inputLines = []
        sessionStartedAt = Date()
        primaryLanguageCode = settings.primaryLanguageCode
        secondaryLanguageCode = settings.secondaryLanguageCode

        // Build translators with @Sendable callbacks that hop to MainActor.
        let primary = RealtimeTranslator(
            apiKey: settings.apiKey,
            targetLanguageCode: primaryLanguageCode
        ) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handle(event: event, panel: .primary)
            }
        }

        let secondary = RealtimeTranslator(
            apiKey: settings.apiKey,
            targetLanguageCode: secondaryLanguageCode
        ) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handle(event: event, panel: .secondary)
            }
        }

        primaryTranslator = primary
        secondaryTranslator = secondary

        primary.connect()
        secondary.connect()

        // Mic chunks fan out to both WebSockets.
        audio.onChunk = { [weak primary, weak secondary] data in
            primary?.appendAudio(data)
            secondary?.appendAudio(data)
        }

        do {
            try await audio.start()
            status = .running
        } catch {
            status = .error(error.localizedDescription)
            tearDownConnections()
        }
    }

    func stop() {
        guard status == .running || status == .starting else { return }
        status = .stopping

        audio.stop()
        tearDownConnections()

        // Persist the session if there is anything to save.
        if let startedAt = sessionStartedAt,
           !primaryLines.isEmpty || !secondaryLines.isEmpty || !inputLines.isEmpty {
            // Combine input lines into the panel matching their detected language is
            // hard without per-delta language metadata; for MVP we keep panels as
            // pure target-language transcripts and discard the duplicated input lines.
            let session = ChatSession(
                startedAt: startedAt,
                endedAt: Date(),
                primaryLanguageCode: primaryLanguageCode,
                secondaryLanguageCode: secondaryLanguageCode,
                primaryLines: primaryLines,
                secondaryLines: secondaryLines
            )
            store.save(session)
        }

        sessionStartedAt = nil
        status = .idle
    }

    // MARK: - Private

    private enum Panel { case primary, secondary }

    private func tearDownConnections() {
        audio.onChunk = nil
        primaryTranslator?.close()
        secondaryTranslator?.close()
        primaryTranslator = nil
        secondaryTranslator = nil
    }

    private func handle(event: RealtimeTranslator.Event, panel: Panel) {
        switch event {
        case .state(let s):
            switch s {
            case .failed(let msg):
                status = .error(msg)
            default: break
            }
        case .inputDelta(let delta):
            // Both translators emit input transcripts; we use only the primary's
            // copy to avoid duplicate lines.
            guard panel == .primary else { return }
            lastInputTranscript += delta
            appendDelta(delta, to: &inputLines, languageCode: "auto", kind: .input)
        case .outputDelta(let delta):
            switch panel {
            case .primary:
                primaryTranscript += delta
                appendDelta(delta, to: &primaryLines, languageCode: primaryLanguageCode, kind: .output)
            case .secondary:
                secondaryTranscript += delta
                appendDelta(delta, to: &secondaryLines, languageCode: secondaryLanguageCode, kind: .output)
            }
        case .error(let msg):
            status = .error(msg)
        }
    }

    /// Append a delta to a per-panel buffer, grouping deltas into "lines" so the
    /// archive stays human-readable. We start a new line if the previous line ends
    /// with sentence-ending punctuation or if more than 1.5 seconds passed.
    private func appendDelta(_ delta: String,
                             to lines: inout [TranscriptLine],
                             languageCode: String,
                             kind: TranscriptLine.Kind) {
        let now = Date()
        if var last = lines.last,
           now.timeIntervalSince(last.timestamp) < 1.5,
           !last.text.hasSuffix(".") && !last.text.hasSuffix("?") &&
            !last.text.hasSuffix("!") && !last.text.hasSuffix("。") &&
            !last.text.hasSuffix("？") && !last.text.hasSuffix("！") {
            last.text += delta
            last.timestamp = now
            lines[lines.count - 1] = last
        } else {
            lines.append(TranscriptLine(
                timestamp: now,
                languageCode: languageCode,
                text: delta,
                kind: kind
            ))
        }
    }
}
