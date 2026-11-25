import Foundation

/// Einstellungen des Hintergrunddienstes. Fehlende oder ungueltige Werte fallen auf Standardwerte zurueck.
public struct AgentSettings: Codable, Equatable, Sendable {
    public static let defaults = AgentSettings()

    /// Sekunden zwischen zwei Messungen (1...300).
    public var sampleInterval: TimeInterval
    /// Aufbewahrungsdauer der Snapshots in Tagen (1...365).
    public var retentionDays: Int
    /// Prozesse, die unabhaengig von ihrer CPU-Last immer erfasst werden.
    public var watchedProcessNames: [String]
    /// Anzahl der Prozesse mit der hoechsten CPU-Last pro Snapshot (1...50).
    public var topProcessCount: Int
    /// Alarm, wenn der freie Speicher unter diesen Prozentwert faellt (1...90).
    public var memoryLowPercent: Double
    /// Alarm, wenn ein Prozess ueber diesem CPU-Wert (Prozent eines Kerns) liegt (50...1600).
    public var processCPUPercent: Double
    /// Alarm, wenn ein Prozess ueber dieser Leistungsaufnahme in Watt liegt (0,5...100).
    public var processEnergyWatts: Double
    /// Sekunden, die niedriger Speicher anhalten muss (10...3600).
    public var memoryMinimumSeconds: TimeInterval
    /// Sekunden, die hohe CPU-Last oder hoher Energieverbrauch anhalten muss (10...3600).
    public var loadMinimumSeconds: TimeInterval

    public init(
        sampleInterval: TimeInterval = 5,
        retentionDays: Int = 14,
        watchedProcessNames: [String] = [],
        topProcessCount: Int = 10,
        memoryLowPercent: Double = 15,
        processCPUPercent: Double = 200,
        processEnergyWatts: Double = 8,
        memoryMinimumSeconds: TimeInterval = 60,
        loadMinimumSeconds: TimeInterval = 120
    ) {
        self.memoryLowPercent = memoryLowPercent
        self.processCPUPercent = processCPUPercent
        self.processEnergyWatts = processEnergyWatts
        self.memoryMinimumSeconds = memoryMinimumSeconds
        self.loadMinimumSeconds = loadMinimumSeconds
        self.sampleInterval = sampleInterval
        self.retentionDays = retentionDays
        self.watchedProcessNames = watchedProcessNames
        self.topProcessCount = topProcessCount
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = AgentSettings.defaults
        sampleInterval = try container.decodeIfPresent(TimeInterval.self, forKey: .sampleInterval) ?? fallback.sampleInterval
        retentionDays = try container.decodeIfPresent(Int.self, forKey: .retentionDays) ?? fallback.retentionDays
        watchedProcessNames = try container.decodeIfPresent([String].self, forKey: .watchedProcessNames) ?? fallback.watchedProcessNames
        topProcessCount = try container.decodeIfPresent(Int.self, forKey: .topProcessCount) ?? fallback.topProcessCount
        memoryLowPercent = try container.decodeIfPresent(Double.self, forKey: .memoryLowPercent) ?? fallback.memoryLowPercent
        processCPUPercent = try container.decodeIfPresent(Double.self, forKey: .processCPUPercent) ?? fallback.processCPUPercent
        processEnergyWatts = try container.decodeIfPresent(Double.self, forKey: .processEnergyWatts) ?? fallback.processEnergyWatts
        memoryMinimumSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .memoryMinimumSeconds) ?? fallback.memoryMinimumSeconds
        loadMinimumSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .loadMinimumSeconds) ?? fallback.loadMinimumSeconds
    }

    public func clamped() -> AgentSettings {
        AgentSettings(
            sampleInterval: min(max(sampleInterval, 1), 300),
            retentionDays: min(max(retentionDays, 1), 365),
            watchedProcessNames: watchedProcessNames,
            topProcessCount: min(max(topProcessCount, 1), 50),
            memoryLowPercent: min(max(memoryLowPercent, 1), 90),
            processCPUPercent: min(max(processCPUPercent, 50), 1_600),
            processEnergyWatts: min(max(processEnergyWatts, 0.5), 100),
            memoryMinimumSeconds: min(max(memoryMinimumSeconds, 10), 3_600),
            loadMinimumSeconds: min(max(loadMinimumSeconds, 10), 3_600)
        )
    }

    /// Laedt und begrenzt die Einstellungen; bei fehlender oder defekter Datei gelten die Standardwerte.
    public static func load(from url: URL) -> AgentSettings {
        guard let data = try? Data(contentsOf: url),
              let settings = try? JSONDecoder().decode(AgentSettings.self, from: data)
        else { return defaults }
        return settings.clamped()
    }

    /// Zerlegt einen Freitext (Komma oder Zeilenumbruch) in eindeutige Prozessnamen.
    public static func parseWatchedNames(_ text: String) -> [String] {
        var seen = Set<String>()
        return text
            .split(whereSeparator: { $0 == "," || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}
