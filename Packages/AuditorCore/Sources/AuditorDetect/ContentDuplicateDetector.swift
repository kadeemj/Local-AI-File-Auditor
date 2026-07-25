import AuditorHashing
import AuditorModels
import Foundation

/// Content-level duplicates: same text, different bytes (Word export vs PDF,
/// re-saved by another app, rescanned). Works over MinHash fingerprints the
/// engine computed; collapses byte-identical files first so exact-duplicate
/// sets aren't re-reported as content duplicates.
public struct ContentDuplicateDetector: Detector {
    public static let id = "core.contentDuplicates"
    public let displayName = "Content duplicates"
    public let requiredSignals: DetectorSignals = [.textContent]

    let finder: ContentDuplicateFinder

    public init(similarityThreshold: Double = 0.85) {
        self.finder = ContentDuplicateFinder(threshold: similarityThreshold)
    }

    public func detect(context: DetectionContext) async throws -> [Finding] {
        guard let fingerprints = context.textFingerprints, fingerprints.count >= 2 else { return [] }
        let recordsByPath = Dictionary(uniqueKeysWithValues: context.files.map { ($0.path, $0) })

        // Byte-identical files are already exact-duplicate findings; keep one
        // representative per exact set so this detector reports only true
        // "same content, different file" cases.
        var exactGroupByPath: [String: String] = [:]
        for group in context.duplicateGroups ?? [] {
            for file in group.files { exactGroupByPath[file.path] = group.contentHash }
        }

        var findings: [Finding] = []
        for set in finder.duplicateSets(in: fingerprints) {
            // Collapse byte-identical members to one representative each —
            // the best-ranked keeper of its exact group, not an arbitrary path.
            var standalone: [FileRecord] = []
            var byExactGroup: [String: [FileRecord]] = [:]
            for path in set.paths {
                guard let record = recordsByPath[path] else { continue }
                if let exactGroup = exactGroupByPath[path] {
                    byExactGroup[exactGroup, default: []].append(record)
                } else {
                    standalone.append(record)
                }
            }
            let records = standalone + byExactGroup.values.compactMap { members in
                members.min { KeeperRanking.rank($0) < KeeperRanking.rank($1) }
            }
            guard records.count >= 2 else { continue }

            let ranked = records.sorted { KeeperRanking.rank($0) < KeeperRanking.rank($1) }
            let keeper = ranked[0]
            let extras = Array(ranked.dropFirst())
            let wasted = extras.reduce(Int64(0)) { $0 + $1.size }
            let percent = Int((set.minimumSimilarity * 100).rounded())

            findings.append(Finding(
                detectorID: Self.id,
                kind: "core.duplicateSet.content",
                severity: .medium,
                files: ranked.map(FileRef.init),
                evidence: .contentDuplicateSet(estimatedSimilarity: set.minimumSimilarity, wastedBytes: wasted),
                explanation: "\(records.count) files contain the same text (≥\(percent)% similar) "
                    + "even though their bytes differ — likely the same document saved by "
                    + "different apps or exported to another format. "
                    + "“\(keeper.filename)” looks canonical.",
                recommendation: .keepCanonical(keep: FileRef(keeper), archive: extras.map(FileRef.init)),
                confidence: set.minimumSimilarity,
                stableKeyMaterial: "content:\(records.map(\.path).sorted().joined(separator: "|"))",
                scanID: context.scanID
            ))
        }

        return findings.sorted { $0.stableKey < $1.stableKey }
    }
}
