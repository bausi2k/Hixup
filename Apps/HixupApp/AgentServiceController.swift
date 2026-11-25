import Observation
import ServiceManagement

/// Meldet den eingebetteten Agent (Login-Item) an und ab.
@MainActor
@Observable
final class AgentServiceController {
    private let service = SMAppService.loginItem(identifier: "casa.gruber.hixup.agent")

    private(set) var status: SMAppService.Status
    private(set) var lastError: String?

    init() {
        status = service.status
    }

    var isEnabled: Bool { status == .enabled }

    var statusDescription: String {
        switch status {
        case .enabled: "Hintergrunddienst läuft"
        case .requiresApproval: "Freigabe in den Systemeinstellungen nötig"
        case .notRegistered: "Hintergrunddienst aus"
        case .notFound: "Agent nicht gefunden"
        @unknown default: "Unbekannter Status"
        }
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        status = service.status
    }

    func openLoginItemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
