import Foundation
import SQLite3

/// Speichert Snapshots als JSON in SQLite. Der Zeitstempel ist als Spalte indiziert.
public final class SQLiteSnapshotStore: SnapshotStore, @unchecked Sendable {
    private static let schema = """
        CREATE TABLE IF NOT EXISTS snapshots (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp REAL NOT NULL,
            payload BLOB NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_snapshots_timestamp ON snapshots(timestamp);
        """

    private let database: SQLiteDatabase
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// - Parameter path: Dateipfad oder `":memory:"`.
    public init(path: String) throws {
        database = try SQLiteDatabase(path: path, schema: Self.schema)
    }

    var journalMode: String { database.journalMode }

    public func append(_ snapshot: Snapshot) throws {
        let payload: Data
        do {
            payload = try encoder.encode(snapshot)
        } catch {
            throw StorageError.encodingFailed(String(describing: error))
        }

        try database.withStatement("INSERT INTO snapshots (timestamp, payload) VALUES (?, ?)") { statement in
            sqlite3_bind_double(statement, 1, snapshot.timestamp.timeIntervalSince1970)
            SQLiteDatabase.bind(payload, at: 2, in: statement)
            try database.step(statement, expecting: SQLITE_DONE)
        }
    }

    public func snapshots(from start: Date, to end: Date) throws -> [Snapshot] {
        try database.withStatement(
            "SELECT payload FROM snapshots WHERE timestamp >= ? AND timestamp <= ? ORDER BY timestamp ASC, id ASC"
        ) { statement in
            sqlite3_bind_double(statement, 1, start.timeIntervalSince1970)
            sqlite3_bind_double(statement, 2, end.timeIntervalSince1970)

            var result: [Snapshot] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let data = SQLiteDatabase.decodeBlob(from: statement, column: 0) else { continue }
                result.append(try decoder.decode(Snapshot.self, from: data))
            }
            return result
        }
    }

    @discardableResult
    public func purge(olderThan date: Date) throws -> Int {
        try database.withStatement("DELETE FROM snapshots WHERE timestamp < ?") { statement in
            sqlite3_bind_double(statement, 1, date.timeIntervalSince1970)
            try database.step(statement, expecting: SQLITE_DONE)
            return database.changedRows()
        }
    }

    public func count() throws -> Int {
        try database.withStatement("SELECT COUNT(*) FROM snapshots") { statement in
            try database.step(statement, expecting: SQLITE_ROW)
            return Int(sqlite3_column_int64(statement, 0))
        }
    }
}
