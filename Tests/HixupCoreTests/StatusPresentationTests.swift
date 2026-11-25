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
