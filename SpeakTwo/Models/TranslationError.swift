import Foundation

/// Turns a raw error string (from the OpenAI realtime API or the local audio
/// pipeline) into a user-facing title, plain-language explanation, and an
/// optional recovery action shown in the home-screen alert.
struct TranslationError: Equatable {

    enum Recovery: Equatable {
        case none
        case openSettings
        case openURL(URL)
    }

    let title: String
    let message: String
    let recovery: Recovery
    let recoveryTitle: String?

    init(raw: String) {
        let text = raw.lowercased()

        if text.contains("quota") || text.contains("billing") || text.contains("insufficient_quota") {
            title = "Out of OpenAI credit"
            message = "Your OpenAI account has run out of quota. Add credit or upgrade your plan in the OpenAI billing page, then tap Start to try again."
            recovery = .openURL(URL(string: "https://platform.openai.com/account/billing")!)
            recoveryTitle = "Open billing"

        } else if text.contains("api key") || text.contains("apikey")
                    || text.contains("invalid_api_key") || text.contains("incorrect api key")
                    || text.contains("unauthorized") || text.contains("authentication")
                    || text.contains("401") {
            title = "Check your API key"
            message = "SpeakTwo couldn't sign in to OpenAI. Open Settings and make sure your API key is entered correctly and is still active."
            recovery = .openSettings
            recoveryTitle = "Open Settings"

        } else if text.contains("rate limit") || text.contains("rate_limit") || text.contains("429") {
            title = "Too many requests"
            message = "OpenAI is rate-limiting your account right now. Wait a few seconds, then tap Start to try again."
            recovery = .none
            recoveryTitle = nil

        } else if text.contains("socket is not connected") || text.contains("send failed")
                    || text.contains("receive failed") || text.contains("network")
                    || text.contains("connection") || text.contains("offline")
                    || text.contains("timed out") || text.contains("internet") {
            title = "Connection lost"
            message = "The connection to the translation service dropped. Check your internet connection, then tap Start to reconnect."
            recovery = .none
            recoveryTitle = nil

        } else if text.contains("microphone") || text.contains("audio") || text.contains("permission") {
            title = "Microphone unavailable"
            message = "SpeakTwo couldn't start the microphone. Check that microphone access is allowed in your device Settings, then tap Start to try again."
            recovery = .none
            recoveryTitle = nil

        } else {
            title = "Translation error"
            message = raw
            recovery = .none
            recoveryTitle = nil
        }
    }
}
