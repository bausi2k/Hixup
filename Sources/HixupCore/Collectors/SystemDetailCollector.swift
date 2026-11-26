import Foundation

public protocol SystemDetailProviding: Sendable {
    func memoryPressure() -> MemoryPressureLevel
    func swapUsage() -> (used: UInt64, total: UInt64)
    func thermalLevel() -> ThermalLevel
    func lowPowerMode() -> Bool
    func network() async -> NetworkDetail
}

/// Sammelt die Tiefenmessung fuer einen Marker aus einem austauschbaren Provider.
public struct SystemDetailCollector: Sendable {
    private let provider: any SystemDetailProviding

    public init(provider: any SystemDetailProviding = SystemDetailProvider()) {
        self.provider = provider
    }

    public func collect() async -> SystemDetail {
        let swap = provider.swapUsage()
        return SystemDetail(
            memoryPressure: provider.memoryPressure(),
            swapUsedBytes: swap.used,
            swapTotalBytes: swap.total,
            thermal: provider.thermalLevel(),
            lowPowerMode: provider.lowPowerMode(),
            network: await provider.network()
        )
    }
}
