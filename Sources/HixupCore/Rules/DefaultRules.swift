public enum DefaultRules {
    public static let all: [Rule] = [memoryLow, cpuSustained, energySustained, cpuSystemHigh]

    /// Die Standardregeln mit Schwellen und Mindestdauern aus den Einstellungen.
    public static func rules(for settings: AgentSettings) -> [Rule] {
        let settings = settings.clamped()
        return [
            Rule(
                id: memoryLow.id, title: memoryLow.title, severity: memoryLow.severity,
                metric: memoryLow.metric, comparison: memoryLow.comparison,
                threshold: settings.memoryLowPercent,
                minimumDuration: settings.memoryMinimumSeconds, cooldown: memoryLow.cooldown
            ),
            Rule(
                id: cpuSustained.id, title: cpuSustained.title, severity: cpuSustained.severity,
                metric: cpuSustained.metric, comparison: cpuSustained.comparison,
                threshold: settings.processCPUPercent,
                minimumDuration: settings.loadMinimumSeconds, cooldown: cpuSustained.cooldown
            ),
            Rule(
                id: energySustained.id, title: energySustained.title, severity: energySustained.severity,
                metric: energySustained.metric, comparison: energySustained.comparison,
                threshold: settings.processEnergyWatts,
                minimumDuration: settings.loadMinimumSeconds, cooldown: energySustained.cooldown
            ),
            Rule(
                id: cpuSystemHigh.id, title: cpuSystemHigh.title, severity: cpuSystemHigh.severity,
                metric: cpuSystemHigh.metric, comparison: cpuSystemHigh.comparison,
                threshold: settings.systemCPUPercent,
                minimumDuration: settings.loadMinimumSeconds, cooldown: cpuSystemHigh.cooldown
            )
        ]
    }

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

    public static let cpuSystemHigh = Rule(
        id: "cpu-system-high", title: "Gesamt-CPU-Last hoch", severity: .warning,
        metric: .systemCPUPercent, comparison: .above, threshold: 90,
        minimumDuration: 120, cooldown: 900
    )

    public static let energySustained = Rule(
        id: "energy-sustained", title: "Prozess mit hohem Energieverbrauch", severity: .warning,
        metric: .highestProcessEnergyWatts, comparison: .above, threshold: 8,
        minimumDuration: 120, cooldown: 900
    )
}
