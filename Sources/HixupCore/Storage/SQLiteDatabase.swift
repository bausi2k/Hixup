import Foundation
import SQLite3

/// Duenne, thread-sichere Huelle um eine SQLite-Verbindung. Dateien laufen im WAL-Modus,
/// damit ein Prozess lesen kann, waehrend ein anderer schreibt.
final class SQLiteDatabase: @unchecked Sendable {
    static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private let handle: OpaquePointer
    private let lock = NSLock()

    /// - Parameters:
    ///   - path: Dateipfad oder `":memory:"`.
    ///   - schema: SQL zum Anlegen der Tabellen (idempotent).
    init(path: String, schema: String) throws {
        var opened: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &opened, flags, nil) == SQLITE_OK, let opened else {
            let message = opened.map { String(cString: sqlite3_errmsg($0)) } ?? "unbekannter Fehler"
            sqlite3_close(opened)
            throw StorageError.openFailed(message)
        }
        handle = opened

        sqlite3_busy_timeout(handle, 5_000)
        try execute("PRAGMA journal_mode=WAL;")
        try execute(schema)
    }

    deinit {
        sqlite3_close(handle)
    }

    var journalMode: String {
        (try? withStatement("PRAGMA journal_mode") { statement in
            try step(statement, expecting: SQLITE_ROW)
            return String(cString: sqlite3_column_text(statement, 0))
        }) ?? ""
    }

    func execute(_ sql: String) throws {
        lock.lock()
        defer { lock.unlock() }
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else {
            throw StorageError.queryFailed(String(cString: sqlite3_errmsg(handle)))
        }
    }

    /// Bereitet ein Statement vor, fuehrt `body` unter Sperre aus und gibt das Statement wieder frei.
    func withStatement<T>(_ sql: String, _ body: (OpaquePointer) throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw StorageError.queryFailed(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        return try body(statement)
    }

    func step(_ statement: OpaquePointer, expecting expected: Int32) throws {
        guard sqlite3_step(statement) == expected else {
            throw StorageError.queryFailed(String(cString: sqlite3_errmsg(handle)))
        }
    }

    /// Anzahl der zuletzt geaenderten Zeilen; nur innerhalb von `withStatement` aufrufen.
    func changedRows() -> Int {
        Int(sqlite3_changes(handle))
    }

    static func bind(_ data: Data, at index: Int32, in statement: OpaquePointer) {
        _ = data.withUnsafeBytes {
            sqlite3_bind_blob(statement, index, $0.baseAddress, Int32($0.count), transient)
        }
    }

    static func decodeBlob(from statement: OpaquePointer, column: Int32) -> Data? {
        let length = Int(sqlite3_column_bytes(statement, column))
        guard let bytes = sqlite3_column_blob(statement, column) else { return nil }
        return Data(bytes: bytes, count: length)
    }
}
