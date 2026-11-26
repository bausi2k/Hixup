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
    private let idleInterval: Duration
    private var task: Task<Void, Never>?
    private var activeSources = Set<String>()
    private var isRefreshing = false

    /// - Parameters:
    ///   - refreshInterval: Takt, solange Popover oder Dashboard sichtbar sind.
    ///   - idleInterval: Seltenerer Takt nur fuer das Menueleisten-Symbol.
    init(refreshInterval: Duration = .seconds(5), idleInterval: Duration = .seconds(20)) {
        self.refreshInterval = refreshInterval
        self.idleInterval = idleInterval
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

    /// Meldet, ob eine Ansicht (z. B. "popover" oder "dashboard") sichtbar ist; solange mindestens eine
    /// sichtbar ist, gilt der schnelle Takt.
    func setActive(_ active: Bool, source: String) {
        let wasIdle = activeSources.isEmpty
        if active { activeSources.insert(source) } else { activeSources.remove(source) }
        if wasIdle && !activeSources.isEmpty { refresh() }
    }

    /// Liest im Hintergrund, damit das Dekodieren der Snapshots die Oberflaeche nicht blockiert.
    func refresh() {
        guard let service, !isRefreshing else { return }
        isRefreshing = true
        Task { [weak self] in
            let result = await Task.detached(priority: .utility) { Result { try service.overview() } }.value
            self?.apply(result)
        }
    }

    private func apply(_ result: Result<(status: SystemStatus, trend: [TrendPoint]), Error>) {
        isRefreshing = false
        switch result {
        case .success(let overview):
            // Unveraenderte Werte nicht neu zuweisen: jede Zuweisung loest eine Neuberechnung der Ansichten aus.
            if status != overview.status { status = overview.status }
            if trend != overview.trend { trend = overview.trend }
            if loadError != nil { loadError = nil }
        case .failure(let error):
            loadError = error.localizedDescription
        }
    }

    private var currentInterval: Duration { activeSources.isEmpty ? idleInterval : refreshInterval }

    private func start() {
        refresh()
        task = Task { [weak self] in
            while !Task.isCancelled {
                let interval = self?.currentInterval ?? .seconds(20)
                try? await Task.sleep(for: interval)
                self?.refresh()
            }
        }
    }
}
