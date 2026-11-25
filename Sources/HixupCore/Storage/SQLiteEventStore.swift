import Foundation
import SQLite3

/// Speichert Alerts (als JSON) und Marker in SQLite. Darf dieselbe Datei wie `SQLiteSnapshotStore` nutzen.
public final class SQLiteEventStore: EventStore, @unchecked Sendable {
    private static let schema = """
        CREATE TABLE IF NOT EXISTS alerts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp REAL NOT NULL,
            payload BLOB NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_alerts_timestamp ON alerts(timestamp);
        CREATE TABLE IF NOT EXISTS markers (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp REAL NOT NULL,
            note TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_markers_timestamp ON markers(timestamp);
        """

    private let database: SQLiteDatabase
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// - Parameter path: Dateipfad oder `":memory:"`.
    public init(path: String) throws {
        database = try SQLiteDatabase(path: path, schema: Self.schema)
    }

    public func record(_ alert: Alert) throws {
        let payload: Data
        do {
            payload = try encoder.encode(alert)
        } catch {
            throw StorageError.encodingFailed(String(describing: error))
        }

        try database.withStatement("INSERT INTO alerts (timestamp, payload) VALUES (?, ?)") { statement in
            sqlite3_bind_double(statement, 1, alert.timestamp.timeIntervalSince1970)
            SQLiteDatabase.bind(payload, at: 2, in: statement)
            try database.step(statement, expecting: SQLITE_DONE)
        }
    }

    public func alerts(from start: Date, to end: Date) throws -> [Alert] {
        try database.withStatement(
            "SELECT payload FROM alerts WHERE timestamp >= ? AND timestamp <= ? ORDER BY timestamp ASC, id ASC"
        ) { statement in
            sqlite3_bind_double(statement, 1, start.timeIntervalSince1970)
            sqlite3_bind_double(statement, 2, end.timeIntervalSince1970)

            var result: [Alert] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let data = SQLiteDatabase.decodeBlob(from: statement, column: 0) else { continue }
                result.append(try decoder.decode(Alert.self, from: data))
            }
            return result
        }
    }

    public func addMarker(_ marker: Marker) throws {
        try database.withStatement("INSERT INTO markers (timestamp, note) VALUES (?, ?)") { statement in
            sqlite3_bind_double(statement, 1, marker.timestamp.timeIntervalSince1970)
            if let note = marker.note {
                sqlite3_bind_text(statement, 2, note, -1, SQLiteDatabase.transient)
            } else {
                sqlite3_bind_null(statement, 2)
            }
            try database.step(statement, expecting: SQLITE_DONE)
        }
    }

    public func markers(from start: Date, to end: Date) throws -> [Marker] {
        try database.withStatement(
            "SELECT timestamp, note FROM markers WHERE timestamp >= ? AND timestamp <= ? ORDER BY timestamp ASC, id ASC"
        ) { statement in
            sqlite3_bind_double(statement, 1, start.timeIntervalSince1970)
            sqlite3_bind_double(statement, 2, end.timeIntervalSince1970)

            var result: [Marker] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let note = sqlite3_column_type(statement, 1) == SQLITE_NULL
                    ? nil : String(cString: sqlite3_column_text(statement, 1))
                result.append(Marker(timestamp: Date(timeIntervalSince1970: sqlite3_column_double(statement, 0)), note: note))
            }
            return result
        }
    }

    @discardableResult
    public func purge(olderThan date: Date) throws -> Int {
        try ["alerts", "markers"].reduce(0) { total, table in
            total + (try database.withStatement("DELETE FROM \(table) WHERE timestamp < ?") { statement in
                sqlite3_bind_double(statement, 1, date.timeIntervalSince1970)
                try database.step(statement, expecting: SQLITE_DONE)
                return database.changedRows()
            })
        }
    }
}
