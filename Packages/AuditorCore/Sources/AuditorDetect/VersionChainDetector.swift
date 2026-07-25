import AuditorModels
import Foundation

/// Finds version families from filenames + metadata alone (no content reads):
/// same directory, same extension, same normalized stem, distinguished by real
/// version signals. Foundation Models judging of ambiguous clusters is Phase 5;
/// this detector is the rules-only foundation it refines.
public struct VersionChainDetector: Detector {
    public static let id = "core.versions"
    public let displayName = "Outdated versions"
    public let requiredSignals: DetectorSignals = []

    /// Below this the cluster isn't reported (Phase 5 routes 0.4–0.85 to the
    /// on-device model instead of dropping).
    static let reportThreshold = 0.5

    public init() {}

    public func detect(context: DetectionContext) async throws -> [Finding] {
        let parsed = context.files.map { (record: $0, tokens: VersionTokenParser.parse(filename: $0.filename)) }

        // Cluster key: directory + extension + stem. Same-extension is a
        // deliberate false-positive guard — "report.docx" vs "report.pdf" is an
        // export, not a version chain.
        var clusters: [String: [(record: FileRecord, tokens: VersionTokens)]] = [:]
        for entry in parsed where !entry.tokens.stem.isEmpty {
            let directory = (entry.record.path as NSString).deletingLastPathComponent
            let ext = (entry.record.filename as NSString).pathExtension.lowercased()
            clusters["\(directory)\u{1F}\(ext)\u{1F}\(entry.tokens.stem)", default: []].append(entry)
        }

        var findings: [Finding] = []
        for cluster in clusters.values where cluster.count >= 2 {
            guard cluster.contains(where: \.tokens.hasVersionSignal) else { continue }

            let ranked = ClusterRanker.rank(cluster: cluster, stem: cluster[0].tokens.stem)
            guard ranked.confidence >= Self.reportThreshold else { continue }

            let keeper = ranked.orderedFiles[0]
            let stale = Array(ranked.orderedFiles.dropFirst())
            let directory = (keeper.path as NSString).deletingLastPathComponent

            findings.append(Finding(
                detectorID: Self.id,
                kind: "core.versionChain",
                severity: .medium,
                files: ranked.orderedFiles.map(FileRef.init),
                evidence: .versionChain(
                    rankedFilenames: ranked.orderedFiles.map(\.filename),
                    stem: ranked.stem,
                    signals: ranked.signals,
                    confidence: ranked.confidence,
                    judge: .rules
                ),
                explanation: "\(cluster.count) files in “\((directory as NSString).lastPathComponent)” "
                    + "appear to be versions of the same document (“\(ranked.stem)”). "
                    + "“\(keeper.filename)” ranks most current — \(ranked.signals.first ?? "based on filename and dates"). "
                    + "Consider archiving the older \(stale.count).",
                recommendation: .keepCanonical(keep: FileRef(keeper), archive: stale.map(FileRef.init)),
                confidence: ranked.confidence,
                stableKeyMaterial: "versionChain:\(ranked.stem)",
                scanID: context.scanID
            ))
        }

        return findings.sorted { $0.stableKey < $1.stableKey }
    }
}
