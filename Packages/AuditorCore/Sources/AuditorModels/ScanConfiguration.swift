import Foundation

/// How the crawler treats cloud placeholders (iCloud / File Provider dataless items).
public enum CloudScanMode: Codable, Sendable, Hashable {
    /// Never download; placeholders get name/metadata analysis only.
    case metadataOnly
    /// May download files needed for content analysis, up to a byte budget.
    case downloadWhenNeeded(budgetBytes: Int64)
    /// Skip cloud placeholders entirely.
    case localOnly
}

public struct SkipRules: Codable, Sendable, Hashable {
    public var skipHidden: Bool
    public var skipPackages: Bool
    public var directoryDenylist: Set<String>
    public var minFileSize: Int64
    /// Files larger than this get size + partial-hash grouping only.
    public var maxFullHashSize: Int64
    public var cloudMode: CloudScanMode

    public init(
        skipHidden: Bool = true,
        skipPackages: Bool = true,
        directoryDenylist: Set<String> = ["node_modules", ".git", ".Trash", "DerivedData"],
        minFileSize: Int64 = 1,
        maxFullHashSize: Int64 = 4 << 30,
        cloudMode: CloudScanMode = .metadataOnly
    ) {
        self.skipHidden = skipHidden
        self.skipPackages = skipPackages
        self.directoryDenylist = directoryDenylist
        self.minFileSize = minFileSize
        self.maxFullHashSize = maxFullHashSize
        self.cloudMode = cloudMode
    }
}

public struct ScanConfiguration: Codable, Sendable {
    public var rootPaths: [String]
    public var skipRules: SkipRules
    /// Identifier of the active policy (naming template, folder taxonomy), if any.
    public var policyID: String?

    public init(rootPaths: [String], skipRules: SkipRules = SkipRules(), policyID: String? = nil) {
        self.rootPaths = rootPaths
        self.skipRules = skipRules
        self.policyID = policyID
    }
}
