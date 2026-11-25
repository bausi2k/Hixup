public enum DefaultRules {
    public static let all: [Rule] = [memoryLow, cpuSustained]

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
}
