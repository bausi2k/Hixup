import Charts
import HixupCore
import SwiftUI

/// Verlaufsdiagramm mit Alerts, Markern, optionaler Schwelle und hervorgehobenem Zeitpunkt.
struct HistoryChart: View {
    let title: String
    let unit: String
    let points: [(Date, Double)]
    let tint: Color
    let alerts: [HixupCore.Alert]
    let markers: [Marker]
    var threshold: Double?
    var domain: ClosedRange<Double>?
    let focusedTime: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            if points.isEmpty {
                Text("Keine Daten im Zeitraum").font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                chart.frame(height: 140)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private var chart: some View {
        Chart {
            ForEach(points, id: \.0) { point in
                AreaMark(x: .value("Zeit", point.0), y: .value(title, point.1))
                    .foregroundStyle(tint.opacity(0.18))
                LineMark(x: .value("Zeit", point.0), y: .value(title, point.1))
                    .foregroundStyle(tint)
            }
            if let threshold {
                RuleMark(y: .value("Schwelle", threshold))
                    .foregroundStyle(.red.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
            ForEach(alerts, id: \.timestamp) { alert in
                RuleMark(x: .value("Alert", alert.timestamp))
                    .foregroundStyle(alert.severity == .critical ? Color.red : Color.orange)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
            ForEach(markers, id: \.timestamp) { marker in
                RuleMark(x: .value("Marker", marker.timestamp))
                    .foregroundStyle(.blue)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))
            }
            if let focusedTime {
                RuleMark(x: .value("Auswahl", focusedTime))
                    .foregroundStyle(.primary)
                    .lineStyle(StrokeStyle(lineWidth: 2))
            }
        }
        .chartYAxisLabel(unit)
        .chartYScale(domain: domain.map { $0 } ?? 0...max(points.map(\.1).max() ?? 1, 1) * 1.1)
    }
}
