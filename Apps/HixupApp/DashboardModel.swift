import Foundation
import HixupCore
import Observation

@MainActor
@Observable
final class DashboardModel {
    var range: HistoryRange = .hour {
        didSet { if range != oldValue { refresh() } }
    }
    /// Zeitpunkt, auf den ein angeklickter Alert oder Marker in den Diagrammen zeigt.
    var focusedTime: Date?
    private(set) var history: History?
    private(set) var loadError: String?

    private let service: HistoryService?
    private let reports: MarkerReportService?
    private var task: Task<Void, Never>?

    init(refreshInterval: Duration = .seconds(10)) {
        do {
            try FileManager.default.createDirectory(
                at: HixupPaths.supportDirectory, withIntermediateDirectories: true
            )
            let path = HixupPaths.databaseURL.path
            let snapshots = try SQLiteSnapshotStore(path: path)
            let events = try SQLiteEventStore(path: path)
            service = HistoryService(snapshots: snapshots, events: events)
            reports = MarkerReportService(
                snapshots: snapshots, events: events,
                settings: { AgentSettings.load(from: HixupPaths.settingsURL) }
            )
        } catch {
            service = nil
            reports = nil
            loadError = error.localizedDescription
        }
        refresh()
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: refreshInterval)
                self?.refresh()
            }
        }
    }

    /// Markdown-Bericht fuer eine KI-Analyse der gegebenen Marker.
    func report(for markers: [Marker]) -> String? {
        try? reports?.report(for: markers)
    }

    func refresh() {
        guard let service else { return }
        let range = range
        do {
            history = try service.history(range: range)
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }
}
