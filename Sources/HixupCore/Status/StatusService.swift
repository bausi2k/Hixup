import Foundation

/// Ein Punkt der Verlaufsgrafik: Summe der erfassten Prozesslast je Snapshot.
public struct TrendPoint: Equatable, Sendable {
    public let timestamp: Date
    public let availableMemoryPercent: Double
    public let cpuPercent: Double
    public let energyWatts: Double
    /// Gesamtauslastung aller Kerne (0...100); `nil` in aelteren Snapshots.
    public let systemCPUPercent: Double?

    init(
        timestamp: Date, availableMemoryPercent: Double, cpuPercent: Double, energyWatts: Double,
        systemCPUPercent: Double?
    ) {
        self.timestamp = timestamp
        self.availableMemoryPercent = availableMemoryPercent
        self.cpuPercent = cpuPercent
        self.energyWatts = energyWatts
        self.systemCPUPercent = systemCPUPercent
    }

    init(snapshot: Snapshot) {
        timestamp = snapshot.timestamp
        availableMemoryPercent = snapshot.memory.availablePercent
        cpuPercent = snapshot.processes.reduce(0) { $0 + $1.cpuPercent }
        energyWatts = snapshot.processes.reduce(0) { $0 + $1.energyWatts }
        systemCPUPercent = snapshot.systemCPUPercent
    }
}

/// Liest Snapshots und Events aus den Stores und liefert den aktuellen Status samt Verlauf.
public struct StatusService: Sendable {
    private let snapshots: any SnapshotStore
    private let events: any EventStore
    private let evaluatorProvider: @Sendable () -> StatusEvaluator
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
        self.init(
            snapshots: snapshots, events: events, evaluatorProvider: { evaluator },
            lookback: lookback, alertHistory: alertHistory
        )
    }

    /// - Parameter evaluatorProvider: Wird bei jeder Abfrage aufgerufen, z. B. um geaenderte Regeln zu uebernehmen.
    public init(
        snapshots: any SnapshotStore, events: any EventStore,
        evaluatorProvider: @escaping @Sendable () -> StatusEvaluator,
        lookback: TimeInterval = 600, alertHistory: TimeInterval = 86_400
    ) {
        self.snapshots = snapshots
        self.events = events
        self.evaluatorProvider = evaluatorProvider
        self.lookback = lookback
        self.alertHistory = alertHistory
    }

    /// Status und Verlauf aus einem einzigen Lesevorgang; spart gegenueber `current` plus `trend` das doppelte
    /// Dekodieren derselben Snapshots.
    public func overview(now: Date = Date(), trendWindow: TimeInterval = 600) throws -> (status: SystemStatus, trend: [TrendPoint]) {
        let recent = try snapshots.snapshots(from: now.addingTimeInterval(-max(lookback, trendWindow)), to: now)
        let alerts = try events.alerts(from: now.addingTimeInterval(-alertHistory), to: now)
        let status = evaluatorProvider().evaluate(
            snapshots: recent.filter { $0.timestamp >= now.addingTimeInterval(-lookback) },
            recentAlerts: alerts, now: now
        )
        let trend = recent.filter { $0.timestamp >= now.addingTimeInterval(-trendWindow) }.map(TrendPoint.init(snapshot:))
        return (status, trend)
    }

    public func current(now: Date = Date()) throws -> SystemStatus {
        let recent = try snapshots.snapshots(from: now.addingTimeInterval(-lookback), to: now)
        let alerts = try events.alerts(from: now.addingTimeInterval(-alertHistory), to: now)
        return evaluatorProvider().evaluate(snapshots: recent, recentAlerts: alerts, now: now)
    }

    public func trend(now: Date = Date(), window: TimeInterval = 600) throws -> [TrendPoint] {
        try snapshots.snapshots(from: now.addingTimeInterval(-window), to: now).map(TrendPoint.init(snapshot:))
    }
}
