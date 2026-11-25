/// Aufbereitete Speichermesswerte eines Zeitpunkts.
public struct MemorySample: Codable, Equatable, Sendable {
    public let totalBytes: UInt64
    public let usedBytes: UInt64
    public let compressedBytes: UInt64
    /// Anteil des Speichers, der ohne Verdraengung sofort verfuegbar ist (0...100).
    public let availablePercent: Double

    public init(totalBytes: UInt64, usedBytes: UInt64, compressedBytes: UInt64, availablePercent: Double) {
        self.totalBytes = totalBytes
        self.usedBytes = usedBytes
        self.compressedBytes = compressedBytes
        self.availablePercent = availablePercent
    }
}

/// Aufbereitete Prozesswerte eines Zeitpunkts.
public struct ProcessSample: Codable, Equatable, Sendable {
    public let pid: Int32
    public let name: String
    public let residentBytes: UInt64
    /// Prozent eines Kerns; Mehrkernlast kann ueber 100 liegen.
    public let cpuPercent: Double
    /// Vom System geschaetzte Leistungsaufnahme in Watt ("Energie-Einfluss"), kein Messgeraet.
    public let energyWatts: Double
    /// Aufweck-Ereignisse pro Sekunde (Idle-Wakeups + Interrupts).
    public let wakeupsPerSecond: Double

    public init(
        pid: Int32, name: String, residentBytes: UInt64, cpuPercent: Double,
        energyWatts: Double = 0, wakeupsPerSecond: Double = 0
    ) {
        self.pid = pid
        self.name = name
        self.residentBytes = residentBytes
        self.cpuPercent = cpuPercent
        self.energyWatts = energyWatts
        self.wakeupsPerSecond = wakeupsPerSecond
    }

    /// Aeltere gespeicherte Snapshots kennen Energie und Wakeups nicht; sie gelten als 0.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pid = try container.decode(Int32.self, forKey: .pid)
        name = try container.decode(String.self, forKey: .name)
        residentBytes = try container.decode(UInt64.self, forKey: .residentBytes)
        cpuPercent = try container.decode(Double.self, forKey: .cpuPercent)
        energyWatts = try container.decodeIfPresent(Double.self, forKey: .energyWatts) ?? 0
        wakeupsPerSecond = try container.decodeIfPresent(Double.self, forKey: .wakeupsPerSecond) ?? 0
    }
}
