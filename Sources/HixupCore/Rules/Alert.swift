import Foundation

public struct Alert: Codable, Equatable, Sendable {
    public let ruleID: String
    public let title: String
    public let severity: Severity
    public let value: Double
    public let threshold: Double
    /// Verursacher, z. B. der Prozessname bei CPU-Regeln.
    public let detail: String?
    public let timestamp: Date
}
