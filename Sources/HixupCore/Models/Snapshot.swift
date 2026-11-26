import Foundation

/// Ein Messzeitpunkt: Speicherwerte plus ausgewaehlte Prozesse. Einheit der Speicherung.
public struct Snapshot: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let memory: MemorySample
    public let processes: [ProcessSample]
    /// Gesamtauslastung aller Kerne in Prozent (0...100); `nil` bei der ersten Messung und in alten Snapshots.
    public let systemCPUPercent: Double?
    /// Speicherdruck des Systems; `nil` in aelteren Snapshots.
    public let memoryPressure: MemoryPressureLevel?

    public init(
        timestamp: Date, memory: MemorySample, processes: [ProcessSample], systemCPUPercent: Double? = nil,
        memoryPressure: MemoryPressureLevel? = nil
    ) {
        self.memoryPressure = memoryPressure
        self.systemCPUPercent = systemCPUPercent
        self.timestamp = timestamp
        self.memory = memory
        self.processes = processes
    }
}

extension Snapshot {
    /// Grobe Gesamtbelastung zum Auswaehlen von Spitzen: CPU (100 % = ein Kern), Energie und Speicherdruck.
    var loadScore: Double {
        let cpu = systemCPUPercent ?? processes.reduce(0) { $0 + $1.cpuPercent }
        let energy = processes.reduce(0) { $0 + $1.energyWatts }
        return cpu / 100 + energy / 10 + (100 - memory.availablePercent) / 100 + (memoryPressure?.numeric ?? 0) / 2
    }
}
