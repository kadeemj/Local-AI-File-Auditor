import AuditorModels
import Foundation
import GRDB

public struct StoredFolderProfile: Codable, Sendable, Equatable {
    public let path: String
    public let embedding: [Double]
    public let description: String?
    public let updatedAt: Date

    public init(path: String, embedding: [Double], description: String? = nil, updatedAt: Date = Date()) {
        self.path = path
        self.embedding = embedding
        self.description = description
        self.updatedAt = updatedAt
    }
}

/// A user-granted folder and its security-scoped bookmark blob.
/// The app creates bookmarks via `URL.bookmarkData`; the engine only persists them.
public struct StoredWatchedFolder: Codable, Sendable, Equatable {
    public let path: String
    public let bookmark: Data?
    public let cloudMode: CloudScanMode
    public let addedAt: Date

    public init(
        path: String,
        bookmark: Data?,
        cloudMode: CloudScanMode = .metadataOnly,
        addedAt: Date = Date()
    ) {
        self.path = path
        self.bookmark = bookmark
        self.cloudMode = cloudMode
        self.addedAt = addedAt
    }
}

/// Owns the SQLite database (GRDB). One writer for the app; in-memory queues for tests.
/// Extracted document text is never stored — only fingerprints, metadata, and findings.
public final class AuditorDatabase: Sendable {
    public let writer: any DatabaseWriter

    public init(path: String) throws {
        var config = Configuration()
        config.foreignKeysEnabled = true
        let pool = try DatabasePool(path: path, configuration: config)
        self.writer = pool
        try Self.migrator.migrate(pool)
    }

    public static func inMemory() throws -> AuditorDatabase {
        try AuditorDatabase(queue: DatabaseQueue())
    }

    private init(queue: DatabaseQueue) throws {
        self.writer = queue
        try Self.migrator.migrate(queue)
    }

    public func saveFolderProfiles(_ profiles: [StoredFolderProfile]) throws {
        let encoder = JSONEncoder()
        try writer.write { database in
            for profile in profiles {
                guard !profile.path.isEmpty,
                      !profile.embedding.isEmpty,
                      profile.embedding.allSatisfy(\.isFinite)
                else { continue }
                let embeddingData = try encoder.encode(profile.embedding)
                try database.execute(
                    sql: """
                        INSERT INTO folder_profiles (path, embedding, description, updated_at)
                        VALUES (?, ?, ?, ?)
                        ON CONFLICT(path) DO UPDATE SET
                            embedding = excluded.embedding,
                            description = excluded.description,
                            updated_at = excluded.updated_at
                        """,
                    arguments: [profile.path, embeddingData, profile.description, profile.updatedAt]
                )
            }
        }
    }

    public func loadFolderProfiles() throws -> [StoredFolderProfile] {
        let decoder = JSONDecoder()
        return try writer.read { database in
            let rows = try Row.fetchAll(
                database,
                sql: "SELECT path, embedding, description, updated_at FROM folder_profiles ORDER BY path"
            )
            return try rows.compactMap { row in
                guard let embeddingData: Data = row["embedding"] else { return nil }
                return StoredFolderProfile(
                    path: row["path"],
                    embedding: try decoder.decode([Double].self, from: embeddingData),
                    description: row["description"],
                    updatedAt: row["updated_at"]
                )
            }
        }
    }

    public func saveWatchedFolder(_ folder: StoredWatchedFolder) throws {
        let encoder = JSONEncoder()
        let cloudModeJSON = try encoder.encode(folder.cloudMode)
        try writer.write { database in
            try database.execute(
                sql: """
                    INSERT INTO watched_folders (path, bookmark, cloud_mode_json, added_at)
                    VALUES (?, ?, ?, ?)
                    ON CONFLICT(path) DO UPDATE SET
                        bookmark = excluded.bookmark,
                        cloud_mode_json = excluded.cloud_mode_json,
                        added_at = excluded.added_at
                    """,
                arguments: [folder.path, folder.bookmark, cloudModeJSON, folder.addedAt]
            )
        }
    }

    public func loadWatchedFolders() throws -> [StoredWatchedFolder] {
        let decoder = JSONDecoder()
        return try writer.read { database in
            let rows = try Row.fetchAll(
                database,
                sql: """
                    SELECT path, bookmark, cloud_mode_json, added_at
                    FROM watched_folders
                    ORDER BY added_at ASC
                    """
            )
            return rows.map { row in
                let cloudMode: CloudScanMode
                if let data: Data = row["cloud_mode_json"],
                   let decoded = try? decoder.decode(CloudScanMode.self, from: data) {
                    cloudMode = decoded
                } else {
                    cloudMode = .metadataOnly
                }
                return StoredWatchedFolder(
                    path: row["path"],
                    bookmark: row["bookmark"],
                    cloudMode: cloudMode,
                    addedAt: row["added_at"]
                )
            }
        }
    }

    public func removeWatchedFolder(path: String) throws {
        try writer.write { database in
            try database.execute(
                sql: "DELETE FROM watched_folders WHERE path = ?",
                arguments: [path]
            )
        }
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            try db.create(table: "scans") { t in
                t.column("id", .text).primaryKey()
                t.column("started_at", .datetime).notNull()
                t.column("config_json", .text).notNull()
                t.column("summary_json", .text)
            }

            try db.create(table: "scan_cache") { t in
                t.column("path", .text).primaryKey()
                t.column("size", .integer).notNull()
                t.column("mtime_ns", .integer).notNull()
                t.column("file_id", .text)
                t.column("partial_hash", .text)
                t.column("full_hash", .text)
                t.column("text_fingerprint", .blob)
                t.column("last_seen_scan", .text).notNull()
            }
            try db.create(index: "idx_scan_cache_full_hash", on: "scan_cache", columns: ["full_hash"])

            try db.create(table: "findings") { t in
                t.column("id", .text).primaryKey()
                t.column("stable_key", .text).notNull().unique()
                t.column("detector_id", .text).notNull()
                t.column("kind", .text).notNull()
                t.column("severity", .integer).notNull()
                t.column("payload_json", .text).notNull()
                t.column("decision", .text).notNull()
                t.column("scan_id", .text).notNull()
                t.column("created_at", .datetime).notNull()
            }

            try db.create(table: "watched_folders") { t in
                t.column("path", .text).primaryKey()
                t.column("bookmark", .blob)
                t.column("cloud_mode_json", .text)
                t.column("added_at", .datetime).notNull()
            }

            try db.create(table: "folder_profiles") { t in
                t.column("path", .text).primaryKey()
                t.column("embedding", .blob)
                t.column("description", .text)
                t.column("updated_at", .datetime).notNull()
            }

            try db.create(table: "apply_journal") { t in
                t.column("id", .integer).primaryKey(autoincrement: true)
                t.column("batch_id", .text).notNull().indexed()
                t.column("finding_id", .text).notNull()
                t.column("operation", .text).notNull()
                t.column("original_path", .text).notNull()
                t.column("new_path", .text).notNull()
                t.column("performed_at", .datetime).notNull()
                t.column("undone_at", .datetime)
            }
        }

        return migrator
    }
}
