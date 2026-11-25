import Foundation

/// Ein Messzeitpunkt: Speicherwerte plus ausgewaehlte Prozesse. Einheit der Speicherung.
public struct Snapshot: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let memory: MemorySample
    public let processes: [ProcessSample]
    /// Gesamtauslastung aller Kerne in Prozent (0...100); `nil` bei der ersten Messung und in alten Snapshots.
    public let systemCPUPercent: Double?

    public init(timestamp: Date, memory: MemorySample, processes: [ProcessSample], systemCPUPercent: Double? = nil) {
        self.systemCPUPercent = systemCPUPercent
        self.timestamp = timestamp
        self.memory = memory
        self.processes = processes
    }
}
