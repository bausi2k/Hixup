import Foundation
import Testing
@testable import HixupCore

private func date(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

private func busy(_ cpu: Double) -> [ProcessSample] {
    [ProcessSample(pid: 1, name: "node", residentBytes: 0, cpuPercent: cpu)]
}

@Suite struct PeakSamplingTests {
    @Test func returnsAllSnapshotsWhenBelowTheLimit() throws {
        let store = try SQLiteSnapshotStore(path: ":memory:")
        for second in 0..<10 { try store.append(makeSnapshot(at: TimeInterval(second))) }

        let result = try store.peakSnapshots(from: date(0), to: date(100), maxPoints: 50)

        #expect(result.count == 10)
    }

    @Test func keepsShortSpikeThatEvenStrideWouldDrop() throws {
        let store = try SQLiteSnapshotStore(path: ":memory:")
        for second in 0..<1000 {
            let spike = second == 7
            try store.append(makeSnapshot(at: TimeInterval(second), processes: busy(spike ? 800 : 1)))
        }

        let peaks = try store.peakSnapshots(from: date(0), to: date(999), maxPoints: 100)
        let even = try store.sampledSnapshots(from: date(0), to: date(999), maxPoints: 100)

        #expect(peaks.contains { $0.timestamp == date(7) })
        #expect(!even.contains { $0.timestamp == date(7) })
    }

    @Test func returnsAtMostOnePointPerBucketInOrder() throws {
        let store = try SQLiteSnapshotStore(path: ":memory:")
        for second in 0..<1000 { try store.append(makeSnapshot(at: TimeInterval(second))) }

        let result = try store.peakSnapshots(from: date(0), to: date(999), maxPoints: 100)

        #expect(result.count <= 101)
        #expect(result.count >= 90)
        #expect(result.map(\.timestamp) == result.map(\.timestamp).sorted())
    }

    @Test func lowMemoryCountsAsPeak() throws {
        let store = try SQLiteSnapshotStore(path: ":memory:")
        for second in 0..<200 {
            try store.append(makeSnapshot(at: TimeInterval(second), available: second == 33 ? 3 : 60))
        }

        let result = try store.peakSnapshots(from: date(0), to: date(199), maxPoints: 20)

        #expect(result.contains { $0.timestamp == date(33) })
    }

    @Test func snapshotsWithoutStoredScoreStillAppear() throws {
        let store = try SQLiteSnapshotStore(path: ":memory:")
        try store.append(makeSnapshot(at: 1))

        #expect(try store.peakSnapshots(from: date(0), to: date(10), maxPoints: 1).count == 1)
    }

    @Test func historyChartKeepsPeaksWhileOffendersUseEvenSamples() throws {
        let snapshots = try SQLiteSnapshotStore(path: ":memory:")
        let events = try SQLiteEventStore(path: ":memory:")
        for second in 0..<1000 {
            try snapshots.append(makeSnapshot(at: TimeInterval(second), processes: busy(second == 7 ? 800 : 1)))
        }

        let history = try HistoryService(snapshots: snapshots, events: events, maxPoints: 100)
            .history(range: .hour, now: date(1000))

        #expect(history.points.contains { $0.cpuPercent == 800 })
        #expect((history.offenders.first?.cpuPercent ?? 0) < 100)
    }
}
