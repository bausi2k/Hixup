import Foundation
import Testing
@testable import HixupCore

private final class Box<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value
    init(_ value: Value) { stored = value }
    var value: Value {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

private struct QueueSampler: SnapshotSampling {
    let snapshots: Box<[Result<Snapshot, CollectorError>]>

    init(_ items: [Result<Snapshot, CollectorError>]) { snapshots = Box(items) }

    func sample(at date: Date, settings: AgentSettings) throws -> Snapshot {
        var queue = snapshots.value
        let next = queue.removeFirst()
        snapshots.value = queue
        return try next.get()
    }
}

private final class SpyStore: SnapshotStore, @unchecked Sendable {
    let appended = Box<[Snapshot]>([])
    let purgeDates = Box<[Date]>([])

    func append(_ snapshot: Snapshot) throws { appended.value.append(snapshot) }
    func snapshots(from start: Date, to end: Date) throws -> [Snapshot] { [] }
    func sampledSnapshots(from start: Date, to end: Date, maxPoints: Int) throws -> [Snapshot] { [] }
    func purge(olderThan date: Date) throws -> Int { purgeDates.value.append(date); return 0 }
    func count() throws -> Int { appended.value.count }
}

private final class SpyEventStore: EventStore, @unchecked Sendable {
    let recorded = Box<[Alert]>([])
    let purgeDates = Box<[Date]>([])
    var failsRecording = false

    func record(_ alert: Alert) throws {
        if failsRecording { throw StorageError.queryFailed("test") }
        recorded.value.append(alert)
    }
    func alerts(from start: Date, to end: Date) throws -> [Alert] { recorded.value }
    func addMarker(_ marker: Marker) throws {}
    func markers(from start: Date, to end: Date) throws -> [Marker] { [] }
    func purge(olderThan date: Date) throws -> Int { purgeDates.value.append(date); return 0 }
}

private final class SpyNotifier: AlertNotifier, @unchecked Sendable {
    let alerts = Box<[Alert]>([])
    func notify(_ alert: Alert) async { alerts.value.append(alert) }
}

/// Wirft nach `limit` Aufrufen `CancellationError`, um die Schleife zu beenden.
private final class LimitedSleeper: Sleeper, @unchecked Sendable {
    let durations = Box<[TimeInterval]>([])
    let limit: Int
    var onSleep: (@Sendable (Int) -> Void)?

    init(limit: Int) { self.limit = limit }

    func sleep(for seconds: TimeInterval) async throws {
        durations.value.append(seconds)
        onSleep?(durations.value.count)
        if durations.value.count >= limit { throw CancellationError() }
    }
}

private func makeRunner(
    samples: [Result<Snapshot, CollectorError>],
    rules: [Rule] = [],
    store: SpyStore = SpyStore(),
    events: SpyEventStore = SpyEventStore(),
    notifier: SpyNotifier = SpyNotifier(),
    sleeper: Sleeper = LimitedSleeper(limit: 1),
    settings: @escaping @Sendable () -> AgentSettings = { .defaults },
    now: @escaping @Sendable () -> Date = { Date(timeIntervalSince1970: 0) },
    errors: Box<[String]> = Box([])
) -> AgentRunner {
    AgentRunner(
        sampler: QueueSampler(samples), store: store, events: events, engine: RuleEngine(rules: rules),
        notifier: notifier, sleeper: sleeper, loadSettings: settings, now: now,
        reportError: { errors.value.append(String(describing: $0)) }
    )
}

private let lowMemory = Rule(
    id: "memory-low", title: "Speicher knapp", severity: .critical,
    metric: .availableMemoryPercent, comparison: .below, threshold: 15,
    minimumDuration: 60, cooldown: 600
)

@Suite struct AgentRunnerTests {
    @Test func tickStoresTheSampledSnapshot() async {
        let store = SpyStore()
        let snapshot = makeSnapshot(at: 10)
        let runner = makeRunner(samples: [.success(snapshot)], store: store)

        await runner.tick()

        #expect(store.appended.value == [snapshot])
    }

    @Test func tickNotifiesAlertsRaisedByTheRuleEngine() async {
        let notifier = SpyNotifier()
        let runner = makeRunner(
            samples: [.success(makeSnapshot(at: 0, available: 5)), .success(makeSnapshot(at: 60, available: 5))],
            rules: [lowMemory], notifier: notifier
        )

        await runner.tick()
        #expect(notifier.alerts.value.isEmpty)
        await runner.tick()

        #expect(notifier.alerts.value.map(\.ruleID) == ["memory-low"])
    }

    @Test func samplerFailureIsReportedAndDoesNotStopLaterTicks() async {
        let store = SpyStore()
        let errors = Box<[String]>([])
        let runner = makeRunner(
            samples: [.failure(.systemCallFailed("host_statistics64")), .success(makeSnapshot(at: 5))],
            store: store, errors: errors
        )

        await runner.tick()
        await runner.tick()

        #expect(errors.value.count == 1)
        #expect(store.appended.value.count == 1)
    }

    @Test func purgeRunsOnFirstTickAndThenOncePerDay() async {
        let store = SpyStore()
        let clock = Box(Date(timeIntervalSince1970: 1_000_000))
        let runner = makeRunner(
            samples: (0..<4).map { .success(makeSnapshot(at: TimeInterval($0))) },
            store: store, settings: { AgentSettings(retentionDays: 14) }, now: { clock.value }
        )

        await runner.tick()
        clock.value = clock.value.addingTimeInterval(3_600)
        await runner.tick()
        clock.value = clock.value.addingTimeInterval(86_400)
        await runner.tick()

        #expect(store.purgeDates.value.count == 2)
        #expect(store.purgeDates.value.first == Date(timeIntervalSince1970: 1_000_000 - 14 * 86_400))
    }

    @Test func runUsesConfiguredIntervalAndReloadsSettingsEveryTick() async {
        let interval = Box<TimeInterval>(5)
        let sleeper = LimitedSleeper(limit: 3)
        sleeper.onSleep = { count in if count == 1 { interval.value = 10 } }
        let runner = makeRunner(
            samples: (0..<3).map { .success(makeSnapshot(at: TimeInterval($0))) },
            sleeper: sleeper, settings: { AgentSettings(sampleInterval: interval.value) }
        )

        await runner.run()

        #expect(sleeper.durations.value == [5, 10, 10])
    }

    @Test func runReturnsWhenSleepIsCancelled() async {
        let store = SpyStore()
        let runner = makeRunner(
            samples: [.success(makeSnapshot(at: 0))],
            store: store, sleeper: LimitedSleeper(limit: 1)
        )

        await runner.run()

        #expect(store.appended.value.count == 1)
    }

    @Test func raisedAlertsArePersistedInTheEventStore() async {
        let events = SpyEventStore()
        let runner = makeRunner(
            samples: [.success(makeSnapshot(at: 0, available: 5)), .success(makeSnapshot(at: 60, available: 5))],
            rules: [lowMemory], events: events
        )

        await runner.tick()
        await runner.tick()

        #expect(events.recorded.value.map(\.ruleID) == ["memory-low"])
    }

    @Test func eventStoreFailureIsReportedButTheNotificationStillGoesOut() async {
        let events = SpyEventStore()
        events.failsRecording = true
        let notifier = SpyNotifier()
        let errors = Box<[String]>([])
        let runner = makeRunner(
            samples: [.success(makeSnapshot(at: 0, available: 5)), .success(makeSnapshot(at: 60, available: 5))],
            rules: [lowMemory], events: events, notifier: notifier, errors: errors
        )

        await runner.tick()
        await runner.tick()

        #expect(errors.value.count == 1)
        #expect(notifier.alerts.value.count == 1)
    }

    @Test func retentionPurgeAlsoCoversTheEventStore() async {
        let events = SpyEventStore()
        let runner = makeRunner(
            samples: [.success(makeSnapshot(at: 0))],
            events: events, settings: { AgentSettings(retentionDays: 7) },
            now: { Date(timeIntervalSince1970: 1_000_000) }
        )

        await runner.tick()

        #expect(events.purgeDates.value == [Date(timeIntervalSince1970: 1_000_000 - 7 * 86_400)])
    }
}
