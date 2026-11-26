import Foundation

public enum MemoryPressureLevel: String, Codable, Sendable {
    case normal
    case warning
    case critical

    /// Werte von `kern.memorystatus_vm_pressure_level`: 1 normal, 2 Warnung, 4 kritisch.
    init(kernelLevel: Int32) {
        switch kernelLevel {
        case 2: self = .warning
        case 4: self = .critical
        default: self = .normal
        }
    }
}

public enum ThermalLevel: String, Codable, Sendable {
    case nominal
    case fair
    case serious
    case critical

    init(_ state: ProcessInfo.ThermalState) {
        switch state {
        case .nominal: self = .nominal
        case .fair: self = .fair
        case .serious: self = .serious
        case .critical: self = .critical
        @unknown default: self = .nominal
        }
    }
}

public enum NetworkKind: String, Codable, Sendable {
    case wifi
    case ethernet
    case vpn
    case other
    case none

    /// Schliesst aus dem Schnittstellennamen auf die Art; `wifiInterface` ist der Name der WLAN-Schnittstelle.
    static func classify(interface: String?, wifiInterface: String?) -> NetworkKind {
        guard let interface else { return .none }
        if ["utun", "ipsec", "ppp", "tun", "tap"].contains(where: interface.hasPrefix) { return .vpn }
        if interface == wifiInterface { return .wifi }
        return interface.hasPrefix("en") ? .ethernet : .other
    }
}

/// Ergebnis einer kurzen Ping-Messung.
public struct LatencyProbe: Codable, Equatable, Sendable {
    public let host: String
    /// `nil`, wenn alle Pakete verloren gingen.
    public let averageMs: Double?
    public let maxMs: Double?
    public let packetLossPercent: Double

    public init(host: String, averageMs: Double?, maxMs: Double?, packetLossPercent: Double) {
        self.host = host
        self.averageMs = averageMs
        self.maxMs = maxMs
        self.packetLossPercent = packetLossPercent
    }

    /// Liest die Zusammenfassung der `ping`-Ausgabe; unlesbare Ausgabe zaehlt als Totalverlust.
    static func parse(pingOutput: String, host: String) -> LatencyProbe {
        let loss = pingOutput.firstMatch(of: /([0-9.]+)% packet loss/).flatMap { Double($0.1) } ?? 100
        let times = pingOutput.firstMatch(of: /= ([0-9.]+)\/([0-9.]+)\/([0-9.]+)\/([0-9.]+) ms/)
        return LatencyProbe(
            host: host,
            averageMs: times.flatMap { Double($0.2) },
            maxMs: times.flatMap { Double($0.3) },
            packetLossPercent: loss
        )
    }
}

public struct NetworkDetail: Codable, Equatable, Sendable {
    public let interface: String?
    public let kind: NetworkKind
    public let gateway: LatencyProbe?
    public let internet: LatencyProbe?

    public init(interface: String?, kind: NetworkKind, gateway: LatencyProbe?, internet: LatencyProbe?) {
        self.interface = interface
        self.kind = kind
        self.gateway = gateway
        self.internet = internet
    }
}

/// Tiefenmessung zum Zeitpunkt eines Markers: Werte, die nicht dauernd erfasst werden.
public struct SystemDetail: Codable, Equatable, Sendable {
    public let memoryPressure: MemoryPressureLevel
    public let swapUsedBytes: UInt64
    public let swapTotalBytes: UInt64
    public let thermal: ThermalLevel
    public let lowPowerMode: Bool
    public let network: NetworkDetail

    public init(
        memoryPressure: MemoryPressureLevel, swapUsedBytes: UInt64, swapTotalBytes: UInt64,
        thermal: ThermalLevel, lowPowerMode: Bool, network: NetworkDetail
    ) {
        self.memoryPressure = memoryPressure
        self.swapUsedBytes = swapUsedBytes
        self.swapTotalBytes = swapTotalBytes
        self.thermal = thermal
        self.lowPowerMode = lowPowerMode
        self.network = network
    }
}
