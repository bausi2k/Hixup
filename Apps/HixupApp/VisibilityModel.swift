import AppKit
import HixupCore
import Observation

/// Dock-Symbol und Menueleisten-Symbol der App; wird in den UserDefaults gespeichert.
@MainActor @Observable
final class VisibilityModel {
    private static let dockKey = "showInDock"
    private static let menuBarKey = "showMenuBarItem"

    private(set) var value: AppVisibility

    init() {
        let defaults = UserDefaults.standard
        let stored = AppVisibility(
            showInDock: defaults.object(forKey: Self.dockKey) as? Bool ?? true,
            showMenuBarItem: defaults.object(forKey: Self.menuBarKey) as? Bool ?? true
        )
        value = stored.normalized()
        applyActivationPolicy()
    }

    func setDock(_ enabled: Bool) { update(value.settingDock(enabled)) }
    func setMenuBar(_ enabled: Bool) { update(value.settingMenuBar(enabled)) }

    private func update(_ new: AppVisibility) {
        value = new
        let defaults = UserDefaults.standard
        defaults.set(new.showInDock, forKey: Self.dockKey)
        defaults.set(new.showMenuBarItem, forKey: Self.menuBarKey)
        applyActivationPolicy()
        if new.showInDock { NSApplication.shared.activate(ignoringOtherApps: true) }
    }

    private func applyActivationPolicy() {
        let policy: NSApplication.ActivationPolicy = value.showInDock ? .regular : .accessory
        // SwiftUI kann den Initialisierer mehrfach ausfuehren; ein unveraenderter Wert darf nichts bewirken.
        if NSApplication.shared.activationPolicy() != policy { NSApplication.shared.setActivationPolicy(policy) }
    }
}
