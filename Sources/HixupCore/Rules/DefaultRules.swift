public enum DefaultRules {
    public static let all: [Rule] = [memoryLow, cpuSustained, energySustained]

    public static let memoryLow = Rule(
        id: "memory-low", title: "Freier Speicher knapp", severity: .critical,
        metric: .availableMemoryPercent, comparison: .below, threshold: 15,
        minimumDuration: 60, cooldown: 600
    )

    public static let cpuSustained = Rule(
        id: "cpu-sustained", title: "Prozess mit anhaltend hoher CPU-Last", severity: .warning,
        metric: .highestProcessCPUPercent, comparison: .above, threshold: 200,
        minimumDuration: 120, cooldown: 900
    )

    public static let energySustained = Rule(
        id: "energy-sustained", title: "Prozess mit hohem Energieverbrauch", severity: .warning,
        metric: .highestProcessEnergyWatts, comparison: .above, threshold: 8,
        minimumDuration: 120, cooldown: 900
    )
}
