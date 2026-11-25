import HixupCore
import SwiftUI

@main
struct HixupApp: App {
    @State private var service = AgentServiceController()
    @State private var model = StatusModel()
    @State private var dashboard = DashboardModel()
    @State private var language = LanguageModel()

    var body: some Scene {
        MenuBarExtra {
            StatusPopover(model: model, service: service).environment(language)
        } label: {
            Image(systemName: StatusPresentation.symbolName(for: model.level))
        }
        .menuBarExtraStyle(.window)

        Window("Hixup", id: "dashboard") {
            DashboardView(status: model, model: dashboard).environment(language)
        }

        Settings {
            SettingsView().environment(language)
        }
    }
}
