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
    private let recorder: MarkerRecorder?
    private var task: Task<Void, Never>?
    private var isVisible = false
    private var isRefreshing = false
    private var needsRefresh = false

    init() {
        do {
            try FileManager.default.createDirectory(
                at: HixupPaths.supportDirectory, withIntermediateDirectories: true
            )
            let path = HixupPaths.databaseURL.path
            let snapshots = try SQLiteSnapshotStore(path: path)
            let events = try SQLiteEventStore(path: path)
            service = HistoryService(snapshots: snapshots, events: events)
            recorder = MarkerRecorder(events: events)
            reports = MarkerReportService(
                snapshots: snapshots, events: events,
                settings: { AgentSettings.load(from: HixupPaths.settingsURL) }
            )
        } catch {
            service = nil
            reports = nil
            recorder = nil
            loadError = error.localizedDescription
        }
        task = Task { [weak self] in
            while !Task.isCancelled {
                let seconds = self?.range.refreshInterval ?? 10
                try? await Task.sleep(for: .seconds(seconds))
                self?.refresh()
            }
        }
    }

    /// Sichtbar: ab jetzt wird gelesen und aktualisiert. Unsichtbar: nichts mehr lesen, Verlaufsdaten freigeben.
    func setVisible(_ visible: Bool) {
        isVisible = visible
        if visible { refresh() } else { history = nil }
    }

    /// Markdown-Bericht fuer eine KI-Analyse der gegebenen Marker.
    func report(for markers: [Marker], includeAssessment: Bool = true) -> String? {
        try? reports?.report(for: markers, includeAssessment: includeAssessment)
    }

    /// Speichert die Notiz eines Markers; gibt den aktualisierten Marker zurueck.
    func updateNote(_ text: String?, for marker: Marker) -> Marker? {
        guard let updated = try? recorder?.updateNote(text, for: marker) else { return nil }
        refresh()
        return updated
    }

    func insight(for marker: Marker) -> MarkerInsight? {
        try? reports?.insight(for: marker)
    }

    /// Liest im Hintergrund; nur solange das Fenster sichtbar ist.
    func refresh() {
        guard isVisible, let service else { return }
        if isRefreshing {
            needsRefresh = true
            return
        }
        isRefreshing = true
        let range = range
        Task { [weak self] in
            let result = await Task.detached(priority: .utility) { Result { try service.history(range: range) } }.value
            self?.apply(result, range: range)
        }
    }

    private func apply(_ result: Result<History, Error>, range: HistoryRange) {
        isRefreshing = false
        if isVisible, range == self.range {
            switch result {
            case .success(let value):
                if history != value { history = value }
                if loadError != nil { loadError = nil }
            case .failure(let error):
                loadError = error.localizedDescription
            }
        }
        if needsRefresh {
            needsRefresh = false
            refresh()
        }
    }
}
