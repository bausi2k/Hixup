import Foundation
import Testing
@testable import HixupCore

final class StubProcessLister: ProcessListing, @unchecked Sendable {
    var batches: [[RawProcess]]
    init(_ batches: [[RawProcess]]) { self.batches = batches }
    func list() throws -> [RawProcess] { batches.removeFirst() }
}

private func proc(
    _ pid: Int32, _ name: String, cpuNs: UInt64, rssMB: UInt64 = 100,
    energyNJ: UInt64 = 0, wakeups: UInt64 = 0
) -> RawProcess {
    RawProcess(
        pid: pid, name: name, residentBytes: rssMB * 1_048_576, cpuTimeNanoseconds: cpuNs,
        energyNanojoules: energyNJ, wakeups: wakeups
    )
}

@Suite struct ProcessCollectorTests {
    private let t0 = Date(timeIntervalSince1970: 1_000)

    @Test func firstCollectionReportsZeroCPUBecauseNoBaselineExists() throws {
        let lister = StubProcessLister([[proc(1, "a", cpuNs: 5_000_000_000)]])
        let collector = ProcessCollector(lister: lister)
        let result = try collector.collect(at: t0)
        #expect(result.first?.cpuPercent == 0)
    }

    @Test func cpuPercentIsDeltaCPUTimeOverWallTime() throws {
        let lister = StubProcessLister([
            [proc(1, "a", cpuNs: 0)],
            [proc(1, "a", cpuNs: 1_000_000_000)]
        ])
        let collector = ProcessCollector(lister: lister)
        _ = try collector.collect(at: t0)
        let result = try collector.collect(at: t0.addingTimeInterval(2))
        #expect(result.first?.cpuPercent == 50.0)
    }

    @Test func multiCoreUsageCanExceedHundredPercent() throws {
        let lister = StubProcessLister([
            [proc(1, "a", cpuNs: 0)],
            [proc(1, "a", cpuNs: 3_000_000_000)]
        ])
        let collector = ProcessCollector(lister: lister)
        _ = try collector.collect(at: t0)
        let result = try collector.collect(at: t0.addingTimeInterval(1))
        #expect(result.first?.cpuPercent == 300.0)
    }

    @Test func reusedPidWithSmallerCPUTimeIsTreatedAsNewProcess() throws {
        let lister = StubProcessLister([
            [proc(1, "old", cpuNs: 9_000_000_000)],
            [proc(1, "new", cpuNs: 100)]
        ])
        let collector = ProcessCollector(lister: lister)
        _ = try collector.collect(at: t0)
        let result = try collector.collect(at: t0.addingTimeInterval(1))
        #expect(result.first?.cpuPercent == 0)
    }

    @Test func resultIsSortedByCPUDescending() throws {
        let lister = StubProcessLister([
            [proc(1, "low", cpuNs: 0), proc(2, "high", cpuNs: 0)],
            [proc(1, "low", cpuNs: 100_000_000), proc(2, "high", cpuNs: 900_000_000)]
        ])
        let collector = ProcessCollector(lister: lister)
        _ = try collector.collect(at: t0)
        let result = try collector.collect(at: t0.addingTimeInterval(1))
        #expect(result.map(\.name) == ["high", "low"])
    }

    @Test func topNLimitsResultCount() throws {
        let batch = (1...10).map { proc(Int32($0), "p\($0)", cpuNs: 0) }
        let collector = ProcessCollector(lister: StubProcessLister([batch]))
        #expect(try collector.collect(at: t0, topCount: 3).count == 3)
    }

    @Test func watchedNamesAreAlwaysIncludedEvenOutsideTopN() throws {
        let batch = (1...10).map { proc(Int32($0), "p\($0)", cpuNs: 0) } + [proc(99, "Citrix Viewer", cpuNs: 0)]
        let collector = ProcessCollector(lister: StubProcessLister([batch]))
        let result = try collector.collect(at: t0, topCount: 2, watchedNames: ["Citrix Viewer"])
        #expect(result.contains { $0.name == "Citrix Viewer" })
        #expect(result.count == 3)
    }

    @Test func systemListerSeesCurrentProcess() throws {
        let processes = try SystemProcessLister().list()
        #expect(processes.contains { $0.pid == ProcessInfo.processInfo.processIdentifier })
    }

    // MARK: - Energie und Wakeups

    @Test func energyWattsIsEnergyDeltaOverWallTime() throws {
        let lister = StubProcessLister([
            [proc(1, "a", cpuNs: 0, energyNJ: 1_000_000_000)],
            [proc(1, "a", cpuNs: 0, energyNJ: 3_000_000_000)]
        ])
        let collector = ProcessCollector(lister: lister)
        _ = try collector.collect(at: t0)
        let result = try collector.collect(at: t0.addingTimeInterval(2))
        #expect(result.first?.energyWatts == 1.0)
    }

    @Test func wakeupsPerSecondIsWakeupDeltaOverWallTime() throws {
        let lister = StubProcessLister([
            [proc(1, "a", cpuNs: 0, wakeups: 100)],
            [proc(1, "a", cpuNs: 0, wakeups: 300)]
        ])
        let collector = ProcessCollector(lister: lister)
        _ = try collector.collect(at: t0)
        let result = try collector.collect(at: t0.addingTimeInterval(2))
        #expect(result.first?.wakeupsPerSecond == 100.0)
    }

    @Test func firstCollectionReportsZeroEnergyAndWakeups() throws {
        let lister = StubProcessLister([[proc(1, "a", cpuNs: 5, energyNJ: 9_000_000_000, wakeups: 500)]])
        let result = try ProcessCollector(lister: lister).collect(at: t0)
        #expect(result.first?.energyWatts == 0)
        #expect(result.first?.wakeupsPerSecond == 0)
    }

    @Test func decreasingEnergyCounterYieldsZeroInsteadOfNegativeWatts() throws {
        let lister = StubProcessLister([
            [proc(1, "a", cpuNs: 0, energyNJ: 5_000_000_000)],
            [proc(1, "a", cpuNs: 0, energyNJ: 1_000_000_000)]
        ])
        let collector = ProcessCollector(lister: lister)
        _ = try collector.collect(at: t0)
        let result = try collector.collect(at: t0.addingTimeInterval(1))
        #expect(result.first?.energyWatts == 0)
    }

    @Test func energyHungryProcessWithLowCPUIsIncludedOutsideTopN() throws {
        let idle = (1...5).map { proc(Int32($0), "p\($0)", cpuNs: 0) }
        let batches = [
            idle + [proc(99, "GPUHog", cpuNs: 0, energyNJ: 0)],
            idle.map { proc($0.pid, $0.name, cpuNs: 500_000_000) } + [proc(99, "GPUHog", cpuNs: 0, energyNJ: 5_000_000_000)]
        ]
        let collector = ProcessCollector(lister: StubProcessLister(batches))
        _ = try collector.collect(at: t0, topCount: 2)
        let result = try collector.collect(at: t0.addingTimeInterval(1), topCount: 2)

        #expect(result.contains { $0.name == "GPUHog" })
    }

    @Test func processesWithoutEnergyUseAreNotAddedToTheSelection() throws {
        let batch = (1...10).map { proc(Int32($0), "p\($0)", cpuNs: 0) }
        let result = try ProcessCollector(lister: StubProcessLister([batch])).collect(at: t0, topCount: 3)
        #expect(result.count == 3)
    }

    @Test func legacyProcessSampleJSONWithoutEnergyFieldsStillDecodes() throws {
        let json = #"{"pid":1,"name":"old","residentBytes":10,"cpuPercent":12.5}"#
        let sample = try JSONDecoder().decode(ProcessSample.self, from: Data(json.utf8))
        #expect(sample.cpuPercent == 12.5)
        #expect(sample.energyWatts == 0)
        #expect(sample.wakeupsPerSecond == 0)
    }

    @Test func systemListerReportsEnergyForBusyCurrentProcess() throws {
        var value = 0.0
        let end = Date().addingTimeInterval(0.2)
        while Date() < end { value += sin(value) + 1 }
        #expect(value > 0)

        let me = try SystemProcessLister().list().first { $0.pid == ProcessInfo.processInfo.processIdentifier }
        #expect((me?.energyNanojoules ?? 0) > 0)
    }
}
