import AuditorModels
import Foundation
import UniformTypeIdentifiers

/// Enumerates user-selected roots and yields `FileRecord` batches of ~512.
///
/// Design notes:
/// - `FileManager.enumerator` with prefetched resource keys batches attribute
///   reads via getattrlistbulk on APFS — no per-file stat round trips.
/// - The (non-Sendable) enumerator is confined to a single Task.
/// - Cloud placeholders are never opened here; they are flagged so downstream
///   stages honor the scan's `CloudScanMode`.
public struct FileCrawler: Sendable {
    static let batchSize = 512

    static let resourceKeys: [URLResourceKey] = [
        .isRegularFileKey, .isDirectoryKey, .isPackageKey, .isSymbolicLinkKey,
        .fileSizeKey, .contentModificationDateKey, .creationDateKey,
        .fileResourceIdentifierKey, .contentTypeKey,
        .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey,
    ]

    public init() {}

    public func crawl(roots: [URL], rules: SkipRules) -> AsyncThrowingStream<[FileRecord], Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var batch: [FileRecord] = []
                    batch.reserveCapacity(Self.batchSize)

                    for root in roots {
                        try Task.checkCancellation()
                        try Self.crawlRoot(root, rules: rules) { record in
                            batch.append(record)
                            if batch.count >= Self.batchSize {
                                continuation.yield(batch)
                                batch.removeAll(keepingCapacity: true)
                            }
                        }
                    }

                    if !batch.isEmpty {
                        continuation.yield(batch)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func crawlRoot(
        _ root: URL,
        rules: SkipRules,
        emit: (FileRecord) -> Void
    ) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw ScanError.rootUnreadable(path: root.path)
        }

        var options: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
        if rules.skipHidden {
            options.insert(.skipsHiddenFiles)
        }

        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: resourceKeys,
            options: options,
            errorHandler: { _, _ in true }  // unreadable subtrees are skipped, not fatal
        ) else {
            throw ScanError.rootUnreadable(path: root.path)
        }

        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: Set(resourceKeys)) else { continue }

            if values.isDirectory == true {
                if rules.directoryDenylist.contains(url.lastPathComponent) {
                    enumerator.skipDescendants()
                }
                continue
            }

            if values.isSymbolicLink == true { continue }
            guard values.isRegularFile == true else { continue }

            let size = Int64(values.fileSize ?? 0)
            guard size >= rules.minFileSize else { continue }

            let isDataless = values.isUbiquitousItem == true
                && values.ubiquitousItemDownloadingStatus != .current

            if isDataless, case .localOnly = rules.cloudMode { continue }

            let mtime = values.contentModificationDate ?? Date(timeIntervalSince1970: 0)

            emit(FileRecord(
                path: url.path,
                size: size,
                mtimeNanoseconds: Int64(mtime.timeIntervalSince1970 * 1_000_000_000),
                createdAt: values.creationDate,
                fileID: (values.fileResourceIdentifier).map { "\($0)" },
                contentType: values.contentType?.identifier,
                isDatalessCloudItem: isDataless
            ))
        }
    }
}
