import HixupCore
import SwiftUI

@main
struct HixupApp: App {
    @State private var service = AgentServiceController()
    @State private var model = StatusModel()

    var body: some Scene {
        MenuBarExtra {
            StatusPopover(model: model, service: service)
        } label: {
            Image(systemName: StatusPresentation.symbolName(for: model.level))
        }
        .menuBarExtraStyle(.window)
    }
}
