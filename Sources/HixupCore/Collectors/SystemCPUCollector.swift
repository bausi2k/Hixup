import Foundation

/// Kumulierte CPU-Ticks aller Kerne.
public struct RawCPUTicks: Equatable, Sendable {
    public var busy: UInt64
    public var total: UInt64

    public init(busy: UInt64, total: UInt64) {
        self.busy = busy
        self.total = total
    }
}

public protocol CPUTicksProviding: Sendable {
    func read() throws -> RawCPUTicks
}

/// Gesamtauslastung aus der Differenz zweier Tick-Messungen. Enthaelt auch Last, die keinem
/// erfassten Prozess zugeordnet ist, etwa `kernel_task`.
public final class SystemCPUCollector: @unchecked Sendable {
    private let provider: any CPUTicksProviding
    private let lock = NSLock()
    private var baseline: RawCPUTicks?

    public init(provider: any CPUTicksProviding = MachCPUTicksProvider()) {
        self.provider = provider
    }

    /// - Returns: Prozent (0...100) seit der letzten Messung, `nil` ohne Vergleichswert.
    public func collect() throws -> Double? {
        let current = try provider.read()
        lock.lock()
        defer { lock.unlock() }
        defer { baseline = current }

        guard let baseline, current.total > baseline.total, current.busy >= baseline.busy else { return nil }
        let percent = Double(current.busy - baseline.busy) / Double(current.total - baseline.total) * 100
        return min(max(percent, 0), 100)
    }
}
