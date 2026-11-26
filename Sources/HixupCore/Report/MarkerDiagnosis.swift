import Foundation

public enum DiagnosisCause: String, Sendable, CaseIterable {
    case memory, cpu, energy, thermal, network, hixup, none, noData
}

public enum DiagnosisConfidence: Int, Comparable, Sendable {
    case low = 0
    case medium
    case high

    public static func < (lhs: DiagnosisConfidence, rhs: DiagnosisConfidence) -> Bool { lhs.rawValue < rhs.rawValue }

    public func name(language: AppLanguage? = nil) -> String {
        switch self {
        case .low: L10n.translate("Niedrig", language: language)
        case .medium: L10n.translate("Mittel", language: language)
        case .high: L10n.translate("Hoch", language: language)
        }
    }
}

public struct DiagnosisFinding: Equatable, Sendable {
    public let cause: DiagnosisCause
    public let confidence: DiagnosisConfidence
    public let title: String
    public let evidence: String
}

/// Regelbasierte Einschaetzung, was zum Zeitpunkt eines Markers Probleme gemacht haben koennte.
/// Eine Heuristik auf den erfassten Messwerten, keine Gewissheit.
public struct MarkerDiagnosis: Sendable {
    private let language: AppLanguage?
    private let window: TimeInterval

    public init(language: AppLanguage? = nil, window: TimeInterval = 300) {
        self.language = language
        self.window = window
    }

    public func findings(marker: Marker, snapshots: [Snapshot], settings: AgentSettings) -> [DiagnosisFinding] {
        let metrics = MarkerMetrics.compute(marker: marker, snapshots: snapshots)
        let offenders = StatusEvaluator(
            rules: [], offenderWindow: 2 * window + 1, staleAfter: .infinity, maxOffenders: 8
        ).evaluate(snapshots: snapshots, now: snapshots.map(\.timestamp).max() ?? marker.timestamp).offenders

        var findings = [
            memoryFinding(marker.detail, windowPressure: snapshots.compactMap(\.memoryPressure).max { $0.numeric < $1.numeric }, metrics: metrics, settings: settings),
            cpuFinding(metrics: metrics, offenders: offenders, settings: settings),
            energyFinding(offenders: offenders, settings: settings),
            thermalFinding(marker.detail),
            networkFinding(marker.detail),
            hixupFinding(offenders)
        ].compactMap { $0 }

        if findings.isEmpty {
            let hasData = marker.detail != nil || !snapshots.isEmpty
            findings = [DiagnosisFinding(
                cause: hasData ? .none : .noData, confidence: .low,
                title: t(hasData ? "Keine Ursache in den Messwerten sichtbar" : "Zu wenig Daten"),
                evidence: t(hasData
                    ? "Alle erfassten Werte sind unauffällig. Mögliche Ursachen außerhalb der Messung: Festplatte, GPU oder die Anwendung selbst."
                    : "Für diesen Marker liegen keine Messpunkte und keine Tiefenmessung vor.")
            )]
        }
        let order = DiagnosisCause.allCases
        return findings.sorted {
            $0.confidence != $1.confidence
                ? $0.confidence > $1.confidence
                : (order.firstIndex(of: $0.cause) ?? 0) < (order.firstIndex(of: $1.cause) ?? 0)
        }
    }

    // MARK: - Regeln

    private func memoryFinding(
        _ detail: SystemDetail?, windowPressure: MemoryPressureLevel?, metrics: MarkerMetrics, settings: AgentSettings
    ) -> DiagnosisFinding? {
        let pressure = [detail?.memoryPressure, windowPressure].compactMap { $0 }.max { $0.numeric < $1.numeric } ?? .normal
        let lowest = metrics.freeMemory.peak
        let belowThreshold = lowest.map { $0 < settings.memoryLowPercent } ?? false
        let swapHigh = (detail?.swapUsedBytes ?? 0) > 2 * 1_073_741_824

        var confidence: DiagnosisConfidence?
        switch pressure {
        case .critical: confidence = .high
        case .warning: confidence = belowThreshold ? .high : .medium
        case .normal: confidence = belowThreshold || swapHigh ? .medium : nil
        }
        guard let confidence else { return nil }

        var parts = [t("Speicherdruck: %@", pressure.name(language: language))]
        if let lowest { parts.append(t("freier Speicher bis %@ %% (Schwelle %@ %%)", num(lowest), num(settings.memoryLowPercent))) }
        if let detail {
            parts.append(t("Swap %@ von %@", bytes(detail.swapUsedBytes), bytes(detail.swapTotalBytes)))
        }
        return DiagnosisFinding(cause: .memory, confidence: confidence, title: t("Speicherknappheit"), evidence: parts.joined(separator: "; "))
    }

    private func cpuFinding(metrics: MarkerMetrics, offenders: [Offender], settings: AgentSettings) -> DiagnosisFinding? {
        let system = metrics.cpuTotal.peak
        let top = offenders.filter { !StatusEvaluator.isOwnProcess(name: $0.name) }.max { $0.cpuPercent < $1.cpuPercent }
        let heavyProcess = top.map { $0.cpuPercent >= settings.processCPUPercent } ?? false

        let confidence: DiagnosisConfidence
        if let system, system >= settings.systemCPUPercent { confidence = .high }
        else if heavyProcess || (system ?? 0) >= 75 { confidence = .medium }
        else { return nil }

        var parts: [String] = []
        if let system { parts.append(t("Gesamt-CPU bis %@ %%", num(system))) }
        if let top, top.cpuPercent >= 50 || heavyProcess {
            parts.append(t("Hauptverbraucher: %@ (Ø CPU %@ %%)", top.name, num(top.cpuPercent)))
        }
        return DiagnosisFinding(cause: .cpu, confidence: confidence, title: t("Hohe CPU-Last"), evidence: parts.joined(separator: "; "))
    }

    private func energyFinding(offenders: [Offender], settings: AgentSettings) -> DiagnosisFinding? {
        guard let top = offenders.filter({ !StatusEvaluator.isOwnProcess(name: $0.name) }).max(by: { $0.energyWatts < $1.energyWatts }),
              top.energyWatts >= settings.processEnergyWatts else { return nil }
        return DiagnosisFinding(
            cause: .energy, confidence: .medium, title: t("Hoher Energieverbrauch"),
            evidence: t("%@: Ø %@ W (Schwelle %@ W)", top.name, num(top.energyWatts, 1), num(settings.processEnergyWatts, 1))
        )
    }

    private func thermalFinding(_ detail: SystemDetail?) -> DiagnosisFinding? {
        guard let thermal = detail?.thermal, thermal != .nominal else { return nil }
        let high = thermal == .serious || thermal == .critical
        return DiagnosisFinding(
            cause: .thermal, confidence: high ? .high : .low,
            title: t(high ? "Thermische Drosselung möglich" : "Thermik erhöht"),
            evidence: t("Thermischer Zustand: %@", thermal.name(language: language))
        )
    }

    private func networkFinding(_ detail: SystemDetail?) -> DiagnosisFinding? {
        guard let network = detail?.network else { return nil }
        var parts: [String] = []
        var confidence: DiagnosisConfidence?
        func raise(_ level: DiagnosisConfidence) { confidence = max(confidence ?? .low, level) }

        if let internet = network.internet {
            if internet.packetLossPercent >= 5 { parts.append(t("Paketverlust Internet %@ %%", num(internet.packetLossPercent, 1))); raise(.high) }
            else if let average = internet.averageMs, average >= 150 { parts.append(t("Internet-Latenz %@ ms", num(average))); raise(.medium) }
        }
        if let gateway = network.gateway {
            if gateway.packetLossPercent >= 5 { parts.append(t("Paketverlust Router %@ %%", num(gateway.packetLossPercent, 1))); raise(.high) }
            else if let average = gateway.averageMs, average >= 20 { parts.append(t("Router-Latenz %@ ms", num(average))); raise(.medium) }
        }
        guard let confidence else { return nil }
        if network.kind == .vpn { parts.append(t("VPN aktiv")) }
        return DiagnosisFinding(cause: .network, confidence: confidence, title: t("Netzwerkprobleme"), evidence: parts.joined(separator: "; "))
    }

    private func hixupFinding(_ offenders: [Offender]) -> DiagnosisFinding? {
        guard let own = offenders.first(where: { StatusEvaluator.isOwnProcess(name: $0.name) && !$0.reasons.isEmpty }) else { return nil }
        return DiagnosisFinding(
            cause: .hixup, confidence: .low, title: t("Hixup selbst verbraucht viel"),
            evidence: t("%@: Ø CPU %@ %%", own.name, num(own.cpuPercent))
        )
    }

    // MARK: - Texte

    private func t(_ key: String, _ args: CVarArg...) -> String { L10n.translate(key, language: language, args: args) }

    private func num(_ value: Double, _ fraction: Int = 0) -> String {
        let rounded = value.rounded() == value && fraction == 1 ? 0 : fraction
        return value.formatted(.number.precision(.fractionLength(rounded)).grouping(.never).locale(locale))
    }

    private func bytes(_ value: UInt64) -> String {
        let megabytes = Double(value) / 1_048_576
        return megabytes < 1_024 ? num(megabytes) + " MB" : num(megabytes / 1_024, 1) + " GB"
    }

    private var locale: Locale { Locale(identifier: L10n.resolved(language) == .de ? "de_AT" : "en_GB") }
}
