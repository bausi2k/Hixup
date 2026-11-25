import Foundation
import Testing
@testable import HixupCore

private func makeAlert(at seconds: TimeInterval, rule: String = "memory-low", detail: String? = nil) -> Alert {
    Alert(
        ruleID: rule, title: "Titel \(rule)", severity: .critical, value: 12, threshold: 15,
        detail: detail, timestamp: Date(timeIntervalSince1970: seconds)
    )
}

private func date(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

@Suite struct EventStoreTests {
    @Test func recordedAlertCanBeReadBackUnchanged() throws {
        let store = try SQLiteEventStore(path: ":memory:")
        let alert = makeAlert(at: 100, rule: "cpu-sustained", detail: "WindowServer")

        try store.record(alert)

        #expect(try store.alerts(from: date(0), to: date(200)) == [alert])
    }

    @Test func alertRangeQueryIsFilteredAndSortedAscending() throws {
        let store = try SQLiteEventStore(path: ":memory:")
        for seconds in [300, 100, 200, 400] as [TimeInterval] { try store.record(makeAlert(at: seconds)) }

        let result = try store.alerts(from: date(150), to: date(350))

        #expect(result.map(\.timestamp.timeIntervalSince1970) == [200, 300])
    }

    @Test func markerWithAndWithoutNoteRoundTrips() throws {
        let store = try SQLiteEventStore(path: ":memory:")
        let plain = Marker(timestamp: date(100), note: nil)
        let noted = Marker(timestamp: date(200), note: "Citrix ruckelt")

        try store.addMarker(plain)
        try store.addMarker(noted)

        #expect(try store.markers(from: date(0), to: date(300)) == [plain, noted])
    }

    @Test func markerRangeQueryIsFiltered() throws {
        let store = try SQLiteEventStore(path: ":memory:")
        for seconds in [100, 200, 300] as [TimeInterval] { try store.addMarker(Marker(timestamp: date(seconds), note: nil)) }

        #expect(try store.markers(from: date(150), to: date(250)).count == 1)
    }

    @Test func purgeRemovesOldAlertsAndMarkersAndReturnsTotalCount() throws {
        let store = try SQLiteEventStore(path: ":memory:")
        try store.record(makeAlert(at: 100))
        try store.record(makeAlert(at: 300))
        try store.addMarker(Marker(timestamp: date(100), note: nil))
        try store.addMarker(Marker(timestamp: date(300), note: nil))

        let deleted = try store.purge(olderThan: date(200))

        #expect(deleted == 2)
        #expect(try store.alerts(from: date(0), to: date(1_000)).count == 1)
        #expect(try store.markers(from: date(0), to: date(1_000)).count == 1)
    }

    @Test func eventsAreSharedBetweenInstancesOnTheSameFile() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("hixup-events-\(UUID().uuidString).sqlite").path
        defer {
            for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path + suffix) }
        }

        try SQLiteEventStore(path: path).record(makeAlert(at: 100))

        #expect(try SQLiteEventStore(path: path).alerts(from: date(0), to: date(200)).count == 1)
    }

    @Test func eventStoreAndSnapshotStoreCanShareOneDatabaseFile() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("hixup-shared-\(UUID().uuidString).sqlite").path
        defer {
            for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path + suffix) }
        }
        let snapshots = try SQLiteSnapshotStore(path: path)
        let events = try SQLiteEventStore(path: path)

        try snapshots.append(makeSnapshot(at: 100))
        try events.record(makeAlert(at: 100))

        #expect(try snapshots.count() == 1)
        #expect(try events.alerts(from: date(0), to: date(200)).count == 1)
    }
}
