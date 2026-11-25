import HixupCore
import SwiftUI

struct SettingsView: View {
    @State private var interval: Double
    @State private var retentionDays: Int
    @State private var topCount: Int
    @State private var watched: String
    @State private var message: String?

    init() {
        let settings = AgentSettings.load(from: HixupPaths.settingsURL)
        _interval = State(initialValue: settings.sampleInterval)
        _retentionDays = State(initialValue: settings.retentionDays)
        _topCount = State(initialValue: settings.topProcessCount)
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
            watchedProcessNames: AgentSettings.parseWatchedNames(watched), topProcessCount: topCount
        ).clamped()
        do {
            try settings.save(to: HixupPaths.settingsURL)
            message = "Gesichert. Der Dienst übernimmt es bei der nächsten Messung."
        } catch {
            message = "Fehler: \(error.localizedDescription)"
        }
    }
}
