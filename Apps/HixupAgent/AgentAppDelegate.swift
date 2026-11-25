import AppKit
import HixupCore
import OSLog

final class AgentAppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "casa.gruber.hixup.agent", category: "agent")
    private var runTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let notifier = UserNotificationAlertNotifier()
        notifier.requestAuthorization()

        do {
            try FileManager.default.createDirectory(at: HixupPaths.supportDirectory, withIntermediateDirectories: true)
            let store = try SQLiteSnapshotStore(path: HixupPaths.databaseURL.path)
            let logger = logger
            let runner = AgentRunner(
                sampler: SystemSnapshotSampler(),
                store: store,
                engine: RuleEngine(rules: DefaultRules.all),
                notifier: notifier,
                loadSettings: { AgentSettings.load(from: HixupPaths.settingsURL) },
                reportError: { logger.error("\(String(describing: $0), privacy: .public)") }
            )
            runTask = Task { await runner.run() }
            logger.info("Agent gestartet")
        } catch {
            logger.fault("Start fehlgeschlagen: \(String(describing: error), privacy: .public)")
            NSApp.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        runTask?.cancel()
    }
}
