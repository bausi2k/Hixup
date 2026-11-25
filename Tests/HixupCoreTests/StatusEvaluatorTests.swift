import Foundation
import Testing
@testable import HixupCore

private let memoryRule = Rule(
    id: "memory-low", title: "Speicher knapp", severity: .critical,
    metric: .availableMemoryPercent, comparison: .below, threshold: 15,
    minimumDuration: 60, cooldown: 600
)

private let cpuRule = Rule(
    id: "cpu-sustained", title: "Hohe CPU-Last", severity: .warning,
    metric: .highestProcessCPUPercent, comparison: .above, threshold: 200,
    minimumDuration: 30, cooldown: 300
)

private func process(
    _ name: String, pid: Int32 = 1, cpu: Double = 0, energy: Double = 0,
    rssMB: UInt64 = 100, wakeups: Double = 0
) -> ProcessSample {
    ProcessSample(
        pid: pid, name: name, residentBytes: rssMB * 1_048_576, cpuPercent: cpu,
        energyWatts: energy, wakeupsPerSecond: wakeups
    )
}

/// Snapshots im 10-Sekunden-Takt von `start` bis `end` mit gleichbleibenden Werten.
private func series(
    from start: TimeInterval, to end: TimeInterval,
    available: Double = 50, processes: [ProcessSample] = []
) -> [Snapshot] {
    stride(from: start, through: end, by: 10).map { makeSnapshot(at: $0, available: available, processes: processes) }
}

private func evaluator(
    rules: [Rule] = [memoryRule, cpuRule], window: TimeInterval = 30, maxOffenders: Int = 5
) -> StatusEvaluator {
    StatusEvaluator(rules: rules, offenderWindow: window, staleAfter: 30, maxOffenders: maxOffenders)
}

private func date(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

@Suite struct StatusEvaluatorTests {
    // MARK: - Gesamtstatus

    @Test func noSnapshotsMeansUnknown() {
        let status = evaluator().evaluate(snapshots: [], now: date(100))
        #expect(status.level == .unknown)
        #expect(status.violations.isEmpty)
        #expect(status.memory == nil)
    }

    @Test func staleLatestSnapshotMeansUnknown() {
        let status = evaluator().evaluate(snapshots: series(from: 0, to: 10), now: date(500))
        #expect(status.level == .unknown)
    }

    @Test func healthyLatestSnapshotMeansOK() {
        let status = evaluator().evaluate(snapshots: series(from: 0, to: 100), now: date(105))
        #expect(status.level == .ok)
        #expect(status.violations.isEmpty)
    }

    @Test func healthLevelsAreOrderedBySeverity() {
        #expect(HealthLevel.critical > HealthLevel.warning)
        #expect(HealthLevel.warning > HealthLevel.ok)
        #expect(HealthLevel.ok > HealthLevel.unknown)
    }

    @Test func violationBelowMinimumDurationIsListedButDoesNotRaiseTheLevel() {
        let snapshots = series(from: 0, to: 40, available: 10)
        let status = evaluator().evaluate(snapshots: snapshots, now: date(45))

        #expect(status.violations.count == 1)
        #expect(status.violations.first?.isSustained == false)
        #expect(status.level == .ok)
    }

    @Test func sustainedWarningRaisesLevelToWarning() {
        let busy = process("WindowServer", cpu: 250)
        let status = evaluator().evaluate(snapshots: series(from: 0, to: 30, processes: [busy]), now: date(35))

        #expect(status.level == .warning)
        #expect(status.violations.first?.ruleID == "cpu-sustained")
        #expect(status.violations.first?.isSustained == true)
    }

    @Test func sustainedCriticalBeatsWarning() {
        let busy = process("node", cpu: 300)
        let snapshots = series(from: 0, to: 60, available: 5, processes: [busy])
        let status = evaluator().evaluate(snapshots: snapshots, now: date(65))

        #expect(status.level == .critical)
        #expect(status.violations.count == 2)
    }

    // MARK: - Verstoesse

    @Test func violationSinceMarksStartOfTheCurrentConsecutiveRun() {
        let snapshots = series(from: 0, to: 10, available: 10)
            + series(from: 20, to: 20, available: 60)
            + series(from: 30, to: 70, available: 10)
        let status = evaluator().evaluate(snapshots: snapshots, now: date(75))

        let violation = status.violations.first { $0.ruleID == "memory-low" }
        #expect(violation?.since == date(30))
        #expect(violation?.duration == 40)
        #expect(violation?.isSustained == false)
    }

    @Test func violationCarriesValueThresholdAndCulprit() {
        let busy = process("Citrix Viewer", cpu: 410)
        let status = evaluator().evaluate(snapshots: series(from: 0, to: 30, processes: [busy]), now: date(35))

        let violation = status.violations.first
        #expect(violation?.value == 410)
        #expect(violation?.threshold == 200)
        #expect(violation?.detail == "Citrix Viewer")
    }

    @Test func recoveredRuleIsNotListed() {
        let snapshots = series(from: 0, to: 50, available: 10) + series(from: 60, to: 60, available: 60)
        let status = evaluator().evaluate(snapshots: snapshots, now: date(65))

        #expect(status.violations.isEmpty)
        #expect(status.level == .ok)
    }

    // MARK: - Verursacher

    @Test func processesWithTheSameNameAreAggregated() {
        let helpers = [
            process("Chrome Helper", pid: 1, cpu: 60, energy: 1, rssMB: 500),
            process("Chrome Helper", pid: 2, cpu: 40, energy: 0.5, rssMB: 300)
        ]
        let status = evaluator().evaluate(snapshots: series(from: 0, to: 0, processes: helpers), now: date(5))

        #expect(status.offenders.count == 1)
        #expect(status.offenders.first?.cpuPercent == 100)
        #expect(status.offenders.first?.energyWatts == 1.5)
        #expect(status.offenders.first?.residentBytes == 800 * 1_048_576)
        #expect(status.offenders.first?.processCount == 2)
    }

    @Test func offendersAreRankedByScoreAndLimited() {
        let processes = [
            process("small", pid: 1, cpu: 10),
            process("huge", pid: 2, cpu: 300, energy: 9),
            process("medium", pid: 3, cpu: 120)
        ]
        let status = evaluator(maxOffenders: 2)
            .evaluate(snapshots: series(from: 0, to: 0, processes: processes), now: date(5))

        #expect(status.offenders.map(\.name) == ["huge", "medium"])
    }

    @Test func reasonsFlagOnlyMetricsAtOrAboveTheirThresholds() {
        let processes = [
            process("hog", pid: 1, cpu: 200, energy: 6, rssMB: 5_000, wakeups: 2_000),
            process("calm", pid: 2, cpu: 5, energy: 0.1, rssMB: 100, wakeups: 10)
        ]
        let status = evaluator().evaluate(snapshots: series(from: 0, to: 0, processes: processes), now: date(5))

        let hog = status.offenders.first { $0.name == "hog" }
        let calm = status.offenders.first { $0.name == "calm" }
        #expect(Set(hog?.reasons ?? []) == [.cpu, .energy, .memory, .wakeups])
        #expect(calm?.reasons.isEmpty == true)
    }

    @Test func offenderValuesAreAveragedOverTheWindow() {
        let snapshots = [
            makeSnapshot(at: 80, processes: [process("a", cpu: 200)]),
            makeSnapshot(at: 90, processes: [process("a", cpu: 0)])
        ]
        let status = evaluator(window: 30).evaluate(snapshots: snapshots, now: date(95))

        #expect(status.offenders.first?.cpuPercent == 100)
    }

    @Test func snapshotsOutsideTheWindowDoNotInfluenceOffenders() {
        let snapshots = [
            makeSnapshot(at: 0, processes: [process("old", cpu: 900)]),
            makeSnapshot(at: 100, processes: [process("new", cpu: 50)])
        ]
        let status = evaluator(window: 30).evaluate(snapshots: snapshots, now: date(105))

        #expect(status.offenders.map(\.name) == ["new"])
    }

    @Test func processMissingFromSomeSnapshotsCountsAsZeroForRates() {
        let snapshots = [
            makeSnapshot(at: 80, processes: [process("a", cpu: 300)]),
            makeSnapshot(at: 90, processes: []),
            makeSnapshot(at: 100, processes: [])
        ]
        let status = evaluator(window: 30).evaluate(snapshots: snapshots, now: date(105))

        #expect(status.offenders.first?.cpuPercent == 100)
    }

    // MARK: - Sonstiges

    @Test func memorySummaryComesFromTheLatestSnapshot() {
        let snapshots = [makeSnapshot(at: 0, available: 70), makeSnapshot(at: 10, available: 33)]
        let status = evaluator().evaluate(snapshots: snapshots, now: date(15))

        #expect(status.memory?.availablePercent == 33)
        #expect(status.timestamp == date(10))
    }

    @Test func recentAlertsArePassedThroughNewestFirstAndLimited() {
        let alerts = (1...5).map {
            Alert(
                ruleID: "r\($0)", title: "t", severity: .warning, value: 1, threshold: 1,
                detail: nil, timestamp: date(TimeInterval($0))
            )
        }
        let status = StatusEvaluator(rules: [], maxRecentAlerts: 3)
            .evaluate(snapshots: series(from: 0, to: 10), recentAlerts: alerts, now: date(15))

        #expect(status.recentAlerts.map(\.ruleID) == ["r5", "r4", "r3"])
    }
}
