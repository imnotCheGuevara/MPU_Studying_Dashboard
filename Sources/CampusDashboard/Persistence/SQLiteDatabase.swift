import Foundation
import SQLite3

enum DatabaseError: Error, Equatable, CustomStringConvertible {
    case open(String)
    case execute(String)
    case prepare(String)
    case bind(String)
    case step(String)
    case migration(expected: Int, actual: Int)

    var description: String {
        switch self {
        case .open(let message): "Unable to open database: \(message)"
        case .execute(let message): "Unable to execute database statement: \(message)"
        case .prepare(let message): "Unable to prepare database statement: \(message)"
        case .bind(let message): "Unable to bind database value: \(message)"
        case .step(let message): "Unable to read database result: \(message)"
        case .migration(let expected, let actual): "Database migration ended at \(actual), expected \(expected)"
        }
    }
}

enum SQLiteValue: Equatable, Sendable {
    case text(String)
    case integer(Int64)
    case real(Double)
    case blob(Data)
    case null
}

struct SQLiteRow: Sendable {
    private let values: [String: SQLiteValue]

    init(values: [String: SQLiteValue]) {
        self.values = values
    }

    func string(_ name: String) -> String? {
        guard case .text(let value) = values[name] else { return nil }
        return value
    }

    func int(_ name: String) -> Int64? {
        guard case .integer(let value) = values[name] else { return nil }
        return value
    }

    func double(_ name: String) -> Double? {
        switch values[name] {
        case .real(let value): value
        case .integer(let value): Double(value)
        default: nil
        }
    }

    func data(_ name: String) -> Data? {
        guard case .blob(let value) = values[name] else { return nil }
        return value
    }

    var firstInteger: Int64? {
        for value in values.values {
            if case .integer(let integer) = value { return integer }
        }
        return nil
    }
}

final class SQLiteDatabase: @unchecked Sendable {
    static let currentSchemaVersion = 13

    private let handle: OpaquePointer
    private let lock = NSRecursiveLock()

    init(path: String, migrate: Bool = true) throws {
        if path != ":memory:" {
            let parent = URL(fileURLWithPath: path).deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        }

        var connection: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &connection, flags, nil) == SQLITE_OK, let connection else {
            let message = connection.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            if let connection { sqlite3_close(connection) }
            throw DatabaseError.open(message)
        }
        handle = connection

        do {
            try execute("PRAGMA foreign_keys = ON")
            try execute("PRAGMA journal_mode = WAL")
            try execute("PRAGMA busy_timeout = 5000")
            if migrate { try DatabaseMigrator.migrate(self) }
        } catch {
            sqlite3_close(connection)
            throw error
        }
    }

    deinit {
        sqlite3_close(handle)
    }

    func execute(_ sql: String, bindings: [SQLiteValue] = []) throws {
        try lock.withLock {
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }
            try bind(bindings, to: statement)
            while true {
                switch sqlite3_step(statement) {
                case SQLITE_ROW:
                    continue
                case SQLITE_DONE:
                    return
                default:
                    throw DatabaseError.execute(errorMessage)
                }
            }
        }
    }

    func query(_ sql: String, bindings: [SQLiteValue] = []) throws -> [SQLiteRow] {
        try lock.withLock {
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }
            try bind(bindings, to: statement)
            var rows: [SQLiteRow] = []

            while true {
                switch sqlite3_step(statement) {
                case SQLITE_ROW:
                    var values: [String: SQLiteValue] = [:]
                    for index in 0..<sqlite3_column_count(statement) {
                        let name = String(cString: sqlite3_column_name(statement, index))
                        switch sqlite3_column_type(statement, index) {
                        case SQLITE_INTEGER:
                            values[name] = .integer(sqlite3_column_int64(statement, index))
                        case SQLITE_FLOAT:
                            values[name] = .real(sqlite3_column_double(statement, index))
                        case SQLITE_BLOB:
                            let count = Int(sqlite3_column_bytes(statement, index))
                            if count == 0 {
                                values[name] = .blob(Data())
                            } else if let bytes = sqlite3_column_blob(statement, index) {
                                values[name] = .blob(Data(bytes: bytes, count: count))
                            }
                        case SQLITE_NULL:
                            values[name] = .null
                        default:
                            if let text = sqlite3_column_text(statement, index) {
                                values[name] = .text(String(cString: text))
                            }
                        }
                    }
                    rows.append(SQLiteRow(values: values))
                case SQLITE_DONE:
                    return rows
                default:
                    throw DatabaseError.step(errorMessage)
                }
            }
        }
    }

    func scalarInt(_ sql: String) throws -> Int {
        let row = try query(sql).first
        return Int(row?.int("value") ?? row?.firstInteger ?? 0)
    }

    func transaction<T>(_ operation: () throws -> T) throws -> T {
        try lock.withLock {
            try execute("BEGIN IMMEDIATE")
            do {
                let result = try operation()
                try execute("COMMIT")
                return result
            } catch {
                try? execute("ROLLBACK")
                throw error
            }
        }
    }

    private var errorMessage: String { String(cString: sqlite3_errmsg(handle)) }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw DatabaseError.prepare(errorMessage)
        }
        return statement
    }

    private func bind(_ values: [SQLiteValue], to statement: OpaquePointer) throws {
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch value {
            case .text(let string):
                result = sqlite3_bind_text(statement, index, string, -1, transient)
            case .integer(let integer):
                result = sqlite3_bind_int64(statement, index, integer)
            case .real(let double):
                result = sqlite3_bind_double(statement, index, double)
            case .blob(let data):
                result = data.withUnsafeBytes { bytes in
                    sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(data.count), transient)
                }
            case .null:
                result = sqlite3_bind_null(statement, index)
            }
            guard result == SQLITE_OK else { throw DatabaseError.bind(errorMessage) }
        }
    }
}
