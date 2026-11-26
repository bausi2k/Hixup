import Foundation

/// Angaben zum Mac, damit eine Analyse die Messwerte einordnen kann.
public struct SystemInfo: Equatable, Sendable {
    public let model: String
    public let chip: String
    public let memoryBytes: UInt64
    public let osVersion: String
    public let uptime: TimeInterval

    public init(model: String, chip: String, memoryBytes: UInt64, osVersion: String, uptime: TimeInterval) {
        self.model = model
        self.chip = chip
        self.memoryBytes = memoryBytes
        self.osVersion = osVersion
        self.uptime = uptime
    }

    public static func current() -> SystemInfo {
        func string(_ name: String) -> String {
            var size = 0
            guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "?" }
            var buffer = [CChar](repeating: 0, count: size)
            guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return "?" }
            return String(cString: buffer)
        }
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return SystemInfo(
            model: string("hw.model"), chip: string("machdep.cpu.brand_string"),
            memoryBytes: ProcessInfo.processInfo.physicalMemory,
            osVersion: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            uptime: ProcessInfo.processInfo.systemUptime
        )
    }
}

public struct MarkerReportInput: Sendable {
    public let markers: [Marker]
    public let snapshots: [Snapshot]
    public let alerts: [Alert]
    public let settings: AgentSettings
    public let system: SystemInfo

    public init(markers: [Marker], snapshots: [Snapshot], alerts: [Alert], settings: AgentSettings, system: SystemInfo) {
        self.markers = markers
        self.snapshots = snapshots
        self.alerts = alerts
        self.settings = settings
        self.system = system
    }
}

/// Erzeugt aus Markern, Messwerten und Alerts einen Markdown-Bericht, den man einer KI zur Ursachenanalyse
/// uebergeben kann. Rein berechnend und damit testbar.
public struct MarkerReportBuilder: Sendable {
    private let language: AppLanguage?
    private let timeZone: TimeZone
    private let window: TimeInterval
    private let now: Date
    private let includeAssessment: Bool

    /// - Parameters:
    ///   - language: Sprache des Berichts; `nil` nutzt die aktuelle Sprache.
    ///   - window: Sekunden vor und nach einem Marker, die betrachtet werden.
    ///   - includeAssessment: Nimmt die heuristische Einschaetzung von Hixup in den Bericht auf.
    ///   - now: Obergrenze fuer die erwartete Messpunktzahl; Zukunft zaehlt nicht als Luecke.
    public init(
        language: AppLanguage? = nil, timeZone: TimeZone = .current, window: TimeInterval = 300, now: Date = Date(),
        includeAssessment: Bool = true
    ) {
        self.includeAssessment = includeAssessment
        self.now = now
        self.language = language
        self.timeZone = timeZone
        self.window = window
    }

    public func build(_ input: MarkerReportInput) -> String {
        var lines = [t("# Hixup-Bericht: Ruckler-Analyse"), "", t(Key.intro), ""]
        lines += systemSection(input)
        let markers = input.markers.sorted { $0.timestamp < $1.timestamp }
        if markers.isEmpty { lines += ["", t("Keine Marker im Zeitraum.")] }
        for (index, marker) in markers.enumerated() {
            lines += [""] + markerSection(marker, number: index + 1, input: input)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - System

    private func systemSection(_ input: MarkerReportInput) -> [String] {
        let system = input.system
        let settings = input.settings
        return [
            t("## System"),
            "- " + t(
                "Gerät: %@ · %@ · %@ GB RAM · macOS %@ · Betriebszeit %@", system.model, system.chip,
                number(Double(system.memoryBytes) / 1_073_741_824, fraction: 1), system.osVersion, uptimeText(system.uptime)
            ),
            "- " + t(
                "Messung: alle %@ s; erfasst werden Speicher, Gesamt-CPU und die belastungsstärksten Prozesse (CPU, Energie, RAM, Wakeups).",
                number(settings.sampleInterval, fraction: 0)
            ),
            "- " + t(
                "Schwellen: freier Speicher unter %@ %%, Prozess-CPU über %@ %%, Prozess-Energie über %@ W, Gesamt-CPU über %@ %%.",
                number(settings.memoryLowPercent, fraction: 0), number(settings.processCPUPercent, fraction: 0),
                number(settings.processEnergyWatts, fraction: 1), number(settings.systemCPUPercent, fraction: 0)
            ),
            "- " + t("Nicht erfasst: Festplatten-Last, GPU, einzelne Fenster; Netzwerk nur beim Marker.")
        ]
    }

    private func uptimeText(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        let days = minutes / 1_440
        if days > 0 { return t("%d T. %d Std.", days, minutes % 1_440 / 60) }
        return t("%d Std. %d Min.", minutes / 60, minutes % 60)
    }

    // MARK: - Marker

    private func markerSection(_ marker: Marker, number index: Int, input: MarkerReportInput) -> [String] {
        let title = marker.note.map { " – „\($0)“" } ?? ""
        var lines = ["## Marker \(index) – \(dateText(marker.timestamp))\(title)", ""]
        lines += detailLines(marker.detail)

        let start = marker.timestamp.addingTimeInterval(-window)
        let end = marker.timestamp.addingTimeInterval(window)
        let inWindow = input.snapshots.filter { $0.timestamp >= start && $0.timestamp <= end }
            .sorted { $0.timestamp < $1.timestamp }
        let observed = min(end, now).timeIntervalSince(start)
        let expected = max(Int(observed / max(input.settings.sampleInterval, 1)), 0)

        lines += [""] + metricTable(marker: marker, snapshots: inWindow)
        if includeAssessment { lines += [""] + assessmentLines(marker: marker, snapshots: inWindow, settings: input.settings) }
        if inWindow.count * 10 < expected * 7 {
            lines += ["", t("Hinweis: Nur %d von ca. %d erwarteten Messpunkten im Fenster (lief der Dienst zeitweise nicht?).", inWindow.count, expected)]
        }
        lines += [""] + appLines(inWindow)
        lines += [""] + alertLines(input.alerts.filter { $0.timestamp >= start && $0.timestamp <= end })
        return lines
    }

    private func assessmentLines(marker: Marker, snapshots: [Snapshot], settings: AgentSettings) -> [String] {
        let findings = MarkerDiagnosis(language: language, window: window)
            .findings(marker: marker, snapshots: snapshots, settings: settings)
        var lines = [t("### Vorläufige Einschätzung von Hixup (heuristisch, kann falsch sein)")]
        for finding in findings {
            lines.append("- **\(finding.title)** (\(finding.confidence.name(language: language))): \(finding.evidence)")
        }
        return lines
    }

    private func detailLines(_ detail: SystemDetail?) -> [String] {
        guard let detail else { return [t("Keine Tiefenmessung vorhanden (älterer Marker oder die Messung lief nicht durch).")] }
        return [t("### Tiefenmessung beim Marker")] + detailSummary(detail).map { "- " + $0 }
    }

    /// Die Zeilen der Tiefenmessung als Text, auch fuer die Oberflaeche.
    public func detailSummary(_ detail: SystemDetail) -> [String] {
        var lines = [
            t("Speicherdruck: %@", detail.memoryPressure.name(language: language)),
            t("Swap: %@ von %@", bytesText(detail.swapUsedBytes), bytesText(detail.swapTotalBytes)),
            t("Thermik: %@", detail.thermal.name(language: language)),
            t("Energiesparmodus: %@", detail.lowPowerMode ? t("an") : t("aus"))
        ]
        let network = detail.network
        let interface = network.interface.map { " (\($0))" } ?? ""
        lines.append(t("Netzwerk: %@", network.kind.name(language: language) + interface))
        if let gateway = network.gateway { lines.append(t("Router (%@): %@", gateway.host, latencyText(gateway))) }
        if let internet = network.internet { lines.append(t("Internet (%@): %@", internet.host, latencyText(internet))) }
        return lines
    }

    private func latencyText(_ probe: LatencyProbe) -> String {
        let loss = number(probe.packetLossPercent, fraction: probe.packetLossPercent.rounded() == probe.packetLossPercent ? 0 : 1)
        guard let average = probe.averageMs, let maximum = probe.maxMs else {
            return t("keine Antwort (%@ %% Paketverlust)", loss)
        }
        return t("%@ ms Ø, max %@ ms, %@ %% Paketverlust", number(average, fraction: 0), number(maximum, fraction: 0), loss)
    }

    // MARK: - Messwerte

    private func metricTable(marker: Marker, snapshots: [Snapshot]) -> [String] {
        let metrics = MarkerMetrics.compute(marker: marker, snapshots: snapshots)
        func row(_ name: String, _ metric: MarkerMetric, text: (Double) -> String) -> String {
            "| \(name) | \(metric.before.map(text) ?? "–") | \(metric.atMarker.map(text) ?? "–") | \(metric.peak.map(text) ?? "–") |"
        }
        return [
            "| " + t("Messwert") + " | " + t("Ø davor (%d Min.)", Int(window / 60)) + " | " + t("Beim Marker") + " | " + t("Spitze im Fenster") + " |",
            "|---|---|---|---|",
            row(t("Freier Speicher"), metrics.freeMemory, text: percentText),
            row(t("CPU gesamt"), metrics.cpuTotal, text: percentText),
            row(t("Energie (Summe Top-Prozesse)"), metrics.energy, text: { number($0, fraction: 1) + " W" })
        ]
    }

    private func appLines(_ snapshots: [Snapshot]) -> [String] {
        guard let last = snapshots.last else { return [t("Keine Messpunkte im Fenster.")] }
        let offenders = StatusEvaluator(
            rules: [], offenderWindow: 2 * window + 1, staleAfter: .infinity, maxOffenders: 5
        ).evaluate(snapshots: snapshots, now: last.timestamp).offenders
        var lines = [t("Ressourcenhungrigste Apps im Fenster (±%d Min.):", Int(window / 60))]
        for offender in offenders {
            let name = offender.processCount > 1 ? "\(offender.name) ×\(offender.processCount)" : offender.name
            lines.append("- " + t(
                "%@: Ø CPU %@, %@ W, %@ RAM", name, percentText(offender.cpuPercent),
                number(offender.energyWatts, fraction: 1), bytesText(offender.residentBytes)
            ))
        }
        return lines
    }

    private func alertLines(_ alerts: [Alert]) -> [String] {
        guard !alerts.isEmpty else { return [t("Keine Alerts im Fenster.")] }
        var lines = [t("Alerts im Fenster:")]
        for alert in alerts.sorted(by: { $0.timestamp < $1.timestamp }) {
            let cause = alert.detail.map { ": \($0)" } ?? ""
            lines.append("- " + t(
                "%@ – %@%@ (%@, Wert %@, Schwelle %@)", timeText(alert.timestamp), alert.title, cause,
                alert.severity == .critical ? t("kritisch") : t("Warnung"),
                number(alert.value, fraction: 1), number(alert.threshold, fraction: 0)
            ))
        }
        return lines
    }

    // MARK: - Texte

    private func bytesText(_ bytes: UInt64) -> String {
        let megabytes = Double(bytes) / 1_048_576
        if megabytes < 1_024 { return number(megabytes, fraction: 0) + " MB" }
        return number(megabytes / 1_024, fraction: 1) + " GB"
    }

    private func percentText(_ value: Double) -> String { number(value, fraction: 0) + " %" }

    private func number(_ value: Double, fraction: Int) -> String {
        value.formatted(.number.precision(.fractionLength(fraction)).grouping(.never).locale(locale))
    }

    private var locale: Locale { Locale(identifier: L10n.resolved(language) == .de ? "de_AT" : "en_GB") }

    private func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        return formatter
    }

    private func dateText(_ date: Date) -> String {
        formatter(L10n.resolved(language) == .de ? "dd.MM.yyyy HH:mm:ss" : "yyyy-MM-dd HH:mm:ss").string(from: date)
    }

    private func timeText(_ date: Date) -> String { formatter("HH:mm:ss").string(from: date) }

    private func t(_ key: String, _ args: CVarArg...) -> String {
        L10n.translate(key, language: language, args: args)
    }

    private enum Key {
        static let intro = "Dieser Bericht stammt von Hixup, einer Überwachung für den Mac. Ein „Marker“ bedeutet: Der Nutzer hat in diesem Moment einen Ruckler oder Hänger bemerkt. Bitte analysiere pro Marker die wahrscheinlichste Ursache anhand der Messwerte, nenne Auffälligkeiten (Speicherdruck, CPU, Energie, Thermik, Netzwerk) und empfiehl konkrete nächste Schritte."
    }
}
