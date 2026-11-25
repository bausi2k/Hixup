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
    @State private var hoveredPoint: (Date, Double)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            if points.isEmpty {
                Text(L10n.tr("Keine Daten im Zeitraum")).font(.caption).foregroundStyle(.secondary)
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
                    .annotation(position: .top, alignment: .leading, spacing: 2) {
                        Text(L10n.tr("Schwelle %@", "\(Int(threshold)) \(unit)"))
                            .font(.caption2).foregroundStyle(.red.opacity(0.8))
                    }
            }
            ForEach(alerts, id: \.timestamp) { alert in
                PointMark(x: .value("Alert", alert.timestamp), y: .value(title, value(at: alert.timestamp)))
                    .foregroundStyle(alert.severity == .critical ? Color.red : Color.orange)
                    .symbolSize(70)
            }
            ForEach(markers, id: \.timestamp) { marker in
                RuleMark(x: .value("Marker", marker.timestamp))
                    .foregroundStyle(.blue)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))
            }
            if let hoveredPoint {
                RuleMark(x: .value("Zeit", hoveredPoint.0))
                    .foregroundStyle(.secondary.opacity(0.5))
                    .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        VStack(spacing: 1) {
                            Text("\(hoveredPoint.1.formatted(.number.precision(.fractionLength(1)).locale(L10n.locale))) \(unit)")
                                .font(.caption.weight(.semibold))
                            Text(hoveredPoint.0.formatted(date: .abbreviated, time: .standard))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        .padding(4)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                    }
            }
            if let focusedTime {
                RuleMark(x: .value("Auswahl", focusedTime))
                    .foregroundStyle(.primary)
                    .lineStyle(StrokeStyle(lineWidth: 2))
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            guard let frame = proxy.plotFrame else { return }
                            let x = location.x - geometry[frame].origin.x
                            hoveredPoint = proxy.value(atX: x, as: Date.self).flatMap(nearestPoint(to:))
                        case .ended:
                            hoveredPoint = nil
                        }
                    }
            }
        }
        .chartYAxisLabel(unit)
        .chartYScale(domain: domain.map { $0 } ?? 0...max(points.map(\.1).max() ?? 1, 1) * 1.1)
    }

    private func nearestPoint(to date: Date) -> (Date, Double)? {
        points.min { abs($0.0.timeIntervalSince(date)) < abs($1.0.timeIntervalSince(date)) }
    }

    private func value(at date: Date) -> Double {
        nearestPoint(to: date)?.1 ?? 0
    }
}
