import AppKit
import Charts
import HixupCore
import SwiftUI
import UniformTypeIdentifiers

struct DashboardView: View {
    let status: StatusModel
    @Bindable var model: DashboardModel
    @State private var eventFilter = EventFilter.all
    @State private var exportMessage: String?

    @Environment(LanguageModel.self) private var languageModel

    var body: some View {
        let _ = languageModel.language
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if let history = model.history {
                    charts(history)
                    timeline(history)
                } else if let error = model.loadError {
                    Text(error).foregroundStyle(.red)
                }
            }
            .padding(20)
        }
        .frame(minWidth: 760, minHeight: 640)
    }

    // MARK: - Kopf

    private var subtitle: String {
        let mood = StatusPresentation.mood(for: status.level)
        guard let name = status.status.flatMap(StatusPresentation.hungriestApp(in:)) else { return mood }
        return "\(mood) " + L10n.tr("Am hungrigsten: %@", name)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Circle().fill(status.level.color).frame(width: 16, height: 16)
            VStack(alignment: .leading) {
                Text(status.status.map(StatusPresentation.headline(for:)) ?? L10n.tr("Keine aktuellen Daten"))
                    .font(.title2.weight(.semibold))
                Text(subtitle).foregroundStyle(.secondary)
            }
            Spacer()
            Picker(L10n.tr("Zeitraum"), selection: $model.range) {
                ForEach(HistoryRange.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 240)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Diagramme

    private func charts(_ history: History) -> some View {
        let settings = AgentSettings.load(from: HixupPaths.settingsURL)
        return Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                HistoryChart(
                    title: L10n.tr("Freier Speicher"), unit: "%",
                    points: history.points.map { ($0.timestamp, $0.availableMemoryPercent) },
                    tint: .blue, alerts: history.alerts, markers: history.markers,
                    threshold: settings.memoryLowPercent, domain: 0...100, focusedTime: model.focusedTime
                )
                cpuChart(history, threshold: settings.systemCPUPercent)
            }
            GridRow {
                HistoryChart(
                    title: L10n.tr("Energie"), unit: "W",
                    points: history.points.map { ($0.timestamp, $0.energyWatts) },
                    tint: .orange, alerts: history.alerts, markers: history.markers,
                    focusedTime: model.focusedTime
                )
                offenders(history.offenders)
            }
        }
    }

    @ViewBuilder
    private func cpuChart(_ history: History, threshold: Double) -> some View {
        if history.points.contains(where: { $0.systemCPUPercent != nil }) {
            HistoryChart(
                title: L10n.tr("CPU gesamt"), unit: "%",
                points: history.points.compactMap { point in point.systemCPUPercent.map { (point.timestamp, $0) } },
                tint: .purple, alerts: history.alerts, markers: history.markers,
                threshold: threshold,
                domain: 0...100, focusedTime: model.focusedTime
            )
        } else {
            HistoryChart(
                title: L10n.tr("CPU (Top-Prozesse)"), unit: "%",
                points: history.points.map { ($0.timestamp, $0.cpuPercent) },
                tint: .purple, alerts: history.alerts, markers: history.markers,
                focusedTime: model.focusedTime
            )
        }
    }

    // MARK: - Verursacher

    private func offenders(_ offenders: [Offender]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(StatusPresentation.hungriestAppRangeTitle).font(.headline)
            if offenders.isEmpty {
                Text(L10n.tr("Kein Hunger in Sicht")).foregroundStyle(.secondary)
            } else {
                Table(offenders) {
                    TableColumn(L10n.tr("Name")) { offender in
                        Text(offender.processCount > 1 ? "\(offender.name) ×\(offender.processCount)" : offender.name)
                            .foregroundStyle(offender.reasons.isEmpty ? Color.primary : Color.orange)
                    }
                    TableColumn(L10n.tr("CPU")) { Text(StatusPresentation.cpuText($0.cpuPercent)).monospacedDigit() }
                        .width(60)
                    TableColumn(L10n.tr("Energie")) { Text(StatusPresentation.energyText($0.energyWatts)).monospacedDigit() }
                        .width(60)
                    TableColumn(L10n.tr("Speicher")) {
                        Text(StatusPresentation.memoryText(bytes: $0.residentBytes)).monospacedDigit()
                    }
                    .width(70)
                }
                .frame(height: CGFloat(offenders.count) * 28 + 36)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Zeitleiste

    private struct Entry: Identifiable {
        let id: String
        let time: Date
        let title: String
        let subtitle: String
        let icon: String
        let color: Color
    }

    private func entries(_ history: History) -> [Entry] {
        let alerts = history.alerts.map { alert in
            Entry(
                id: "a-\(alert.ruleID)-\(alert.timestamp.timeIntervalSince1970)", time: alert.timestamp,
                title: alert.detail.map { "\(alert.title): \($0)" } ?? alert.title,
                subtitle: L10n.tr("%.1f (Schwelle %.0f)", alert.value, alert.threshold),
                icon: alert.severity == .critical ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill",
                color: alert.severity == .critical ? .red : .orange
            )
        }
        let markers = history.markers.map {
            Entry(
                id: "m-\($0.timestamp.timeIntervalSince1970)", time: $0.timestamp,
                title: $0.note ?? L10n.tr("Marker"), subtitle: L10n.tr("Manuell gesetzt"),
                icon: "flag.fill", color: .blue
            )
        }
        return (alerts + markers).sorted { $0.time > $1.time }
    }

    private enum EventFilter: CaseIterable {
        case all, alerts, markers

        var title: String {
            switch self {
            case .all: L10n.tr("Alle")
            case .alerts: L10n.tr("Alerts")
            case .markers: L10n.tr("Marker")
            }
        }
    }

    private func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return L10n.tr("Heute") }
        if calendar.isDateInYesterday(day) { return L10n.tr("Gestern") }
        return day.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(L10n.locale))
    }

    private func timeline(_ history: History) -> some View {
        let items = entries(history).filter { entry in
            switch eventFilter {
            case .all: true
            case .alerts: entry.id.hasPrefix("a-")
            case .markers: entry.id.hasPrefix("m-")
            }
        }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.tr("Ereignisse")).font(.headline)
                Spacer()
                Picker(L10n.tr("Ereignisse"), selection: $eventFilter) {
                    ForEach(EventFilter.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 220)
                exportMenu(history)
            }
            if let exportMessage { Text(exportMessage).font(.caption).foregroundStyle(.secondary) }
            if items.isEmpty {
                Text(L10n.tr("Keine Alerts oder Marker im Zeitraum")).foregroundStyle(.secondary)
            }
            ForEach(DayGrouping.group(items, date: \.time), id: \.day) { group in
                Text(dayTitle(group.day)).font(.subheadline.weight(.semibold)).padding(.top, 4)
                ForEach(group.items) { item in entryRow(item, history: history) }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }

    private func entryRow(_ item: Entry, history: History) -> some View {
        Button {
            model.focusedTime = model.focusedTime == item.time ? nil : item.time
        } label: {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: item.icon).foregroundStyle(item.color)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title).font(.callout)
                    Text("\(item.time.formatted(date: .omitted, time: .standard)) · \(item.subtitle)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(6)
            .background(
                model.focusedTime == item.time ? Color.accentColor.opacity(0.15) : .clear,
                in: RoundedRectangle(cornerRadius: 6)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(L10n.tr("Hebt den Zeitpunkt in den Diagrammen hervor"))
        .contextMenu {
            if let marker = history.markers.first(where: { $0.timestamp == item.time }) {
                Button(L10n.tr("Marker für KI kopieren")) { copyReport([marker]) }
            }
        }
    }

    // MARK: - KI-Export

    private func exportMenu(_ history: History) -> some View {
        Menu {
            Button(L10n.tr("Alle Marker kopieren")) { copyReport(history.markers) }
            Button(L10n.tr("Alle Marker als Datei sichern…")) { saveReport(history.markers) }
        } label: {
            Label(L10n.tr("Für KI exportieren"), systemImage: "square.and.arrow.up")
        }
        .menuStyle(.borderlessButton).fixedSize()
        .disabled(history.markers.isEmpty)
        .help(L10n.tr("Erzeugt einen Bericht mit Messwerten rund um die Marker für eine KI-Analyse"))
    }

    private func copyReport(_ markers: [Marker]) {
        guard let text = model.report(for: markers) else {
            exportMessage = L10n.tr("Bericht konnte nicht erstellt werden")
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        exportMessage = L10n.tr("In die Zwischenablage kopiert")
    }

    private func saveReport(_ markers: [Marker]) {
        guard let text = model.report(for: markers) else {
            exportMessage = L10n.tr("Bericht konnte nicht erstellt werden")
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = "hixup-report-\(Date.now.formatted(.iso8601.year().month().day())).md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            exportMessage = L10n.tr("Bericht gespeichert")
        } catch {
            exportMessage = L10n.tr("Fehler: %@", error.localizedDescription)
        }
    }
}
