import Foundation
import Testing
@testable import HixupCore

private let lowMemoryRule = Rule(
    id: "memory-low", title: "Speicher knapp", severity: .critical,
    metric: .availableMemoryPercent, comparison: .below, threshold: 15,
    minimumDuration: 60, cooldown: 600
)

private let highCPURule = Rule(
    id: "cpu-high", title: "Hohe CPU-Last", severity: .warning,
    metric: .highestProcessCPUPercent, comparison: .above, threshold: 200,
    minimumDuration: 30, cooldown: 300
)

/// Speist Messwerte im 10-Sekunden-Takt ein und sammelt alle Alerts.
private func feed(
    _ engine: RuleEngine, from start: TimeInterval, to end: TimeInterval,
    available: Double = 50, processes: [ProcessSample] = []
) -> [Alert] {
    stride(from: start, through: end, by: 10).flatMap {
        engine.evaluate(makeSnapshot(at: $0, available: available, processes: processes))
    }
}

private let highEnergyRule = Rule(
    id: "energy-high", title: "Hoher Energieverbrauch", severity: .warning,
    metric: .highestProcessEnergyWatts, comparison: .above, threshold: 4,
    minimumDuration: 30, cooldown: 300
)

@Suite struct RuleEngineTests {
    @Test func noAlertBeforeMinimumDurationIsReached() {
        let engine = RuleEngine(rules: [lowMemoryRule])
        #expect(feed(engine, from: 0, to: 50, available: 10).isEmpty)
    }

    @Test func alertFiresOnceMinimumDurationIsReached() {
        let engine = RuleEngine(rules: [lowMemoryRule])
        let alerts = feed(engine, from: 0, to: 60, available: 10)

        #expect(alerts.count == 1)
        #expect(alerts.first?.ruleID == "memory-low")
        #expect(alerts.first?.severity == .critical)
        #expect(alerts.first?.value == 10)
        #expect(alerts.first?.timestamp == Date(timeIntervalSince1970: 60))
    }

    @Test func valuesAtThresholdDoNotViolateStrictComparison() {
        let engine = RuleEngine(rules: [lowMemoryRule])
        #expect(feed(engine, from: 0, to: 300, available: 15).isEmpty)
    }

    @Test func shortSpikesInterruptedByRecoveryNeverFire() {
        let engine = RuleEngine(rules: [lowMemoryRule])
        var alerts = feed(engine, from: 0, to: 40, available: 10)
        alerts += feed(engine, from: 50, to: 60, available: 60)
        alerts += feed(engine, from: 70, to: 100, available: 10)
        #expect(alerts.isEmpty)
    }

    @Test func cooldownSuppressesRepeatedAlertsWhileConditionPersists() {
        let engine = RuleEngine(rules: [lowMemoryRule])
        let alerts = feed(engine, from: 0, to: 650, available: 10)

        #expect(alerts.map(\.timestamp.timeIntervalSince1970) == [60])
    }

    @Test func alertFiresAgainAfterCooldownExpires() {
        let engine = RuleEngine(rules: [lowMemoryRule])
        let alerts = feed(engine, from: 0, to: 670, available: 10)

        #expect(alerts.map(\.timestamp.timeIntervalSince1970) == [60, 660])
    }

    @Test func recoveryDoesNotResetCooldown() {
        let engine = RuleEngine(rules: [lowMemoryRule])
        var alerts = feed(engine, from: 0, to: 60, available: 10)
        alerts += feed(engine, from: 70, to: 80, available: 60)
        alerts += feed(engine, from: 90, to: 200, available: 10)

        #expect(alerts.count == 1)
    }

    @Test func cpuRuleReportsTheResponsibleProcess() {
        let engine = RuleEngine(rules: [highCPURule])
        let busy = ProcessSample(pid: 1, name: "WindowServer", residentBytes: 1, cpuPercent: 250)
        let calm = ProcessSample(pid: 2, name: "Finder", residentBytes: 1, cpuPercent: 3)

        let alerts = feed(engine, from: 0, to: 30, processes: [calm, busy])

        #expect(alerts.count == 1)
        #expect(alerts.first?.detail == "WindowServer")
        #expect(alerts.first?.value == 250)
    }

    @Test func missingProcessDataCountsAsNoViolation() {
        let engine = RuleEngine(rules: [highCPURule])
        #expect(feed(engine, from: 0, to: 120, processes: []).isEmpty)
    }

    @Test func rulesAreTrackedIndependently() {
        let engine = RuleEngine(rules: [lowMemoryRule, highCPURule])
        let busy = ProcessSample(pid: 1, name: "node", residentBytes: 1, cpuPercent: 300)

        let alerts = feed(engine, from: 0, to: 60, available: 10, processes: [busy])

        #expect(Set(alerts.map(\.ruleID)) == ["memory-low", "cpu-high"])
    }

    @Test func energyRuleReportsTheResponsibleProcess() {
        let engine = RuleEngine(rules: [highEnergyRule])
        let hog = ProcessSample(pid: 1, name: "Citrix Viewer", residentBytes: 1, cpuPercent: 20, energyWatts: 6.5)
        let calm = ProcessSample(pid: 2, name: "Finder", residentBytes: 1, cpuPercent: 1, energyWatts: 0.1)

        let alerts = feed(engine, from: 0, to: 30, processes: [calm, hog])

        #expect(alerts.count == 1)
        #expect(alerts.first?.detail == "Citrix Viewer")
        #expect(alerts.first?.value == 6.5)
    }

    @Test func defaultRulesContainMemoryCPUAndEnergyChecks() {
        let ids = Set(DefaultRules.all.map(\.id))
        #expect(ids == ["memory-low", "cpu-sustained", "energy-sustained", "cpu-system-high"])
    }

    @Test func defaultEnergyRuleUsesEightWattsForTwoMinutes() {
        #expect(DefaultRules.energySustained.threshold == 8)
        #expect(DefaultRules.energySustained.minimumDuration == 120)
    }
}
