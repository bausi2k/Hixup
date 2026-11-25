import Foundation

/// Manuell gesetzte Markierung eines Hick-ups, z. B. per Hotkey.
public struct Marker: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let note: String?

    public init(timestamp: Date, note: String?) {
        self.timestamp = timestamp
        self.note = note
    }
}

/// Persistenz fuer ausgeloeste Alerts und manuelle Marker (Verlauf fuer die Oberflaeche).
public protocol EventStore: Sendable {
    func record(_ alert: Alert) throws
    /// Alerts im geschlossenen Zeitraum, aufsteigend nach Zeitstempel.
    func alerts(from start: Date, to end: Date) throws -> [Alert]
    func addMarker(_ marker: Marker) throws
    /// Marker im geschlossenen Zeitraum, aufsteigend nach Zeitstempel.
    func markers(from start: Date, to end: Date) throws -> [Marker]
    /// Loescht Alerts und Marker vor `date` und gibt die Gesamtzahl zurueck.
    @discardableResult
    func purge(olderThan date: Date) throws -> Int
}
