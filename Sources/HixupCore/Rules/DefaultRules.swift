public enum DefaultRules {
    public static var all: [Rule] {
        [memoryLow, cpuSustained, energySustained, cpuSystemHigh, memoryPressureWarning, memoryPressureCritical]
    }

    /// Die Standardregeln mit Schwellen und Mindestdauern aus den Einstellungen.
    public static func rules(for settings: AgentSettings) -> [Rule] {
        let settings = settings.clamped()
        let base = [
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
        guard settings.memoryPressureAlerts else { return base }
        return base + [
            Rule(
                id: memoryPressureWarning.id, title: memoryPressureWarning.title, severity: memoryPressureWarning.severity,
                metric: memoryPressureWarning.metric, comparison: memoryPressureWarning.comparison,
                threshold: memoryPressureWarning.threshold,
                minimumDuration: settings.memoryMinimumSeconds, cooldown: memoryPressureWarning.cooldown
            ),
            Rule(
                id: memoryPressureCritical.id, title: memoryPressureCritical.title, severity: memoryPressureCritical.severity,
                metric: memoryPressureCritical.metric, comparison: memoryPressureCritical.comparison,
                threshold: memoryPressureCritical.threshold,
                minimumDuration: min(settings.memoryMinimumSeconds, 30), cooldown: memoryPressureCritical.cooldown
            )
        ]
    }

    public static var memoryLow: Rule { Rule(
        id: "memory-low", title: L10n.tr("Freier Speicher knapp"), severity: .critical,
        metric: .availableMemoryPercent, comparison: .below, threshold: 15,
        minimumDuration: 60, cooldown: 600
    ) }

    public static var cpuSustained: Rule { Rule(
        id: "cpu-sustained", title: L10n.tr("Prozess mit anhaltend hoher CPU-Last"), severity: .warning,
        metric: .highestProcessCPUPercent, comparison: .above, threshold: 200,
        minimumDuration: 120, cooldown: 900
    ) }

    public static var cpuSystemHigh: Rule { Rule(
        id: "cpu-system-high", title: L10n.tr("Gesamt-CPU-Last hoch"), severity: .warning,
        metric: .systemCPUPercent, comparison: .above, threshold: 90,
        minimumDuration: 120, cooldown: 900
    ) }

    public static var energySustained: Rule { Rule(
        id: "energy-sustained", title: L10n.tr("Prozess mit hohem Energieverbrauch"), severity: .warning,
        metric: .highestProcessEnergyWatts, comparison: .above, threshold: 8,
        minimumDuration: 120, cooldown: 900
    ) }

    /// Speicherdruck ab Stufe "Warnung" (Stufe 1 liegt ueber 0).
    public static var memoryPressureWarning: Rule { Rule(
        id: "memory-pressure-warning", title: L10n.tr("Speicherdruck erhöht"), severity: .warning,
        metric: .memoryPressure, comparison: .above, threshold: 0,
        minimumDuration: 60, cooldown: 900
    ) }

    /// Speicherdruck "kritisch" (Stufe 2 liegt ueber 1).
    public static var memoryPressureCritical: Rule { Rule(
        id: "memory-pressure-critical", title: L10n.tr("Speicherdruck kritisch"), severity: .critical,
        metric: .memoryPressure, comparison: .above, threshold: 1,
        minimumDuration: 30, cooldown: 600
    ) }
}
