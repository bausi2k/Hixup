import Foundation

/// Bestimmt den Anzeigenamen eines Prozesses. `proc_name` kuerzt auf rund 31 Zeichen; der Dateiname des
/// Programms im Pfad ist vollstaendig.
enum ProcessNaming {
    static func displayName(path: String?, fallback: String, pid: Int32 = 0) -> String {
        if let path, !path.isEmpty {
            let last = (path as NSString).lastPathComponent
            if !last.isEmpty { return last }
        }
        return fallback.isEmpty ? "pid \(pid)" : fallback
    }
}
