import Foundation

public protocol SnapshotSampling: Sendable {
    func sample(at date: Date, settings: AgentSettings) throws -> Snapshot
}

public protocol AlertNotifier: Sendable {
    func notify(_ alert: Alert) async
}

/// Abstraktion der Wartezeit, damit Tests ohne echte Sekunden laufen.
public protocol Sleeper: Sendable {
    func sleep(for seconds: TimeInterval) async throws
}

public struct TaskSleeper: Sleeper {
    public init() {}

    public func sleep(for seconds: TimeInterval) async throws {
        try await Task.sleep(for: .seconds(seconds))
    }
}

/// Misst Speicher und Prozesse mit den System-Collectors.
public struct SystemSnapshotSampler: SnapshotSampling {
    private let memory: MemoryCollector
    private let processes: ProcessCollector
    private let cpu: SystemCPUCollector
    private let pressure: @Sendable () -> MemoryPressureLevel

    public init(
        memory: MemoryCollector = MemoryCollector(),
        processes: ProcessCollector = ProcessCollector(),
        cpu: SystemCPUCollector = SystemCPUCollector(),
        pressure: @escaping @Sendable () -> MemoryPressureLevel = { SystemDetailProvider().memoryPressure() }
    ) {
        self.pressure = pressure
        self.memory = memory
        self.cpu = cpu
        self.processes = processes
    }

    public func sample(at date: Date, settings: AgentSettings) throws -> Snapshot {
        Snapshot(
            timestamp: date,
            memory: try memory.collect(),
            processes: try processes.collect(
                at: date,
                topCount: settings.topProcessCount,
                watchedNames: Set(settings.watchedProcessNames)
            ),
            systemCPUPercent: try cpu.collect(),
            memoryPressure: pressure()
        )
    }
}
