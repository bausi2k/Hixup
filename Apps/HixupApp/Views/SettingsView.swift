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
    @State private var pressureAlerts: Bool
    @State private var message: String?
    @State private var lastLevel: SensitivityLevel
    @State private var showFineTuning = false

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
        _pressureAlerts = State(initialValue: settings.memoryPressureAlerts)
        _lastLevel = State(initialValue: SensitivityLevel.matching(settings) ?? .borderCollie)
        _watched = State(initialValue: settings.watchedProcessNames.joined(separator: "\n"))
    }

    @Environment(LanguageModel.self) private var languageModel
    @Environment(VisibilityModel.self) private var visibility

    var body: some View {
        let _ = languageModel.language
        Form {
            Section {
                sensitivity
                DisclosureGroup(L10n.tr("Feineinstellung der Schwellen"), isExpanded: $showFineTuning) { thresholds }
            } header: {
                Text(L10n.tr("Alarme"))
            } footer: {
                Text(L10n.tr("Ein Alarm entsteht, wenn ein Wert seine Schwelle für die Mindestdauer überschreitet."))
            }
            Section {
                Stepper(value: $interval, in: 1...300, step: 1) {
                    LabeledContent(L10n.tr("Messintervall"), value: "\(Int(interval)) s")
                }
                Stepper(value: $topCount, in: 1...50) {
                    LabeledContent(L10n.tr("Prozesse pro Messung"), value: "\(topCount)")
                }
                Stepper(value: $retentionDays, in: 1...365) {
                    LabeledContent(L10n.tr("Aufbewahrung"), value: L10n.tr("%d Tage", retentionDays))
                }
            } header: {
                Text(L10n.tr("Messung"))
            } footer: {
                Text(L10n.tr("Kürzere Intervalle erkennen Spitzen genauer, brauchen aber mehr Speicherplatz."))
            }
            Section {
                TextEditor(text: $watched)
                    .font(.body.monospaced())
                    .frame(height: 80)
                    .accessibilityLabel(L10n.tr("Beobachtete Prozesse"))
            } header: {
                Text(L10n.tr("Immer erfassen"))
            } footer: {
                Text(L10n.tr("Prozessnamen, getrennt durch Komma oder Zeilenumbruch, z. B. Citrix Viewer."))
            }
            Section {
                @Bindable var languageModel = languageModel
                Picker(L10n.tr("Sprache"), selection: $languageModel.language) {
                    Text(L10n.tr("System")).tag(AppLanguage.system)
                    Text("Deutsch").tag(AppLanguage.de)
                    Text("English").tag(AppLanguage.en)
                }
                Toggle(L10n.tr("Im Dock anzeigen"), isOn: Binding(
                    get: { visibility.value.showInDock }, set: { visibility.setDock($0) }
                ))
                Toggle(L10n.tr("Menüleisten-Symbol anzeigen"), isOn: Binding(
                    get: { visibility.value.showMenuBarItem }, set: { visibility.setMenuBar($0) }
                ))
            } header: {
                Text(L10n.tr("Darstellung"))
            } footer: {
                Text(L10n.tr("Mindestens eines von beiden bleibt aktiv, damit Hixup erreichbar bleibt."))
            }
            Section {
                LabeledContent("Hotkey", value: "⌃⌥⌘H")
            } header: {
                Text(L10n.tr("Marker"))
            } footer: {
                Text(L10n.tr("Setzt in jeder App eine Markierung \"jetzt ruckelt es\" im Verlauf. Läuft über den Hintergrunddienst."))
            }
            HStack {
                if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button(L10n.tr("Sichern"), action: save).keyboardShortcut(.defaultAction)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Empfindlichkeit

    private var currentSettings: AgentSettings {
        AgentSettings(
            memoryLowPercent: memoryLow, processCPUPercent: cpuPercent, processEnergyWatts: energyWatts,
            memoryMinimumSeconds: memorySeconds, loadMinimumSeconds: loadSeconds, systemCPUPercent: systemCPU
        )
    }

    private var matchingLevel: SensitivityLevel? { SensitivityLevel.matching(currentSettings) }

    private var sensitivity: some View {
        let levels = SensitivityLevel.allCases
        let slider = Binding<Double>(
            get: { Double(levels.firstIndex(of: matchingLevel ?? lastLevel) ?? 1) },
            set: { select(levels[Int($0.rounded())]) }
        )
        return VStack(alignment: .leading, spacing: 6) {
            Slider(value: slider, in: 0...Double(levels.count - 1), step: 1)
                .accessibilityLabel(L10n.tr("Empfindlichkeit"))
                .accessibilityValue((matchingLevel ?? lastLevel).title)
            HStack {
                ForEach(levels, id: \.self) { level in
                    Text(level.title)
                        .font(.caption.weight(level == matchingLevel ? .bold : .regular))
                        .frame(maxWidth: .infinity, alignment: alignment(for: level))
                }
            }
            Text(matchingLevel?.summary ?? L10n.tr("Individuell: eigene Werte aus der Feineinstellung."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func alignment(for level: SensitivityLevel) -> Alignment {
        switch level {
        case .labrador: .leading
        case .borderCollie: .center
        case .dobermann: .trailing
        }
    }

    private func select(_ level: SensitivityLevel) {
        lastLevel = level
        let preset = level.applied(to: currentSettings)
        memoryLow = preset.memoryLowPercent
        cpuPercent = preset.processCPUPercent
        energyWatts = preset.processEnergyWatts
        systemCPU = preset.systemCPUPercent
        memorySeconds = preset.memoryMinimumSeconds
        loadSeconds = preset.loadMinimumSeconds
    }

    @ViewBuilder
    private var thresholds: some View {
                Toggle(L10n.tr("Speicherdruck-Alarm"), isOn: $pressureAlerts)
                Text(L10n.tr("Alarm, wenn macOS den Speicherdruck als erhöht oder kritisch meldet."))
                    .font(.caption).foregroundStyle(.secondary)
                Stepper(value: $memoryLow, in: 1...90, step: 1) {
                    LabeledContent(L10n.tr("Speicher knapp unter"), value: "\(Int(memoryLow)) %")
                }
                Stepper(value: $memorySeconds, in: 10...3_600, step: 10) {
                    LabeledContent(L10n.tr("… für mindestens"), value: "\(Int(memorySeconds)) s")
                }
                Stepper(value: $cpuPercent, in: 50...1_600, step: 25) {
                    LabeledContent(L10n.tr("Prozess-CPU über"), value: "\(Int(cpuPercent)) %")
                }
                Stepper(value: $energyWatts, in: 0.5...100, step: 0.5) {
                    LabeledContent(L10n.tr("Prozess-Energie über"), value: String(format: "%.1f W", energyWatts))
                }
                Stepper(value: $systemCPU, in: 30...100, step: 5) {
                    LabeledContent(L10n.tr("Gesamt-CPU über"), value: "\(Int(systemCPU)) %")
                }
                Stepper(value: $loadSeconds, in: 10...3_600, step: 10) {
                    LabeledContent(L10n.tr("CPU/Energie für mindestens"), value: "\(Int(loadSeconds)) s")
                }
                Button(L10n.tr("Standardwerte (Border Collie)")) { select(.borderCollie) }
                }

    private func save() {
        let settings = AgentSettings(
            sampleInterval: interval, retentionDays: retentionDays,
            watchedProcessNames: AgentSettings.parseWatchedNames(watched), topProcessCount: topCount,
            memoryLowPercent: memoryLow, processCPUPercent: cpuPercent, processEnergyWatts: energyWatts,
            memoryMinimumSeconds: memorySeconds, loadMinimumSeconds: loadSeconds,
            systemCPUPercent: systemCPU, language: languageModel.language, memoryPressureAlerts: pressureAlerts
        ).clamped()
        do {
            try settings.save(to: HixupPaths.settingsURL)
            message = L10n.tr("Gesichert. Der Dienst übernimmt es bei der nächsten Messung.")
        } catch {
            message = L10n.tr("Fehler: %@", error.localizedDescription)
        }
    }
}
