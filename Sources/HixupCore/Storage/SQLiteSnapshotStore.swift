import Foundation
import SQLite3

/// Speichert Snapshots als JSON in SQLite. Der Zeitstempel ist als Spalte indiziert.
public final class SQLiteSnapshotStore: SnapshotStore, @unchecked Sendable {
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private let database: OpaquePointer
    private let lock = NSLock()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// - Parameter path: Dateipfad oder `":memory:"`.
    public init(path: String) throws {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let handle
        else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unbekannter Fehler"
            sqlite3_close(handle)
            throw StorageError.openFailed(message)
        }
        database = handle

        try execute("""
            CREATE TABLE IF NOT EXISTS snapshots (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp REAL NOT NULL,
                payload BLOB NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_snapshots_timestamp ON snapshots(timestamp);
            """)
    }

    deinit {
        sqlite3_close(database)
    }

    public func append(_ snapshot: Snapshot) throws {
        let payload: Data
        do {
            payload = try encoder.encode(snapshot)
        } catch {
            throw StorageError.encodingFailed(String(describing: error))
        }

        try withStatement("INSERT INTO snapshots (timestamp, payload) VALUES (?, ?)") { statement in
            sqlite3_bind_double(statement, 1, snapshot.timestamp.timeIntervalSince1970)
            _ = payload.withUnsafeBytes {
                sqlite3_bind_blob(statement, 2, $0.baseAddress, Int32($0.count), Self.transient)
            }
            try step(statement, expecting: SQLITE_DONE)
        }
    }

    public func snapshots(from start: Date, to end: Date) throws -> [Snapshot] {
        try withStatement(
            "SELECT payload FROM snapshots WHERE timestamp >= ? AND timestamp <= ? ORDER BY timestamp ASC, id ASC"
        ) { statement in
            sqlite3_bind_double(statement, 1, start.timeIntervalSince1970)
            sqlite3_bind_double(statement, 2, end.timeIntervalSince1970)

            var result: [Snapshot] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let length = Int(sqlite3_column_bytes(statement, 0))
                guard let bytes = sqlite3_column_blob(statement, 0) else { continue }
                result.append(try decoder.decode(Snapshot.self, from: Data(bytes: bytes, count: length)))
            }
            return result
        }
    }

    @discardableResult
    public func purge(olderThan date: Date) throws -> Int {
        try withStatement("DELETE FROM snapshots WHERE timestamp < ?") { statement in
            sqlite3_bind_double(statement, 1, date.timeIntervalSince1970)
            try step(statement, expecting: SQLITE_DONE)
            return Int(sqlite3_changes(database))
        }
    }

    public func count() throws -> Int {
        try withStatement("SELECT COUNT(*) FROM snapshots") { statement in
            try step(statement, expecting: SQLITE_ROW)
            return Int(sqlite3_column_int64(statement, 0))
        }
    }

    // MARK: - SQLite-Helfer

    private func execute(_ sql: String) throws {
        lock.lock()
        defer { lock.unlock() }
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw StorageError.queryFailed(String(cString: sqlite3_errmsg(database)))
        }
    }

    private func withStatement<T>(_ sql: String, _ body: (OpaquePointer) throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw StorageError.queryFailed(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }
        return try body(statement)
    }

    private func step(_ statement: OpaquePointer, expecting expected: Int32) throws {
        guard sqlite3_step(statement) == expected else {
            throw StorageError.queryFailed(String(cString: sqlite3_errmsg(database)))
        }
    }
}
