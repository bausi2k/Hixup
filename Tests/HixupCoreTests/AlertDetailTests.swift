import Foundation
import Testing
@testable import HixupCore

private let utc = TimeZone(identifier: "UTC")!
private func date(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

private struct FakeProvider: SystemDetailProviding {
    func memoryPressure() -> MemoryPressureLevel { .critical }
    func swapUsage() -> (used: UInt64, total: UInt64) { (3_000, 8_000) }
    func thermalLevel() -> ThermalLevel { .nominal }
    func lowPowerMode() -> Bool { false }
    func network() async -> NetworkDetail { NetworkDetail(interface: "en0", kind: .ethernet, gateway: nil, internet: nil) }
}

private func detail() -> SystemDetail {
    SystemDetail(
        memoryPressure: .critical, swapUsedBytes: 5, swapTotalBytes: 10, thermal: .nominal, lowPowerMode: false,
        network: NetworkDetail(interface: "en0", kind: .ethernet, gateway: nil, internet: nil)
    )
}

private func alert(_ seconds: TimeInterval = 1_000, rule: String = "memory-low", system: SystemDetail? = nil) -> Alert {
    Alert(
        ruleID: rule, title: "Freier Speicher knapp", severity: .critical, value: 9, threshold: 15,
        detail: nil, timestamp: date(seconds), system: system
    )
}

private func snap(_ seconds: TimeInterval, available: Double = 50) -> Snapshot {
    Snapshot(
        timestamp: date(seconds),
        memory: MemorySample(totalBytes: 16_000_000_000, usedBytes: 8_000_000_000, compressedBytes: 0, availablePercent: available),
        processes: [ProcessSample(pid: 1, name: "node", residentBytes: 1_000, cpuPercent: 10, energyWatts: 1)],
        systemCPUPercent: 20
    )
}

private let system = SystemInfo(model: "Mac15,3", chip: "Apple M3 Pro", memoryBytes: 36 * 1_073_741_824, osVersion: "26.1", uptime: 3_600)

@Suite struct AlertDetailStorageTests {
    @Test func detailCanBeAttachedToAnAlertAndReadBack() throws {
        let store = try SQLiteEventStore(path: ":memory:")
        let stored = alert()
        try store.record(stored)

        try store.setAlertDetail(detail(), for: stored)

        let loaded = try #require(store.alerts(from: date(0), to: date(2_000)).first)
        #expect(loaded.system == detail())
        #expect(loaded.title == "Freier Speicher knapp")
    }

    @Test func onlyTheMatchingAlertChanges() throws {
        let store = try SQLiteEventStore(path: ":memory:")
        try store.record(alert(1_000, rule: "memory-low"))
        try store.record(alert(1_000, rule: "cpu-sustained"))

        try store.setAlertDetail(detail(), for: alert(1_000, rule: "cpu-sustained"))

        let alerts = try store.alerts(from: date(0), to: date(2_000))
        #expect(alerts.first { $0.ruleID == "cpu-sustained" }?.system == detail())
        #expect(alerts.first { $0.ruleID == "memory-low" }?.system == nil)
    }

    @Test func oldAlertsWithoutSystemStayReadable() throws {
        let json = #"{"ruleID":"r","title":"t","severity":"warning","value":1,"threshold":1,"timestamp":100}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        let old = try decoder.decode(Alert.self, from: Data(json.utf8))
        #expect(old.system == nil)
    }
}

@Suite struct AlertDetailRecorderTests {
    @Test func recorderAttachesTheDeepMeasurementToTheAlert() async throws {
        let store = try SQLiteEventStore(path: ":memory:")
        let stored = alert()
        try store.record(stored)
        let recorder = AlertDetailRecorder(events: store, detail: SystemDetailCollector(provider: FakeProvider()))

        await recorder.attachDetail(to: stored)

        #expect(try store.alerts(from: date(0), to: date(2_000)).first?.system?.memoryPressure == .critical)
    }
}

@Suite struct AlertReportTests {
    private func report(_ alerts: [Alert], markers: [Marker] = [], language: AppLanguage = .de) -> String {
        let input = MarkerReportInput(
            markers: markers, snapshots: [snap(900, available: 40), snap(1_000, available: 9)], alerts: alerts,
            settings: .defaults, system: system, focusAlerts: alerts
        )
        return MarkerReportBuilder(language: language, timeZone: utc).build(input)
    }

    @Test func alertReportNamesTitleSeverityValueAndThreshold() {
        let text = report([alert(1_000, system: detail())])

        #expect(text.contains("## Alarm 1 – 01.01.1970 00:16:40 – „Freier Speicher knapp“"))
        #expect(text.contains("kritisch"))
        #expect(text.contains("Wert 9"))
        #expect(text.contains("Schwelle 15"))
    }

    @Test func introExplainsThatHixupRaisedTheAlert() {
        let text = report([alert()])
        #expect(text.contains("Alarm bedeutet"))
        #expect(!text.contains("Ein „Marker“ bedeutet"))
    }

    @Test func alertReportContainsTheDeepMeasurementMetricsAndAssessment() {
        let text = report([alert(1_000, system: detail())])

        #expect(text.contains("Speicherdruck: kritisch"))
        #expect(text.contains("| Freier Speicher |"))
        #expect(text.contains("Vorläufige Einschätzung von Hixup"))
    }

    @Test func alertWithoutDeepMeasurementSaysSo() {
        #expect(report([alert()]).contains("Keine Tiefenmessung"))
    }

    @Test func markersAndAlertsAreNumberedSeparately() {
        let text = report([alert(2_000)], markers: [Marker(timestamp: date(1_000), note: "x")])
        #expect(text.contains("## Marker 1"))
        #expect(text.contains("## Alarm 1"))
        #expect(text.contains("Marker"))
    }

    @Test func pressureAlertsShowLevelNamesInsteadOfNumbers() {
        let pressure = Alert(
            ruleID: "memory-pressure-warning", title: "Speicherdruck erhöht", severity: .warning, value: 1, threshold: 0,
            detail: nil, timestamp: date(1_000)
        )
        let text = report([pressure])
        #expect(text.contains("Wert Warnung, Schwelle über normal"))
    }

    @Test func englishAlertReportUsesEnglishTexts() {
        let text = report([alert(1_000, system: detail())], language: .en)
        #expect(text.contains("## Alert 1"))
        #expect(text.contains("An alert means"))
    }
}

@Suite struct AlertServiceTests {
    @Test func serviceBuildsAnAlertReportAndInsight() throws {
        let snapshots = try SQLiteSnapshotStore(path: ":memory:")
        let events = try SQLiteEventStore(path: ":memory:")
        let stored = alert(1_000, system: detail())
        try events.record(stored)
        try snapshots.append(snap(950, available: 12))
        try snapshots.append(snap(1_000, available: 9))
        let service = MarkerReportService(snapshots: snapshots, events: events, settings: { .defaults }, system: { system })

        let text = try service.report(forAlerts: [stored], language: .de)
        let insight = try service.insight(forAlert: stored, language: .de)

        #expect(text.contains("## Alarm 1"))
        #expect(insight.metrics.freeMemory.peak == 9)
        #expect(insight.findings.first?.cause == .memory)
    }
}
