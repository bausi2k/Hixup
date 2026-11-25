import Foundation
import Testing
@testable import HixupCore

@Suite struct LocalizationTests {
    @Test func englishTranslationIsUsedWhenRequested() {
        #expect(L10n.translate("Alles in Ordnung", language: .en) == "All good")
        #expect(L10n.translate("Alles in Ordnung", language: .de) == "Alles in Ordnung")
    }

    @Test func unknownKeysFallBackToTheKey() {
        #expect(L10n.translate("gibt es nicht", language: .en) == "gibt es nicht")
    }

    @Test func argumentsAreSubstituted() {
        #expect(L10n.translate("%@ und %d weitere", language: .en, args: ["CPU", 2]) == "CPU and 2 more")
        #expect(L10n.translate("%@ und %d weitere", language: .de, args: ["CPU", 2]) == "CPU und 2 weitere")
    }

    @Test func systemLanguageFollowsPreferredLanguagesWithEnglishFallback() {
        #expect(L10n.resolved(.system, preferred: ["de-AT", "en"]) == .de)
        #expect(L10n.resolved(.system, preferred: ["en-GB"]) == .en)
        #expect(L10n.resolved(.system, preferred: ["fr-FR"]) == .en)
        #expect(L10n.resolved(.de, preferred: ["en"]) == .de)
        #expect(L10n.resolved(.en, preferred: ["de"]) == .en)
    }

    @Test func everyGermanKeyHasAnEnglishTranslation() throws {
        let german = try keys(of: "de")
        let english = try keys(of: "en")
        #expect(!german.isEmpty)
        #expect(german == english)
    }

    @Test func languageSettingSurvivesSavingAndOldFilesDefaultToSystem() throws {
        var settings = AgentSettings.defaults
        settings.language = .en
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(AgentSettings.self, from: data).language == .en)

        let old = try JSONDecoder().decode(AgentSettings.self, from: Data(#"{"sampleInterval":10}"#.utf8))
        #expect(old.language == .system)
    }

    private func keys(of code: String) throws -> Set<String> {
        let url = try #require(L10n.bundle.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: code))
        let table = try #require(NSDictionary(contentsOf: url) as? [String: String])
        return Set(table.keys)
    }
}
