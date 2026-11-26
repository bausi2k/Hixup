import Foundation

public enum HistoryRange: String, CaseIterable, Sendable {
    case hour
    case day
    case twoWeeks

    public var duration: TimeInterval {
        switch self {
        case .hour: 3_600
        case .day: 86_400
        case .twoWeeks: 14 * 86_400
        }
    }

    /// Sekunden zwischen zwei Aktualisierungen; lange Zeitraeume aendern sich kaum sichtbar.
    public var refreshInterval: TimeInterval {
        switch self {
        case .hour: 10
        case .day: 60
        case .twoWeeks: 300
        }
    }

    public var title: String {
        switch self {
        case .hour: L10n.tr("1 Std.")
        case .day: L10n.tr("24 Std.")
        case .twoWeeks: L10n.tr("14 Tage")
        }
    }
}

/// Verlauf eines Zeitraums fuer das Dashboard.
public struct History: Equatable, Sendable {
    public let range: HistoryRange
    public let points: [TrendPoint]
    public let alerts: [Alert]
    public let markers: [Marker]
    /// Verursacher ueber den gesamten Zeitraum (Mittel gleichmaessig ausgeduennter Snapshots, ohne Spitzen-Verzerrung).
    public let offenders: [Offender]
}

public struct HistoryService: Sendable {
    private let snapshots: any SnapshotStore
    private let events: any EventStore
    private let maxPoints: Int
    private let maxOffenders: Int
    /// Anzahl gleichmaessig verteilter Snapshots, aus denen die Rangliste berechnet wird; das genuegt statistisch.
    private let offenderSamples = 120

    /// - Parameter maxPoints: Obergrenze der Diagrammpunkte; laengere Zeitraeume werden ausgeduennt.
    public init(snapshots: any SnapshotStore, events: any EventStore, maxPoints: Int = 400, maxOffenders: Int = 8) {
        self.snapshots = snapshots
        self.events = events
        self.maxPoints = maxPoints
        self.maxOffenders = maxOffenders
    }

    public func history(range: HistoryRange, now: Date = Date()) throws -> History {
        let start = now.addingTimeInterval(-range.duration)
        let sampled = try snapshots.sampledSnapshots(from: start, to: now, maxPoints: min(maxPoints, offenderSamples))
        let points = try snapshots.peakPoints(from: start, to: now, maxPoints: maxPoints)
        let evaluator = StatusEvaluator(
            rules: [], offenderWindow: range.duration, staleAfter: .infinity, maxOffenders: maxOffenders
        )
        return History(
            range: range,
            points: points,
            alerts: try events.alerts(from: start, to: now),
            markers: try events.markers(from: start, to: now),
            offenders: evaluator.evaluate(snapshots: sampled, now: now).offenders
        )
    }
}
