import Foundation

/// Gemeinsame Dateipfade von App und Agent (beide laufen ohne Sandbox).
public enum HixupPaths {
    public static var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Hixup", isDirectory: true)
    }

    public static var databaseURL: URL { supportDirectory.appendingPathComponent("hixup.sqlite") }
    public static var settingsURL: URL { supportDirectory.appendingPathComponent("settings.json") }
}
