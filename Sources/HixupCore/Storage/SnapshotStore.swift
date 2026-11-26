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
    /// Wie `sampledSnapshots`, behaelt aber je Zeitabschnitt den am hoechsten belasteten Snapshot,
    /// damit kurze Spitzen in langen Zeitraeumen sichtbar bleiben.
    func peakSnapshots(from start: Date, to end: Date, maxPoints: Int) throws -> [Snapshot]
    /// Wie `peakSnapshots`, liefert aber nur die Diagrammwerte und liest sie aus Spalten, ohne JSON zu dekodieren.
    func peakPoints(from start: Date, to end: Date, maxPoints: Int) throws -> [TrendPoint]
    /// Loescht alle Snapshots vor `date` und gibt die Anzahl zurueck.
    @discardableResult
    func purge(olderThan date: Date) throws -> Int
    func count() throws -> Int
}
