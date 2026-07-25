import AuditorHashing
import AuditorModels
import Foundation

/// Turns duplicate groups into findings with a recommended keeper.
/// Keeper heuristic (deterministic, from the plan): prefer the copy outside
/// derivative locations, with the cleanest name, earliest created as tiebreak.
public struct DuplicateDetector: Detector {
    public static let id = "core.duplicates"
    public let displayName = "Duplicate documents"
    public let requiredSignals: DetectorSignals = [.hashes]

    public init() {}

    public func detect(context: DetectionContext) async throws -> [Finding] {
        (context.duplicateGroups ?? []).compactMap { group in
            makeFinding(from: group, scanID: context.scanID)
        }
    }

    private func makeFinding(from group: DuplicateGroup, scanID: UUID) -> Finding? {
        guard group.files.count >= 2 else { return nil }

        let ranked = group.files.sorted { keeperRank($0) < keeperRank($1) }
        let keeper = ranked[0]
        let extras = Array(ranked.dropFirst())
        let wasted = extras.reduce(Int64(0)) { $0 + $1.size }

        let verified = group.isPartialOnly
            ? "matching size and sampled content (too large for full verification)"
            : "identical content, SHA-256 verified"
        let formatter = ByteCountFormatter()

        return Finding(
            detectorID: Self.id,
            kind: group.isPartialOnly ? "core.duplicateSet.probable" : "core.duplicateSet.exact",
            severity: .medium,
            files: group.files.map(FileRef.init),
            evidence: .duplicateSet(contentHash: group.contentHash, wastedBytes: wasted),
            explanation: "\(group.files.count) files contain \(verified). "
                + "Keeping “\(keeper.filename)” and archiving the other \(extras.count) "
                + "would reclaim \(formatter.string(fromByteCount: wasted)).",
            recommendation: .keepCanonical(
                keep: FileRef(keeper),
                archive: extras.map(FileRef.init)
            ),
            confidence: group.isPartialOnly ? 0.9 : 1.0,
            stableKeyMaterial: group.contentHash,
            scanID: scanID
        )
    }

    /// Lower ranks first. Tuple compares penalty, then name length, then age.
    private func keeperRank(_ record: FileRecord) -> (Int, Int, TimeInterval) {
        let name = record.filename.lowercased()
        var penalty = 0

        if name.contains("copy") { penalty += 3 }
        if name.range(of: #"\(\d+\)"#, options: .regularExpression) != nil { penalty += 3 }
        for token in ["final", "draft", "old", "new", "backup", "bak"] where name.contains(token) {
            penalty += 1
        }
        if record.path.contains("/Downloads/") { penalty += 4 }

        return (penalty, record.filename.count, record.createdAt?.timeIntervalSince1970 ?? .infinity)
    }
}
