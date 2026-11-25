import HixupCore
import SwiftUI

extension HealthLevel {
    var color: Color {
        switch self {
        case .unknown: .secondary
        case .ok: .green
        case .warning: .orange
        case .critical: .red
        }
    }

    var title: String {
        switch self {
        case .unknown: "Unbekannt"
        case .ok: "OK"
        case .warning: "Warnung"
        case .critical: "Kritisch"
        }
    }
}
