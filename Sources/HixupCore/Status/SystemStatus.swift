import Foundation

public enum HealthLevel: String, Codable, Sendable, Comparable {
    /// Keine aktuellen Daten, z. B. weil der Hintergrunddienst nicht laeuft.
    case unknown
    case ok
    case warning
    case critical

    private var rank: Int {
        switch self {
        case .unknown: 0
        case .ok: 1
        case .warning: 2
        case .critical: 3
        }
    }

    public static func < (lhs: HealthLevel, rhs: HealthLevel) -> Bool { lhs.rank < rhs.rank }
}

/// Eine Regel, die im neuesten Snapshot gerade verletzt ist.
public struct ActiveViolation: Equatable, Sendable {
    public let ruleID: String
    public let title: String
    public let severity: Severity
    public let metric: Metric
    public let value: Double
    public let threshold: Double
    public let comparison: Comparison
    /// Verursacher, z. B. der Prozessname.
    public let detail: String?
    /// Beginn der aktuellen ununterbrochenen Verletzung.
    public let since: Date
    public let duration: TimeInterval
    public let minimumDuration: TimeInterval
    /// `true`, sobald die Verletzung die Mindestdauer der Regel erreicht hat (dann hebt sie den Gesamtstatus an).
    public let isSustained: Bool
}

public enum OffenderReason: String, Codable, Sendable, CaseIterable {
    case cpu
    case energy
    case memory
    case wakeups
}

/// Referenzwerte, ab denen ein Prozess als auffaellig gilt; zugleich Skala fuer die Rangliste.
public struct OffenderThresholds: Equatable, Sendable {
    public var cpuPercent: Double
    public var energyWatts: Double
    public var residentBytes: UInt64
    public var wakeupsPerSecond: Double

    public init(
        cpuPercent: Double = 150,
        energyWatts: Double = 5,
        residentBytes: UInt64 = 4 * 1_073_741_824,
        wakeupsPerSecond: Double = 1_000
    ) {
        self.cpuPercent = cpuPercent
        self.energyWatts = energyWatts
        self.residentBytes = residentBytes
        self.wakeupsPerSecond = wakeupsPerSecond
    }

    public static let defaults = OffenderThresholds()
}

/// Prozessgruppe (gleicher Name) mit ihrer Belastung ueber das Beobachtungsfenster.
public struct Offender: Equatable, Sendable {
    public let name: String
    public let processCount: Int
    public let cpuPercent: Double
    public let energyWatts: Double
    public let wakeupsPerSecond: Double
    public let residentBytes: UInt64
    /// Summe der Verhaeltnisse zu den Referenzwerten; je hoeher, desto staerker belastet der Prozess das System.
    public let score: Double
    /// Metriken, die ihre Referenzwerte erreichen oder ueberschreiten.
    public let reasons: [OffenderReason]
}

extension Offender: Identifiable {
    public var id: String { name }
}

public struct SystemStatus: Equatable, Sendable {
    public let level: HealthLevel
    /// Zeitstempel des neuesten Snapshots.
    public let timestamp: Date?
    public let memory: MemorySample?
    public let violations: [ActiveViolation]
    public let offenders: [Offender]
    /// Zuletzt ausgeloeste Alerts, neueste zuerst.
    public let recentAlerts: [Alert]
}
