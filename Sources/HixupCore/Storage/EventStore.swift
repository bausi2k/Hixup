import Foundation

/// Manuell gesetzte Markierung eines Hick-ups, z. B. per Hotkey.
public struct Marker: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let note: String?
    /// Tiefenmessung zum Zeitpunkt der Markierung; wird kurz nach dem Setzen nachgetragen.
    public let detail: SystemDetail?

    public init(timestamp: Date, note: String?, detail: SystemDetail? = nil) {
        self.timestamp = timestamp
        self.note = note
        self.detail = detail
    }
}

extension Marker: Identifiable {
    public var id: Date { timestamp }
}

/// Persistenz fuer ausgeloeste Alerts und manuelle Marker (Verlauf fuer die Oberflaeche).
public protocol EventStore: Sendable {
    func record(_ alert: Alert) throws
    /// Alerts im geschlossenen Zeitraum, aufsteigend nach Zeitstempel.
    func alerts(from start: Date, to end: Date) throws -> [Alert]
    func addMarker(_ marker: Marker) throws
    /// Setzt oder entfernt (`nil`) die Notiz des Markers mit diesem Zeitstempel.
    func setMarkerNote(_ note: String?, at timestamp: Date) throws
    /// Traegt die Tiefenmessung zum Marker mit diesem Zeitstempel nach.
    func setMarkerDetail(_ detail: SystemDetail, at timestamp: Date) throws
    /// Marker im geschlossenen Zeitraum, aufsteigend nach Zeitstempel.
    func markers(from start: Date, to end: Date) throws -> [Marker]
    /// Loescht Alerts und Marker vor `date` und gibt die Gesamtzahl zurueck.
    @discardableResult
    func purge(olderThan date: Date) throws -> Int
}
