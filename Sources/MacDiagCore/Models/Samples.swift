/// Aufbereitete Speichermesswerte eines Zeitpunkts.
public struct MemorySample: Codable, Equatable, Sendable {
    public let totalBytes: UInt64
    public let usedBytes: UInt64
    public let compressedBytes: UInt64
    /// Anteil des Speichers, der ohne Verdraengung sofort verfuegbar ist (0...100).
    public let availablePercent: Double
}

/// Aufbereitete Prozesswerte eines Zeitpunkts.
public struct ProcessSample: Codable, Equatable, Sendable {
    public let pid: Int32
    public let name: String
    public let residentBytes: UInt64
    /// Prozent eines Kerns; Mehrkernlast kann ueber 100 liegen.
    public let cpuPercent: Double
}
