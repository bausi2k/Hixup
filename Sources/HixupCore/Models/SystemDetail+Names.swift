import Foundation

/// Lesbare, uebersetzte Namen der Zustaende (fuer Bericht, Einschaetzung und Oberflaeche).
extension MemoryPressureLevel {
    public func name(language: AppLanguage? = nil) -> String {
        switch self {
        case .normal: L10n.translate("normal", language: language)
        case .warning: L10n.translate("Warnung", language: language)
        case .critical: L10n.translate("kritisch", language: language)
        }
    }
}

extension ThermalLevel {
    public func name(language: AppLanguage? = nil) -> String {
        switch self {
        case .nominal: L10n.translate("normal", language: language)
        case .fair: L10n.translate("erhöht", language: language)
        case .serious: L10n.translate("hoch", language: language)
        case .critical: L10n.translate("kritisch", language: language)
        }
    }
}

extension NetworkKind {
    public func name(language: AppLanguage? = nil) -> String {
        switch self {
        case .wifi: "WLAN"
        case .ethernet: "Ethernet"
        case .vpn: "VPN"
        case .other: L10n.translate("Sonstiges", language: language)
        case .none: L10n.translate("keine Verbindung", language: language)
        }
    }
}
