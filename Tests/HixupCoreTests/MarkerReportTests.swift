import Foundation
import Testing
@testable import HixupCore

private let utc = TimeZone(identifier: "UTC")!
private func date(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

private let system = SystemInfo(
    model: "Mac15,3", chip: "Apple M3 Pro", memoryBytes: 36 * 1_073_741_824,
    osVersion: "26.1", uptime: 3 * 86_400 + 4 * 3_600
)

private func detail() -> SystemDetail {
    SystemDetail(
        memoryPressure: .critical, swapUsedBytes: UInt64(3.2 * 1_073_741_824), swapTotalBytes: 8 * 1_073_741_824,
        thermal: .serious, lowPowerMode: false,
        network: NetworkDetail(
            interface: "utun4", kind: .vpn,
            gateway: LatencyProbe(host: "10.0.0.1", averageMs: 5, maxMs: 9, packetLossPercent: 0),
            internet: LatencyProbe(host: "1.1.1.1", averageMs: 80, maxMs: 200, packetLossPercent: 33.3)
        )
    )
}

private func snapshot(
    _ seconds: TimeInterval, available: Double = 50, cpu: Double? = 20, process: String = "node", processCPU: Double = 10
) -> Snapshot {
    Snapshot(
        timestamp: date(seconds),
        memory: MemorySample(
            totalBytes: 16_000_000_000, usedBytes: 8_000_000_000, compressedBytes: 0, availablePercent: available
        ),
        processes: [ProcessSample(pid: 1, name: process, residentBytes: 1_073_741_824, cpuPercent: processCPU, energyWatts: 2)],
        systemCPUPercent: cpu
    )
}

private func input(markers: [Marker], snapshots: [Snapshot] = [], alerts: [Alert] = []) -> MarkerReportInput {
    MarkerReportInput(markers: markers, snapshots: snapshots, alerts: alerts, settings: .defaults, system: system)
}

private func build(_ input: MarkerReportInput, language: AppLanguage = .de) -> String {
    MarkerReportBuilder(language: language, timeZone: utc).build(input)
}

@Suite struct MarkerReportTests {
    @Test func reportContainsIntroSystemInfoAndMarkerHeader() {
        let marker = Marker(timestamp: date(1_000_000), note: "Citrix hängt")
        let text = build(input(markers: [marker]))

        #expect(text.contains("# Hixup-Bericht: Ruckler-Analyse"))
        #expect(text.contains("Ursache"))
        #expect(text.contains("Mac15,3"))
        #expect(text.contains("Apple M3 Pro"))
        #expect(text.contains("36,0 GB RAM"))
        #expect(text.contains("3 T. 4 Std."))
        #expect(text.contains("## Marker 1 – 12.01.1970 13:46:40 – „Citrix hängt“"))
    }

    @Test func settingsAreListedSoTheAIKnowsWhatConspicuousMeans() {
        let text = build(input(markers: [Marker(timestamp: date(0), note: nil)]))
        #expect(text.contains("alle 5 s"))
        #expect(text.contains("freier Speicher unter 15 %"))
        #expect(text.contains("Nicht erfasst"))
    }

    @Test func detailIsRenderedWhenPresent() {
        let marker = Marker(timestamp: date(1_000), note: nil, detail: detail())
        let text = build(input(markers: [marker]))

        #expect(text.contains("Speicherdruck: kritisch"))
        #expect(text.contains("Swap: 3,2 GB von 8,0 GB"))
        #expect(text.contains("Thermik: hoch"))
        #expect(text.contains("VPN (utun4)"))
        #expect(text.contains("Internet (1.1.1.1): 80 ms Ø, max 200 ms, 33,3 % Paketverlust"))
    }

    @Test func missingDetailIsMentioned() {
        let text = build(input(markers: [Marker(timestamp: date(1_000), note: nil)]))
        #expect(text.contains("Keine Tiefenmessung"))
    }

    @Test func metricTableShowsAverageBeforeValueAtMarkerAndPeak() {
        let marker = Marker(timestamp: date(1_000), note: nil)
        let snapshots = [
            snapshot(700, available: 60, cpu: 20), snapshot(800, available: 40, cpu: 40),
            snapshot(1_000, available: 9, cpu: 96), snapshot(1_100, available: 30, cpu: 50)
        ]
        let text = build(input(markers: [marker], snapshots: snapshots))

        #expect(text.contains("| Freier Speicher | 50 % | 9 % | 9 % |"))
        #expect(text.contains("| CPU gesamt | 30 % | 96 % | 96 % |"))
    }

    @Test func hungriestAppsInTheWindowAreListed() {
        let marker = Marker(timestamp: date(1_000), note: nil)
        let snapshots = [
            snapshot(900, process: "Citrix Viewer", processCPU: 300),
            snapshot(1_000, process: "Citrix Viewer", processCPU: 310)
        ]
        let text = build(input(markers: [marker], snapshots: snapshots))

        #expect(text.contains("Ressourcenhungrigste Apps"))
        #expect(text.contains("- Citrix Viewer: Ø CPU 305 %"))
    }

    @Test func onlyAlertsInsideTheWindowAreListed() {
        let marker = Marker(timestamp: date(1_000), note: nil)
        let inside = Alert(
            ruleID: "memory-low", title: "Freier Speicher knapp", severity: .critical, value: 9, threshold: 15,
            detail: nil, timestamp: date(950)
        )
        let outside = Alert(
            ruleID: "cpu", title: "Weit weg", severity: .warning, value: 1, threshold: 1,
            detail: nil, timestamp: date(50_000)
        )
        let text = build(input(markers: [marker], alerts: [inside, outside]))

        #expect(text.contains("Freier Speicher knapp"))
        #expect(!text.contains("Weit weg"))
    }

    @Test func fewSamplesProduceAGapNote() {
        let marker = Marker(timestamp: date(1_000), note: nil)
        let text = build(input(markers: [marker], snapshots: [snapshot(1_000)]))
        #expect(text.contains("Hinweis: Nur 1 von ca."))
    }

    @Test func noMarkersGivesAShortNote() {
        #expect(build(input(markers: [])).contains("Keine Marker im Zeitraum."))
    }

    @Test func englishReportUsesEnglishTexts() {
        let marker = Marker(timestamp: date(1_000), note: nil, detail: detail())
        let text = build(input(markers: [marker]), language: .en)

        #expect(text.contains("# Hixup report: stutter analysis"))
        #expect(text.contains("Memory pressure: critical"))
        #expect(text.contains("Swap: 3.2 GB of 8.0 GB"))
        #expect(text.contains("Thermal: serious"))
    }

    @Test func multipleMarkersAreNumberedInTimeOrder() {
        let markers = [Marker(timestamp: date(5_000), note: "b"), Marker(timestamp: date(1_000), note: "a")]
        let text = build(input(markers: markers))

        #expect(text.contains("## Marker 1"))
        #expect(text.contains("## Marker 2"))
        #expect(text.range(of: "„a“")!.lowerBound < text.range(of: "„b“")!.lowerBound)
    }
}

@Suite struct MarkerReportGapTests {
    @Test func futureTimeInTheWindowIsNotCountedAsAGap() {
        let marker = Marker(timestamp: date(1_000), note: nil)
        let snapshots = stride(from: 700.0, through: 1_000, by: 5).map { snapshot($0) }
        let builder = MarkerReportBuilder(language: .de, timeZone: utc, now: date(1_000))

        let text = builder.build(input(markers: [marker], snapshots: snapshots))

        #expect(!text.contains("Hinweis: Nur"))
    }
}

@Suite struct MarkerReportServiceTests {
    @Test func serviceBuildsTheReportFromTheStores() throws {
        let snapshots = try SQLiteSnapshotStore(path: ":memory:")
        let events = try SQLiteEventStore(path: ":memory:")
        let marker = Marker(timestamp: date(1_000), note: "ruckelt")
        try events.addMarker(marker)
        try snapshots.append(snapshot(950, available: 12, process: "Citrix Viewer", processCPU: 280))
        try snapshots.append(snapshot(99_999))

        let service = MarkerReportService(snapshots: snapshots, events: events, settings: { .defaults }, system: { system })
        let text = try service.report(for: [marker], language: .de)

        #expect(text.contains("„ruckelt“"))
        #expect(text.contains("Citrix Viewer"))
        #expect(text.contains("Mac15,3"))
    }

    @Test func serviceHandlesAnEmptyMarkerList() throws {
        let snapshots = try SQLiteSnapshotStore(path: ":memory:")
        let events = try SQLiteEventStore(path: ":memory:")
        let service = MarkerReportService(snapshots: snapshots, events: events, settings: { .defaults }, system: { system })

        #expect(try service.report(for: [], language: .de).contains("Keine Marker im Zeitraum."))
    }
}
