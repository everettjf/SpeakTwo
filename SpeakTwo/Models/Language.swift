import Foundation

struct Language: Identifiable, Hashable, Codable, Sendable {
    let code: String
    let name: String
    let nativeName: String

    var id: String { code }
}

enum SupportedLanguages {
    // The 13 output languages supported by gpt-realtime-translate.
    static let outputs: [Language] = [
        Language(code: "en", name: "English", nativeName: "English"),
        Language(code: "zh", name: "Chinese (Mandarin)", nativeName: "中文"),
        Language(code: "es", name: "Spanish", nativeName: "Español"),
        Language(code: "pt", name: "Portuguese", nativeName: "Português"),
        Language(code: "fr", name: "French", nativeName: "Français"),
        Language(code: "de", name: "German", nativeName: "Deutsch"),
        Language(code: "it", name: "Italian", nativeName: "Italiano"),
        Language(code: "ja", name: "Japanese", nativeName: "日本語"),
        Language(code: "ko", name: "Korean", nativeName: "한국어"),
        Language(code: "ru", name: "Russian", nativeName: "Русский"),
        Language(code: "hi", name: "Hindi", nativeName: "हिन्दी"),
        Language(code: "id", name: "Indonesian", nativeName: "Bahasa Indonesia"),
        Language(code: "vi", name: "Vietnamese", nativeName: "Tiếng Việt"),
    ]

    static func byCode(_ code: String) -> Language? {
        outputs.first { $0.code == code }
    }
}
