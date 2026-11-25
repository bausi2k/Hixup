import Foundation
import Testing
@testable import HixupCore

private func date(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

private func makeService(
    lookback: TimeInterval = 600
) throws -> (StatusService, SQLiteSnapshotStore, SQLiteEventStore) {
    let snapshots = try SQLiteSnapshotStore(path: ":memory:")
    let events = try SQLiteEventStore(path: ":memory:")
    let service = StatusService(snapshots: snapshots, events: events, lookback: lookback)
    return (service, snapshots, events)
}

@Suite struct StatusServiceTests {
    @Test func emptyStoreYieldsUnknown() throws {
        let (service, _, _) = try makeService()
        #expect(try service.current(now: date(100)).level == .unknown)
    }

    @Test func currentEvaluatesStoredSnapshots() throws {
        let (service, snapshots, _) = try makeService()
        for second in stride(from: 0.0, through: 100, by: 10) {
            try snapshots.append(makeSnapshot(at: second, available: 8))
        }

        let status = try service.current(now: date(105))

        #expect(status.level == .critical)
        #expect(status.violations.first?.ruleID == "memory-low")
    }

    @Test func snapshotsBeyondTheLookbackAreIgnored() throws {
        let (service, snapshots, _) = try makeService(lookback: 50)
        for second in stride(from: 0.0, through: 100, by: 10) {
            try snapshots.append(makeSnapshot(at: second, available: second < 60 ? 8 : 50))
        }

        #expect(try service.current(now: date(105)).violations.isEmpty)
    }

    @Test func currentIncludesRecentAlerts() throws {
        let (service, snapshots, events) = try makeService()
        try snapshots.append(makeSnapshot(at: 100))
        try events.record(Alert(
            ruleID: "memory-low", title: "Speicher knapp", severity: .critical,
            value: 9, threshold: 15, detail: nil, timestamp: date(90)
        ))

        #expect(try service.current(now: date(105)).recentAlerts.map(\.ruleID) == ["memory-low"])
    }

    @Test func trendSumsProcessLoadPerSnapshotWithinTheWindow() throws {
        let (service, snapshots, _) = try makeService()
        let processes = [
            ProcessSample(pid: 1, name: "a", residentBytes: 0, cpuPercent: 40, energyWatts: 1.5),
            ProcessSample(pid: 2, name: "b", residentBytes: 0, cpuPercent: 60, energyWatts: 0.5)
        ]
        try snapshots.append(makeSnapshot(at: 0, available: 90))
        try snapshots.append(makeSnapshot(at: 200, available: 40, processes: processes))

        let trend = try service.trend(now: date(210), window: 100)

        #expect(trend.count == 1)
        #expect(trend.first?.timestamp == date(200))
        #expect(trend.first?.availableMemoryPercent == 40)
        #expect(trend.first?.cpuPercent == 100)
        #expect(trend.first?.energyWatts == 2)
    }
}
