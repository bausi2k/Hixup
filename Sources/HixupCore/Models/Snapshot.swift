import Foundation

/// Ein Messzeitpunkt: Speicherwerte plus ausgewaehlte Prozesse. Einheit der Speicherung.
public struct Snapshot: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let memory: MemorySample
    public let processes: [ProcessSample]

    public init(timestamp: Date, memory: MemorySample, processes: [ProcessSample]) {
        self.timestamp = timestamp
        self.memory = memory
        self.processes = processes
    }
}
