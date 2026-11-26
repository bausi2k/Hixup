import Foundation
import Testing
@testable import HixupCore

private struct FakeProvider: SystemDetailProviding {
    var pressure: MemoryPressureLevel = .normal
    var swap = (used: UInt64(0), total: UInt64(0))
    var thermal: ThermalLevel = .nominal
    var lowPower = false
    var net = NetworkDetail(interface: "en0", kind: .wifi, gateway: nil, internet: nil)

    func memoryPressure() -> MemoryPressureLevel { pressure }
    func swapUsage() -> (used: UInt64, total: UInt64) { swap }
    func thermalLevel() -> ThermalLevel { thermal }
    func lowPowerMode() -> Bool { lowPower }
    func network() async -> NetworkDetail { net }
}

@Suite struct SystemDetailCollectorTests {
    @Test func collectorCombinesAllProviderValues() async {
        let provider = FakeProvider(
            pressure: .critical, swap: (used: 3_000, total: 8_000), thermal: .serious, lowPower: true,
            net: NetworkDetail(
                interface: "utun4", kind: .vpn,
                gateway: LatencyProbe(host: "10.0.0.1", averageMs: 5, maxMs: 9, packetLossPercent: 0),
                internet: LatencyProbe(host: "1.1.1.1", averageMs: 80, maxMs: 200, packetLossPercent: 33.3)
            )
        )

        let detail = await SystemDetailCollector(provider: provider).collect()

        #expect(detail.memoryPressure == .critical)
        #expect(detail.swapUsedBytes == 3_000)
        #expect(detail.swapTotalBytes == 8_000)
        #expect(detail.thermal == .serious)
        #expect(detail.lowPowerMode)
        #expect(detail.network.kind == .vpn)
        #expect(detail.network.internet?.packetLossPercent == 33.3)
    }

    @Test func detailSurvivesJSONRoundTrip() throws {
        let detail = SystemDetail(
            memoryPressure: .warning, swapUsedBytes: 1, swapTotalBytes: 2, thermal: .fair, lowPowerMode: false,
            network: NetworkDetail(interface: nil, kind: .none, gateway: nil, internet: nil)
        )
        let data = try JSONEncoder().encode(detail)
        #expect(try JSONDecoder().decode(SystemDetail.self, from: data) == detail)
    }
}

@Suite struct SystemDetailParsingTests {
    @Test func pressureLevelsMapFromTheKernelValues() {
        #expect(MemoryPressureLevel(kernelLevel: 1) == .normal)
        #expect(MemoryPressureLevel(kernelLevel: 2) == .warning)
        #expect(MemoryPressureLevel(kernelLevel: 4) == .critical)
        #expect(MemoryPressureLevel(kernelLevel: 99) == .normal)
    }

    @Test func thermalLevelsMapFromProcessInfo() {
        #expect(ThermalLevel(ProcessInfo.ThermalState.nominal) == .nominal)
        #expect(ThermalLevel(ProcessInfo.ThermalState.fair) == .fair)
        #expect(ThermalLevel(ProcessInfo.ThermalState.serious) == .serious)
        #expect(ThermalLevel(ProcessInfo.ThermalState.critical) == .critical)
    }

    @Test func networkKindIsDerivedFromTheInterfaceName() {
        #expect(NetworkKind.classify(interface: "utun3", wifiInterface: "en0") == .vpn)
        #expect(NetworkKind.classify(interface: "ipsec0", wifiInterface: "en0") == .vpn)
        #expect(NetworkKind.classify(interface: "en0", wifiInterface: "en0") == .wifi)
        #expect(NetworkKind.classify(interface: "en5", wifiInterface: "en0") == .ethernet)
        #expect(NetworkKind.classify(interface: "bridge0", wifiInterface: "en0") == .other)
        #expect(NetworkKind.classify(interface: nil, wifiInterface: "en0") == .none)
    }

    @Test func pingOutputIsParsed() {
        let output = """
        PING 1.1.1.1 (1.1.1.1): 56 data bytes

        --- 1.1.1.1 ping statistics ---
        3 packets transmitted, 2 packets received, 33.3% packet loss
        round-trip min/avg/max/stddev = 10.123/12.456/15.789/2.345 ms
        """

        let probe = LatencyProbe.parse(pingOutput: output, host: "1.1.1.1")

        #expect(probe.host == "1.1.1.1")
        #expect(probe.averageMs == 12.456)
        #expect(probe.maxMs == 15.789)
        #expect(probe.packetLossPercent == 33.3)
    }

    @Test func totalLossHasNoLatency() {
        let output = "--- 10.0.0.1 ping statistics ---\n3 packets transmitted, 0 packets received, 100.0% packet loss\n"
        let probe = LatencyProbe.parse(pingOutput: output, host: "10.0.0.1")
        #expect(probe.averageMs == nil)
        #expect(probe.packetLossPercent == 100)
    }

    @Test func unparsableOutputCountsAsTotalLoss() {
        let probe = LatencyProbe.parse(pingOutput: "ping: cannot resolve", host: "x")
        #expect(probe.averageMs == nil)
        #expect(probe.packetLossPercent == 100)
    }
}

@Suite struct MarkerDetailStorageTests {
    private func detail() -> SystemDetail {
        SystemDetail(
            memoryPressure: .warning, swapUsedBytes: 5, swapTotalBytes: 10, thermal: .nominal, lowPowerMode: false,
            network: NetworkDetail(interface: "en0", kind: .wifi, gateway: nil, internet: nil)
        )
    }

    @Test func markerDetailCanBeAttachedAndReadBack() throws {
        let store = try SQLiteEventStore(path: ":memory:")
        let time = Date(timeIntervalSince1970: 100)
        try store.addMarker(Marker(timestamp: time, note: "ruckelt"))

        try store.setMarkerDetail(detail(), at: time)

        let markers = try store.markers(from: Date(timeIntervalSince1970: 0), to: Date(timeIntervalSince1970: 200))
        #expect(markers.first?.detail == detail())
        #expect(markers.first?.note == "ruckelt")
    }

    @Test func markersWithoutDetailStayReadable() throws {
        let store = try SQLiteEventStore(path: ":memory:")
        try store.addMarker(Marker(timestamp: Date(timeIntervalSince1970: 1), note: nil))
        let markers = try store.markers(from: Date(timeIntervalSince1970: 0), to: Date(timeIntervalSince1970: 2))
        #expect(markers.first?.detail == nil)
    }

    @Test func oldDatabaseWithoutDetailColumnIsMigrated() throws {
        let path = NSTemporaryDirectory() + "hixup-migration-\(UUID().uuidString).sqlite"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let legacy = try SQLiteDatabase(path: path, schema: """
            CREATE TABLE markers (id INTEGER PRIMARY KEY AUTOINCREMENT, timestamp REAL NOT NULL, note TEXT);
            INSERT INTO markers (timestamp, note) VALUES (50, 'alt');
            """)
        _ = legacy

        let store = try SQLiteEventStore(path: path)
        try store.setMarkerDetail(detail(), at: Date(timeIntervalSince1970: 50))

        let markers = try store.markers(from: Date(timeIntervalSince1970: 0), to: Date(timeIntervalSince1970: 100))
        #expect(markers.first?.note == "alt")
        #expect(markers.first?.detail == detail())
    }
}

@Suite struct MarkerRecorderDetailTests {
    @Test func recorderAttachesCollectedDetailToTheMarker() async throws {
        let store = try SQLiteEventStore(path: ":memory:")
        let time = Date(timeIntervalSince1970: 10)
        let collector = SystemDetailCollector(provider: FakeProvider(pressure: .critical))
        let recorder = MarkerRecorder(events: store, detail: collector, now: { time })

        let marker = try recorder.mark(note: "x")
        await recorder.attachDetail(to: marker)

        let stored = try store.markers(from: Date(timeIntervalSince1970: 0), to: Date(timeIntervalSince1970: 20))
        #expect(stored.first?.detail?.memoryPressure == .critical)
    }

    @Test func markWithoutCollectorStillWorks() async throws {
        let store = try SQLiteEventStore(path: ":memory:")
        let recorder = MarkerRecorder(events: store)
        let marker = try recorder.mark()
        await recorder.attachDetail(to: marker)
        #expect(try store.markers(from: .distantPast, to: .distantFuture).first?.detail == nil)
    }
}

@Suite struct SystemDetailProviderTests {
    @Test func systemProviderReadsPlausibleLocalValues() {
        let provider = SystemDetailProvider()

        let swap = provider.swapUsage()
        #expect(swap.used <= swap.total)
        _ = provider.memoryPressure()
        _ = provider.thermalLevel()
        _ = provider.lowPowerMode()
    }
}
