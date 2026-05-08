import Foundation
import NaturalLanguage
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

    /// Chronological chat-mode list. Each turn = one detected utterance plus
    /// the matching translation into the *other* language.
    private(set) var chatTurns: [ChatTurn] = []

    private(set) var primaryLanguageCode: String = "en"
    private(set) var secondaryLanguageCode: String = "zh"

    private let settings: AppSettings
    private let store: SessionStore
    private let usage: UsageTracker

    private let audio = AudioCaptureService()
    private var primaryTranslator: RealtimeTranslator?
    private var secondaryTranslator: RealtimeTranslator?

    private var sessionStartedAt: Date?
    private var primaryLines: [TranscriptLine] = []
    private var secondaryLines: [TranscriptLine] = []
    private var inputLines: [TranscriptLine] = []

    // Chat-turn streaming state. `openTurn` is exposed read-only so views can
    // render the in-progress turn before it is finalized into `chatTurns`.
    private(set) var openTurn: ChatTurn?
    private var openTurnLastInputAt: Date = .distantPast
    private var openTurnTranslatedFromPanel: Panel?

    init(settings: AppSettings, store: SessionStore, usage: UsageTracker) {
        self.settings = settings
        self.store = store
        self.usage = usage
    }

    // MARK: - Public

    func dismissError() {
        if case .error = status { status = .idle }
    }

    func start() async {
        // A previous error should not block restarting.
        if case .error = status { status = .idle }
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
        chatTurns = []
        openTurn = nil
        openTurnTranslatedFromPanel = nil
        sessionStartedAt = Date()
        primaryLanguageCode = settings.primaryLanguageCode
        secondaryLanguageCode = settings.secondaryLanguageCode

        let turnDetection: RealtimeTranslator.TurnDetection
        switch settings.responseSpeed {
        case .fast: turnDetection = .fast
        case .standard: turnDetection = .standard
        case .smart: turnDetection = .smart
        }

        let noiseReduction: RealtimeTranslator.NoiseReduction
        switch settings.micScenario {
        case .closeSingle: noiseReduction = .nearField
        case .desktopTwo: noiseReduction = .farField
        }

        // Build translators with @Sendable callbacks that hop to MainActor.
        let primary = RealtimeTranslator(
            apiKey: settings.apiKey,
            targetLanguageCode: primaryLanguageCode,
            turnDetection: turnDetection,
            noiseReduction: noiseReduction
        ) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handle(event: event, panel: .primary)
            }
        }

        let secondary = RealtimeTranslator(
            apiKey: settings.apiKey,
            targetLanguageCode: secondaryLanguageCode,
            turnDetection: turnDetection,
            noiseReduction: noiseReduction
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

        let captureMode: AudioCaptureService.CaptureMode = (settings.autoLevel == .on) ? .voiceChat : .measurement

        do {
            try await audio.start(mode: captureMode)
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

        // Finalize any open chat turn.
        if let turn = openTurn {
            chatTurns.append(turn)
            openTurn = nil
            openTurnTranslatedFromPanel = nil
        }

        // Record usage for this session, regardless of whether transcripts arrived.
        if let startedAt = sessionStartedAt {
            let elapsed = Date().timeIntervalSince(startedAt)
            usage.recordSession(durationSeconds: elapsed)
        }

        // Persist the session if there is anything to save.
        if let startedAt = sessionStartedAt,
           !primaryLines.isEmpty || !secondaryLines.isEmpty || !inputLines.isEmpty || !chatTurns.isEmpty {
            let session = ChatSession(
                startedAt: startedAt,
                endedAt: Date(),
                primaryLanguageCode: primaryLanguageCode,
                secondaryLanguageCode: secondaryLanguageCode,
                primaryLines: primaryLines,
                secondaryLines: secondaryLines,
                chatTurns: chatTurns
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
            updateChatTurnFromInput(delta: delta)
        case .outputDelta(let delta):
            switch panel {
            case .primary:
                primaryTranscript += delta
                appendDelta(delta, to: &primaryLines, languageCode: primaryLanguageCode, kind: .output)
            case .secondary:
                secondaryTranscript += delta
                appendDelta(delta, to: &secondaryLines, languageCode: secondaryLanguageCode, kind: .output)
            }
            updateChatTurnFromOutput(delta: delta, panel: panel)
        case .error(let msg):
            status = .error(msg)
        }
    }

    // MARK: - Chat turn building

    private func updateChatTurnFromInput(delta: String) {
        let now = Date()
        // Start a new turn after a 1.5s silence gap or after a sentence terminator.
        if openTurn == nil || shouldFinalizeTurn(now: now) {
            if let finished = openTurn {
                chatTurns.append(finished)
            }
            openTurn = ChatTurn(
                startedAt: now,
                sourceLanguageCode: "auto",
                sourceText: delta,
                translatedLanguageCode: "",
                translatedText: ""
            )
            openTurnTranslatedFromPanel = nil
        } else {
            openTurn?.sourceText += delta
        }
        openTurnLastInputAt = now

        // Detect source language once we have a few characters; pick the
        // *other* configured language as the translation target.
        if let turn = openTurn,
           turn.sourceLanguageCode == "auto",
           turn.sourceText.unicodeScalars.count >= 4,
           let detected = detectLanguage(turn.sourceText) {
            openTurn?.sourceLanguageCode = detected
            let normalized = String(detected.split(separator: "-").first ?? Substring(detected))
            if normalized == primaryLanguageCode {
                openTurn?.translatedLanguageCode = secondaryLanguageCode
                openTurnTranslatedFromPanel = .secondary
            } else if normalized == secondaryLanguageCode {
                openTurn?.translatedLanguageCode = primaryLanguageCode
                openTurnTranslatedFromPanel = .primary
            } else {
                // Detected language isn't either configured language; default to
                // routing through the primary panel's translation.
                openTurn?.translatedLanguageCode = primaryLanguageCode
                openTurnTranslatedFromPanel = .primary
            }
        }
    }

    private func updateChatTurnFromOutput(delta: String, panel: Panel) {
        // Only append to the current turn if this delta is the actual translation
        // (not the echo of the same-language session).
        guard openTurn != nil, let routePanel = openTurnTranslatedFromPanel,
              routePanel == panel else { return }
        openTurn?.translatedText += delta
    }

    private func shouldFinalizeTurn(now: Date) -> Bool {
        guard openTurn != nil else { return false }
        if now.timeIntervalSince(openTurnLastInputAt) > 1.5 { return true }
        if let last = openTurn?.sourceText.last,
           ".?!。？！".contains(last) { return true }
        return false
    }

    private func detectLanguage(_ text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue
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
