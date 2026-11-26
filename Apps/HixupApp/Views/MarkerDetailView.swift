import AppKit
import HixupCore
import SwiftUI
import UniformTypeIdentifiers

/// Detailansicht eines Markers: Messwerte, moegliche Ursachen und Vorschau des KI-Berichts.
struct MarkerDetailView: View {
    let marker: Marker
    let model: DashboardModel

    @Environment(\.dismiss) private var dismiss
    @Environment(LanguageModel.self) private var languageModel
    @AppStorage("includeAssessment") private var includeAssessment = true
    @State private var insight: MarkerInsight?
    @State private var reportText = ""
    @State private var showPreview = false
    @State private var message: String?
    @State private var note: String

    init(marker: Marker, model: DashboardModel) {
        self.marker = marker
        self.model = model
        _note = State(initialValue: marker.note ?? "")
    }

    /// Der Marker mit der gerade eingetragenen Notiz; Grundlage fuer Titel und Bericht.
    private var current: Marker {
        Marker(timestamp: marker.timestamp, note: note.isEmpty ? nil : note, detail: marker.detail)
    }

    var body: some View {
        let _ = languageModel.language
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    measurements
                    causes
                    aiSection
                }
                .padding(20)
            }
            Divider()
            footer
        }
        .frame(minWidth: 560, idealWidth: 600, minHeight: 640)
        .onAppear(perform: load)
        .onChange(of: includeAssessment) { _, _ in reloadReport() }
    }

    // MARK: - Abschnitte

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(current.note ?? L10n.tr("Marker"), systemImage: "flag.fill")
                .font(.title2.weight(.semibold)).foregroundStyle(.primary)
            TextField(L10n.tr("Notiz hinzufügen"), text: $note)
                .textFieldStyle(.roundedBorder)
                .onSubmit(saveNote)
                .padding(.vertical, 2)
            Text(marker.timestamp.formatted(date: .complete, time: .standard))
                .foregroundStyle(.secondary)
        }
    }

    private var measurements: some View {
        card(L10n.tr("Messwerte beim Marker")) {
            if let detail = marker.detail {
                ForEach(MarkerReportBuilder().detailSummary(detail), id: \.self) { Text($0).font(.callout) }
            } else {
                Text(L10n.tr("Keine Tiefenmessung für diesen Marker.")).foregroundStyle(.secondary)
            }
            if let insight {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                    GridRow {
                        Text(L10n.tr("Messwert"))
                        Text(L10n.tr("Ø davor (%d Min.)", 5))
                        Text(L10n.tr("Beim Marker"))
                        Text(L10n.tr("Spitze im Fenster"))
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    Divider()
                    metricRow(L10n.tr("Freier Speicher"), insight.metrics.freeMemory, StatusPresentation.cpuText)
                    metricRow(L10n.tr("CPU gesamt"), insight.metrics.cpuTotal, StatusPresentation.cpuText)
                    metricRow(L10n.tr("Energie (Summe Top-Prozesse)"), insight.metrics.energy, StatusPresentation.energyText)
                }
                .padding(.top, 4)
                Text(L10n.tr("Messpunkte im Fenster: %d", insight.sampleCount))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func metricRow(_ name: String, _ metric: MarkerMetric, _ text: (Double) -> String) -> some View {
        GridRow {
            Text(name)
            Text(metric.before.map(text) ?? "–")
            Text(metric.atMarker.map(text) ?? "–")
            Text(metric.peak.map(text) ?? "–")
        }
        .font(.callout.monospacedDigit())
    }

    private var causes: some View {
        card(L10n.tr("Mögliche Ursachen")) {
            if let insight {
                ForEach(Array(insight.findings.enumerated()), id: \.offset) { _, finding in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(finding.title).font(.callout.weight(.semibold))
                            Text(finding.confidence.name())
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(color(finding.confidence).opacity(0.2), in: Capsule())
                        }
                        Text(finding.evidence).font(.caption).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            Text(L10n.tr("Heuristische Einschätzung auf den erfassten Messwerten, keine Gewissheit."))
                .font(.caption2).foregroundStyle(.tertiary).padding(.top, 2)
        }
    }

    private var aiSection: some View {
        card(L10n.tr("Was an die KI geht")) {
            Text(L10n.tr("Hixup sendet nichts selbst. Der Bericht verlässt die App nur, wenn Du ihn kopierst oder speicherst."))
                .font(.callout)
            Text(L10n.tr("Enthalten: Prozessnamen, Messwerte und Systemdaten (Modell, macOS-Version). Nicht enthalten: Dateiinhalte, Dateinamen, Benutzername."))
                .font(.caption).foregroundStyle(.secondary)
            Toggle(L10n.tr("Einschätzung von Hixup im Bericht"), isOn: $includeAssessment)
            DisclosureGroup(
                "\(L10n.tr("Vorschau des Berichts")) · \(L10n.tr("%d Zeichen", reportText.count))", isExpanded: $showPreview
            ) {
                ScrollView {
                    Text(reportText)
                        .font(.caption.monospaced()).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 220)
                .padding(8)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private var footer: some View {
        HStack {
            if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
            Spacer()
            Button(L10n.tr("Kopieren"), action: copy)
            Button(L10n.tr("Als Datei sichern…"), action: save)
            Button(L10n.tr("Schließen")) { dismiss() }.keyboardShortcut(.defaultAction)
        }
        .padding(12)
    }

    // MARK: - Hilfen

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }

    private func color(_ confidence: DiagnosisConfidence) -> Color {
        switch confidence {
        case .high: .red
        case .medium: .orange
        case .low: .gray
        }
    }

    private func load() {
        insight = model.insight(for: marker)
        reloadReport()
    }

    private func reloadReport() {
        reportText = model.report(for: [current], includeAssessment: includeAssessment) ?? ""
    }

    private func saveNote() {
        guard let updated = model.updateNote(note, for: marker) else { return }
        note = updated.note ?? ""
        reloadReport()
        message = L10n.tr("Notiz gespeichert")
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(reportText, forType: .string)
        message = L10n.tr("In die Zwischenablage kopiert")
    }

    private func save() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = "hixup-report-\(marker.timestamp.formatted(.iso8601.year().month().day())).md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try reportText.write(to: url, atomically: true, encoding: .utf8)
            message = L10n.tr("Bericht gespeichert")
        } catch {
            message = L10n.tr("Fehler: %@", error.localizedDescription)
        }
    }
}
