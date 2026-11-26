import Foundation

/// Haengt an einen ausgeloesten Alert die Tiefenmessung (Netzwerk, Swap, Thermik), damit sich der Alarm spaeter
/// wie ein Marker analysieren laesst. Laeuft nach dem Ausloesen, damit die Messung die Benachrichtigung nicht aufhaelt.
public struct AlertDetailRecorder: Sendable {
    private let events: any EventStore
    private let detail: SystemDetailCollector

    public init(events: any EventStore, detail: SystemDetailCollector = SystemDetailCollector()) {
        self.events = events
        self.detail = detail
    }

    public func attachDetail(to alert: Alert) async {
        try? events.setAlertDetail(await detail.collect(), for: alert)
    }
}
