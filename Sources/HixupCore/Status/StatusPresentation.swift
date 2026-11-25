import Foundation

/// Textliche und symbolische Darstellung des Status; bewusst ohne UI-Framework, damit testbar.
public enum StatusPresentation {
    private static let locale = Locale(identifier: "de_AT")

    public static func headline(for status: SystemStatus) -> String {
        switch status.level {
        case .unknown:
            return "Keine aktuellen Daten"
        case .ok:
            return "Alles in Ordnung"
        case .warning, .critical:
            let sustained = status.violations.filter(\.isSustained)
            guard let first = sustained.first else { return "Alles in Ordnung" }
            let others = sustained.count - 1
            return others > 0 ? "\(first.title) und \(others) weitere" : first.title
        }
    }

    /// SF-Symbol fuer die Menueleiste (monochrom, Zustand ueber die Form erkennbar).
    public static func symbolName(for level: HealthLevel) -> String {
        switch level {
        case .unknown: "waveform.path.ecg.rectangle"
        case .ok: "waveform.path.ecg"
        case .warning: "exclamationmark.triangle"
        case .critical: "exclamationmark.octagon"
        }
    }

    public static func valueText(_ violation: ActiveViolation) -> String {
        format(violation.value, metric: violation.metric)
    }

    public static func thresholdText(_ violation: ActiveViolation) -> String {
        let direction = violation.comparison == .above ? "über" : "unter"
        return "\(direction) \(format(violation.threshold, metric: violation.metric))"
    }

    public static func label(for reason: OffenderReason) -> String {
        switch reason {
        case .cpu: "CPU"
        case .energy: "Energie"
        case .memory: "Speicher"
        case .wakeups: "Wakeups"
        }
    }

    private static func format(_ value: Double, metric: Metric) -> String {
        let fraction = metric == .highestProcessEnergyWatts ? 1 : 0
        let number = value.formatted(.number.precision(.fractionLength(fraction)).locale(locale))
        return "\(number) \(metric == .highestProcessEnergyWatts ? "W" : "%")"
    }
}
