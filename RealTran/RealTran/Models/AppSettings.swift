import Foundation
import Observation

enum DisplayMode: String, Codable, Sendable, CaseIterable {
    /// Two panels stacked, top one rotated 180° for the person sitting opposite.
    case faceToFace
    /// Single chronological chat list — both readers sit side by side.
    case chat
}

@Observable
@MainActor
final class AppSettings {
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let primaryLanguage = "primaryLanguage"
        static let secondaryLanguage = "secondaryLanguage"
        static let displayMode = "displayMode"
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
    }

    var primaryLanguage: Language {
        SupportedLanguages.byCode(primaryLanguageCode) ?? SupportedLanguages.outputs[0]
    }

    var secondaryLanguage: Language {
        SupportedLanguages.byCode(secondaryLanguageCode) ?? SupportedLanguages.outputs[1]
    }

    var hasAPIKey: Bool { !apiKey.isEmpty }
}
