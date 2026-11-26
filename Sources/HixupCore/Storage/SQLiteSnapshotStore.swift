import Foundation
import SQLite3

/// Speichert Snapshots als JSON in SQLite. Der Zeitstempel ist als Spalte indiziert.
public final class SQLiteSnapshotStore: SnapshotStore, @unchecked Sendable {
    private static let schema = """
        CREATE TABLE IF NOT EXISTS snapshots (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp REAL NOT NULL,
            payload BLOB NOT NULL,
            load REAL,
            avail REAL,
            cpu_sum REAL,
            energy_sum REAL,
            sys_cpu REAL
        );
        CREATE INDEX IF NOT EXISTS idx_snapshots_timestamp ON snapshots(timestamp);
        """

    private let database: SQLiteDatabase
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// - Parameter path: Dateipfad oder `":memory:"`.
    public init(path: String) throws {
        database = try SQLiteDatabase(path: path, schema: Self.schema)
        try addMissingColumns()
    }

    /// Migration fuer aeltere Datenbanken: ergaenzt `load` und die Diagrammspalten. Alte Zeilen bleiben ohne
    /// Werte und werden beim Lesen weiter aus dem JSON gelesen.
    private func addMissingColumns() throws {
        let existing = try database.withStatement("PRAGMA table_info(snapshots)") { statement in
            var names = Set<String>()
            while sqlite3_step(statement) == SQLITE_ROW { names.insert(String(cString: sqlite3_column_text(statement, 1))) }
            return names
        }
        for column in ["load", "avail", "cpu_sum", "energy_sum", "sys_cpu"] where !existing.contains(column) {
            try database.execute("ALTER TABLE snapshots ADD COLUMN \(column) REAL;")
        }
    }

    /// Entfernt die Diagrammspalten, um Altdaten nachzustellen.
    func clearSummaryColumnsForTesting() throws {
        try database.execute("UPDATE snapshots SET avail = NULL, cpu_sum = NULL, energy_sum = NULL, sys_cpu = NULL;")
    }

    var journalMode: String { database.journalMode }

    public func append(_ snapshot: Snapshot) throws {
        let payload: Data
        do {
            payload = try encoder.encode(snapshot)
        } catch {
            throw StorageError.encodingFailed(String(describing: error))
        }

        try database.withStatement(
            "INSERT INTO snapshots (timestamp, payload, load, avail, cpu_sum, energy_sum, sys_cpu) VALUES (?, ?, ?, ?, ?, ?, ?)"
        ) { statement in
            let point = TrendPoint(snapshot: snapshot)
            sqlite3_bind_double(statement, 1, snapshot.timestamp.timeIntervalSince1970)
            SQLiteDatabase.bind(payload, at: 2, in: statement)
            sqlite3_bind_double(statement, 3, snapshot.loadScore)
            sqlite3_bind_double(statement, 4, point.availableMemoryPercent)
            sqlite3_bind_double(statement, 5, point.cpuPercent)
            sqlite3_bind_double(statement, 6, point.energyWatts)
            if let systemCPU = point.systemCPUPercent { sqlite3_bind_double(statement, 7, systemCPU) } else { sqlite3_bind_null(statement, 7) }
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

    public func sampledSnapshots(from start: Date, to end: Date, maxPoints: Int) throws -> [Snapshot] {
        let total = try count(from: start, to: end)
        let stride = max(1, Int((Double(total) / Double(max(maxPoints, 1))).rounded(.up)))

        return try database.withStatement(
            "SELECT payload FROM snapshots WHERE timestamp >= ? AND timestamp <= ? AND id % ? = 0 ORDER BY timestamp ASC, id ASC"
        ) { statement in
            sqlite3_bind_double(statement, 1, start.timeIntervalSince1970)
            sqlite3_bind_double(statement, 2, end.timeIntervalSince1970)
            sqlite3_bind_int64(statement, 3, Int64(stride))

            var result: [Snapshot] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let data = SQLiteDatabase.decodeBlob(from: statement, column: 0) else { continue }
                result.append(try decoder.decode(Snapshot.self, from: data))
            }
            return result
        }
    }

    public func peakSnapshots(from start: Date, to end: Date, maxPoints: Int) throws -> [Snapshot] {
        let limit = max(maxPoints, 1)
        if try count(from: start, to: end) <= limit { return try snapshots(from: start, to: end) }

        let bucketSeconds = max(end.timeIntervalSince(start) / Double(limit), 0.001)
        return try database.withStatement("""
            SELECT payload, MAX(COALESCE(load, 0)) FROM snapshots
            WHERE timestamp >= ? AND timestamp <= ?
            GROUP BY CAST((timestamp - ?) / ? AS INTEGER)
            ORDER BY timestamp ASC, id ASC
            """) { statement in
            sqlite3_bind_double(statement, 1, start.timeIntervalSince1970)
            sqlite3_bind_double(statement, 2, end.timeIntervalSince1970)
            sqlite3_bind_double(statement, 3, start.timeIntervalSince1970)
            sqlite3_bind_double(statement, 4, bucketSeconds)

            var result: [Snapshot] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let data = SQLiteDatabase.decodeBlob(from: statement, column: 0) else { continue }
                result.append(try decoder.decode(Snapshot.self, from: data))
            }
            return result
        }
    }

    public func peakPoints(from start: Date, to end: Date, maxPoints: Int) throws -> [TrendPoint] {
        let limit = max(maxPoints, 1)
        let grouped = try count(from: start, to: end) > limit
        let bucketSeconds = max(end.timeIntervalSince(start) / Double(limit), 0.001)
        let sql = """
            SELECT timestamp, avail, cpu_sum, energy_sum, sys_cpu, CASE WHEN avail IS NULL THEN payload END, MAX(COALESCE(load, 0))
            FROM snapshots WHERE timestamp >= ? AND timestamp <= ?
            \(grouped ? "GROUP BY CAST((timestamp - ?) / ? AS INTEGER)" : "GROUP BY id")
            ORDER BY timestamp ASC
            """
        return try database.withStatement(sql) { statement in
            sqlite3_bind_double(statement, 1, start.timeIntervalSince1970)
            sqlite3_bind_double(statement, 2, end.timeIntervalSince1970)
            if grouped {
                sqlite3_bind_double(statement, 3, start.timeIntervalSince1970)
                sqlite3_bind_double(statement, 4, bucketSeconds)
            }

            var result: [TrendPoint] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                if sqlite3_column_type(statement, 1) != SQLITE_NULL {
                    let systemCPU = sqlite3_column_type(statement, 4) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 4)
                    result.append(TrendPoint(
                        timestamp: Date(timeIntervalSince1970: sqlite3_column_double(statement, 0)),
                        availableMemoryPercent: sqlite3_column_double(statement, 1),
                        cpuPercent: sqlite3_column_double(statement, 2),
                        energyWatts: sqlite3_column_double(statement, 3),
                        systemCPUPercent: systemCPU
                    ))
                } else if let data = SQLiteDatabase.decodeBlob(from: statement, column: 5) {
                    result.append(TrendPoint(snapshot: try decoder.decode(Snapshot.self, from: data)))
                }
            }
            return result
        }
    }

    private func count(from start: Date, to end: Date) throws -> Int {
        try database.withStatement(
            "SELECT COUNT(*) FROM snapshots WHERE timestamp >= ? AND timestamp <= ?"
        ) { statement in
            sqlite3_bind_double(statement, 1, start.timeIntervalSince1970)
            sqlite3_bind_double(statement, 2, end.timeIntervalSince1970)
            try database.step(statement, expecting: SQLITE_ROW)
            return Int(sqlite3_column_int64(statement, 0))
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
