import Foundation

/// Wo die App sichtbar ist: Dock-Symbol und/oder Menueleisten-Symbol. Mindestens eines bleibt aktiv,
/// damit die App immer erreichbar ist.
public struct AppVisibility: Equatable, Sendable {
    public var showInDock: Bool
    public var showMenuBarItem: Bool

    public static let defaults = AppVisibility(showInDock: true, showMenuBarItem: true)

    public init(showInDock: Bool, showMenuBarItem: Bool) {
        self.showInDock = showInDock
        self.showMenuBarItem = showMenuBarItem
    }

    /// Schaltet das Dock-Symbol; wird das letzte sichtbare abgeschaltet, springt das andere an.
    public func settingDock(_ enabled: Bool) -> AppVisibility {
        AppVisibility(showInDock: enabled, showMenuBarItem: enabled ? showMenuBarItem : true)
    }

    /// Schaltet das Menueleisten-Symbol; wird das letzte sichtbare abgeschaltet, springt das andere an.
    public func settingMenuBar(_ enabled: Bool) -> AppVisibility {
        AppVisibility(showInDock: enabled ? showInDock : true, showMenuBarItem: enabled)
    }

    /// Gespeicherte Werte, bei denen beides aus ist, fallen auf die Standardwerte zurueck.
    public func normalized() -> AppVisibility {
        showInDock || showMenuBarItem ? self : .defaults
    }
}
