import Charts
import HixupCore
import SwiftUI

/// Kachel mit aktuellem Wert und Verlaufslinie.
struct TrendTile: View {
    let title: String
    let value: String
    let points: [(Date, Double)]
    let tint: Color
    var domain: ClosedRange<Double>?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.monospacedDigit().weight(.semibold))
            chart.frame(height: 32)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var chart: some View {
        let base = Chart(points, id: \.0) { point in
            AreaMark(x: .value("Zeit", point.0), y: .value(title, point.1))
                .foregroundStyle(tint.opacity(0.2))
            LineMark(x: .value("Zeit", point.0), y: .value(title, point.1))
                .foregroundStyle(tint)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        if let domain {
            base.chartYScale(domain: domain)
        } else {
            base.chartYScale(domain: .automatic(includesZero: true))
        }
    }
}
