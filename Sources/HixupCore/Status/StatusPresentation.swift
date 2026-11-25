import Foundation

/// Textliche und symbolische Darstellung des Status; bewusst ohne UI-Framework, damit testbar.
public enum StatusPresentation {
    private static let locale = Locale(identifier: "de_AT")

    public static func headline(for status: SystemStatus) -> String {
        switch status.level {
        case .unknown:
            return L10n.tr("Keine aktuellen Daten")
        case .ok:
            return L10n.tr("Alles in Ordnung")
        case .warning, .critical:
            let sustained = status.violations.filter(\.isSustained)
            guard let first = sustained.first else { return L10n.tr("Alles in Ordnung") }
            let others = sustained.count - 1
            return others > 0 ? L10n.tr("%@ und %d weitere", first.title, others) : first.title
        }
    }

    public static var hungriestAppTitle: String { L10n.tr("Ressourcenhungrigste App") }
    public static var hungriestAppRangeTitle: String { L10n.tr("Ressourcenhungrigste Apps im Zeitraum") }

    /// Stimmung des Hundes zum Gesamtstatus; die Alarmtexte selbst bleiben sachlich.
    public static func mood(for level: HealthLevel) -> String {
        switch level {
        case .unknown: L10n.tr("Hixup schläft tief – keine Daten.")
        case .ok: L10n.tr("Alles ruhig, Hixup döst.")
        case .warning: L10n.tr("Hixup spitzt die Ohren.")
        case .critical: L10n.tr("Hixup schlägt an!")
        }
    }

    /// Name der Prozessgruppe mit der hoechsten Belastung, falls vorhanden.
    public static func hungriestApp(in status: SystemStatus) -> String? {
        status.offenders.first?.name
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
        let direction = violation.comparison == .above ? L10n.tr("über") : L10n.tr("unter")
        return "\(direction) \(format(violation.threshold, metric: violation.metric))"
    }

    public static func label(for reason: OffenderReason) -> String {
        switch reason {
        case .cpu: L10n.tr("CPU")
        case .energy: L10n.tr("Energie")
        case .memory: L10n.tr("Speicher")
        case .wakeups: L10n.tr("Wakeups")
        }
    }

    private static func format(_ value: Double, metric: Metric) -> String {
        let fraction = metric == .highestProcessEnergyWatts ? 1 : 0
        let number = value.formatted(.number.precision(.fractionLength(fraction)).locale(locale))
        return "\(number) \(metric == .highestProcessEnergyWatts ? "W" : "%")"
    }
}
