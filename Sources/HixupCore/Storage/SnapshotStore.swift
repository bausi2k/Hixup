import Foundation

public enum StorageError: Error, Equatable, Sendable {
    case openFailed(String)
    case queryFailed(String)
    case encodingFailed(String)
}

public protocol SnapshotStore: Sendable {
    func append(_ snapshot: Snapshot) throws
    /// Liefert Snapshots im geschlossenen Zeitraum, aufsteigend nach Zeitstempel.
    func snapshots(from start: Date, to end: Date) throws -> [Snapshot]
    /// Wie `snapshots(from:to:)`, aber gleichmaessig ausgeduennt auf hoechstens ungefaehr `maxPoints` Eintraege.
    func sampledSnapshots(from start: Date, to end: Date, maxPoints: Int) throws -> [Snapshot]
    /// Loescht alle Snapshots vor `date` und gibt die Anzahl zurueck.
    @discardableResult
    func purge(olderThan date: Date) throws -> Int
    func count() throws -> Int
}
