import Foundation
import Testing
@testable import HixupCore

@Suite struct AppVisibilityTests {
    @Test func defaultsShowDockIconAndMenuBarItem() {
        #expect(AppVisibility.defaults.showInDock)
        #expect(AppVisibility.defaults.showMenuBarItem)
    }

    @Test func dockIconCanBeDisabledWhileMenuBarStays() {
        let result = AppVisibility.defaults.settingDock(false)
        #expect(result == AppVisibility(showInDock: false, showMenuBarItem: true))
    }

    @Test func menuBarItemCanBeDisabledWhileDockStays() {
        let result = AppVisibility.defaults.settingMenuBar(false)
        #expect(result == AppVisibility(showInDock: true, showMenuBarItem: false))
    }

    @Test func disablingTheLastVisibleEntryEnablesTheOther() {
        let dockOnly = AppVisibility(showInDock: true, showMenuBarItem: false)
        #expect(dockOnly.settingDock(false) == AppVisibility(showInDock: false, showMenuBarItem: true))

        let menuBarOnly = AppVisibility(showInDock: false, showMenuBarItem: true)
        #expect(menuBarOnly.settingMenuBar(false) == AppVisibility(showInDock: true, showMenuBarItem: false))
    }

    @Test func normalizingNeverLeavesTheAppUnreachable() {
        let none = AppVisibility(showInDock: false, showMenuBarItem: false)
        #expect(none.normalized() == .defaults)
        #expect(AppVisibility.defaults.normalized() == .defaults)
    }
}
