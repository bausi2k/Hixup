import Foundation

/// Setzt eine manuelle Markierung "genau jetzt ruckelt es" (Hotkey oder Button). Die Markierung wird
/// sofort gespeichert; die langsamere Tiefenmessung (Netzwerk) wird anschliessend nachgetragen.
public struct MarkerRecorder: Sendable {
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

    /// Erfasst die Tiefenmessung und haengt sie an den Marker; ohne Collector passiert nichts.
    public func attachDetail(to marker: Marker) async {
        guard let detail else { return }
        try? events.setMarkerDetail(await detail.collect(), at: marker.timestamp)
    }
}
