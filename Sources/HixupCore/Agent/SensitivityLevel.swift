import Foundation

/// Drei Voreinstellungen fuer die Alarm-Schwellen, benannt nach Hunderassen: vom gelassenen
/// Labrador ueber den aufmerksamen Border Collie bis zum strengen Dobermann.
public enum SensitivityLevel: String, CaseIterable, Sendable {
    case labrador
    case borderCollie
    case dobermann

    public var title: String {
        switch self {
        case .labrador: "Labrador"
        case .borderCollie: "Border Collie"
        case .dobermann: "Dobermann"
        }
    }

    public var summary: String {
        switch self {
        case .labrador: "Gelassen: meldet sich nur bei klaren Problemen."
        case .borderCollie: "Aufmerksam: ausgewogene Standardwerte."
        case .dobermann: "Wachsam: schlägt früh und schnell an."
        }
    }

    /// Setzt alle Schwellen und Mindestdauern; Messintervall, Aufbewahrung und Prozesslisten bleiben.
    public func applied(to settings: AgentSettings) -> AgentSettings {
        var result = settings
        let preset = thresholds
        result.memoryLowPercent = preset.memoryLowPercent
        result.processCPUPercent = preset.processCPUPercent
        result.processEnergyWatts = preset.processEnergyWatts
        result.systemCPUPercent = preset.systemCPUPercent
        result.memoryMinimumSeconds = preset.memoryMinimumSeconds
        result.loadMinimumSeconds = preset.loadMinimumSeconds
        return result
    }

    /// Die Stufe, deren Schwellen exakt den Einstellungen entsprechen; `nil` bei eigenen Werten.
    public static func matching(_ settings: AgentSettings) -> SensitivityLevel? {
        allCases.first { $0.applied(to: settings) == settings }
    }

    private var thresholds: AgentSettings {
        switch self {
        case .labrador:
            AgentSettings(
                memoryLowPercent: 10, processCPUPercent: 300, processEnergyWatts: 12,
                memoryMinimumSeconds: 120, loadMinimumSeconds: 300, systemCPUPercent: 95
            )
        case .borderCollie:
            .defaults
        case .dobermann:
            AgentSettings(
                memoryLowPercent: 25, processCPUPercent: 150, processEnergyWatts: 5,
                memoryMinimumSeconds: 30, loadMinimumSeconds: 60, systemCPUPercent: 80
            )
        }
    }
}
