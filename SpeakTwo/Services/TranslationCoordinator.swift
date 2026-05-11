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

    // Chat-turn streaming state. `openTurn` is the input-receiving slot;
    // `drainingTurn` is a turn whose input has just been closed but whose
    // translation may still be streaming. Holding the previous turn in a
    // draining slot prevents late translation deltas from leaking into the
    // next turn — the OpenAI translations endpoint emits no item_id we
    // could use to demux, so we route by temporal order.
    private(set) var openTurn: ChatTurn?
    private(set) var drainingTurn: ChatTurn?
    private var openTurnLastInputAt: Date = .distantPast
    private var openTurnTranslatedFromPanel: Panel?
    private var drainingTurnTranslatedFromPanel: Panel?
    private var drainingTurnLastOutputAt: Date = .distantPast

    /// If draining's output has been quiet longer than this, the next output
    /// delta likely belongs to the new openTurn — promote draining first.
    private static let drainingContinuityWindow: TimeInterval = 0.5

    init(settings: AppSettings, store: SessionStore, usage: UsageTracker) {
        self.settings = settings
        self.store = store
        self.usage = usage
    }

    // MARK: - Public

    func dismissError() {
        if case .error = status { status = .idle }
    }

    /// True when there is anything visible in the home view (an in-flight or
    /// completed turn, or accumulated transcript text). Used to decide whether
    /// the "new conversation" toolbar action should be enabled.
    var hasContent: Bool {
        !chatTurns.isEmpty
            || openTurn != nil
            || drainingTurn != nil
            || !primaryLines.isEmpty
            || !secondaryLines.isEmpty
            || !primaryTranscript.isEmpty
            || !secondaryTranscript.isEmpty
    }

    /// Stop any running session (which saves it to the archive), then clear
    /// the in-memory display so the home view is ready for a fresh chat.
    /// No-op when there is nothing on screen to avoid empty archive entries.
    func newConversation() {
        guard hasContent else { return }

        if status == .running || status == .starting {
            stop()
        }

        chatTurns = []
        openTurn = nil
        drainingTurn = nil
        primaryTranscript = ""
        secondaryTranscript = ""
        lastInputTranscript = ""
        primaryLines = []
        secondaryLines = []
        inputLines = []
        openTurnTranslatedFromPanel = nil
        drainingTurnTranslatedFromPanel = nil
        drainingTurnLastOutputAt = .distantPast
        openTurnLastInputAt = .distantPast
    }

    func start() async {
        // A previous error should not block restarting.
        if case .error = status { status = .idle }
        guard status != .running, status != .starting else { return }

        guard !settings.apiKey.isEmpty else {
            status = .error("Add your OpenAI API key in Settings.")
            diagLog(.error, tag: "Coord", "Start blocked: no API key")
            return
        }

        diagLog(.info, tag: "Coord", "Start requested: primary=\(settings.primaryLanguageCode), secondary=\(settings.secondaryLanguageCode), mic=\(settings.micScenario.rawValue), autoLevel=\(settings.autoLevel.rawValue)")
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
        drainingTurn = nil
        openTurnTranslatedFromPanel = nil
        drainingTurnTranslatedFromPanel = nil
        drainingTurnLastOutputAt = .distantPast
        sessionStartedAt = Date()
        primaryLanguageCode = settings.primaryLanguageCode
        secondaryLanguageCode = settings.secondaryLanguageCode

        let noiseReduction: RealtimeTranslator.NoiseReduction
        switch settings.micScenario {
        case .closeSingle: noiseReduction = .nearField
        case .desktopTwo: noiseReduction = .farField
        }

        // Build translators with @Sendable callbacks that hop to MainActor.
        let primary = RealtimeTranslator(
            apiKey: settings.apiKey,
            targetLanguageCode: primaryLanguageCode,
            noiseReduction: noiseReduction
        ) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handle(event: event, panel: .primary)
            }
        }

        let secondary = RealtimeTranslator(
            apiKey: settings.apiKey,
            targetLanguageCode: secondaryLanguageCode,
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
            diagLog(.info, tag: "Coord", "Audio started, status=running")
        } catch {
            diagLog(.error, tag: "Audio", "Start failed: \(error.localizedDescription)")
            status = .error(error.localizedDescription)
            tearDownConnections()
        }
    }

    func stop() {
        guard status == .running || status == .starting else { return }
        diagLog(.info, tag: "Coord", "Stop requested")
        status = .stopping

        audio.stop()
        tearDownConnections()

        // Finalize any pending turns in chronological order: draining first
        // (its input was already closed earlier), then the still-open turn.
        if let turn = drainingTurn {
            chatTurns.append(turn)
            drainingTurn = nil
            drainingTurnTranslatedFromPanel = nil
        }
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
                diagLog(.error, tag: "Coord", "Translator \(panel) failed: \(msg)")
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
            diagLog(.error, tag: "Coord", "Translator \(panel) error: \(msg)")
            status = .error(msg)
        }
    }

    // MARK: - Chat turn building

    private func updateChatTurnFromInput(delta: String) {
        let now = Date()
        // Start a new turn after a silence gap. We deliberately do NOT split
        // on sentence terminators alone — continuous speech (e.g. a person
        // narrating a video) emits "…sentence one. sentence two…" without a
        // real pause, and per-sentence splitting fragments the UI into a
        // rapid-fire scroll of short bubbles.
        if openTurn == nil || shouldFinalizeTurn(now: now) {
            if let closing = openTurn {
                // Move the closed input turn into draining so its still-arriving
                // output deltas keep flowing into it instead of leaking into the
                // new openTurn. Only one draining slot exists — if a previous
                // draining turn is still here, promote it now (its output is
                // unlikely to keep coming after this much elapsed time).
                if let oldDraining = drainingTurn {
                    chatTurns.append(oldDraining)
                }
                drainingTurn = closing
                drainingTurnTranslatedFromPanel = openTurnTranslatedFromPanel
                drainingTurnLastOutputAt = now
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
        let now = Date()

        // Late deltas for the previous (draining) turn arrive here. Route them
        // to draining as long as its output stream is still active. Once the
        // gap exceeds drainingContinuityWindow we assume the previous turn's
        // translation is done — promote draining and let this delta fall
        // through to openTurn.
        if drainingTurn != nil, drainingTurnTranslatedFromPanel == panel {
            let stillStreaming = now.timeIntervalSince(drainingTurnLastOutputAt) < Self.drainingContinuityWindow
            if stillStreaming {
                drainingTurn?.translatedText += delta
                drainingTurnLastOutputAt = now
                return
            }
            // Output paused long enough — assume draining is done and promote.
            chatTurns.append(drainingTurn!)
            drainingTurn = nil
            drainingTurnTranslatedFromPanel = nil
            drainingTurnLastOutputAt = .distantPast
        }

        // Only route to openTurn once language detection has assigned a panel.
        guard openTurn != nil, let routePanel = openTurnTranslatedFromPanel,
              routePanel == panel else { return }
        openTurn?.translatedText += delta
    }

    private func shouldFinalizeTurn(now: Date) -> Bool {
        guard openTurn != nil else { return false }
        // Pause-only split. Threshold is generous enough that a speaker
        // pausing to breathe between sentences stays inside one turn,
        // but a real speaker change still gets its own row.
        return now.timeIntervalSince(openTurnLastInputAt) > 2.5
    }

    private func detectLanguage(_ text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue
    }

    /// Append a delta to a per-panel buffer, grouping deltas into "lines" so the
    /// archive stays human-readable. A new line starts after a quiet gap;
    /// punctuation alone doesn't split, matching the chat-turn behavior.
    private func appendDelta(_ delta: String,
                             to lines: inout [TranscriptLine],
                             languageCode: String,
                             kind: TranscriptLine.Kind) {
        let now = Date()
        if var last = lines.last,
           now.timeIntervalSince(last.timestamp) < 2.5 {
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
