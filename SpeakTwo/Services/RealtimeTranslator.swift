import Foundation

/// Single WebSocket connection to gpt-realtime-translate, configured for one
/// target output language. Auto-detects the source language from the audio
/// stream and emits transcript deltas (input = source-lang, output = target-lang).
nonisolated final class RealtimeTranslator: @unchecked Sendable {

    enum State: Sendable {
        case idle
        case connecting
        case ready
        case closed
        case failed(String)
    }

    enum Event: Sendable {
        /// Connection state changes.
        case state(State)
        /// Source-language transcript fragment of what the user just said.
        case inputDelta(String)
        /// Target-language translated transcript fragment.
        case outputDelta(String)
        /// Server reported an error.
        case error(String)
    }

    /// Server-side voice activity detection settings. Maps to the
    /// `turn_detection` block in the realtime `session.update` payload.
    struct TurnDetection: Sendable {
        enum Kind: Sendable { case serverVAD, semanticVAD }
        var kind: Kind
        /// Only used when `kind == .serverVAD`.
        var silenceDurationMs: Int

        static let fast = TurnDetection(kind: .serverVAD, silenceDurationMs: 200)
        static let standard = TurnDetection(kind: .serverVAD, silenceDurationMs: 400)
        static let smart = TurnDetection(kind: .semanticVAD, silenceDurationMs: 0)
    }

    /// Server-side noise reduction profile.
    enum NoiseReduction: String, Sendable {
        case nearField = "near_field"
        case farField = "far_field"
    }

    private let apiKey: String
    private let targetLanguageCode: String
    private let turnDetection: TurnDetection
    private let noiseReduction: NoiseReduction
    private let onEvent: @Sendable (Event) -> Void

    private let session: URLSession
    private var task: URLSessionWebSocketTask?
    private var receiveLoop: Task<Void, Never>?
    private var sendQueue = DispatchQueue(label: "SpeakTwo.WSSend")

    init(apiKey: String,
         targetLanguageCode: String,
         turnDetection: TurnDetection = .standard,
         noiseReduction: NoiseReduction = .farField,
         onEvent: @escaping @Sendable (Event) -> Void) {
        self.apiKey = apiKey
        self.targetLanguageCode = targetLanguageCode
        self.turnDetection = turnDetection
        self.noiseReduction = noiseReduction
        self.onEvent = onEvent
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 60
        cfg.timeoutIntervalForResource = 60 * 60
        self.session = URLSession(configuration: cfg)
    }

    nonisolated func connect() {
        onEvent(.state(.connecting))

        guard let url = URL(string: "wss://api.openai.com/v1/realtime/translations?model=gpt-realtime-translate") else {
            onEvent(.state(.failed("Invalid URL")))
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let task = session.webSocketTask(with: request)
        self.task = task
        task.resume()

        // Send initial session.update.
        var turnDetectionPayload: [String: Any] = [:]
        switch turnDetection.kind {
        case .serverVAD:
            turnDetectionPayload = [
                "type": "server_vad",
                "silence_duration_ms": turnDetection.silenceDurationMs,
            ]
        case .semanticVAD:
            turnDetectionPayload = ["type": "semantic_vad"]
        }

        let sessionUpdate: [String: Any] = [
            "type": "session.update",
            "session": [
                "audio": [
                    "input": [
                        "transcription": ["model": "gpt-realtime-whisper"],
                        "noise_reduction": ["type": noiseReduction.rawValue],
                        "turn_detection": turnDetectionPayload,
                    ],
                    "output": [
                        "language": targetLanguageCode
                    ],
                ],
            ],
        ]
        send(json: sessionUpdate)

        startReceiveLoop()
    }

    nonisolated func close() {
        receiveLoop?.cancel()
        receiveLoop = nil
        // Best-effort: send session.close, then close the socket.
        send(json: ["type": "session.close"])
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        onEvent(.state(.closed))
    }

    /// Send a PCM16 24kHz mono audio chunk.
    nonisolated func appendAudio(_ pcm16Data: Data) {
        let b64 = pcm16Data.base64EncodedString()
        send(json: [
            "type": "session.input_audio_buffer.append",
            "audio": b64,
        ])
    }

    // MARK: - Internals

    nonisolated private func send(json: [String: Any]) {
        guard let task else { return }
        guard let data = try? JSONSerialization.data(withJSONObject: json) else { return }
        guard let str = String(data: data, encoding: .utf8) else { return }
        sendQueue.async {
            task.send(.string(str)) { [weak self] error in
                guard let error else { return }
                // Suppress URL-cancelled errors from intentional close().
                if Self.isCancellationError(error) { return }
                self?.onEvent(.error("Send failed: \(error.localizedDescription)"))
            }
        }
    }

    nonisolated private static func isCancellationError(_ error: Error) -> Bool {
        if let urlErr = error as? URLError, urlErr.code == .cancelled { return true }
        let ns = error as NSError
        return ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled
    }

    nonisolated private func startReceiveLoop() {
        receiveLoop?.cancel()
        receiveLoop = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                guard let task = self.task else { break }
                do {
                    let msg = try await task.receive()
                    self.handle(message: msg)
                } catch {
                    if !Task.isCancelled, !Self.isCancellationError(error) {
                        self.onEvent(.state(.failed(error.localizedDescription)))
                    }
                    break
                }
            }
        }
    }

    nonisolated private func handle(message: URLSessionWebSocketTask.Message) {
        let text: String
        switch message {
        case .string(let s): text = s
        case .data(let d): text = String(data: d, encoding: .utf8) ?? ""
        @unknown default: return
        }
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String else { return }

        switch type {
        case "session.created", "session.updated":
            onEvent(.state(.ready))
        case "session.closed":
            onEvent(.state(.closed))
        case "session.input_transcript.delta":
            if let delta = obj["delta"] as? String, !delta.isEmpty {
                onEvent(.inputDelta(delta))
            }
        case "session.output_transcript.delta":
            if let delta = obj["delta"] as? String, !delta.isEmpty {
                onEvent(.outputDelta(delta))
            }
        case "session.output_audio.delta":
            // Ignored for MVP — text only.
            break
        case "error":
            let err = obj["error"] as? [String: Any]
            let msg = err?["message"] as? String ?? "Unknown error"
            onEvent(.error(msg))
        default:
            break
        }
    }
}
