import CoreWLAN
import Foundation
import SystemConfiguration

/// Liest die Tiefenmessung vom System: Speicherdruck und Swap per `sysctl`, Thermik und Energiesparmodus
/// per `ProcessInfo`, Netzwerk per SystemConfiguration und `ping`.
public struct SystemDetailProvider: SystemDetailProviding {
    private let internetHost: String

    public init(internetHost: String = "1.1.1.1") {
        self.internetHost = internetHost
    }

    public func memoryPressure() -> MemoryPressureLevel {
        var level: Int32 = 1
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else { return .normal }
        return MemoryPressureLevel(kernelLevel: level)
    }

    public func swapUsage() -> (used: UInt64, total: UInt64) {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return (0, 0) }
        return (usage.xsu_used, usage.xsu_total)
    }

    public func thermalLevel() -> ThermalLevel {
        ThermalLevel(ProcessInfo.processInfo.thermalState)
    }

    public func lowPowerMode() -> Bool {
        ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    public func network() async -> NetworkDetail {
        let route = Self.primaryRoute()
        let kind = NetworkKind.classify(
            interface: route.interface, wifiInterface: CWWiFiClient.shared().interface()?.interfaceName
        )
        async let gateway = route.router.map { host in Self.ping(host) }?.value
        async let internet = route.interface == nil ? nil : Self.ping(internetHost).value
        return NetworkDetail(interface: route.interface, kind: kind, gateway: await gateway, internet: await internet)
    }

    private static func primaryRoute() -> (interface: String?, router: String?) {
        guard let store = SCDynamicStoreCreate(nil, "hixup" as CFString, nil, nil),
              let global = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any]
        else { return (nil, nil) }
        return (global["PrimaryInterface"] as? String, global["Router"] as? String)
    }

    /// Drei kurze Pings mit Gesamtlimit von vier Sekunden.
    private static func ping(_ host: String) -> Task<LatencyProbe, Never> {
        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/sbin/ping")
            process.arguments = ["-c", "3", "-i", "0.3", "-t", "4", "-q", host]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            do { try process.run() } catch {
                return LatencyProbe(host: host, averageMs: nil, maxMs: nil, packetLossPercent: 100)
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return LatencyProbe.parse(pingOutput: String(decoding: data, as: UTF8.self), host: host)
        }
    }
}
