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

    @Test("folder profile centroids persist without extracted text")
    func folderProfilesRoundTrip() throws {
        let db = try AuditorDatabase.inMemory()
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        try db.saveFolderProfiles([
            StoredFolderProfile(
                path: "/docs/Finance",
                embedding: [0.25, 0.5, 0.75],
                description: "Invoices and budgets",
                updatedAt: timestamp
            ),
        ])

        let profiles = try db.loadFolderProfiles()
        let profile = try #require(profiles.first)
        #expect(profile.path == "/docs/Finance")
        #expect(profile.embedding == [0.25, 0.5, 0.75])
        #expect(profile.description == "Invoices and budgets")
        #expect(profile.updatedAt == timestamp)

        try db.saveFolderProfiles([
            StoredFolderProfile(path: "/docs/Finance", embedding: [1, 0, 0], updatedAt: timestamp),
        ])
        let updated = try #require(db.loadFolderProfiles().first)
        #expect(updated.embedding == [1, 0, 0])
    }

    @Test("watched folders persist bookmarks and cloud mode")
    func watchedFoldersRoundTrip() throws {
        let db = try AuditorDatabase.inMemory()
        let added = Date(timeIntervalSince1970: 1_700_000_100)
        let bookmark = Data("bookmark-bytes".utf8)
        try db.saveWatchedFolder(StoredWatchedFolder(
            path: "/Users/shared/Grants",
            bookmark: bookmark,
            cloudMode: .localOnly,
            addedAt: added
        ))

        let folders = try db.loadWatchedFolders()
        let folder = try #require(folders.first)
        #expect(folder.path == "/Users/shared/Grants")
        #expect(folder.bookmark == bookmark)
        #expect(folder.cloudMode == .localOnly)
        #expect(folder.addedAt == added)

        try db.saveWatchedFolder(StoredWatchedFolder(
            path: "/Users/shared/Grants",
            bookmark: Data("updated".utf8),
            cloudMode: .metadataOnly,
            addedAt: added
        ))
        let updated = try #require(db.loadWatchedFolders().first)
        #expect(updated.bookmark == Data("updated".utf8))
        #expect(updated.cloudMode == .metadataOnly)

        try db.removeWatchedFolder(path: "/Users/shared/Grants")
        #expect(try db.loadWatchedFolders().isEmpty)
    }
}
