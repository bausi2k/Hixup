import Foundation
import Testing
@testable import HixupCore

private final class Box<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value
    init(_ value: Value) { stored = value }
    var value: Value {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

private func rule(_ id: String, in rules: [Rule]) -> Rule? { rules.first { $0.id == id } }

@Suite struct RuleSettingsTests {
    @Test func defaultSettingsReproduceTheDefaultRules() {
        #expect(DefaultRules.rules(for: .defaults) == DefaultRules.all)
    }

    @Test func thresholdsAndDurationsComeFromTheSettings() {
        var settings = AgentSettings.defaults
        settings.memoryLowPercent = 25
        settings.processCPUPercent = 300
        settings.processEnergyWatts = 12
        settings.memoryMinimumSeconds = 30
        settings.loadMinimumSeconds = 45

        let rules = DefaultRules.rules(for: settings)

        #expect(rule("memory-low", in: rules)?.threshold == 25)
        #expect(rule("memory-low", in: rules)?.minimumDuration == 30)
        #expect(rule("cpu-sustained", in: rules)?.threshold == 300)
        #expect(rule("cpu-sustained", in: rules)?.minimumDuration == 45)
        #expect(rule("energy-sustained", in: rules)?.threshold == 12)
        #expect(rule("energy-sustained", in: rules)?.minimumDuration == 45)
    }

    @Test func clampingLimitsRuleValues() {
        var wild = AgentSettings.defaults
        wild.memoryLowPercent = 99
        wild.processCPUPercent = 1
        wild.processEnergyWatts = 0
        wild.memoryMinimumSeconds = 0
        wild.loadMinimumSeconds = 99_999

        let clamped = wild.clamped()

        #expect(clamped.memoryLowPercent == 90)
        #expect(clamped.processCPUPercent == 50)
        #expect(clamped.processEnergyWatts == 0.5)
        #expect(clamped.memoryMinimumSeconds == 10)
        #expect(clamped.loadMinimumSeconds == 3_600)
    }

    @Test func oldSettingsFileWithoutRuleFieldsUsesDefaults() throws {
        let json = #"{"sampleInterval":10,"retentionDays":7}"#
        let settings = try JSONDecoder().decode(AgentSettings.self, from: Data(json.utf8))

        #expect(settings.sampleInterval == 10)
        #expect(settings.memoryLowPercent == AgentSettings.defaults.memoryLowPercent)
        #expect(settings.loadMinimumSeconds == AgentSettings.defaults.loadMinimumSeconds)
    }

    @Test func ruleSettingsSurviveSaveAndLoad() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hixup-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        var settings = AgentSettings.defaults
        settings.processEnergyWatts = 6.5

        try settings.save(to: url)

        #expect(AgentSettings.load(from: url).processEnergyWatts == 6.5)
    }
}

@Suite struct RuleEngineUpdateTests {
    private let low = DefaultRules.memoryLow

    @Test func updatingWithTheSameRuleKeepsTheRunningViolation() {
        let engine = RuleEngine(rules: [low])
        _ = engine.evaluate(makeSnapshot(at: 0, available: 5))

        engine.update(rules: [low])
        let alerts = engine.evaluate(makeSnapshot(at: 60, available: 5))

        #expect(alerts.map(\.ruleID) == ["memory-low"])
    }

    @Test func changingARuleResetsItsState() {
        let engine = RuleEngine(rules: [low])
        _ = engine.evaluate(makeSnapshot(at: 0, available: 5))

        var stricter = AgentSettings.defaults
        stricter.memoryLowPercent = 20
        engine.update(rules: DefaultRules.rules(for: stricter))
        let alerts = engine.evaluate(makeSnapshot(at: 60, available: 5))

        #expect(alerts.isEmpty)
    }

    @Test func newThresholdTakesEffect() {
        let engine = RuleEngine(rules: [low])
        var relaxed = AgentSettings.defaults
        relaxed.memoryLowPercent = 3
        engine.update(rules: DefaultRules.rules(for: relaxed))

        _ = engine.evaluate(makeSnapshot(at: 0, available: 5))
        #expect(engine.evaluate(makeSnapshot(at: 120, available: 5)).isEmpty)
    }
}

@Suite struct StatusServiceRulesTests {
    @Test func providerIsConsultedOnEveryCall() throws {
        let snapshots = try SQLiteSnapshotStore(path: ":memory:")
        let events = try SQLiteEventStore(path: ":memory:")
        for second in stride(from: 0.0, through: 100, by: 10) {
            try snapshots.append(makeSnapshot(at: second, available: 20))
        }
        let threshold = Box(15.0)
        let service = StatusService(snapshots: snapshots, events: events, evaluatorProvider: {
            var settings = AgentSettings.defaults
            settings.memoryLowPercent = threshold.value
            return StatusEvaluator(rules: DefaultRules.rules(for: settings))
        })

        #expect(try service.current(now: Date(timeIntervalSince1970: 105)).violations.isEmpty)
        threshold.value = 30
        #expect(try service.current(now: Date(timeIntervalSince1970: 105)).violations.count == 1)
    }
}
