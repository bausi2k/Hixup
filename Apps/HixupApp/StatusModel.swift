import Foundation
import HixupCore
import Observation

/// Liest den Status regelmaessig aus der Datenbank, die der Agent befuellt.
@MainActor
@Observable
final class StatusModel {
    private(set) var status: SystemStatus?
    private(set) var trend: [TrendPoint] = []
    private(set) var loadError: String?

    private let service: StatusService?
    private let refreshInterval: Duration
    private var task: Task<Void, Never>?

    init(refreshInterval: Duration = .seconds(5)) {
        self.refreshInterval = refreshInterval
        do {
            try FileManager.default.createDirectory(
                at: HixupPaths.supportDirectory, withIntermediateDirectories: true
            )
            let path = HixupPaths.databaseURL.path
            service = StatusService(
                snapshots: try SQLiteSnapshotStore(path: path),
                events: try SQLiteEventStore(path: path)
            )
        } catch {
            service = nil
            loadError = error.localizedDescription
        }
        start()
    }

    var level: HealthLevel { status?.level ?? .unknown }

    func refresh() {
        guard let service else { return }
        do {
            status = try service.current()
            trend = try service.trend()
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func start() {
        refresh()
        task = Task { [weak self, refreshInterval] in
            while !Task.isCancelled {
                try? await Task.sleep(for: refreshInterval)
                self?.refresh()
            }
        }
    }
}
