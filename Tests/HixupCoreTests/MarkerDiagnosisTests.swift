import Foundation
import Testing
@testable import HixupCore

private func date(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

private func snap(
    _ seconds: TimeInterval, available: Double = 50, cpu: Double? = 20,
    process: String = "node", processCPU: Double = 10, energy: Double = 0.5
) -> Snapshot {
    Snapshot(
        timestamp: date(seconds),
        memory: MemorySample(totalBytes: 16_000_000_000, usedBytes: 8_000_000_000, compressedBytes: 0, availablePercent: available),
        processes: [ProcessSample(pid: 1, name: process, residentBytes: 500_000_000, cpuPercent: processCPU, energyWatts: energy)],
        systemCPUPercent: cpu
    )
}

private func detail(
    pressure: MemoryPressureLevel = .normal, swapUsed: UInt64 = 0, thermal: ThermalLevel = .nominal,
    kind: NetworkKind = .ethernet, gateway: LatencyProbe? = LatencyProbe(host: "g", averageMs: 2, maxMs: 4, packetLossPercent: 0),
    internet: LatencyProbe? = LatencyProbe(host: "i", averageMs: 8, maxMs: 12, packetLossPercent: 0)
) -> SystemDetail {
    SystemDetail(
        memoryPressure: pressure, swapUsedBytes: swapUsed, swapTotalBytes: 8 * 1_073_741_824, thermal: thermal,
        lowPowerMode: false, network: NetworkDetail(interface: "en0", kind: kind, gateway: gateway, internet: internet)
    )
}

private func diagnose(_ detail: SystemDetail?, snapshots: [Snapshot] = [snap(1_000)]) -> [DiagnosisFinding] {
    let marker = Marker(timestamp: date(1_000), note: nil, detail: detail)
    return MarkerDiagnosis(language: .de).findings(marker: marker, snapshots: snapshots, settings: .defaults)
}

@Suite struct MarkerDiagnosisTests {
    @Test func criticalMemoryPressureIsAHighConfidenceMemoryFinding() {
        let findings = diagnose(detail(pressure: .critical))
        #expect(findings.first?.cause == .memory)
        #expect(findings.first?.confidence == .high)
        #expect(findings.first?.evidence.contains("Speicherdruck: kritisch") == true)
    }

    @Test func warningPressureAloneIsMedium() {
        let findings = diagnose(detail(pressure: .warning), snapshots: [snap(1_000, available: 25)])
        #expect(findings.first?.cause == .memory)
        #expect(findings.first?.confidence == .medium)
    }

    @Test func lowFreeMemoryBelowTheThresholdIsFlaggedEvenWithNormalPressure() {
        let findings = diagnose(detail(), snapshots: [snap(1_000, available: 9)])
        #expect(findings.first?.cause == .memory)
    }

    @Test func highSystemCPUNamesTheMainConsumer() {
        let findings = diagnose(detail(), snapshots: [snap(900, cpu: 95, process: "Citrix Viewer", processCPU: 310), snap(1_000, cpu: 96, process: "Citrix Viewer", processCPU: 300)])
        let cpu = findings.first { $0.cause == .cpu }
        #expect(cpu?.confidence == .high)
        #expect(cpu?.evidence.contains("Citrix Viewer") == true)
    }

    @Test func aSingleHeavyProcessIsMediumEvenWithModerateTotalCPU() {
        let findings = diagnose(detail(), snapshots: [snap(1_000, cpu: 40, process: "node", processCPU: 260)])
        #expect(findings.first { $0.cause == .cpu }?.confidence == .medium)
    }

    @Test func heavyEnergyUseIsReported() {
        let findings = diagnose(detail(), snapshots: [snap(1_000, process: "Blender", processCPU: 50, energy: 12)])
        #expect(findings.contains { $0.cause == .energy && $0.evidence.contains("Blender") })
    }

    @Test func seriousThermalStateIsHighAndFairIsLow() {
        #expect(diagnose(detail(thermal: .serious)).first { $0.cause == .thermal }?.confidence == .high)
        #expect(diagnose(detail(thermal: .fair)).first { $0.cause == .thermal }?.confidence == .low)
    }

    @Test func packetLossIsAHighConfidenceNetworkFinding() {
        let lossy = LatencyProbe(host: "i", averageMs: 80, maxMs: 200, packetLossPercent: 33.3)
        let finding = diagnose(detail(internet: lossy)).first { $0.cause == .network }
        #expect(finding?.confidence == .high)
        #expect(finding?.evidence.contains("33,3") == true)
    }

    @Test func slowRouterIsMediumAndMentionsVPN() {
        let slow = LatencyProbe(host: "g", averageMs: 45, maxMs: 90, packetLossPercent: 0)
        let finding = diagnose(detail(kind: .vpn, gateway: slow)).first { $0.cause == .network }
        #expect(finding?.confidence == .medium)
        #expect(finding?.evidence.contains("VPN") == true)
    }

    @Test func healthyValuesGiveASingleNothingFoundFinding() {
        let findings = diagnose(detail())
        #expect(findings.map(\.cause) == [.none])
    }

    @Test func missingDataGivesANoDataFinding() {
        #expect(diagnose(nil, snapshots: []).map(\.cause) == [.noData])
    }

    @Test func findingsAreSortedByConfidence() {
        let findings = diagnose(detail(pressure: .warning, thermal: .fair), snapshots: [snap(1_000, available: 25, cpu: 95, processCPU: 300)])
        let confidences = findings.map(\.confidence)
        #expect(confidences == confidences.sorted(by: >))
    }

    @Test func hixupItselfIsReportedOnlyWhenItHogsResources() {
        let quiet = diagnose(detail(), snapshots: [snap(1_000, process: "Hixup", processCPU: 5)])
        #expect(!quiet.contains { $0.cause == .hixup })
        let hog = diagnose(detail(), snapshots: [snap(1_000, process: "Hixup", processCPU: 300)])
        #expect(hog.contains { $0.cause == .hixup })
    }

    @Test func findingsAreEnglishWhenRequested() {
        let marker = Marker(timestamp: date(1_000), note: nil, detail: detail(pressure: .critical))
        let findings = MarkerDiagnosis(language: .en).findings(marker: marker, snapshots: [snap(1_000)], settings: .defaults)
        #expect(findings.first?.title == "Memory shortage")
    }
}

@Suite struct MarkerMetricsTests {
    @Test func metricsSplitIntoBeforeAtMarkerAndPeak() {
        let marker = Marker(timestamp: date(1_000), note: nil)
        let snapshots = [snap(700, available: 60, cpu: 20), snap(800, available: 40, cpu: 40), snap(1_000, available: 9, cpu: 96), snap(1_100, available: 30, cpu: 50)]

        let metrics = MarkerMetrics.compute(marker: marker, snapshots: snapshots)

        #expect(metrics.freeMemory.before == 50)
        #expect(metrics.freeMemory.atMarker == 9)
        #expect(metrics.freeMemory.peak == 9)
        #expect(metrics.cpuTotal.before == 30)
        #expect(metrics.cpuTotal.peak == 96)
    }

    @Test func emptyWindowGivesNilMetrics() {
        let metrics = MarkerMetrics.compute(marker: Marker(timestamp: date(0), note: nil), snapshots: [])
        #expect(metrics.freeMemory.before == nil && metrics.cpuTotal.peak == nil)
    }
}
