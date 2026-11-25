import AppKit
import HixupCore
import SwiftUI

struct StatusPopover: View {
    let model: StatusModel
    let service: AgentServiceController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if let status = model.status, status.level != .unknown {
                tiles(status)
                if !status.violations.isEmpty { violations(status.violations) }
                offenders(status.offenders)
            } else {
                unavailable
            }
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 340)
    }

    // MARK: - Abschnitte

    private var header: some View {
        HStack(spacing: 10) {
            Circle().fill(model.level.color).frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.status.map(StatusPresentation.headline(for:)) ?? "Keine aktuellen Daten")
                    .font(.headline)
                Text(model.level.title).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }

    private func tiles(_ status: SystemStatus) -> some View {
        HStack(spacing: 8) {
            TrendTile(
                title: "Speicher frei",
                value: "\(Int(status.memory?.availablePercent ?? 0)) %",
                points: model.trend.map { ($0.timestamp, $0.availableMemoryPercent) },
                tint: .blue, domain: 0...100
            )
            TrendTile(
                title: "CPU (Top-Prozesse)",
                value: "\(Int(model.trend.last?.cpuPercent ?? 0)) %",
                points: model.trend.map { ($0.timestamp, $0.cpuPercent) },
                tint: .purple
            )
            TrendTile(
                title: "Energie",
                value: String(format: "%.1f W", model.trend.last?.energyWatts ?? 0),
                points: model.trend.map { ($0.timestamp, $0.energyWatts) },
                tint: .orange
            )
        }
    }

    private func violations(_ violations: [ActiveViolation]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Schwellen überschritten").font(.subheadline.weight(.semibold))
            ForEach(violations, id: \.ruleID) { violation in
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: violation.severity == .critical ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(violation.severity == .critical ? .red : .orange)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(violation.detail.map { "\(violation.title): \($0)" } ?? violation.title)
                            .font(.callout)
                        Text("\(StatusPresentation.valueText(violation)) (Schwelle \(StatusPresentation.thresholdText(violation))) seit \(Int(violation.duration)) s"
                            + (violation.isSustained ? "" : " – noch kein Alarm"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func offenders(_ offenders: [Offender]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Größte Verursacher").font(.subheadline.weight(.semibold))
            let maxScore = max(offenders.map(\.score).max() ?? 1, 0.001)
            ForEach(offenders, id: \.name) { offender in
                OffenderRow(offender: offender, relativeScore: offender.score / maxScore)
            }
            if offenders.isEmpty {
                Text("Keine Daten").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var unavailable: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Es liegen keine aktuellen Messwerte vor. Läuft der Hintergrunddienst?")
                .font(.callout).foregroundStyle(.secondary)
            if let error = model.loadError { Text(error).font(.caption).foregroundStyle(.red) }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Hintergrunddienst", isOn: Binding(
                get: { service.isEnabled },
                set: { service.setEnabled($0) }
            ))
            if let error = service.lastError { Text(error).font(.caption).foregroundStyle(.red) }
            if service.status == .requiresApproval {
                Button("Systemeinstellungen öffnen") { service.openLoginItemSettings() }
            }
            HStack {
                Spacer()
                Button("Beenden") { NSApplication.shared.terminate(nil) }
            }
        }
    }
}

private struct OffenderRow: View {
    let offender: Offender
    let relativeScore: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(offender.processCount > 1 ? "\(offender.name) ×\(offender.processCount)" : offender.name)
                    .font(.callout).lineLimit(1)
                Spacer()
                ForEach(offender.reasons, id: \.self) { reason in
                    Text(StatusPresentation.label(for: reason))
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(.orange.opacity(0.2), in: Capsule())
                }
            }
            ProgressView(value: relativeScore)
                .tint(offender.reasons.isEmpty ? .gray : .orange)
            Text(String(format: "CPU %.0f %% · %.1f W · %.0f Wakeups/s", offender.cpuPercent, offender.energyWatts, offender.wakeupsPerSecond))
                .font(.caption2).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
