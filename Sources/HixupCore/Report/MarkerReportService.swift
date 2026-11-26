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
    public func report(for markers: [Marker], language: AppLanguage? = nil) throws -> String {
        let input: MarkerReportInput
        if let first = markers.map(\.timestamp).min(), let last = markers.map(\.timestamp).max() {
            let start = first.addingTimeInterval(-window)
            let end = last.addingTimeInterval(window)
            input = MarkerReportInput(
                markers: markers, snapshots: try snapshots.snapshots(from: start, to: end),
                alerts: try events.alerts(from: start, to: end), settings: settings(), system: system()
            )
        } else {
            input = MarkerReportInput(markers: [], snapshots: [], alerts: [], settings: settings(), system: system())
        }
        return MarkerReportBuilder(language: language, window: window).build(input)
    }
}
