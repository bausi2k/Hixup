import Foundation

public enum Severity: String, Codable, Sendable {
    case warning
    case critical
}

public enum Comparison: String, Codable, Sendable {
    case below
    case above

    func isViolated(value: Double, threshold: Double) -> Bool {
        switch self {
        case .below: value < threshold
        case .above: value > threshold
        }
    }
}

/// Gemessener Wert einer Metrik, optional mit Verursacher (z. B. Prozessname).
struct MetricReading: Equatable {
    let value: Double
    let detail: String?
}

public enum Metric: String, Codable, Sendable {
    case availableMemoryPercent
    case highestProcessCPUPercent
    case highestProcessEnergyWatts
    case systemCPUPercent

    func reading(in snapshot: Snapshot) -> MetricReading? {
        switch self {
        case .availableMemoryPercent:
            return MetricReading(value: snapshot.memory.availablePercent, detail: nil)
        case .highestProcessCPUPercent:
            return snapshot.processes
                .max { $0.cpuPercent < $1.cpuPercent }
                .map { MetricReading(value: $0.cpuPercent, detail: $0.name) }
        case .highestProcessEnergyWatts:
            return snapshot.processes
                .max { $0.energyWatts < $1.energyWatts }
                .map { MetricReading(value: $0.energyWatts, detail: $0.name) }
        case .systemCPUPercent:
            return snapshot.systemCPUPercent.map { MetricReading(value: $0, detail: nil) }
        }
    }
}

/// Eine Bedingung, die ueber `minimumDuration` anhalten muss, bevor ein Alert entsteht.
public struct Rule: Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let severity: Severity
    public let metric: Metric
    public let comparison: Comparison
    public let threshold: Double
    public let minimumDuration: TimeInterval
    /// Mindestabstand zwischen zwei Alerts derselben Regel.
    public let cooldown: TimeInterval

    public init(
        id: String, title: String, severity: Severity,
        metric: Metric, comparison: Comparison, threshold: Double,
        minimumDuration: TimeInterval, cooldown: TimeInterval
    ) {
        self.id = id
        self.title = title
        self.severity = severity
        self.metric = metric
        self.comparison = comparison
        self.threshold = threshold
        self.minimumDuration = minimumDuration
        self.cooldown = cooldown
    }
}
