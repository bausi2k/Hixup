import Foundation
import Testing
@testable import HixupCore

@Suite struct AgentSettingsTests {
    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("hixup-settings-\(UUID().uuidString).json")
    }

    @Test func defaultsMatchDocumentedValues() {
        let defaults = AgentSettings.defaults
        #expect(defaults.sampleInterval == 5)
        #expect(defaults.retentionDays == 14)
        #expect(defaults.topProcessCount == 10)
        #expect(defaults.watchedProcessNames.isEmpty)
    }

    @Test func clampedLimitsValuesToAllowedRanges() {
        let wild = AgentSettings(sampleInterval: 0.1, retentionDays: 9_999, watchedProcessNames: [], topProcessCount: 0)
        let clamped = wild.clamped()

        #expect(clamped.sampleInterval == 1)
        #expect(clamped.retentionDays == 365)
        #expect(clamped.topProcessCount == 1)
    }

    @Test func clampedLimitsTooLargeIntervals() {
        #expect(AgentSettings(sampleInterval: 10_000).clamped().sampleInterval == 300)
    }

    @Test func missingFileYieldsDefaults() {
        #expect(AgentSettings.load(from: temporaryURL()) == .defaults)
    }

    @Test func invalidJSONYieldsDefaults() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("{ not json".utf8).write(to: url)

        #expect(AgentSettings.load(from: url) == .defaults)
    }

    @Test func partialJSONKeepsDefaultsForMissingKeys() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(#"{"sampleInterval": 30}"#.utf8).write(to: url)

        let loaded = AgentSettings.load(from: url)

        #expect(loaded.sampleInterval == 30)
        #expect(loaded.retentionDays == 14)
    }

    @Test func loadedValuesAreClamped() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(#"{"sampleInterval": 0}"#.utf8).write(to: url)

        #expect(AgentSettings.load(from: url).sampleInterval == 1)
    }

    @Test func savedSettingsCanBeLoadedAgain() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let settings = AgentSettings(sampleInterval: 20, retentionDays: 7, watchedProcessNames: ["Citrix Viewer"], topProcessCount: 5)

        try settings.save(to: url)

        #expect(AgentSettings.load(from: url) == settings)
    }
}
