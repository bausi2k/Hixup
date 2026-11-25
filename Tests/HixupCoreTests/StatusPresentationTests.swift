import Foundation
import Testing
@testable import HixupCore

private func violation(
    _ metric: Metric = .highestProcessCPUPercent, title: String = "Hohe CPU-Last",
    severity: Severity = .warning, value: Double = 410, threshold: Double = 200,
    comparison: Comparison = .above, detail: String? = "Citrix Viewer", sustained: Bool = true
) -> ActiveViolation {
    ActiveViolation(
        ruleID: "r", title: title, severity: severity, metric: metric, value: value,
        threshold: threshold, comparison: comparison, detail: detail,
        since: Date(timeIntervalSince1970: 0), duration: 60, minimumDuration: 30, isSustained: sustained
    )
}

private func status(_ level: HealthLevel, violations: [ActiveViolation] = []) -> SystemStatus {
    SystemStatus(level: level, timestamp: nil, memory: nil, violations: violations, offenders: [], recentAlerts: [])
}

@Suite struct StatusPresentationTests {
    @Test func headlinesForHealthyAndUnknown() {
        #expect(StatusPresentation.headline(for: status(.ok)) == "Alles in Ordnung")
        #expect(StatusPresentation.headline(for: status(.unknown)) == "Keine aktuellen Daten")
    }

    @Test func headlineNamesTheMostSevereSustainedViolation() {
        let result = status(.critical, violations: [violation(title: "Speicher knapp", severity: .critical)])
        #expect(StatusPresentation.headline(for: result) == "Speicher knapp")
    }

    @Test func headlineCountsFurtherSustainedViolations() {
        let result = status(.critical, violations: [
            violation(title: "Speicher knapp", severity: .critical),
            violation(title: "Hohe CPU-Last"),
            violation(title: "Hoher Energieverbrauch")
        ])
        #expect(StatusPresentation.headline(for: result) == "Speicher knapp und 2 weitere")
    }

    @Test func headlineIgnoresViolationsThatAreNotYetSustained() {
        let result = status(.ok, violations: [violation(sustained: false)])
        #expect(StatusPresentation.headline(for: result) == "Alles in Ordnung")
    }

    @Test func symbolsDifferPerLevel() {
        let names = [HealthLevel.unknown, .ok, .warning, .critical].map(StatusPresentation.symbolName(for:))
        #expect(Set(names).count >= 3)
        #expect(StatusPresentation.symbolName(for: .critical) != StatusPresentation.symbolName(for: .ok))
    }

    @Test func valueTextUsesTheUnitOfTheMetric() {
        #expect(StatusPresentation.valueText(violation()) == "410 %")
        #expect(StatusPresentation.valueText(violation(.highestProcessEnergyWatts, value: 9.24)) == "9,2 W")
        #expect(StatusPresentation.valueText(violation(.availableMemoryPercent, value: 10.4)) == "10 %")
    }

    @Test func thresholdTextShowsDirection() {
        #expect(StatusPresentation.thresholdText(violation()) == "über 200 %")
        let low = violation(.availableMemoryPercent, value: 10, threshold: 15, comparison: .below)
        #expect(StatusPresentation.thresholdText(low) == "unter 15 %")
    }

    @Test func offenderReasonsAreLabelled() {
        #expect(StatusPresentation.label(for: .cpu) == "CPU")
        #expect(StatusPresentation.label(for: .energy) == "Energie")
        #expect(StatusPresentation.label(for: .memory) == "Speicher")
        #expect(StatusPresentation.label(for: .wakeups) == "Wakeups")
    }
}

@Suite struct HundeWordingTests {
    private func offender(_ name: String) -> Offender {
        Offender(
            name: name, processCount: 1, cpuPercent: 10, energyWatts: 1, wakeupsPerSecond: 0,
            residentBytes: 0, score: 1, reasons: []
        )
    }

    @Test func moodDescribesEveryLevelInDogTerms() {
        #expect(StatusPresentation.mood(for: .ok) == "Alles ruhig, Hixup döst.")
        #expect(StatusPresentation.mood(for: .warning) == "Hixup spitzt die Ohren.")
        #expect(StatusPresentation.mood(for: .critical) == "Hixup schlägt an!")
        #expect(StatusPresentation.mood(for: .unknown) == "Hixup schläft tief – keine Daten.")
    }

    @Test func hungriestAppIsNamedFromTheTopOffender() {
        let result = SystemStatus(
            level: .ok, timestamp: nil, memory: nil, violations: [],
            offenders: [offender("Chrome"), offender("Slack")], recentAlerts: []
        )
        #expect(StatusPresentation.hungriestApp(in: result) == "Chrome")
        #expect(StatusPresentation.hungriestApp(in: status(.ok)) == nil)
    }

    @Test func sectionTitlesUseTheNewWording() {
        #expect(StatusPresentation.hungriestAppTitle == "Ressourcenhungrigste App")
        #expect(StatusPresentation.hungriestAppRangeTitle == "Ressourcenhungrigste Apps im Zeitraum")
    }
}

@Suite struct PopoverTextTests {
    private func offender(
        cpu: Double = 0, energy: Double = 0, rssGB: Double = 0, wakeups: Double = 0
    ) -> Offender {
        Offender(
            name: "x", processCount: 1, cpuPercent: cpu, energyWatts: energy, wakeupsPerSecond: wakeups,
            residentBytes: UInt64(rssGB * 1_073_741_824), score: 0, reasons: []
        )
    }

    @Test func durationsAreShownInTheLargestSensibleUnit() {
        #expect(StatusPresentation.durationText(45) == "45 s")
        #expect(StatusPresentation.durationText(120) == "2 Min.")
        #expect(StatusPresentation.durationText(3_600) == "1 Std.")
        #expect(StatusPresentation.durationText(3_900) == "1 Std. 5 Min.")
    }

    @Test func violationLineCombinesValueThresholdAndDuration() {
        let line = StatusPresentation.violationLine(violation(
            .availableMemoryPercent, title: "Freier Speicher knapp", value: 9, threshold: 15, comparison: .below
        ))
        #expect(line == "9 % (Schwelle unter 15 %), seit 1 Min.")
    }

    @Test func headlineMetricPicksTheMetricClosestToItsLimit() {
        #expect(StatusPresentation.headlineMetric(for: offender(cpu: 240, energy: 1)) == "CPU 240 %")
        #expect(StatusPresentation.headlineMetric(for: offender(cpu: 10, energy: 9)) == "9,0 W")
        #expect(StatusPresentation.headlineMetric(for: offender(cpu: 10, rssGB: 8)) == "8,0 GB RAM")
        #expect(StatusPresentation.headlineMetric(for: offender(cpu: 10, wakeups: 3_000)) == "3000 Wakeups/s")
    }
}
