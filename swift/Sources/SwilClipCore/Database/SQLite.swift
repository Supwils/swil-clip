import Foundation
import SQLite3

/// `sqlite3_bind_*` needs to know whether it may keep the caller's buffer.
/// `SQLITE_TRANSIENT` tells it to copy, which is the only safe answer when the
/// bytes come from a Swift value whose lifetime ends at the call.
private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public enum SQLiteError: Error, CustomStringConvertible {
    case open(path: String, message: String)
    case prepare(sql: String, message: String)
    case step(sql: String, message: String)

    public var description: String {
        switch self {
        case .open(let path, let message): "cannot open \(path): \(message)"
        case .prepare(let sql, let message): "cannot prepare «\(sql)»: \(message)"
        case .step(let sql, let message): "cannot run «\(sql)»: \(message)"
        }
    }
}

/// A value that can be bound to a statement parameter.
public enum SQLValue: Equatable, Sendable {
    case null
    case integer(Int64)
    case text(String)
    case blob(Data)

    public static func bool(_ value: Bool) -> SQLValue { .integer(value ? 1 : 0) }
    public static func date(_ value: Date) -> SQLValue {
        // Whole milliseconds since the epoch: ordered, compact, and directly
        // comparable in SQL, unlike a floating-point interval.
        .integer(Int64(value.timeIntervalSince1970 * 1000))
    }
    public static func optionalInt(_ value: Int?) -> SQLValue {
        value.map { .integer(Int64($0)) } ?? .null
    }
    public static func optionalText(_ value: String?) -> SQLValue {
        value.map { .text($0) } ?? .null
    }
}

/// One row, addressed by column index.
public struct Row {
    private let handle: OpaquePointer

    init(handle: OpaquePointer) { self.handle = handle }

    public func isNull(_ index: Int32) -> Bool {
        sqlite3_column_type(handle, index) == SQLITE_NULL
    }

    public func int(_ index: Int32) -> Int64 { sqlite3_column_int64(handle, index) }
    public func optionalInt(_ index: Int32) -> Int? {
        isNull(index) ? nil : Int(sqlite3_column_int64(handle, index))
    }
    public func bool(_ index: Int32) -> Bool { sqlite3_column_int64(handle, index) != 0 }

    public func date(_ index: Int32) -> Date {
        Date(timeIntervalSince1970: Double(sqlite3_column_int64(handle, index)) / 1000)
    }

    public func text(_ index: Int32) -> String {
        guard let cString = sqlite3_column_text(handle, index) else { return "" }
        return String(cString: cString)
    }

    public func optionalText(_ index: Int32) -> String? {
        isNull(index) ? nil : text(index)
    }

    public func blob(_ index: Int32) -> Data {
        let byteCount = Int(sqlite3_column_bytes(handle, index))
        guard byteCount > 0, let pointer = sqlite3_column_blob(handle, index) else { return Data() }
        return Data(bytes: pointer, count: byteCount)
    }
}

/// A minimal typed wrapper over the system SQLite.
///
/// Deliberately not a general-purpose library — it covers exactly the two tables
/// this app has. See the spec §4.2 for why a dependency was not taken: the
/// surface is small enough to own and test, and owning it means the hot paths
/// keep their prepared statements instead of re-parsing SQL on every keystroke.
///
/// Not thread-safe by construction. Each instance is owned exclusively by one
/// actor, which is what makes that acceptable rather than merely convenient.
public final class Database {
    private var handle: OpaquePointer?
    /// Prepared statements, kept alive for the connection's lifetime. Re-parsing
    /// the same INSERT on every clipboard change is pure waste at 500 ms cadence.
    private var statementCache: [String: OpaquePointer] = [:]

    public init(path: String) throws {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            sqlite3_close_v2(handle)
            throw SQLiteError.open(path: path, message: message)
        }
        self.handle = handle

        // WAL keeps readers from blocking the writer, which matters because the
        // pasteboard poller writes while the panel is reading. NORMAL is the
        // documented safe pairing with WAL: durable across process crashes,
        // trading only a power-loss window we do not need to defend.
        try execute("PRAGMA journal_mode = WAL")
        try execute("PRAGMA synchronous = NORMAL")
        try execute("PRAGMA foreign_keys = ON")
        // Rows are read one at a time and never held; a large page cache would
        // just be resident memory this app has no use for.
        try execute("PRAGMA cache_size = -2000")
    }

    deinit {
        for (_, statement) in statementCache { sqlite3_finalize(statement) }
        sqlite3_close_v2(handle)
    }

    private var errorMessage: String {
        handle.map { String(cString: sqlite3_errmsg($0)) } ?? "no connection"
    }

    /// Run a statement that returns no rows (DDL, PRAGMA, INSERT, UPDATE).
    public func execute(_ sql: String, _ bindings: [SQLValue] = []) throws {
        let statement = try cachedStatement(sql)
        defer { sqlite3_reset(statement); sqlite3_clear_bindings(statement) }
        bind(bindings, to: statement)
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE || result == SQLITE_ROW else {
            throw SQLiteError.step(sql: sql, message: errorMessage)
        }
    }

    /// Run a query, mapping each row. Rows are decoded during iteration and the
    /// `Row` handle must not escape the closure — it points into the statement.
    public func query<T>(
        _ sql: String,
        _ bindings: [SQLValue] = [],
        decode: (Row) throws -> T
    ) throws -> [T] {
        let statement = try cachedStatement(sql)
        defer { sqlite3_reset(statement); sqlite3_clear_bindings(statement) }
        bind(bindings, to: statement)

        var results: [T] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else {
                throw SQLiteError.step(sql: sql, message: errorMessage)
            }
            results.append(try decode(Row(handle: statement)))
        }
        return results
    }

    public func queryOne<T>(
        _ sql: String,
        _ bindings: [SQLValue] = [],
        decode: (Row) throws -> T
    ) throws -> T? {
        try query(sql, bindings, decode: decode).first
    }

    /// Run `body` inside a transaction, rolling back if it throws.
    ///
    /// Used for multi-row work — migration especially, where a partial import
    /// would be worse than none, since the marker would suppress a retry.
    public func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do {
            let value = try body()
            try execute("COMMIT")
            return value
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    // MARK: - Statements

    private func cachedStatement(_ sql: String) throws -> OpaquePointer {
        if let cached = statementCache[sql] { return cached }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            throw SQLiteError.prepare(sql: sql, message: errorMessage)
        }
        statementCache[sql] = statement
        return statement
    }

    private func bind(_ values: [SQLValue], to statement: OpaquePointer) {
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            switch value {
            case .null:
                sqlite3_bind_null(statement, index)
            case .integer(let number):
                sqlite3_bind_int64(statement, index, number)
            case .text(let string):
                sqlite3_bind_text(statement, index, string, -1, sqliteTransient)
            case .blob(let data):
                if data.isEmpty {
                    sqlite3_bind_zeroblob(statement, index, 0)
                } else {
                    _ = data.withUnsafeBytes { buffer in
                        sqlite3_bind_blob(
                            statement, index, buffer.baseAddress,
                            Int32(buffer.count), sqliteTransient
                        )
                    }
                }
            }
        }
    }
}
