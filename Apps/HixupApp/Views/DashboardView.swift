import Charts
import HixupCore
import SwiftUI

struct DashboardView: View {
    let status: StatusModel
    @Bindable var model: DashboardModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if let history = model.history {
                    charts(history)
                    HStack(alignment: .top, spacing: 16) {
                        offenders(history.offenders)
                        timeline(history)
                    }
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
        return "\(mood) Am hungrigsten: \(name)"
    }

    private var header: some View {
        HStack(spacing: 12) {
            Circle().fill(status.level.color).frame(width: 16, height: 16)
            VStack(alignment: .leading) {
                Text(status.status.map(StatusPresentation.headline(for:)) ?? "Keine aktuellen Daten")
                    .font(.title2.weight(.semibold))
                Text(subtitle).foregroundStyle(.secondary)
            }
            Spacer()
            Picker("Zeitraum", selection: $model.range) {
                ForEach(HistoryRange.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 240)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Diagramme

    private func charts(_ history: History) -> some View {
        VStack(spacing: 12) {
            HistoryChart(
                title: "Freier Speicher", unit: "%",
                points: history.points.map { ($0.timestamp, $0.availableMemoryPercent) },
                tint: .blue, alerts: history.alerts, markers: history.markers,
                threshold: 15, domain: 0...100, focusedTime: model.focusedTime
            )
            HStack(spacing: 12) {
                cpuChart(history)
                HistoryChart(
                    title: "Energie", unit: "W",
                    points: history.points.map { ($0.timestamp, $0.energyWatts) },
                    tint: .orange, alerts: history.alerts, markers: history.markers,
                    focusedTime: model.focusedTime
                )
            }
        }
    }

    @ViewBuilder
    private func cpuChart(_ history: History) -> some View {
        if history.points.contains(where: { $0.systemCPUPercent != nil }) {
            HistoryChart(
                title: "CPU gesamt", unit: "%",
                points: history.points.compactMap { point in point.systemCPUPercent.map { (point.timestamp, $0) } },
                tint: .purple, alerts: history.alerts, markers: history.markers,
                threshold: AgentSettings.load(from: HixupPaths.settingsURL).systemCPUPercent,
                domain: 0...100, focusedTime: model.focusedTime
            )
        } else {
            HistoryChart(
                title: "CPU (Top-Prozesse)", unit: "%",
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
                Text("Keine Daten").foregroundStyle(.secondary)
            } else {
                Chart(offenders, id: \.name) { offender in
                    BarMark(
                        x: .value("Belastung", offender.score),
                        y: .value("Prozess", offender.name)
                    )
                    .foregroundStyle(offender.reasons.isEmpty ? Color.gray : Color.orange)
                    .annotation(position: .trailing) {
                        Text(String(format: "%.0f %% · %.1f W", offender.cpuPercent, offender.energyWatts))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .chartXAxis(.hidden)
                .frame(height: CGFloat(offenders.count) * 34 + 10)
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
                subtitle: String(format: "%.1f (Schwelle %.0f)", alert.value, alert.threshold),
                icon: alert.severity == .critical ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill",
                color: alert.severity == .critical ? .red : .orange
            )
        }
        let markers = history.markers.map {
            Entry(
                id: "m-\($0.timestamp.timeIntervalSince1970)", time: $0.timestamp,
                title: $0.note ?? "Marker", subtitle: "Manuell gesetzt",
                icon: "flag.fill", color: .blue
            )
        }
        return (alerts + markers).sorted { $0.time > $1.time }
    }

    private func timeline(_ history: History) -> some View {
        let items = entries(history)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Ereignisse").font(.headline)
            if items.isEmpty {
                Text("Keine Alerts oder Marker im Zeitraum").foregroundStyle(.secondary)
            }
            ForEach(items) { item in
                Button {
                    model.focusedTime = model.focusedTime == item.time ? nil : item.time
                } label: {
                    HStack(alignment: .firstTextBaseline) {
                        Image(systemName: item.icon).foregroundStyle(item.color)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title).font(.callout)
                            Text("\(item.time.formatted(date: .abbreviated, time: .standard)) · \(item.subtitle)")
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
                .accessibilityHint("Hebt den Zeitpunkt in den Diagrammen hervor")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }
}
