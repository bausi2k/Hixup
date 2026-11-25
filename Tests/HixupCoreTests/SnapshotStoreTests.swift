import Foundation
import Testing
@testable import HixupCore

func makeSnapshot(
    at seconds: TimeInterval,
    available: Double = 50,
    processes: [ProcessSample] = []
) -> Snapshot {
    Snapshot(
        timestamp: Date(timeIntervalSince1970: seconds),
        memory: MemorySample(
            totalBytes: 16_000_000_000, usedBytes: 8_000_000_000,
            compressedBytes: 1_000_000_000, availablePercent: available
        ),
        processes: processes
    )
}

@Suite struct SnapshotStoreTests {
    @Test func appendedSnapshotCanBeReadBackUnchanged() throws {
        let store = try SQLiteSnapshotStore(path: ":memory:")
        let process = ProcessSample(pid: 7, name: "Citrix Viewer", residentBytes: 1_024, cpuPercent: 42.5)
        let snapshot = makeSnapshot(at: 100, available: 12.5, processes: [process])

        try store.append(snapshot)

        #expect(try store.snapshots(from: Date(timeIntervalSince1970: 0), to: Date(timeIntervalSince1970: 200)) == [snapshot])
    }

    @Test func rangeQueryReturnsOnlyMatchingSnapshotsSortedAscending() throws {
        let store = try SQLiteSnapshotStore(path: ":memory:")
        for seconds in [300, 100, 200, 400] as [TimeInterval] {
            try store.append(makeSnapshot(at: seconds))
        }

        let result = try store.snapshots(
            from: Date(timeIntervalSince1970: 150),
            to: Date(timeIntervalSince1970: 350)
        )

        #expect(result.map(\.timestamp.timeIntervalSince1970) == [200, 300])
    }

    @Test func purgeRemovesOnlyOlderSnapshotsAndReturnsDeletedCount() throws {
        let store = try SQLiteSnapshotStore(path: ":memory:")
        for seconds in [100, 200, 300] as [TimeInterval] {
            try store.append(makeSnapshot(at: seconds))
        }

        let deleted = try store.purge(olderThan: Date(timeIntervalSince1970: 250))

        #expect(deleted == 2)
        #expect(try store.count() == 1)
    }

    @Test func dataPersistsAcrossStoreInstances() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("hixup-test-\(UUID().uuidString).sqlite").path
        defer { try? FileManager.default.removeItem(atPath: path) }

        try SQLiteSnapshotStore(path: path).append(makeSnapshot(at: 100))

        #expect(try SQLiteSnapshotStore(path: path).count() == 1)
    }

    @Test func openingAnUnwritablePathThrows() {
        #expect(throws: StorageError.self) {
            try SQLiteSnapshotStore(path: "/nonexistent-dir/hixup.sqlite")
        }
    }

    @Test func fileDatabaseUsesWriteAheadLogging() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("hixup-wal-\(UUID().uuidString).sqlite").path
        defer {
            for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path + suffix) }
        }

        #expect(try SQLiteSnapshotStore(path: path).journalMode == "wal")
    }

    @Test func readerAndWriterCanWorkConcurrentlyOnTheSameFile() async throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("hixup-concurrent-\(UUID().uuidString).sqlite").path
        defer {
            for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path + suffix) }
        }
        let writer = try SQLiteSnapshotStore(path: path)
        let reader = try SQLiteSnapshotStore(path: path)

        let writes = Task.detached {
            for index in 0..<200 { try writer.append(makeSnapshot(at: TimeInterval(index))) }
        }
        let reads = Task.detached {
            for _ in 0..<200 { _ = try reader.count() }
        }

        try await writes.value
        try await reads.value
        #expect(try reader.count() == 200)
    }
}
