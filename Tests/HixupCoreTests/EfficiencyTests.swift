import Foundation
import Testing
@testable import HixupCore

private func date(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

private func busy(_ cpu: Double, energy: Double = 1) -> [ProcessSample] {
    [ProcessSample(pid: 1, name: "node", residentBytes: 1_000, cpuPercent: cpu, energyWatts: energy)]
}

private func snap(_ seconds: TimeInterval, available: Double = 50, cpu: Double = 10, systemCPU: Double? = 20, pressure: MemoryPressureLevel? = nil) -> Snapshot {
    Snapshot(
        timestamp: date(seconds),
        memory: MemorySample(totalBytes: 16_000_000_000, usedBytes: 8_000_000_000, compressedBytes: 0, availablePercent: available),
        processes: busy(cpu), systemCPUPercent: systemCPU, memoryPressure: pressure
    )
}

@Suite struct OverviewTests {
    @Test func overviewMatchesCurrentAndTrendReadSeparately() throws {
        let snapshots = try SQLiteSnapshotStore(path: ":memory:")
        let events = try SQLiteEventStore(path: ":memory:")
        for second in stride(from: 0.0, through: 600, by: 10) { try snapshots.append(snap(second, available: second < 300 ? 60 : 12)) }
        let service = StatusService(snapshots: snapshots, events: events, evaluator: StatusEvaluator(staleAfter: 60))
        let now = date(605)

        let overview = try service.overview(now: now)

        #expect(overview.status == (try service.current(now: now)))
        #expect(overview.trend == (try service.trend(now: now)))
    }
}

@Suite struct PeakPointTests {
    @Test func pointsMatchTheDecodedSnapshots() throws {
        let store = try SQLiteSnapshotStore(path: ":memory:")
        for second in 0..<500 {
            try store.append(snap(TimeInterval(second), available: Double(20 + second % 30), cpu: second == 7 ? 800 : 5, systemCPU: nil, pressure: .warning))
        }

        let points = try store.peakPoints(from: date(0), to: date(499), maxPoints: 50)
        let expected = try store.peakSnapshots(from: date(0), to: date(499), maxPoints: 50).map(TrendPoint.init(snapshot:))

        #expect(points == expected)
        #expect(points.contains { $0.cpuPercent == 800 })
    }

    @Test func belowTheLimitAllPointsAreReturned() throws {
        let store = try SQLiteSnapshotStore(path: ":memory:")
        for second in 0..<10 { try store.append(snap(TimeInterval(second))) }
        #expect(try store.peakPoints(from: date(0), to: date(100), maxPoints: 50).count == 10)
    }

    @Test func legacyRowsWithoutSummaryColumnsStillProduceTheSamePoints() throws {
        let path = NSTemporaryDirectory() + "hixup-legacy-\(UUID().uuidString).sqlite"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let store = try SQLiteSnapshotStore(path: path)
        for second in 0..<200 { try store.append(snap(TimeInterval(second), available: Double(20 + second % 30))) }
        let expected = try store.peakPoints(from: date(0), to: date(199), maxPoints: 20)

        try store.clearSummaryColumnsForTesting()
        let legacy = try store.peakPoints(from: date(0), to: date(199), maxPoints: 20)

        #expect(legacy == expected)
    }

    @Test func historyUsesPeakPointsAndFewerOffenderSamples() throws {
        let snapshots = try SQLiteSnapshotStore(path: ":memory:")
        let events = try SQLiteEventStore(path: ":memory:")
        for second in 0..<1000 { try snapshots.append(snap(TimeInterval(second), cpu: second == 7 ? 800 : 1, systemCPU: nil)) }

        let history = try HistoryService(snapshots: snapshots, events: events, maxPoints: 100).history(range: .hour, now: date(1000))

        #expect(history.points.contains { $0.cpuPercent == 800 })
        #expect(history.points.count <= 101)
        #expect(!history.offenders.isEmpty)
    }
}

@Suite struct RefreshIntervalTests {
    @Test func longerRangesRefreshLessOften() {
        #expect(HistoryRange.hour.refreshInterval < HistoryRange.day.refreshInterval)
        #expect(HistoryRange.day.refreshInterval < HistoryRange.twoWeeks.refreshInterval)
    }
}
