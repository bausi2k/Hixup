import HixupCore
import SwiftUI

struct SettingsView: View {
    @State private var interval: Double
    @State private var retentionDays: Int
    @State private var topCount: Int
    @State private var watched: String
    @State private var memoryLow: Double
    @State private var cpuPercent: Double
    @State private var energyWatts: Double
    @State private var systemCPU: Double
    @State private var memorySeconds: Double
    @State private var loadSeconds: Double
    @State private var message: String?

    init() {
        let settings = AgentSettings.load(from: HixupPaths.settingsURL)
        _interval = State(initialValue: settings.sampleInterval)
        _retentionDays = State(initialValue: settings.retentionDays)
        _topCount = State(initialValue: settings.topProcessCount)
        _memoryLow = State(initialValue: settings.memoryLowPercent)
        _cpuPercent = State(initialValue: settings.processCPUPercent)
        _energyWatts = State(initialValue: settings.processEnergyWatts)
        _systemCPU = State(initialValue: settings.systemCPUPercent)
        _memorySeconds = State(initialValue: settings.memoryMinimumSeconds)
        _loadSeconds = State(initialValue: settings.loadMinimumSeconds)
        _watched = State(initialValue: settings.watchedProcessNames.joined(separator: "\n"))
    }

    var body: some View {
        Form {
            Section("Messung") {
                Stepper(value: $interval, in: 1...300, step: 1) {
                    LabeledContent("Messintervall", value: "\(Int(interval)) s")
                }
                Stepper(value: $topCount, in: 1...50) {
                    LabeledContent("Prozesse pro Messung", value: "\(topCount)")
                }
                Stepper(value: $retentionDays, in: 1...365) {
                    LabeledContent("Aufbewahrung", value: "\(retentionDays) Tage")
                }
            }
            Section("Schwellen") {
                Stepper(value: $memoryLow, in: 1...90, step: 1) {
                    LabeledContent("Speicher knapp unter", value: "\(Int(memoryLow)) %")
                }
                Stepper(value: $memorySeconds, in: 10...3_600, step: 10) {
                    LabeledContent("… für mindestens", value: "\(Int(memorySeconds)) s")
                }
                Stepper(value: $cpuPercent, in: 50...1_600, step: 25) {
                    LabeledContent("Prozess-CPU über", value: "\(Int(cpuPercent)) %")
                }
                Stepper(value: $energyWatts, in: 0.5...100, step: 0.5) {
                    LabeledContent("Prozess-Energie über", value: String(format: "%.1f W", energyWatts))
                }
                Stepper(value: $systemCPU, in: 30...100, step: 5) {
                    LabeledContent("Gesamt-CPU über", value: "\(Int(systemCPU)) %")
                }
                Stepper(value: $loadSeconds, in: 10...3_600, step: 10) {
                    LabeledContent("CPU/Energie für mindestens", value: "\(Int(loadSeconds)) s")
                }
                Button("Standardwerte") { resetThresholds() }
            }
            Section("Immer erfassen") {
                TextEditor(text: $watched)
                    .font(.body.monospaced())
                    .frame(height: 80)
                    .accessibilityLabel("Beobachtete Prozesse")
                Text("Prozessnamen, getrennt durch Komma oder Zeilenumbruch, z. B. Citrix Viewer.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Marker") {
                LabeledContent("Hotkey", value: "⌃⌥⌘H")
                Text("Setzt in jeder App eine Markierung \"jetzt ruckelt es\" im Verlauf. Läuft über den Hintergrunddienst.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button("Sichern", action: save).keyboardShortcut(.defaultAction)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func save() {
        let settings = AgentSettings(
            sampleInterval: interval, retentionDays: retentionDays,
            watchedProcessNames: AgentSettings.parseWatchedNames(watched), topProcessCount: topCount,
            memoryLowPercent: memoryLow, processCPUPercent: cpuPercent, processEnergyWatts: energyWatts,
            memoryMinimumSeconds: memorySeconds, loadMinimumSeconds: loadSeconds,
            systemCPUPercent: systemCPU
        ).clamped()
        do {
            try settings.save(to: HixupPaths.settingsURL)
            message = "Gesichert. Der Dienst übernimmt es bei der nächsten Messung."
        } catch {
            message = "Fehler: \(error.localizedDescription)"
        }
    }

    private func resetThresholds() {
        let defaults = AgentSettings.defaults
        memoryLow = defaults.memoryLowPercent
        cpuPercent = defaults.processCPUPercent
        energyWatts = defaults.processEnergyWatts
        systemCPU = defaults.systemCPUPercent
        memorySeconds = defaults.memoryMinimumSeconds
        loadSeconds = defaults.loadMinimumSeconds
    }
}
