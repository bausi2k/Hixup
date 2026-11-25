import Foundation
import Testing
@testable import HixupCore

private final class StubCPUProvider: CPUTicksProviding, @unchecked Sendable {
    private var queue: [RawCPUTicks]
    init(_ ticks: [RawCPUTicks]) { queue = ticks }
    func read() throws -> RawCPUTicks { queue.removeFirst() }
}

@Suite struct SystemCPUCollectorTests {
    @Test func firstCollectionHasNoBaseline() throws {
        let collector = SystemCPUCollector(provider: StubCPUProvider([RawCPUTicks(busy: 100, total: 1_000)]))
        #expect(try collector.collect() == nil)
    }

    @Test func percentIsBusyDeltaOverTotalDelta() throws {
        let collector = SystemCPUCollector(provider: StubCPUProvider([
            RawCPUTicks(busy: 100, total: 1_000),
            RawCPUTicks(busy: 400, total: 2_000)
        ]))
        _ = try collector.collect()

        #expect(try collector.collect() == 30)
    }

    @Test func noElapsedTicksYieldsNil() throws {
        let same = RawCPUTicks(busy: 5, total: 50)
        let collector = SystemCPUCollector(provider: StubCPUProvider([same, same]))
        _ = try collector.collect()

        #expect(try collector.collect() == nil)
    }

    @Test func resultIsClampedToValidRange() throws {
        let collector = SystemCPUCollector(provider: StubCPUProvider([
            RawCPUTicks(busy: 0, total: 0),
            RawCPUTicks(busy: 500, total: 100)
        ]))
        _ = try collector.collect()

        #expect(try collector.collect() == 100)
    }

    @Test func systemProviderReturnsGrowingCounters() throws {
        let provider = MachCPUTicksProvider()
        let first = try provider.read()
        var spin = 0.0
        let end = Date().addingTimeInterval(0.1)
        while Date() < end { spin += sin(spin) + 1 }
        let second = try provider.read()

        #expect(spin > 0)
        #expect(second.total >= first.total)
        #expect(second.busy >= first.busy)
    }
}

@Suite struct SystemCPUMetricTests {
    private let rule = DefaultRules.cpuSystemHigh

    @Test func snapshotStoresSystemCPUAndOldJSONStillDecodes() throws {
        let snapshot = Snapshot(
            timestamp: Date(timeIntervalSince1970: 1), memory: makeSnapshot(at: 1).memory,
            processes: [], systemCPUPercent: 42
        )
        let decoded = try JSONDecoder().decode(Snapshot.self, from: JSONEncoder().encode(snapshot))
        #expect(decoded.systemCPUPercent == 42)

        let legacy = try JSONEncoder().encode(makeSnapshot(at: 1))
        #expect(try JSONDecoder().decode(Snapshot.self, from: legacy).systemCPUPercent == nil)
    }

    @Test func ruleFiresAfterMinimumDurationOfHighTotalLoad() {
        let engine = RuleEngine(rules: [rule])
        func load(_ percent: Double?, at time: TimeInterval) -> Snapshot {
            let base = makeSnapshot(at: time)
            return Snapshot(timestamp: base.timestamp, memory: base.memory, processes: [], systemCPUPercent: percent)
        }

        _ = engine.evaluate(load(95, at: 0))
        let alerts = engine.evaluate(load(95, at: rule.minimumDuration))

        #expect(alerts.map(\.ruleID) == ["cpu-system-high"])
    }

    @Test func snapshotWithoutSystemCPUNeverViolatesTheRule() {
        let engine = RuleEngine(rules: [rule])
        _ = engine.evaluate(makeSnapshot(at: 0))
        #expect(engine.evaluate(makeSnapshot(at: 1_000)).isEmpty)
    }

    @Test func thresholdComesFromSettingsAndIsClamped() {
        var settings = AgentSettings.defaults
        settings.systemCPUPercent = 75
        #expect(DefaultRules.rules(for: settings).first { $0.id == "cpu-system-high" }?.threshold == 75)

        settings.systemCPUPercent = 5
        #expect(settings.clamped().systemCPUPercent == 30)
    }

    @Test func trendPointCarriesSystemCPU() {
        let base = makeSnapshot(at: 1)
        let snapshot = Snapshot(timestamp: base.timestamp, memory: base.memory, processes: [], systemCPUPercent: 61)
        #expect(TrendPoint(snapshot: snapshot).systemCPUPercent == 61)
        #expect(TrendPoint(snapshot: base).systemCPUPercent == nil)
    }
}
