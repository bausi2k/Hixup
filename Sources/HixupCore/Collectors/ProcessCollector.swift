import Foundation

public struct RawProcess: Equatable, Sendable {
    public var pid: Int32
    public var name: String
    public var residentBytes: UInt64
    /// Kumulierte CPU-Zeit (User + System) in Nanosekunden.
    public var cpuTimeNanoseconds: UInt64
    /// Kumulierte, vom System geschaetzte Energie in Nanojoule.
    public var energyNanojoules: UInt64
    /// Kumulierte Aufweck-Ereignisse (Idle-Wakeups + Interrupts).
    public var wakeups: UInt64

    public init(
        pid: Int32, name: String, residentBytes: UInt64, cpuTimeNanoseconds: UInt64,
        energyNanojoules: UInt64 = 0, wakeups: UInt64 = 0
    ) {
        self.pid = pid
        self.name = name
        self.residentBytes = residentBytes
        self.cpuTimeNanoseconds = cpuTimeNanoseconds
        self.energyNanojoules = energyNanojoules
        self.wakeups = wakeups
    }
}

public protocol ProcessListing: Sendable {
    func list() throws -> [RawProcess]
}

/// Berechnet CPU-, Energie- und Wakeup-Raten pro Prozess aus der Differenz zweier Messungen.
public final class ProcessCollector: @unchecked Sendable {
    private struct Rates {
        var cpuPercent = 0.0
        var energyWatts = 0.0
        var wakeupsPerSecond = 0.0
    }

    private let lister: any ProcessListing
    private let lock = NSLock()
    private var baselines: [Int32: RawProcess] = [:]
    private var lastTimestamp: Date?

    public init(lister: any ProcessListing = SystemProcessLister()) {
        self.lister = lister
    }

    /// - Parameters:
    ///   - topCount: Anzahl der Prozesse mit der hoechsten CPU-Last bzw. dem hoechsten Energieverbrauch.
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
            let rates = rates(for: process, elapsed: elapsed)
            return ProcessSample(
                pid: process.pid,
                name: process.name,
                residentBytes: process.residentBytes,
                cpuPercent: rates.cpuPercent,
                energyWatts: rates.energyWatts,
                wakeupsPerSecond: rates.wakeupsPerSecond
            )
        }

        baselines = Dictionary(processes.map { ($0.pid, $0) }, uniquingKeysWith: { _, latest in latest })
        lastTimestamp = timestamp

        return select(from: samples, topCount: topCount, watchedNames: watchedNames)
    }

    private func rates(for process: RawProcess, elapsed: TimeInterval) -> Rates {
        guard elapsed > 0,
              let previous = baselines[process.pid],
              previous.name == process.name,
              process.cpuTimeNanoseconds >= previous.cpuTimeNanoseconds
        else { return Rates() }

        let cpuSeconds = Double(process.cpuTimeNanoseconds - previous.cpuTimeNanoseconds) / 1_000_000_000
        let energyJoules = Double(delta(process.energyNanojoules, previous.energyNanojoules)) / 1_000_000_000
        let wakeups = Double(delta(process.wakeups, previous.wakeups))

        return Rates(
            cpuPercent: cpuSeconds / elapsed * 100,
            energyWatts: energyJoules / elapsed,
            wakeupsPerSecond: wakeups / elapsed
        )
    }

    /// Differenz zweier Zaehlerstaende; ein rueckwaerts laufender Zaehler zaehlt als 0.
    private func delta(_ current: UInt64, _ previous: UInt64) -> UInt64 {
        current >= previous ? current - previous : 0
    }

    /// Top-N nach CPU, dazu Top-N nach Energie (nur Prozesse mit Verbrauch) und alle beobachteten Prozesse.
    private func select(from samples: [ProcessSample], topCount: Int, watchedNames: Set<String>) -> [ProcessSample] {
        let limit = max(topCount, 0)
        let byCPU = samples.sorted {
            $0.cpuPercent != $1.cpuPercent ? $0.cpuPercent > $1.cpuPercent : $0.pid < $1.pid
        }
        let topCPU = Array(byCPU.prefix(limit))
        var selected = Set(topCPU.map(\.pid))

        let topEnergy = samples
            .filter { $0.energyWatts > 0 && !selected.contains($0.pid) }
            .sorted { $0.energyWatts != $1.energyWatts ? $0.energyWatts > $1.energyWatts : $0.pid < $1.pid }
            .prefix(limit)
        selected.formUnion(topEnergy.map(\.pid))

        let watched = byCPU.filter { watchedNames.contains($0.name) && !selected.contains($0.pid) }
        return topCPU + topEnergy + watched
    }
}
