import Foundation
import Testing
@testable import HixupCore

private func date(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

private func snap(_ seconds: TimeInterval, pressure: MemoryPressureLevel?, available: Double = 50) -> Snapshot {
    Snapshot(
        timestamp: date(seconds),
        memory: MemorySample(totalBytes: 16_000_000_000, usedBytes: 8_000_000_000, compressedBytes: 0, availablePercent: available),
        processes: [], systemCPUPercent: 10, memoryPressure: pressure
    )
}

private func feed(_ engine: RuleEngine, from start: TimeInterval, to end: TimeInterval, pressure: MemoryPressureLevel?) -> [Alert] {
    stride(from: start, through: end, by: 10).flatMap { engine.evaluate(snap($0, pressure: pressure)) }
}

@Suite struct PressureModelTests {
    @Test func numericLevelsAreOrdered() {
        #expect(MemoryPressureLevel.normal.numeric == 0)
        #expect(MemoryPressureLevel.warning.numeric == 1)
        #expect(MemoryPressureLevel.critical.numeric == 2)
        #expect(MemoryPressureLevel(numeric: 1) == .warning)
        #expect(MemoryPressureLevel(numeric: 2) == .critical)
        #expect(MemoryPressureLevel(numeric: 0) == .normal)
    }

    @Test func oldSnapshotsWithoutPressureStayReadable() throws {
        let old = try JSONEncoder().encode(snap(1, pressure: nil))
        #expect(try JSONDecoder().decode(Snapshot.self, from: old).memoryPressure == nil)

        let data = try JSONEncoder().encode(snap(1, pressure: .warning))
        #expect(try JSONDecoder().decode(Snapshot.self, from: data).memoryPressure == .warning)
    }

    @Test func peakScoreRisesWithPressure() {
        #expect(snap(1, pressure: .critical).loadScore > snap(1, pressure: .warning).loadScore)
        #expect(snap(1, pressure: .warning).loadScore > snap(1, pressure: .normal).loadScore)
    }

    @Test func settingsFlagDefaultsToOnAndSurvivesOldFiles() throws {
        #expect(AgentSettings.defaults.memoryPressureAlerts)
        let old = try JSONDecoder().decode(AgentSettings.self, from: Data(#"{"sampleInterval":10}"#.utf8))
        #expect(old.memoryPressureAlerts)
        var off = AgentSettings.defaults
        off.memoryPressureAlerts = false
        let data = try JSONEncoder().encode(off)
        #expect(try JSONDecoder().decode(AgentSettings.self, from: data).memoryPressureAlerts == false)
    }
}

@Suite struct PressureRuleTests {
    @Test func defaultRulesIncludeBothPressureRules() {
        let ids = Set(DefaultRules.all.map(\.id))
        #expect(ids.contains("memory-pressure-warning"))
        #expect(ids.contains("memory-pressure-critical"))
        #expect(DefaultRules.rules(for: .defaults) == DefaultRules.all)
    }

    @Test func settingsCanSwitchPressureRulesOff() {
        var settings = AgentSettings.defaults
        settings.memoryPressureAlerts = false
        let ids = DefaultRules.rules(for: settings).map(\.id)
        #expect(!ids.contains("memory-pressure-warning"))
        #expect(!ids.contains("memory-pressure-critical"))
        #expect(ids.contains("memory-low"))
    }

    @Test func warningPressureAlertsAfterTheMinimumDuration() {
        let engine = RuleEngine(rules: [DefaultRules.memoryPressureWarning])
        #expect(feed(engine, from: 0, to: 50, pressure: .warning).isEmpty)
        let alerts = feed(RuleEngine(rules: [DefaultRules.memoryPressureWarning]), from: 0, to: 60, pressure: .warning)
        #expect(alerts.count == 1)
        #expect(alerts.first?.ruleID == "memory-pressure-warning")
        #expect(alerts.first?.severity == .warning)
    }

    @Test func normalPressureNeverAlerts() {
        let engine = RuleEngine(rules: [DefaultRules.memoryPressureWarning, DefaultRules.memoryPressureCritical])
        #expect(feed(engine, from: 0, to: 600, pressure: .normal).isEmpty)
    }

    @Test func warningDoesNotTriggerTheCriticalRule() {
        let engine = RuleEngine(rules: [DefaultRules.memoryPressureCritical])
        #expect(feed(engine, from: 0, to: 300, pressure: .warning).isEmpty)
    }

    @Test func criticalPressureAlertsQuicklyAsCritical() {
        let engine = RuleEngine(rules: [DefaultRules.memoryPressureCritical])
        let alerts = feed(engine, from: 0, to: 30, pressure: .critical)
        #expect(alerts.first?.severity == .critical)
    }

    @Test func snapshotsWithoutPressureAreIgnored() {
        let engine = RuleEngine(rules: [DefaultRules.memoryPressureWarning])
        #expect(feed(engine, from: 0, to: 300, pressure: nil).isEmpty)
    }
}

@Suite struct PressurePresentationTests {
    private func violation(value: Double, threshold: Double) -> ActiveViolation {
        ActiveViolation(
            ruleID: "memory-pressure-warning", title: "Speicherdruck erhöht", severity: .warning,
            metric: .memoryPressure, value: value, threshold: threshold, comparison: .above, detail: nil,
            since: date(0), duration: 120, minimumDuration: 60, isSustained: true
        )
    }

    @Test func pressureValuesAreShownAsLevelNames() {
        #expect(StatusPresentation.valueText(violation(value: 1, threshold: 0)) == "Warnung")
        #expect(StatusPresentation.valueText(violation(value: 2, threshold: 1)) == "kritisch")
        #expect(StatusPresentation.thresholdText(violation(value: 1, threshold: 0)) == "über normal")
    }

    @Test func alertBodyNamesTheLevelForPressureAlerts() {
        let alert = Alert(
            ruleID: "memory-pressure-warning", title: "Speicherdruck erhöht", severity: .warning,
            value: 1, threshold: 0, detail: nil, timestamp: date(0)
        )
        #expect(StatusPresentation.alertBody(for: alert) == "Speicherdruck: Warnung")
    }

    @Test func alertBodyForOtherAlertsKeepsTheNumbers() {
        let alert = Alert(
            ruleID: "memory-low", title: "x", severity: .critical, value: 9, threshold: 15, detail: "node", timestamp: date(0)
        )
        #expect(StatusPresentation.alertBody(for: alert) == "Messwert 9, Schwelle 15 (node)")
    }
}

@Suite struct PressureDiagnosisTests {
    @Test func windowPressureCountsEvenWithoutDeepMeasurement() {
        let marker = Marker(timestamp: date(1_000), note: nil)
        let snapshots = [snap(900, pressure: .normal), snap(1_000, pressure: .critical)]
        let findings = MarkerDiagnosis(language: .de).findings(marker: marker, snapshots: snapshots, settings: .defaults)
        #expect(findings.first?.cause == .memory)
        #expect(findings.first?.confidence == .high)
    }
}
