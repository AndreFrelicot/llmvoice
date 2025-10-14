//
//  TranscriptionLanguage.swift
//  VoiceTranscription
//
//  Created by André Frélicot on 2025-10-09
//

import Foundation

/// Represents a language available for speech transcription
struct TranscriptionLanguage: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let name: String
    let localeIdentifier: String
    let flag: String

    /// Common languages supported by iOS Speech Recognition
    static let availableLanguages: [TranscriptionLanguage] = [
        // English variants
        TranscriptionLanguage(id: "en_US", name: "English (US)", localeIdentifier: "en_US", flag: "🇺🇸"),
        TranscriptionLanguage(id: "en_GB", name: "English (UK)", localeIdentifier: "en_GB", flag: "🇬🇧"),
        TranscriptionLanguage(id: "en_AU", name: "English (Australia)", localeIdentifier: "en_AU", flag: "🇦🇺"),
        TranscriptionLanguage(id: "en_CA", name: "English (Canada)", localeIdentifier: "en_CA", flag: "🇨🇦"),

        // French
        TranscriptionLanguage(id: "fr_FR", name: "Français (France)", localeIdentifier: "fr_FR", flag: "🇫🇷"),
        TranscriptionLanguage(id: "fr_CA", name: "Français (Canada)", localeIdentifier: "fr_CA", flag: "🇨🇦"),

        // Spanish
        TranscriptionLanguage(id: "es_ES", name: "Español (España)", localeIdentifier: "es_ES", flag: "🇪🇸"),
        TranscriptionLanguage(id: "es_MX", name: "Español (México)", localeIdentifier: "es_MX", flag: "🇲🇽"),

        // German
        TranscriptionLanguage(id: "de_DE", name: "Deutsch", localeIdentifier: "de_DE", flag: "🇩🇪"),

        // Italian
        TranscriptionLanguage(id: "it_IT", name: "Italiano", localeIdentifier: "it_IT", flag: "🇮🇹"),

        // Portuguese
        TranscriptionLanguage(id: "pt_BR", name: "Português (Brasil)", localeIdentifier: "pt_BR", flag: "🇧🇷"),
        TranscriptionLanguage(id: "pt_PT", name: "Português (Portugal)", localeIdentifier: "pt_PT", flag: "🇵🇹"),

        // Chinese
        TranscriptionLanguage(id: "zh_CN", name: "中文 (简体)", localeIdentifier: "zh_CN", flag: "🇨🇳"),
        TranscriptionLanguage(id: "zh_TW", name: "中文 (繁體)", localeIdentifier: "zh_TW", flag: "🇹🇼"),
        TranscriptionLanguage(id: "zh_HK", name: "中文 (香港)", localeIdentifier: "zh_HK", flag: "🇭🇰"),

        // Japanese
        TranscriptionLanguage(id: "ja_JP", name: "日本語", localeIdentifier: "ja_JP", flag: "🇯🇵"),

        // Korean
        TranscriptionLanguage(id: "ko_KR", name: "한국어", localeIdentifier: "ko_KR", flag: "🇰🇷"),

        // Russian
        TranscriptionLanguage(id: "ru_RU", name: "Русский", localeIdentifier: "ru_RU", flag: "🇷🇺"),

        // Arabic
        TranscriptionLanguage(id: "ar_SA", name: "العربية", localeIdentifier: "ar_SA", flag: "🇸🇦"),

        // Dutch
        TranscriptionLanguage(id: "nl_NL", name: "Nederlands", localeIdentifier: "nl_NL", flag: "🇳🇱"),

        // Swedish
        TranscriptionLanguage(id: "sv_SE", name: "Svenska", localeIdentifier: "sv_SE", flag: "🇸🇪"),

        // Polish
        TranscriptionLanguage(id: "pl_PL", name: "Polski", localeIdentifier: "pl_PL", flag: "🇵🇱"),

        // Turkish
        TranscriptionLanguage(id: "tr_TR", name: "Türkçe", localeIdentifier: "tr_TR", flag: "🇹🇷"),

        // Danish
        TranscriptionLanguage(id: "da_DK", name: "Dansk", localeIdentifier: "da_DK", flag: "🇩🇰"),

        // Finnish
        TranscriptionLanguage(id: "fi_FI", name: "Suomi", localeIdentifier: "fi_FI", flag: "🇫🇮"),

        // Norwegian
        TranscriptionLanguage(id: "nb_NO", name: "Norsk", localeIdentifier: "nb_NO", flag: "🇳🇴"),

        // Thai
        TranscriptionLanguage(id: "th_TH", name: "ไทย", localeIdentifier: "th_TH", flag: "🇹🇭"),

        // Indonesian
        TranscriptionLanguage(id: "id_ID", name: "Bahasa Indonesia", localeIdentifier: "id_ID", flag: "🇮🇩"),

        // Vietnamese
        TranscriptionLanguage(id: "vi_VN", name: "Tiếng Việt", localeIdentifier: "vi_VN", flag: "🇻🇳"),
    ]

    /// Default language (English US)
    static let `default` = availableLanguages[0]

    /// Get device's preferred language if available, otherwise return default
    static var devicePreferred: TranscriptionLanguage {
        let deviceLocale = Locale.current.identifier
        return availableLanguages.first { $0.localeIdentifier == deviceLocale } ?? .default
    }
}
