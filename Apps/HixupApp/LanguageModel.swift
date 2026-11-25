import HixupCore
import Observation

/// Sprache der Oberflaeche. Wird in `settings.json` gespeichert, damit auch der Agent sie uebernimmt;
/// ein Wechsel gilt sofort ohne Neustart.
@MainActor @Observable
final class LanguageModel {
    var language: AppLanguage {
        didSet {
            L10n.setLanguage(language)
            var settings = AgentSettings.load(from: HixupPaths.settingsURL)
            settings.language = language
            try? settings.save(to: HixupPaths.settingsURL)
        }
    }

    init() {
        let stored = AgentSettings.load(from: HixupPaths.settingsURL).language
        language = stored
        L10n.setLanguage(stored)
    }
}
