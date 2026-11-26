import Foundation

/// Ein Messwert im Umfeld eines Markers: Mittel davor, Wert beim Marker, Spitze im Fenster.
public struct MarkerMetric: Equatable, Sendable {
    public let before: Double?
    public let atMarker: Double?
    public let peak: Double?
}

public struct MarkerMetrics: Equatable, Sendable {
    public let freeMemory: MarkerMetric
    public let cpuTotal: MarkerMetric
    public let energy: MarkerMetric

    /// - Parameter snapshots: Messpunkte im Fenster um den Marker. "Spitze" ist beim Speicher das Minimum.
    public static func compute(marker: Marker, snapshots: [Snapshot]) -> MarkerMetrics {
        let before = snapshots.filter { $0.timestamp < marker.timestamp }
        let atMarker = snapshots.min {
            abs($0.timestamp.timeIntervalSince(marker.timestamp)) < abs($1.timestamp.timeIntervalSince(marker.timestamp))
        }
        func metric(_ value: (Snapshot) -> Double?, peak: ([Double]) -> Double?) -> MarkerMetric {
            let past = before.compactMap(value)
            return MarkerMetric(
                before: past.isEmpty ? nil : past.reduce(0, +) / Double(past.count),
                atMarker: atMarker.flatMap(value),
                peak: peak(snapshots.compactMap(value))
            )
        }
        return MarkerMetrics(
            freeMemory: metric({ $0.memory.availablePercent }, peak: { $0.min() }),
            cpuTotal: metric({ $0.systemCPUPercent }, peak: { $0.max() }),
            energy: metric({ $0.processes.reduce(0) { $0 + $1.energyWatts } }, peak: { $0.max() })
        )
    }
}
