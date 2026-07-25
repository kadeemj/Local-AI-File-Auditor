import AuditorModels
import Foundation

public struct RankedVersionCluster: Sendable {
    /// Canonical/most-current first.
    public let orderedFiles: [FileRecord]
    public let stem: String
    public let confidence: Double
    /// Human-readable evidence lines for the finding.
    public let signals: [String]
}

/// Deterministic ranking of a version-family cluster. Priority order (per plan):
/// non-conflicted > non-derivative > explicit version > filename date > status
/// > loose counter > modification time. Confidence reflects how much real
/// signal distinguished the files — mtime alone proves nothing.
public enum ClusterRanker {
    public static func rank(cluster: [(record: FileRecord, tokens: VersionTokens)], stem: String) -> RankedVersionCluster {
        let ordered = cluster.sorted { lhs, rhs in
            descending(sortKey(lhs.tokens, lhs.record), sortKey(rhs.tokens, rhs.record))
        }

        var confidence = 0.5
        var signals: [String] = []

        let versions = Set(cluster.compactMap(\.tokens.explicitVersion))
        if versions.count >= 2 {
            confidence += 0.2
            signals.append("explicit versions: \(versions.sorted().map { "v\($0)" }.joined(separator: ", "))")
        }

        let dates = Set(cluster.compactMap(\.tokens.dateValue))
        if dates.count >= 2 {
            confidence += 0.15
            signals.append("dated filenames: \(dates.sorted().map(formatDateValue).joined(separator: " … "))")
        }

        if cluster.contains(where: \.tokens.isConflictedCopy) {
            confidence += 0.15
            signals.append("sync-conflict copy present")
        }

        let statusRanks = Set(cluster.map(\.tokens.statusRank))
        if statusRanks.count >= 2 {
            confidence += 0.1
            let words = Set(cluster.flatMap(\.tokens.statuses))
            signals.append("status words: \(words.sorted().joined(separator: ", "))")
        }

        let derivativeFlags = Set(cluster.map { isDerivative($0.tokens) })
        if derivativeFlags.count == 2 {
            confidence += 0.1
            signals.append("copy-markers distinguish originals from copies")
        }

        // Contradiction: explicit versions exist but the newest-by-version file
        // is not the newest-by-mtime. Version number wins; trust drops.
        if versions.count >= 2 {
            let byMtime = cluster.max { $0.record.mtimeNanoseconds < $1.record.mtimeNanoseconds }
            if let top = ordered.first, let newest = byMtime, top.record.path != newest.record.path {
                confidence -= 0.15
                signals.append("note: version numbers contradict modification times")
            }
        }

        // Bare years as the ONLY distinguishing token = different documents
        // (invoice 2024 / invoice 2025), not versions.
        let years = Set(cluster.compactMap(\.tokens.yearOnly))
        let hasRealSignal = versions.count >= 2 || dates.count >= 2 || statusRanks.count >= 2
            || derivativeFlags.count == 2 || cluster.contains(where: \.tokens.isConflictedCopy)
            || Set(cluster.compactMap(\.tokens.looseNumber)).count >= 2
        if years.count >= 2 && !hasRealSignal {
            confidence = 0.35
            signals.append("only bare years differ — likely distinct annual documents")
        } else if !hasRealSignal {
            confidence = 0.35
            signals.append("only modification times differ — weak evidence")
        }

        // Wild size divergence suggests unrelated content sharing a name pattern.
        let sizes = cluster.map(\.record.size).filter { $0 > 0 }
        if let smallest = sizes.min(), let largest = sizes.max(), smallest > 0, largest / smallest > 3 {
            confidence -= 0.2
            signals.append("note: file sizes diverge more than 3×")
        }

        return RankedVersionCluster(
            orderedFiles: ordered.map(\.record),
            stem: stem,
            confidence: min(max(confidence, 0.05), 0.98),
            signals: signals
        )
    }

    static func isDerivative(_ tokens: VersionTokens) -> Bool {
        tokens.isCopy || tokens.copyNumber != nil || tokens.isConflictedCopy
    }

    private static func sortKey(_ tokens: VersionTokens, _ record: FileRecord) -> [Int64] {
        [
            tokens.isConflictedCopy ? 0 : 1,
            isDerivative(tokens) ? 0 : 1,
            Int64(tokens.explicitVersion ?? -1),
            Int64(tokens.dateValue ?? -1),
            Int64(tokens.statusRank),
            Int64(tokens.looseNumber ?? -1),
            record.mtimeNanoseconds,
        ]
    }

    private static func formatDateValue(_ value: Int) -> String {
        String(format: "%04d-%02d-%02d", value / 10_000, (value / 100) % 100, value % 100)
    }

    private static func descending(_ lhs: [Int64], _ rhs: [Int64]) -> Bool {
        for (l, r) in zip(lhs, rhs) where l != r { return l > r }
        return false
    }
}
