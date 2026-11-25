import HixupCore
import SwiftUI

@main
struct HixupApp: App {
    @State private var service = AgentServiceController()
    @State private var model = StatusModel()
    @State private var dashboard = DashboardModel()
    @State private var language = LanguageModel()
    @State private var visibility = VisibilityModel()

    var body: some Scene {
        MenuBarExtra(isInserted: Binding(get: { visibility.value.showMenuBarItem }, set: { visibility.setMenuBar($0) })) {
            StatusPopover(model: model, service: service).environment(language)
        } label: {
            Image(systemName: StatusPresentation.symbolName(for: model.level))
        }
        .menuBarExtraStyle(.window)

        Window("Hixup", id: "dashboard") {
            DashboardView(status: model, model: dashboard).environment(language)
        }
        .defaultLaunchBehavior(visibility.value.showInDock ? .presented : .suppressed)

        Settings {
            SettingsView().environment(language).environment(visibility)
        }
    }
}
