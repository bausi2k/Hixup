import Foundation

/// Kern des Hintergrunddienstes: messen, speichern, Regeln auswerten, benachrichtigen.
public actor AgentRunner {
    private static let purgeInterval: TimeInterval = 86_400

    private let sampler: any SnapshotSampling
    private let store: any SnapshotStore
    private let events: any EventStore
    private let engine: RuleEngine
    private let rulesForSettings: (@Sendable (AgentSettings) -> [Rule])?
    private let notifier: any AlertNotifier
    private let sleeper: any Sleeper
    private let loadSettings: @Sendable () -> AgentSettings
    private let now: @Sendable () -> Date
    private let reportError: @Sendable (Error) -> Void
    private var lastPurge: Date?

    public init(
        sampler: any SnapshotSampling,
        store: any SnapshotStore,
        events: any EventStore,
        engine: RuleEngine,
        rulesForSettings: (@Sendable (AgentSettings) -> [Rule])? = nil,
        notifier: any AlertNotifier,
        sleeper: any Sleeper = TaskSleeper(),
        loadSettings: @escaping @Sendable () -> AgentSettings,
        now: @escaping @Sendable () -> Date = { Date() },
        reportError: @escaping @Sendable (Error) -> Void
    ) {
        self.sampler = sampler
        self.store = store
        self.events = events
        self.engine = engine
        self.rulesForSettings = rulesForSettings
        self.notifier = notifier
        self.sleeper = sleeper
        self.loadSettings = loadSettings
        self.now = now
        self.reportError = reportError
    }

    /// Laeuft, bis der umgebende Task abgebrochen wird. Einstellungen werden bei jedem Durchlauf neu geladen.
    public func run() async {
        while !Task.isCancelled {
            await tick()
            do {
                try await sleeper.sleep(for: loadSettings().sampleInterval)
            } catch {
                return
            }
        }
    }

    /// Ein Durchlauf. Fehler werden gemeldet und beenden den Dienst nicht.
    public func tick() async {
        let settings = loadSettings()
        let date = now()

        if let rulesForSettings { engine.update(rules: rulesForSettings(settings)) }
        purgeIfDue(at: date, retentionDays: settings.retentionDays)

        let snapshot: Snapshot
        do {
            snapshot = try sampler.sample(at: date, settings: settings)
        } catch {
            reportError(error)
            return
        }

        do {
            try store.append(snapshot)
        } catch {
            reportError(error)
        }

        for alert in engine.evaluate(snapshot) {
            do {
                try events.record(alert)
            } catch {
                reportError(error)
            }
            await notifier.notify(alert)
        }
    }

    private func purgeIfDue(at date: Date, retentionDays: Int) {
        if let lastPurge, date.timeIntervalSince(lastPurge) < Self.purgeInterval { return }
        lastPurge = date
        let cutoff = date.addingTimeInterval(-Double(retentionDays) * 86_400)
        do {
            try store.purge(olderThan: cutoff)
            try events.purge(olderThan: cutoff)
        } catch {
            reportError(error)
        }
    }
}
