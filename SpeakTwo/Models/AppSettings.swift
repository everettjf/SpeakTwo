import Foundation
import Observation

enum DisplayMode: String, Codable, Sendable, CaseIterable {
    /// Two panels stacked, top one rotated 180° for the person sitting opposite.
    case faceToFace
    /// Single chronological chat list — both readers sit side by side.
    case chat
}

/// How quickly the server commits an utterance and emits the next turn.
enum ResponseSpeed: String, Codable, Sendable, CaseIterable, Identifiable {
    case fast
    case standard
    case smart

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fast: return "Fast"
        case .standard: return "Standard"
        case .smart: return "Smart"
        }
    }

    var detail: String {
        switch self {
        case .fast: return "Shorter pauses trigger output. Best for fast back-and-forth."
        case .standard: return "Balanced pause threshold."
        case .smart: return "Model decides when a sentence is done. Most natural, slightly slower."
        }
    }
}

/// Where the microphone sits relative to speakers.
enum MicScenario: String, Codable, Sendable, CaseIterable, Identifiable {
    case closeSingle
    case desktopTwo

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .closeSingle: return "Close, single speaker"
        case .desktopTwo: return "Across a table, two speakers"
        }
    }

    var detail: String {
        switch self {
        case .closeSingle: return "Phone held close to one person."
        case .desktopTwo: return "Phone on a table between both people."
        }
    }
}

/// Whether iOS should auto-balance levels between near and far speakers.
enum AutoLevel: String, Codable, Sendable, CaseIterable, Identifiable {
    case off
    case on

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off: return "Off (raw audio)"
        case .on: return "On (balance speakers)"
        }
    }

    var detail: String {
        switch self {
        case .off: return "Highest fidelity. Best when one person speaks at a steady distance."
        case .on: return "Levels out volume between near and far speakers. Recommended for two-person use."
        }
    }
}

@Observable
@MainActor
final class AppSettings {
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let primaryLanguage = "primaryLanguage"
        static let secondaryLanguage = "secondaryLanguage"
        static let displayMode = "displayMode"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let responseSpeed = "responseSpeed"
        static let micScenario = "micScenario"
        static let autoLevel = "autoLevel"
    }

    var primaryLanguageCode: String {
        didSet { defaults.set(primaryLanguageCode, forKey: Keys.primaryLanguage) }
    }

    var secondaryLanguageCode: String {
        didSet { defaults.set(secondaryLanguageCode, forKey: Keys.secondaryLanguage) }
    }

    var displayMode: DisplayMode {
        didSet { defaults.set(displayMode.rawValue, forKey: Keys.displayMode) }
    }

    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding) }
    }

    var responseSpeed: ResponseSpeed {
        didSet { defaults.set(responseSpeed.rawValue, forKey: Keys.responseSpeed) }
    }

    var micScenario: MicScenario {
        didSet { defaults.set(micScenario.rawValue, forKey: Keys.micScenario) }
    }

    var autoLevel: AutoLevel {
        didSet { defaults.set(autoLevel.rawValue, forKey: Keys.autoLevel) }
    }

    var apiKey: String {
        get { KeychainStore.shared.apiKey ?? "" }
        set {
            if newValue.isEmpty {
                KeychainStore.shared.deleteAPIKey()
            } else {
                KeychainStore.shared.apiKey = newValue
            }
        }
    }

    init() {
        self.primaryLanguageCode = defaults.string(forKey: Keys.primaryLanguage) ?? "en"
        self.secondaryLanguageCode = defaults.string(forKey: Keys.secondaryLanguage) ?? "zh"
        let modeRaw = defaults.string(forKey: Keys.displayMode) ?? DisplayMode.faceToFace.rawValue
        self.displayMode = DisplayMode(rawValue: modeRaw) ?? .faceToFace
        self.hasCompletedOnboarding = defaults.bool(forKey: Keys.hasCompletedOnboarding)

        let speedRaw = defaults.string(forKey: Keys.responseSpeed) ?? ResponseSpeed.standard.rawValue
        self.responseSpeed = ResponseSpeed(rawValue: speedRaw) ?? .standard

        let scenarioRaw = defaults.string(forKey: Keys.micScenario) ?? MicScenario.desktopTwo.rawValue
        self.micScenario = MicScenario(rawValue: scenarioRaw) ?? .desktopTwo

        let levelRaw = defaults.string(forKey: Keys.autoLevel) ?? AutoLevel.on.rawValue
        self.autoLevel = AutoLevel(rawValue: levelRaw) ?? .on
    }

    var primaryLanguage: Language {
        SupportedLanguages.byCode(primaryLanguageCode) ?? SupportedLanguages.outputs[0]
    }

    var secondaryLanguage: Language {
        SupportedLanguages.byCode(secondaryLanguageCode) ?? SupportedLanguages.outputs[1]
    }

    var hasAPIKey: Bool { !apiKey.isEmpty }
}
