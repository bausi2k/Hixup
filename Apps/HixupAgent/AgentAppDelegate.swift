import AppKit
import Carbon.HIToolbox
import HixupCore
import OSLog

final class AgentAppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "casa.gruber.hixup.agent", category: "agent")
    private var runTask: Task<Void, Never>?
    private var hotKey: HotKeyMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let notifier = UserNotificationAlertNotifier()
        notifier.requestAuthorization()

        do {
            try FileManager.default.createDirectory(at: HixupPaths.supportDirectory, withIntermediateDirectories: true)
            let store = try SQLiteSnapshotStore(path: HixupPaths.databaseURL.path)
            let events = try SQLiteEventStore(path: HixupPaths.databaseURL.path)
            let logger = logger
            let runner = AgentRunner(
                sampler: SystemSnapshotSampler(),
                store: store,
                events: events,
                engine: RuleEngine(rules: DefaultRules.all),
                rulesForSettings: { settings in
                    L10n.setLanguage(settings.language)
                    return DefaultRules.rules(for: settings)
                },
                notifier: notifier,
                loadSettings: { AgentSettings.load(from: HixupPaths.settingsURL) },
                reportError: { logger.error("\(String(describing: $0), privacy: .public)") }
            )
            runTask = Task { await runner.run() }
            registerMarkerHotKey(recorder: MarkerRecorder(events: events))
            logger.info("Agent gestartet")
        } catch {
            logger.fault("Start fehlgeschlagen: \(String(describing: error), privacy: .public)")
            NSApp.terminate(nil)
        }
    }

    /// Ctrl+Option+Cmd+H setzt eine Markierung, egal in welcher App.
    private func registerMarkerHotKey(recorder: MarkerRecorder) {
        let logger = logger
        hotKey = HotKeyMonitor(keyCode: kVK_ANSI_H, modifiers: controlKey | optionKey | cmdKey) {
            do {
                try recorder.mark()
                NSSound(named: "Pop")?.play()
            } catch {
                logger.error("Marker fehlgeschlagen: \(String(describing: error), privacy: .public)")
            }
        }
        if hotKey == nil { logger.error("Hotkey konnte nicht registriert werden") }
    }

    func applicationWillTerminate(_ notification: Notification) {
        runTask?.cancel()
    }
}
