import AppKit
import SwiftUI

@main
struct HixupApp: App {
    @State private var service = AgentServiceController()

    var body: some Scene {
        MenuBarExtra("Hixup", systemImage: "waveform.path.ecg") {
            Toggle("Hintergrunddienst", isOn: Binding(
                get: { service.isEnabled },
                set: { service.setEnabled($0) }
            ))
            Text(service.statusDescription)
            if let error = service.lastError {
                Text(error)
            }
            if service.status == .requiresApproval {
                Button("Systemeinstellungen öffnen") { service.openLoginItemSettings() }
            }
            Divider()
            Button("Beenden") { NSApplication.shared.terminate(nil) }
        }
    }
}
