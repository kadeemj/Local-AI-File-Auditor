import Foundation
import GRDB
import Testing

@testable import AuditorStore

@Suite("AuditorDatabase")
struct AuditorDatabaseTests {
    @Test("migrations create the v1 schema")
    func migrationsApply() throws {
        let db = try AuditorDatabase.inMemory()
        let tables = try db.writer.read { database in
            try String.fetchAll(database, sql: "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name")
        }
        for expected in ["scans", "scan_cache", "findings", "watched_folders", "folder_profiles", "apply_journal"] {
            #expect(tables.contains(expected), "missing table \(expected)")
        }
    }

    @Test("scan_cache rows round-trip")
    func scanCacheRoundTrip() throws {
        let db = try AuditorDatabase.inMemory()
        try db.writer.write { database in
            try database.execute(
                sql: """
                    INSERT INTO scan_cache (path, size, mtime_ns, file_id, partial_hash, full_hash, last_seen_scan)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: ["/tmp/a.pdf", 1024, 1_700_000_000_000_000_000, "fid-1", "p-hash", "f-hash", "scan-1"]
            )
        }
        let row = try db.writer.read { database in
            try Row.fetchOne(database, sql: "SELECT * FROM scan_cache WHERE path = ?", arguments: ["/tmp/a.pdf"])
        }
        #expect(row != nil)
        #expect(row?["full_hash"] == "f-hash")
        #expect(row?["size"] == 1024)
    }

    @Test("findings stable_key uniqueness is enforced")
    func stableKeyUnique() throws {
        let db = try AuditorDatabase.inMemory()
        let insert = """
            INSERT INTO findings (id, stable_key, detector_id, kind, severity, payload_json, decision, scan_id, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
        try db.writer.write { database in
            try database.execute(sql: insert, arguments: [UUID().uuidString, "key-1", "d", "k", 1, "{}", "pending", "s", Date()])
        }
        #expect(throws: DatabaseError.self) {
            try db.writer.write { database in
                try database.execute(sql: insert, arguments: [UUID().uuidString, "key-1", "d", "k", 1, "{}", "pending", "s", Date()])
            }
        }
    }
}
