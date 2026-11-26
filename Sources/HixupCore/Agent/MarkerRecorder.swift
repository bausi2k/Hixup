import Foundation

/// Setzt eine manuelle Markierung "genau jetzt ruckelt es" (Hotkey oder Button). Die Markierung wird
/// sofort gespeichert; die langsamere Tiefenmessung (Netzwerk) wird anschliessend nachgetragen.
public struct MarkerRecorder: Sendable {
    /// Laengere Notizen werden gekuerzt.
    public static let maxNoteLength = 200

    private let events: any EventStore
    private let detail: SystemDetailCollector?
    private let now: @Sendable () -> Date

    public init(
        events: any EventStore, detail: SystemDetailCollector? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.events = events
        self.detail = detail
        self.now = now
    }

    @discardableResult
    public func mark(note: String? = nil) throws -> Marker {
        let marker = Marker(timestamp: now(), note: note)
        try events.addMarker(marker)
        return marker
    }

    /// Setzt die Notiz eines Markers. Leerraum am Rand wird entfernt; ein leerer Text entfernt die Notiz.
    @discardableResult
    public func updateNote(_ text: String?, for marker: Marker) throws -> Marker {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = trimmed.flatMap { $0.isEmpty ? nil : String($0.prefix(Self.maxNoteLength)) }
        try events.setMarkerNote(note, at: marker.timestamp)
        return Marker(timestamp: marker.timestamp, note: note, detail: marker.detail)
    }

    /// Erfasst die Tiefenmessung und haengt sie an den Marker; ohne Collector passiert nichts.
    public func attachDetail(to marker: Marker) async {
        guard let detail else { return }
        try? events.setMarkerDetail(await detail.collect(), at: marker.timestamp)
    }
}
