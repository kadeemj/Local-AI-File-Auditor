import Foundation

/// A file observed during a crawl. Pure value type; produced by AuditorCrawl,
/// consumed by hashing, extraction, and detection.
public struct FileRecord: Codable, Sendable, Hashable, Identifiable {
    public var id: String { path }

    public let path: String
    public let size: Int64
    /// Modification time in nanoseconds since epoch — the incremental-rescan cache key
    /// alongside `size` and `fileID`.
    public let mtimeNanoseconds: Int64
    public let createdAt: Date?
    /// `URLResourceKey.fileResourceIdentifierKey`, stringified. Used to dedupe hardlinks.
    public let fileID: String?
    /// Uniform type identifier string (e.g. "com.adobe.pdf").
    public let contentType: String?
    /// iCloud / File Provider placeholder whose content is not on disk.
    /// Such files must never be opened for content analysis unless the scan's
    /// cloud mode permits an explicit download.
    public let isDatalessCloudItem: Bool

    public init(
        path: String,
        size: Int64,
        mtimeNanoseconds: Int64,
        createdAt: Date? = nil,
        fileID: String? = nil,
        contentType: String? = nil,
        isDatalessCloudItem: Bool = false
    ) {
        self.path = path
        self.size = size
        self.mtimeNanoseconds = mtimeNanoseconds
        self.createdAt = createdAt
        self.fileID = fileID
        self.contentType = contentType
        self.isDatalessCloudItem = isDatalessCloudItem
    }

    public var url: URL { URL(fileURLWithPath: path) }
    public var filename: String { (path as NSString).lastPathComponent }
}

/// A lightweight reference to a file inside a finding's evidence.
public struct FileRef: Codable, Sendable, Hashable {
    public let path: String
    public let size: Int64
    public let modifiedAt: Date

    public init(path: String, size: Int64, modifiedAt: Date) {
        self.path = path
        self.size = size
        self.modifiedAt = modifiedAt
    }

    public init(_ record: FileRecord) {
        self.path = record.path
        self.size = record.size
        self.modifiedAt = Date(timeIntervalSince1970: Double(record.mtimeNanoseconds) / 1_000_000_000)
    }

    public var filename: String { (path as NSString).lastPathComponent }
}
