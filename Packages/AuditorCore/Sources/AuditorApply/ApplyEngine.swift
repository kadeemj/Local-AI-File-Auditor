import AuditorModels
import Foundation

/// One concrete file operation derived from an approved finding.
/// FolderLint renames and moves only — there is no delete operation, by design.
public struct ApplyOperation: Codable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case rename
        case move
    }

    public let findingID: UUID
    public let kind: Kind
    public let originalPath: String
    public let newPath: String

    public init(findingID: UUID, kind: Kind, originalPath: String, newPath: String) {
        self.findingID = findingID
        self.kind = kind
        self.originalPath = originalPath
        self.newPath = newPath
    }
}

public struct ApplyPlan: Sendable {
    public let batchID: UUID
    public let operations: [ApplyOperation]
    /// Conflicts detected during planning (name collisions, dataless placeholders,
    /// files changed since scan). A plan with conflicts cannot be applied as-is.
    public let conflicts: [String]

    public init(batchID: UUID, operations: [ApplyOperation], conflicts: [String]) {
        self.batchID = batchID
        self.operations = operations
        self.conflicts = conflicts
    }
}

/// Phase 9: plan → preview → journal-first restore point → apply → verify → undo.
/// The journal row is committed to the database before any file is touched.
public struct ApplyEngine: Sendable {
    public init() {}
}
