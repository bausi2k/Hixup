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
    private let recorder: MarkerRecorder?
    private let refreshInterval: Duration
    private var task: Task<Void, Never>?

    init(refreshInterval: Duration = .seconds(5)) {
        self.refreshInterval = refreshInterval
        do {
            try FileManager.default.createDirectory(
                at: HixupPaths.supportDirectory, withIntermediateDirectories: true
            )
            let path = HixupPaths.databaseURL.path
            let events = try SQLiteEventStore(path: path)
            service = StatusService(
                snapshots: try SQLiteSnapshotStore(path: path), events: events,
                evaluatorProvider: {
                    StatusEvaluator(rules: DefaultRules.rules(for: AgentSettings.load(from: HixupPaths.settingsURL)))
                }
            )
            recorder = MarkerRecorder(events: events, detail: SystemDetailCollector())
        } catch {
            service = nil
            recorder = nil
            loadError = error.localizedDescription
        }
        start()
    }

    var level: HealthLevel { status?.level ?? .unknown }

    func addMarker() {
        do {
            if let recorder {
                let marker = try recorder.mark()
                Task { await recorder.attachDetail(to: marker) }
            }
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

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
