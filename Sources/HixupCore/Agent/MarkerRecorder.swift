import Foundation

/// Setzt eine manuelle Markierung "genau jetzt ruckelt es" (Hotkey oder Button).
public struct MarkerRecorder: Sendable {
    private let events: any EventStore
    private let now: @Sendable () -> Date

    public init(events: any EventStore, now: @escaping @Sendable () -> Date = { Date() }) {
        self.events = events
        self.now = now
    }

    @discardableResult
    public func mark(note: String? = nil) throws -> Marker {
        let marker = Marker(timestamp: now(), note: note)
        try events.addMarker(marker)
        return marker
    }
}
