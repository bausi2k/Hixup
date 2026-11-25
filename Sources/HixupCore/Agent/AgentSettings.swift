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

    public init(
        sampleInterval: TimeInterval = 5,
        retentionDays: Int = 14,
        watchedProcessNames: [String] = [],
        topProcessCount: Int = 10
    ) {
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
    }

    public func clamped() -> AgentSettings {
        AgentSettings(
            sampleInterval: min(max(sampleInterval, 1), 300),
            retentionDays: min(max(retentionDays, 1), 365),
            watchedProcessNames: watchedProcessNames,
            topProcessCount: min(max(topProcessCount, 1), 50)
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
