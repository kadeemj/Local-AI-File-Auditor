import AuditorAI
import AuditorModels
import Foundation

/// Finds version families from filenames + metadata alone (no content reads):
/// same directory, same extension, same normalized stem, distinguished by real
/// version signals. Ambiguous deterministic rankings are offered to Foundation
/// Models using filenames + filesystem metadata only. Every unavailable,
/// malformed, refused, or low-confidence semantic result falls back to rules.
public struct VersionChainDetector: Detector {
    public static let id = "core.versions"
    public let displayName = "Outdated versions"
    public let requiredSignals: DetectorSignals = [.semanticJudge]

    /// Below this the cluster isn't reported by either judge.
    static let reportThreshold = 0.5
    /// Only this uncertainty band pays the semantic-model cost.
    static let semanticJudgeRange = 0.4...0.85

    private let judgeAvailability: @Sendable () async -> ModelAvailability
    private let judgeRequest: @Sendable (VersionChainJudgeRequest) async throws -> VersionChainJudgment

    public init() {
        let judge = FoundationModelVersionChainJudge()
        self.judgeAvailability = { await judge.availability() }
        self.judgeRequest = { request in try await judge.judge(request) }
    }

    public init(judge: any VersionChainJudging) {
        self.judgeAvailability = { await judge.availability() }
        self.judgeRequest = { request in try await judge.judge(request) }
    }

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

        // Availability can change while the app is running, so this is checked
        // once for every scan rather than cached at launch.
        let semanticJudgeAvailable = await judgeAvailability().isAvailable
        var findings: [Finding] = []
        for cluster in clusters.values where cluster.count >= 2 {
            try Task.checkCancellation()
            guard cluster.contains(where: \.tokens.hasVersionSignal) else { continue }

            let ranked = ClusterRanker.rank(cluster: cluster, stem: cluster[0].tokens.stem)
            if semanticJudgeAvailable, Self.isSemanticCandidate(ranked.confidence),
               let semanticFinding = try await semanticFinding(
                   ranked: ranked,
                   context: context
               ) {
                findings.append(semanticFinding)
                continue
            }

            if let rulesFinding = rulesFinding(ranked: ranked, context: context) {
                findings.append(rulesFinding)
            }
        }

        return findings.sorted { $0.stableKey < $1.stableKey }
    }

    private static func isSemanticCandidate(_ confidence: Double) -> Bool {
        let tolerance = 1e-9
        return confidence >= semanticJudgeRange.lowerBound - tolerance
            && confidence <= semanticJudgeRange.upperBound + tolerance
    }

    private func semanticFinding(
        ranked: RankedVersionCluster,
        context: DetectionContext
    ) async throws -> Finding? {
        let request = VersionChainJudgeRequest(
            stem: ranked.stem,
            candidates: ranked.orderedFiles.enumerated().map { index, file in
                VersionChainCandidate(
                    index: index,
                    filename: file.filename,
                    sizeBytes: file.size,
                    modifiedAt: Date(
                        timeIntervalSince1970: Double(file.mtimeNanoseconds) / 1_000_000_000
                    ),
                    createdAt: file.createdAt
                )
            }
        )

        let judgment: VersionChainJudgment
        do {
            judgment = try await judgeRequest(request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return nil
        }

        guard judgment.isValid(candidateCount: ranked.orderedFiles.count),
              judgment.confidence >= Self.reportThreshold
        else { return nil }

        let orderedFiles = judgment.stalenessRanking.map { ranked.orderedFiles[$0] }
        let rationale = judgment.rationale.trimmingCharacters(in: .whitespacesAndNewlines)
        return makeFinding(
            orderedFiles: orderedFiles,
            stem: ranked.stem,
            signals: ranked.signals + ["on-device judgment: \(rationale)"],
            confidence: judgment.confidence,
            judgeSource: .foundationModel,
            rationale: rationale,
            context: context
        )
    }

    private func rulesFinding(ranked: RankedVersionCluster, context: DetectionContext) -> Finding? {
        guard ranked.confidence >= Self.reportThreshold else { return nil }
        return makeFinding(
            orderedFiles: ranked.orderedFiles,
            stem: ranked.stem,
            signals: ranked.signals,
            confidence: ranked.confidence,
            judgeSource: .rules,
            rationale: ranked.signals.first ?? "based on filename and filesystem dates",
            context: context
        )
    }

    private func makeFinding(
        orderedFiles: [FileRecord],
        stem: String,
        signals: [String],
        confidence: Double,
        judgeSource: JudgeSource,
        rationale: String,
        context: DetectionContext
    ) -> Finding {
        let keeper = orderedFiles[0]
        let stale = Array(orderedFiles.dropFirst())
        let directory = (keeper.path as NSString).deletingLastPathComponent

        return Finding(
            detectorID: Self.id,
            kind: "core.versionChain",
            severity: .medium,
            files: orderedFiles.map(FileRef.init),
            evidence: .versionChain(
                rankedFilenames: orderedFiles.map(\.filename),
                stem: stem,
                signals: signals,
                confidence: confidence,
                judge: judgeSource
            ),
            explanation: "\(orderedFiles.count) files in “\((directory as NSString).lastPathComponent)” "
                + "appear to be versions of the same document (“\(stem)”). "
                + "“\(keeper.filename)” ranks most current — \(rationale). "
                + "Consider archiving the older \(stale.count).",
            recommendation: .keepCanonical(keep: FileRef(keeper), archive: stale.map(FileRef.init)),
            confidence: confidence,
            stableKeyMaterial: "versionChain:\(stem)",
            scanID: context.scanID
        )
    }
}
