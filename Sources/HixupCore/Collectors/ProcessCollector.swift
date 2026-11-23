import Foundation

public struct RawProcess: Equatable, Sendable {
    public var pid: Int32
    public var name: String
    public var residentBytes: UInt64
    /// Kumulierte CPU-Zeit (User + System) in Nanosekunden.
    public var cpuTimeNanoseconds: UInt64

    public init(pid: Int32, name: String, residentBytes: UInt64, cpuTimeNanoseconds: UInt64) {
        self.pid = pid
        self.name = name
        self.residentBytes = residentBytes
        self.cpuTimeNanoseconds = cpuTimeNanoseconds
    }
}

public protocol ProcessListing: Sendable {
    func list() throws -> [RawProcess]
}

/// Berechnet CPU-Last pro Prozess aus der Differenz zweier Messungen.
public final class ProcessCollector: @unchecked Sendable {
    private struct Baseline {
        let name: String
        let cpuTimeNanoseconds: UInt64
    }

    private let lister: any ProcessListing
    private let lock = NSLock()
    private var baselines: [Int32: Baseline] = [:]
    private var lastTimestamp: Date?

    public init(lister: any ProcessListing = SystemProcessLister()) {
        self.lister = lister
    }

    /// - Parameters:
    ///   - topCount: Anzahl der Prozesse mit der hoechsten CPU-Last.
    ///   - watchedNames: Prozesse, die unabhaengig von der Platzierung immer enthalten sind.
    public func collect(
        at timestamp: Date = Date(),
        topCount: Int = 10,
        watchedNames: Set<String> = []
    ) throws -> [ProcessSample] {
        let processes = try lister.list()

        lock.lock()
        defer { lock.unlock() }

        let elapsed = lastTimestamp.map { timestamp.timeIntervalSince($0) } ?? 0
        let samples = processes.map { process in
            ProcessSample(
                pid: process.pid,
                name: process.name,
                residentBytes: process.residentBytes,
                cpuPercent: cpuPercent(for: process, elapsed: elapsed)
            )
        }

        baselines = Dictionary(
            processes.map { ($0.pid, Baseline(name: $0.name, cpuTimeNanoseconds: $0.cpuTimeNanoseconds)) },
            uniquingKeysWith: { _, latest in latest }
        )
        lastTimestamp = timestamp

        return select(from: samples, topCount: topCount, watchedNames: watchedNames)
    }

    private func cpuPercent(for process: RawProcess, elapsed: TimeInterval) -> Double {
        guard elapsed > 0,
              let previous = baselines[process.pid],
              previous.name == process.name,
              process.cpuTimeNanoseconds >= previous.cpuTimeNanoseconds
        else { return 0 }

        let deltaSeconds = Double(process.cpuTimeNanoseconds - previous.cpuTimeNanoseconds) / 1_000_000_000
        return deltaSeconds / elapsed * 100
    }

    private func select(from samples: [ProcessSample], topCount: Int, watchedNames: Set<String>) -> [ProcessSample] {
        let sorted = samples.sorted {
            $0.cpuPercent != $1.cpuPercent ? $0.cpuPercent > $1.cpuPercent : $0.pid < $1.pid
        }
        let top = sorted.prefix(max(topCount, 0))
        let topPids = Set(top.map(\.pid))
        let watched = sorted.filter { watchedNames.contains($0.name) && !topPids.contains($0.pid) }
        return Array(top) + watched
    }
}
