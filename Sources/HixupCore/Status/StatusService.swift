import Foundation

/// Ein Punkt der Verlaufsgrafik: Summe der erfassten Prozesslast je Snapshot.
public struct TrendPoint: Equatable, Sendable {
    public let timestamp: Date
    public let availableMemoryPercent: Double
    public let cpuPercent: Double
    public let energyWatts: Double
}

/// Liest Snapshots und Events aus den Stores und liefert den aktuellen Status samt Verlauf.
public struct StatusService: Sendable {
    private let snapshots: any SnapshotStore
    private let events: any EventStore
    private let evaluator: StatusEvaluator
    private let lookback: TimeInterval
    private let alertHistory: TimeInterval

    /// - Parameters:
    ///   - lookback: So viele Sekunden Snapshots fliessen in die Bewertung ein.
    ///   - alertHistory: So viele Sekunden zurueck werden ausgeloeste Alerts angezeigt.
    public init(
        snapshots: any SnapshotStore, events: any EventStore,
        evaluator: StatusEvaluator = StatusEvaluator(),
        lookback: TimeInterval = 600, alertHistory: TimeInterval = 86_400
    ) {
        self.snapshots = snapshots
        self.events = events
        self.evaluator = evaluator
        self.lookback = lookback
        self.alertHistory = alertHistory
    }

    public func current(now: Date = Date()) throws -> SystemStatus {
        let recent = try snapshots.snapshots(from: now.addingTimeInterval(-lookback), to: now)
        let alerts = try events.alerts(from: now.addingTimeInterval(-alertHistory), to: now)
        return evaluator.evaluate(snapshots: recent, recentAlerts: alerts, now: now)
    }

    public func trend(now: Date = Date(), window: TimeInterval = 600) throws -> [TrendPoint] {
        try snapshots.snapshots(from: now.addingTimeInterval(-window), to: now).map { snapshot in
            TrendPoint(
                timestamp: snapshot.timestamp,
                availableMemoryPercent: snapshot.memory.availablePercent,
                cpuPercent: snapshot.processes.reduce(0) { $0 + $1.cpuPercent },
                energyWatts: snapshot.processes.reduce(0) { $0 + $1.energyWatts }
            )
        }
    }
}
