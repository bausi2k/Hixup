import HixupCore

/// Woran das Detailfenster arbeitet: ein Marker oder ein automatisch ausgeloester Alarm.
enum DetailSubject: Identifiable {
    case marker(Marker)
    case alert(HixupCore.Alert)

    var id: String {
        switch self {
        case .marker(let marker): "m-\(marker.timestamp.timeIntervalSince1970)"
        case .alert(let alert): "a-\(alert.ruleID)-\(alert.timestamp.timeIntervalSince1970)"
        }
    }
}
