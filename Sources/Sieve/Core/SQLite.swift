import Foundation
import SQLite3

/// Minimal, synchronous SQLite wrapper over the system libsqlite3.
/// No external dependencies — the app builds and runs entirely offline.
final class SQLiteDB {
    private var handle: OpaquePointer?
    private let queue = DispatchQueue(label: "sieve.db")
    let path: String

    init(path: String) throws {
        self.path = path
        var h: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &h, flags, nil) == SQLITE_OK, let h else {
            throw SQLError.open(String(cString: sqlite3_errmsg(h)))
        }
        handle = h
        sqlite3_busy_timeout(h, 3000)
        try execute("PRAGMA journal_mode=WAL;")
        try execute("PRAGMA foreign_keys=ON;")
    }

    deinit { if let handle { sqlite3_close_v2(handle) } }

    enum SQLError: LocalizedError {
        case open(String), prepare(String), step(String)
        var errorDescription: String? {
            switch self {
            case .open(let m): return "Could not open database: \(m)"
            case .prepare(let m): return "SQL prepare failed: \(m)"
            case .step(let m): return "SQL failed: \(m)"
            }
        }
    }

    // MARK: - Values

    enum Value {
        case null
        case int(Int64)
        case double(Double)
        case text(String)
        case blob(Data)

        static func of(_ any: Any?) -> Value {
            switch any {
            case nil, is NSNull: return .null
            case let v as Int: return .int(Int64(v))
            case let v as Int64: return .int(v)
            case let v as Bool: return .int(v ? 1 : 0)
            case let v as Double: return .double(v)
            case let v as String: return .text(v)
            case let v as Data: return .blob(v)
            case let v as Date: return .double(v.timeIntervalSince1970)
            default: return .text(String(describing: any!))
            }
        }
    }

    /// One result row, addressable by column name.
    struct Row {
        let columns: [String: Value]
        subscript(_ key: String) -> Value { columns[key] ?? .null }

        func int(_ k: String) -> Int? {
            if case .int(let v) = self[k] { return Int(v) }
            if case .double(let v) = self[k] { return Int(v) }
            if case .text(let v) = self[k] { return Int(v) }
            return nil
        }
        func bool(_ k: String) -> Bool { (int(k) ?? 0) != 0 }
        func double(_ k: String) -> Double? {
            if case .double(let v) = self[k] { return v }
            if case .int(let v) = self[k] { return Double(v) }
            return nil
        }
        func string(_ k: String) -> String? {
            if case .text(let v) = self[k] { return v }
            if case .int(let v) = self[k] { return String(v) }
            if case .double(let v) = self[k] { return String(v) }
            return nil
        }
        func date(_ k: String) -> Date? { double(k).map { Date(timeIntervalSince1970: $0) } }
        func data(_ k: String) -> Data? { if case .blob(let v) = self[k] { return v }; return nil }
    }

    // MARK: - Execution

    func execute(_ sql: String) throws {
        try queue.sync {
            var err: UnsafeMutablePointer<CChar>?
            if sqlite3_exec(handle, sql, nil, nil, &err) != SQLITE_OK {
                let msg = err.map { String(cString: $0) } ?? "unknown"
                sqlite3_free(err)
                throw SQLError.step("\(msg)\n--- while running ---\n\(sql)")
            }
        }
    }

    @discardableResult
    func run(_ sql: String, _ params: [Any?] = []) throws -> Int64 {
        try queue.sync {
            let stmt = try prepare(sql, params)
            defer { sqlite3_finalize(stmt) }
            let rc = sqlite3_step(stmt)
            guard rc == SQLITE_DONE || rc == SQLITE_ROW else {
                throw SQLError.step("\(String(cString: sqlite3_errmsg(handle)))\n--- \(sql)")
            }
            return sqlite3_last_insert_rowid(handle)
        }
    }

    func query(_ sql: String, _ params: [Any?] = []) throws -> [Row] {
        try queue.sync {
            let stmt = try prepare(sql, params)
            defer { sqlite3_finalize(stmt) }
            var rows: [Row] = []
            let colCount = sqlite3_column_count(stmt)
            var names: [String] = []
            for i in 0..<colCount { names.append(String(cString: sqlite3_column_name(stmt, i))) }
            while sqlite3_step(stmt) == SQLITE_ROW {
                var dict: [String: Value] = [:]
                for i in 0..<colCount {
                    switch sqlite3_column_type(stmt, i) {
                    case SQLITE_INTEGER: dict[names[Int(i)]] = .int(sqlite3_column_int64(stmt, i))
                    case SQLITE_FLOAT:   dict[names[Int(i)]] = .double(sqlite3_column_double(stmt, i))
                    case SQLITE_TEXT:
                        if let c = sqlite3_column_text(stmt, i) { dict[names[Int(i)]] = .text(String(cString: c)) }
                    case SQLITE_BLOB:
                        if let b = sqlite3_column_blob(stmt, i) {
                            let n = Int(sqlite3_column_bytes(stmt, i))
                            dict[names[Int(i)]] = .blob(Data(bytes: b, count: n))
                        } else { dict[names[Int(i)]] = .blob(Data()) }
                    default: dict[names[Int(i)]] = .null
                    }
                }
                rows.append(Row(columns: dict))
            }
            return rows
        }
    }

    func scalarInt(_ sql: String, _ params: [Any?] = []) -> Int {
        (try? query(sql, params).first?.int(firstColumnName(sql)) ?? 0) ?? 0
    }

    private func firstColumnName(_ sql: String) -> String { "c" }

    /// COUNT helper — always aliases to `c` so `scalarInt` can read it.
    func count(_ sql: String, _ params: [Any?] = []) -> Int {
        guard let row = try? query(sql, params).first else { return 0 }
        return row.int("c") ?? row.columns.values.compactMap { v -> Int? in
            if case .int(let i) = v { return Int(i) }; return nil
        }.first ?? 0
    }

    func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE;")
        do { try body(); try execute("COMMIT;") }
        catch { try? execute("ROLLBACK;"); throw error }
    }

    private func prepare(_ sql: String, _ params: [Any?]) throws -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SQLError.prepare("\(String(cString: sqlite3_errmsg(handle)))\n--- \(sql)")
        }
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (i, p) in params.enumerated() {
            let idx = Int32(i + 1)
            switch Value.of(p) {
            case .null:        sqlite3_bind_null(stmt, idx)
            case .int(let v):  sqlite3_bind_int64(stmt, idx, v)
            case .double(let v): sqlite3_bind_double(stmt, idx, v)
            case .text(let v): sqlite3_bind_text(stmt, idx, v, -1, SQLITE_TRANSIENT)
            case .blob(let v): _ = v.withUnsafeBytes { sqlite3_bind_blob(stmt, idx, $0.baseAddress, Int32(v.count), SQLITE_TRANSIENT) }
            }
        }
        return stmt
    }
}
