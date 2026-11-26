import Foundation

/// Liest die Daten rund um Marker aus den Stores und erzeugt den Bericht.
public struct MarkerReportService: Sendable {
    private let snapshots: any SnapshotStore
    private let events: any EventStore
    private let settings: @Sendable () -> AgentSettings
    private let system: @Sendable () -> SystemInfo
    private let window: TimeInterval

    public init(
        snapshots: any SnapshotStore, events: any EventStore,
        settings: @escaping @Sendable () -> AgentSettings,
        system: @escaping @Sendable () -> SystemInfo = { SystemInfo.current() },
        window: TimeInterval = 300
    ) {
        self.snapshots = snapshots
        self.events = events
        self.settings = settings
        self.system = system
        self.window = window
    }

    /// Bericht fuer die gegebenen Marker; ohne Marker entsteht ein Bericht mit Hinweis.
    public func report(for markers: [Marker], language: AppLanguage? = nil, includeAssessment: Bool = true) throws -> String {
        try buildReport(markers: markers, alerts: [], language: language, includeAssessment: includeAssessment)
    }

    /// Bericht fuer ausgeloeste Alarme (jeweils ein eigener Abschnitt).
    public func report(forAlerts alerts: [Alert], language: AppLanguage? = nil, includeAssessment: Bool = true) throws -> String {
        try buildReport(markers: [], alerts: alerts, language: language, includeAssessment: includeAssessment)
    }

    private func buildReport(markers: [Marker], alerts: [Alert], language: AppLanguage?, includeAssessment: Bool) throws -> String {
        let times = markers.map(\.timestamp) + alerts.map(\.timestamp)
        let input: MarkerReportInput
        if let first = times.min(), let last = times.max() {
            let start = first.addingTimeInterval(-window)
            let end = last.addingTimeInterval(window)
            input = MarkerReportInput(
                markers: markers, snapshots: try snapshots.snapshots(from: start, to: end),
                alerts: try events.alerts(from: start, to: end), settings: settings(), system: system(),
                focusAlerts: alerts
            )
        } else {
            input = MarkerReportInput(markers: [], snapshots: [], alerts: [], settings: settings(), system: system())
        }
        return MarkerReportBuilder(language: language, window: window, includeAssessment: includeAssessment).build(input)
    }

    /// Messwerte und Einschaetzung zu einem ausgeloesten Alarm.
    public func insight(forAlert alert: Alert, language: AppLanguage? = nil) throws -> MarkerInsight {
        try insight(for: Marker(timestamp: alert.timestamp, note: nil, detail: alert.system), language: language)
    }

    /// Messwerte und Einschaetzung fuer die Detailansicht eines Markers.
    public func insight(for marker: Marker, language: AppLanguage? = nil) throws -> MarkerInsight {
        let start = marker.timestamp.addingTimeInterval(-window)
        let end = marker.timestamp.addingTimeInterval(window)
        let inWindow = try snapshots.snapshots(from: start, to: end)
        return MarkerInsight(
            marker: marker,
            metrics: MarkerMetrics.compute(marker: marker, snapshots: inWindow),
            findings: MarkerDiagnosis(language: language, window: window)
                .findings(marker: marker, snapshots: inWindow, settings: settings()),
            sampleCount: inWindow.count
        )
    }
}

public struct MarkerInsight: Sendable {
    public let marker: Marker
    public let metrics: MarkerMetrics
    public let findings: [DiagnosisFinding]
    public let sampleCount: Int
}
