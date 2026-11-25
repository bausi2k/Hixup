import Foundation

/// Sprachwahl der Oberflaeche. `system` folgt der bevorzugten Systemsprache.
public enum AppLanguage: String, Codable, CaseIterable, Sendable {
    case system
    case de
    case en
}

/// Einfache, prozessweite Lokalisierung ueber `.strings`-Dateien. Als Schluessel dient der deutsche
/// Text; fehlt eine Uebersetzung, erscheint der Schluessel selbst. App und Agent setzen die Sprache
/// aus denselben Einstellungen, ein Wechsel gilt sofort ohne Neustart.
public enum L10n {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var selection: AppLanguage = .de

    /// Aktuelle Auswahl; `.de` bis die App oder der Agent die Einstellungen anwendet.
    public static var language: AppLanguage {
        lock.withLock { selection }
    }

    public static func setLanguage(_ language: AppLanguage) {
        lock.withLock { selection = language }
    }

    /// Die tatsaechlich genutzte Sprache (`de` oder `en`).
    public static func resolved(
        _ language: AppLanguage? = nil, preferred: [String] = Locale.preferredLanguages
    ) -> AppLanguage {
        switch language ?? self.language {
        case .de: return .de
        case .en: return .en
        case .system:
            for code in preferred {
                if code.hasPrefix("de") { return .de }
                if code.hasPrefix("en") { return .en }
            }
            return .en
        }
    }

    /// Uebersetzt `key` in die aktuelle Sprache; `args` ersetzen `%@`/`%d` im Text.
    public static func tr(_ key: String, _ args: CVarArg...) -> String {
        translate(key, args: args)
    }

    static func translate(_ key: String, language: AppLanguage? = nil, args: [CVarArg] = []) -> String {
        let code = resolved(language).rawValue
        let text = table(for: code)[key] ?? key
        return args.isEmpty ? text : String(format: text, locale: Locale(identifier: code), arguments: args)
    }

    static var bundle: Bundle { Bundle.module }

    nonisolated(unsafe) private static var tables: [String: [String: String]] = [:]

    private static func table(for code: String) -> [String: String] {
        lock.withLock {
            if let cached = tables[code] { return cached }
            let url = bundle.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: code)
            let loaded = url.flatMap { NSDictionary(contentsOf: $0) as? [String: String] } ?? [:]
            tables[code] = loaded
            return loaded
        }
    }
}
