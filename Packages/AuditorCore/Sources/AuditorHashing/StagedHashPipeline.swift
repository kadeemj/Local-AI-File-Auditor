import AuditorModels
import Foundation

/// Files that share a full content hash (or, for oversized files, a size+partial
/// signature — flagged so the UI can say "probable" instead of "verified").
public struct DuplicateGroup: Sendable {
    public let contentHash: String
    public let files: [FileRecord]
    public let isPartialOnly: Bool

    public init(contentHash: String, files: [FileRecord], isPartialOnly: Bool) {
        self.contentHash = contentHash
        self.files = files
        self.isPartialOnly = isPartialOnly
    }
}

/// Three-stage duplicate funnel: size grouping (free) → partial hash → full hash.
/// Each stage discards singleton groups, so expensive I/O only touches likely
/// duplicates. Unreadable files drop out silently rather than failing the scan.
public struct StagedHashPipeline: Sendable {
    let hasher: any ContentHasher
    let maxConcurrent: Int

    public init(
        hasher: any ContentHasher = SHA256Hasher(),
        maxConcurrent: Int = min(8, ProcessInfo.processInfo.activeProcessorCount)
    ) {
        self.hasher = hasher
        self.maxConcurrent = max(1, maxConcurrent)
    }

    public func duplicateGroups(in files: [FileRecord], rules: SkipRules) async throws -> [DuplicateGroup] {
        // Never open cloud placeholders; dedupe hardlinks (same file ID = same file).
        var seenFileIDs = Set<String>()
        let candidates = files.filter { record in
            guard !record.isDatalessCloudItem else { return false }
            guard let fileID = record.fileID else { return true }
            return seenFileIDs.insert(fileID).inserted
        }

        // Stage 1: size groups. Eliminates the overwhelming majority of files.
        let bySize = Dictionary(grouping: candidates, by: \.size).values.filter { $0.count > 1 }

        // Stage 2: partial hash within each size group.
        let partialGroups = try await regroup(bySize.flatMap { $0 }) { record in
            try await hasher.partialHash(of: record.url, size: record.size).hex
        }

        // Stage 3: full hash — except oversized files, which keep their
        // size+partial signature and are reported as probable duplicates.
        var results: [DuplicateGroup] = []
        var needFullHash: [FileRecord] = []

        for group in partialGroups {
            if group.first!.size > rules.maxFullHashSize {
                results.append(DuplicateGroup(
                    contentHash: "partial:\(group.key)",
                    files: group.members,
                    isPartialOnly: true
                ))
            } else {
                needFullHash.append(contentsOf: group.members)
            }
        }

        for group in try await regroup(needFullHash, key: { try await hasher.fullHash(of: $0.url).hex }) {
            results.append(DuplicateGroup(contentHash: group.key, files: group.members, isPartialOnly: false))
        }

        return results.sorted { $0.contentHash < $1.contentHash }
    }

    private struct KeyedGroup {
        let key: String
        let members: [FileRecord]
        var first: FileRecord? { members.first }
    }

    /// Hashes `files` with bounded concurrency and returns only groups of ≥2.
    private func regroup(
        _ files: [FileRecord],
        key: @escaping @Sendable (FileRecord) async throws -> String
    ) async throws -> [KeyedGroup] {
        guard !files.isEmpty else { return [] }

        let keyed: [(String, FileRecord)] = try await withThrowingTaskGroup(
            of: (String, FileRecord)?.self
        ) { group in
            var iterator = files.makeIterator()
            var inFlight = 0
            var collected: [(String, FileRecord)] = []

            func addNext() {
                guard let record = iterator.next() else { return }
                inFlight += 1
                group.addTask {
                    // Unreadable/racing files drop out of duplicate analysis.
                    guard let hash = try? await key(record) else { return nil }
                    return (hash, record)
                }
            }

            for _ in 0..<maxConcurrent { addNext() }
            while inFlight > 0 {
                guard let result = try await group.next() else { break }
                inFlight -= 1
                if let result { collected.append(result) }
                addNext()
            }
            return collected
        }

        return Dictionary(grouping: keyed, by: \.0)
            .filter { $0.value.count > 1 }
            .map { KeyedGroup(key: $0.key, members: $0.value.map(\.1)) }
    }
}
