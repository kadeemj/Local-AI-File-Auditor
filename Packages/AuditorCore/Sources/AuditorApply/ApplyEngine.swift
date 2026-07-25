import AuditorModels
import AuditorStore
import Foundation

/// One concrete file operation derived from an approved finding.
/// FolderLint renames and moves only — there is no delete operation, by design.
public struct ApplyOperation: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case rename
        case move
        /// Move aside into `_Archive/` next to the kept canonical file.
        case archive
    }

    public var id: String { "\(findingID.uuidString):\(originalPath)→\(newPath)" }

    public let findingID: UUID
    public let kind: Kind
    public let originalPath: String
    public let newPath: String
    /// Snapshot from the finding / scan, used for changed-since-scan checks.
    public let expectedSize: Int64?
    public let expectedMtime: Date?

    public init(
        findingID: UUID,
        kind: Kind,
        originalPath: String,
        newPath: String,
        expectedSize: Int64? = nil,
        expectedMtime: Date? = nil
    ) {
        self.findingID = findingID
        self.kind = kind
        self.originalPath = originalPath
        self.newPath = newPath
        self.expectedSize = expectedSize
        self.expectedMtime = expectedMtime
    }
}

public struct ApplyConflict: Codable, Sendable, Equatable, Identifiable {
    public var id: String { "\(operation.originalPath)|\(reason.rawValue)|\(detail)" }

    public enum Reason: String, Codable, Sendable {
        case sourceMissing
        case destinationExists
        case destinationCollisionInPlan
        case changedSinceScan
        case datalessCloudItem
        case notAFile
        case unsupportedRecommendation
    }

    public let operation: ApplyOperation
    public let reason: Reason
    public let detail: String

    public init(operation: ApplyOperation, reason: Reason, detail: String) {
        self.operation = operation
        self.reason = reason
        self.detail = detail
    }
}

public struct ApplyPlan: Sendable, Equatable {
    public let batchID: UUID
    public let operations: [ApplyOperation]
    public let conflicts: [ApplyConflict]

    public init(batchID: UUID = UUID(), operations: [ApplyOperation], conflicts: [ApplyConflict]) {
        self.batchID = batchID
        self.operations = operations
        self.conflicts = conflicts
    }

    public var isAppliable: Bool { !operations.isEmpty && conflicts.isEmpty }
}

public struct ApplyResult: Sendable, Equatable {
    public let batchID: UUID
    public let appliedOperations: [ApplyOperation]
    public let findingIDs: [UUID]

    public init(batchID: UUID, appliedOperations: [ApplyOperation], findingIDs: [UUID]) {
        self.batchID = batchID
        self.appliedOperations = appliedOperations
        self.findingIDs = findingIDs
    }
}

public enum ApplyError: Error, Sendable, Equatable {
    case planHasConflicts(Int)
    case emptyPlan
    case sourceMissing(String)
    case destinationExists(String)
    case changedSinceScan(path: String)
    case changedSinceApply(path: String)
    case datalessCloudItem(String)
    case batchNotFound(UUID)
    case batchAlreadyUndone(UUID)
    case ioFailure(String)
}

/// plan → preview → journal-first restore point → apply → verify → undo.
/// Never deletes. Archive means move into `_Archive/`.
public struct ApplyEngine: Sendable {
    private let database: AuditorDatabase

    public init(database: AuditorDatabase) {
        self.database = database
    }

    private var fileManager: FileManager { .default }

    /// Builds rename/move/archive operations from findings and surfaces conflicts.
    /// Only findings with actionable file recommendations produce operations;
    /// `scheduleReminder` / `review` are skipped (no file mutation).
    public func plan(findings: [Finding], batchID: UUID = UUID()) -> ApplyPlan {
        var planned: [ApplyOperation] = []
        var conflicts: [ApplyConflict] = []
        var claimedDestinations: [String: ApplyOperation] = [:]

        for finding in findings {
            let built = buildOperations(for: finding)
            for operation in built.operations {
                if let prior = claimedDestinations[operation.newPath] {
                    conflicts.append(ApplyConflict(
                        operation: operation,
                        reason: .destinationCollisionInPlan,
                        detail: "Also targeted by \(prior.originalPath)"
                    ))
                    continue
                }
                claimedDestinations[operation.newPath] = operation
                if let conflict = validate(operation) {
                    conflicts.append(conflict)
                } else {
                    planned.append(operation)
                }
            }
            conflicts.append(contentsOf: built.conflicts)
        }

        return ApplyPlan(batchID: batchID, operations: planned, conflicts: conflicts)
    }

    /// Commits journal rows, then performs moves. On mid-batch failure, rolls
    /// completed operations back and marks the batch undone.
    @discardableResult
    public func apply(_ plan: ApplyPlan) throws -> ApplyResult {
        guard plan.conflicts.isEmpty else { throw ApplyError.planHasConflicts(plan.conflicts.count) }
        guard !plan.operations.isEmpty else { throw ApplyError.emptyPlan }

        // Re-validate immediately before touching anything.
        for operation in plan.operations {
            if let conflict = validate(operation) {
                throw mapConflict(conflict)
            }
        }

        let now = Date()
        let entries = try plan.operations.map { operation -> StoredJournalEntry in
            let attrs = try fileAttributes(at: operation.originalPath)
            return StoredJournalEntry(
                batchID: plan.batchID,
                findingID: operation.findingID,
                operation: operation.kind.rawValue,
                originalPath: operation.originalPath,
                newPath: operation.newPath,
                originalSize: attrs.size,
                originalMtimeNanoseconds: attrs.mtimeNanoseconds,
                newSize: nil,
                newMtimeNanoseconds: nil,
                performedAt: now,
                undoneAt: nil
            )
        }

        // Restore point first — journal is durable before any rename/move.
        try database.insertJournalEntries(entries)

        var completed: [ApplyOperation] = []
        do {
            for operation in plan.operations {
                try perform(operation)
                completed.append(operation)
                let attrs = try fileAttributes(at: operation.newPath)
                try database.updateJournalNewState(
                    batchID: plan.batchID,
                    originalPath: operation.originalPath,
                    newSize: attrs.size,
                    newMtimeNanoseconds: attrs.mtimeNanoseconds
                )
            }
        } catch {
            for operation in completed.reversed() {
                try? fileManager.moveItem(
                    at: URL(fileURLWithPath: operation.newPath),
                    to: URL(fileURLWithPath: operation.originalPath)
                )
            }
            try? database.markBatchUndone(plan.batchID, at: Date())
            if let applyError = error as? ApplyError {
                throw applyError
            }
            throw ApplyError.ioFailure(String(describing: error))
        }

        let findingIDs = Array(Set(plan.operations.map(\.findingID)))
        return ApplyResult(batchID: plan.batchID, appliedOperations: completed, findingIDs: findingIDs)
    }

    /// Replays a batch in reverse. Refuses if any applied file changed since apply.
    public func undo(batchID: UUID) throws {
        let entries = try database.loadJournalEntries(batchID: batchID)
        guard !entries.isEmpty else { throw ApplyError.batchNotFound(batchID) }
        guard entries.allSatisfy({ $0.undoneAt == nil }) else {
            throw ApplyError.batchAlreadyUndone(batchID)
        }

        for entry in entries.reversed() {
            guard fileManager.fileExists(atPath: entry.newPath) else {
                throw ApplyError.sourceMissing(entry.newPath)
            }
            if fileManager.fileExists(atPath: entry.originalPath) {
                throw ApplyError.destinationExists(entry.originalPath)
            }
            if let size = entry.newSize, let mtime = entry.newMtimeNanoseconds {
                let attrs = try fileAttributes(at: entry.newPath)
                if attrs.size != size || attrs.mtimeNanoseconds != mtime {
                    throw ApplyError.changedSinceApply(path: entry.newPath)
                }
            }
            try fileManager.moveItem(
                at: URL(fileURLWithPath: entry.newPath),
                to: URL(fileURLWithPath: entry.originalPath)
            )
        }

        try database.markBatchUndone(batchID, at: Date())
    }

    // MARK: - Planning helpers

    private struct BuiltOps {
        var operations: [ApplyOperation] = []
        var conflicts: [ApplyConflict] = []
    }

    private func buildOperations(for finding: Finding) -> BuiltOps {
        var built = BuiltOps()
        switch finding.recommendation {
        case .rename(let file, let proposedName):
            let directory = (file.path as NSString).deletingLastPathComponent
            let sanitized = (proposedName as NSString).lastPathComponent
            let destination = (directory as NSString).appendingPathComponent(sanitized)
            if destination == file.path {
                return built
            }
            built.operations.append(ApplyOperation(
                findingID: finding.id,
                kind: .rename,
                originalPath: file.path,
                newPath: destination,
                expectedSize: file.size,
                expectedMtime: file.modifiedAt
            ))

        case .move(let file, let destinationFolder):
            let destination = (destinationFolder as NSString)
                .appendingPathComponent((file.path as NSString).lastPathComponent)
            if destination == file.path {
                return built
            }
            built.operations.append(ApplyOperation(
                findingID: finding.id,
                kind: .move,
                originalPath: file.path,
                newPath: destination,
                expectedSize: file.size,
                expectedMtime: file.modifiedAt
            ))

        case .keepCanonical(_, let archive):
            for file in archive {
                let parent = (file.path as NSString).deletingLastPathComponent
                let archiveDir = (parent as NSString).appendingPathComponent("_Archive")
                let destination = (archiveDir as NSString)
                    .appendingPathComponent((file.path as NSString).lastPathComponent)
                built.operations.append(ApplyOperation(
                    findingID: finding.id,
                    kind: .archive,
                    originalPath: file.path,
                    newPath: destination,
                    expectedSize: file.size,
                    expectedMtime: file.modifiedAt
                ))
            }

        case .scheduleReminder, .review:
            break
        }
        return built
    }

    private func validate(_ operation: ApplyOperation) -> ApplyConflict? {
        let source = URL(fileURLWithPath: operation.originalPath)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: operation.originalPath, isDirectory: &isDirectory) else {
            return ApplyConflict(operation: operation, reason: .sourceMissing, detail: operation.originalPath)
        }
        if isDirectory.boolValue {
            return ApplyConflict(operation: operation, reason: .notAFile, detail: operation.originalPath)
        }
        if isDatalessCloudItem(source) {
            return ApplyConflict(
                operation: operation,
                reason: .datalessCloudItem,
                detail: "Cloud placeholder has no local bytes"
            )
        }
        if let expectedSize = operation.expectedSize, let expectedMtime = operation.expectedMtime {
            do {
                let attrs = try fileAttributes(at: operation.originalPath)
                let expectedNanos = Int64(expectedMtime.timeIntervalSince1970 * 1_000_000_000)
                // Allow 1s slack — FileRef stores Date, filesystem may be second-resolution.
                if attrs.size != expectedSize
                    || abs(attrs.mtimeNanoseconds - expectedNanos) > 1_000_000_000 {
                    return ApplyConflict(
                        operation: operation,
                        reason: .changedSinceScan,
                        detail: "Size or modification time no longer matches the scan snapshot"
                    )
                }
            } catch {
                return ApplyConflict(operation: operation, reason: .sourceMissing, detail: operation.originalPath)
            }
        }
        if fileManager.fileExists(atPath: operation.newPath) {
            return ApplyConflict(operation: operation, reason: .destinationExists, detail: operation.newPath)
        }
        return nil
    }

    private func perform(_ operation: ApplyOperation) throws {
        let destination = URL(fileURLWithPath: operation.newPath)
        let parent = destination.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parent.path) {
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        }
        do {
            try fileManager.moveItem(at: URL(fileURLWithPath: operation.originalPath), to: destination)
        } catch {
            throw ApplyError.ioFailure("move \(operation.originalPath) → \(operation.newPath): \(error)")
        }
    }

    private func mapConflict(_ conflict: ApplyConflict) -> ApplyError {
        switch conflict.reason {
        case .sourceMissing: .sourceMissing(conflict.operation.originalPath)
        case .destinationExists, .destinationCollisionInPlan: .destinationExists(conflict.operation.newPath)
        case .changedSinceScan: .changedSinceScan(path: conflict.operation.originalPath)
        case .datalessCloudItem: .datalessCloudItem(conflict.operation.originalPath)
        case .notAFile: .ioFailure(conflict.detail)
        case .unsupportedRecommendation: .emptyPlan
        }
    }

    private struct FileAttrs {
        let size: Int64
        let mtimeNanoseconds: Int64
    }

    private func fileAttributes(at path: String) throws -> FileAttrs {
        let attrs = try fileManager.attributesOfItem(atPath: path)
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        let mtime = (attrs[.modificationDate] as? Date) ?? Date.distantPast
        return FileAttrs(
            size: size,
            mtimeNanoseconds: Int64(mtime.timeIntervalSince1970 * 1_000_000_000)
        )
    }

    private func isDatalessCloudItem(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey,
        ])
        guard values?.isUbiquitousItem == true else { return false }
        return values?.ubiquitousItemDownloadingStatus == .notDownloaded
    }
}
