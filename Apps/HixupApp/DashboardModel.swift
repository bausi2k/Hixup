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
    private var task: Task<Void, Never>?

    init(refreshInterval: Duration = .seconds(10)) {
        do {
            try FileManager.default.createDirectory(
                at: HixupPaths.supportDirectory, withIntermediateDirectories: true
            )
            let path = HixupPaths.databaseURL.path
            service = HistoryService(
                snapshots: try SQLiteSnapshotStore(path: path),
                events: try SQLiteEventStore(path: path)
            )
        } catch {
            service = nil
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
