import Foundation
import Testing
@testable import HixupCore

private func date(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

private func makeStores() throws -> (SQLiteSnapshotStore, SQLiteEventStore) {
    (try SQLiteSnapshotStore(path: ":memory:"), try SQLiteEventStore(path: ":memory:"))
}

@Suite struct SampledSnapshotsTests {
    @Test func returnsAllSnapshotsWhenBelowTheLimit() throws {
        let (store, _) = try makeStores()
        for second in 0..<10 { try store.append(makeSnapshot(at: TimeInterval(second))) }

        let result = try store.sampledSnapshots(from: date(0), to: date(100), maxPoints: 50)

        #expect(result.count == 10)
    }

    @Test func thinsOutEvenlyAndKeepsOrder() throws {
        let (store, _) = try makeStores()
        for second in 0..<1000 { try store.append(makeSnapshot(at: TimeInterval(second))) }

        let result = try store.sampledSnapshots(from: date(0), to: date(2000), maxPoints: 100)

        #expect(result.count <= 100)
        #expect(result.count >= 50)
        #expect(result.map(\.timestamp) == result.map(\.timestamp).sorted())
    }

    @Test func respectsTheTimeRange() throws {
        let (store, _) = try makeStores()
        for second in 0..<100 { try store.append(makeSnapshot(at: TimeInterval(second))) }

        let result = try store.sampledSnapshots(from: date(40), to: date(49), maxPoints: 100)

        #expect(result.first?.timestamp == date(40))
        #expect(result.last?.timestamp == date(49))
    }
}

@Suite struct HistoryServiceTests {
    @Test func rangesHaveIncreasingDurations() {
        #expect(HistoryRange.hour.duration < HistoryRange.day.duration)
        #expect(HistoryRange.day.duration < HistoryRange.twoWeeks.duration)
    }

    @Test func historyContainsPointsAlertsAndMarkersOfTheRange() throws {
        let (snapshots, events) = try makeStores()
        let busy = ProcessSample(pid: 1, name: "node", residentBytes: 0, cpuPercent: 120, energyWatts: 3)
        try snapshots.append(makeSnapshot(at: 100, available: 40, processes: [busy]))
        try snapshots.append(makeSnapshot(at: 110, available: 30, processes: [busy]))
        try events.record(Alert(
            ruleID: "memory-low", title: "Speicher knapp", severity: .critical,
            value: 9, threshold: 15, detail: nil, timestamp: date(105)
        ))
        try events.addMarker(Marker(timestamp: date(108), note: "ruckelt"))
        try events.addMarker(Marker(timestamp: date(-99_999), note: "zu alt"))

        let service = HistoryService(snapshots: snapshots, events: events)
        let history = try service.history(range: .hour, now: date(120))

        #expect(history.points.count == 2)
        #expect(history.points.last?.availableMemoryPercent == 30)
        #expect(history.alerts.map(\.ruleID) == ["memory-low"])
        #expect(history.markers.map(\.note) == ["ruckelt"])
    }

    @Test func offendersCoverTheWholeRange() throws {
        let (snapshots, events) = try makeStores()
        let early = ProcessSample(pid: 1, name: "early", residentBytes: 0, cpuPercent: 300)
        try snapshots.append(makeSnapshot(at: 100, processes: [early]))
        try snapshots.append(makeSnapshot(at: 3_000, processes: []))

        let service = HistoryService(snapshots: snapshots, events: events)
        let history = try service.history(range: .hour, now: date(3_100))

        #expect(history.offenders.map(\.name) == ["early"])
    }

    @Test func emptyStoreGivesEmptyHistory() throws {
        let (snapshots, events) = try makeStores()
        let history = try HistoryService(snapshots: snapshots, events: events).history(range: .day, now: date(100))

        #expect(history.points.isEmpty)
        #expect(history.offenders.isEmpty)
    }
}
