import AuditorAI
import AuditorModels
import Foundation

struct FolderProfile: Sendable {
    let path: String
    let documentPaths: [String]
    let documentVectors: [[Double]]
    let labelVector: [Double]?

    var centroid: [Double]? {
        var vectors = documentVectors
        if let labelVector { vectors.append(labelVector) }
        return EmbeddingMath.centroid(of: vectors)
    }

    func centroid(excluding documentPath: String) -> [Double]? {
        var vectors = zip(documentPaths, documentVectors)
            .filter { $0.0 != documentPath }
            .map(\.1)
        if let labelVector { vectors.append(labelVector) }
        return EmbeddingMath.centroid(of: vectors)
    }
}

enum FolderProfileBuilder {
    static func build(context: DetectionContext) -> [String: FolderProfile] {
        guard let embeddings = context.documentEmbeddings else { return [:] }
        var grouped: [String: [(String, [Double])]] = [:]

        for file in context.files {
            guard let vector = embeddings[file.path], !vector.isEmpty, vector.allSatisfy(\.isFinite) else { continue }
            let directory = (file.path as NSString).deletingLastPathComponent
            grouped[directory, default: []].append((file.path, vector))
        }

        return grouped.mapValues { entries in
            let directory = (entries[0].0 as NSString).deletingLastPathComponent
            return FolderProfile(
                path: directory,
                documentPaths: entries.map(\.0),
                documentVectors: entries.map(\.1),
                labelVector: context.folderLabelEmbeddings?[directory]
            )
        }
    }
}

public struct MisfiledDetector: Detector {
    public static let id = "core.misfiled"
    public let displayName = "Possible wrong folder"
    public let requiredSignals: DetectorSignals = [.embeddings, .semanticJudge, .policy]

    static let minimumDocumentsPerFolder = 3
    static let minimumSuggestedSimilarity = 0.72
    static let maximumOwnSimilarity = 0.68
    static let minimumSimilarityGain = 0.18

    private let explanationAvailability: @Sendable () async -> ModelAvailability
    private let explainRecommendation: @Sendable (MisfiledExplanationRequest) async throws -> MisfiledExplanation

    public init() {
        let explainer = FoundationModelMisfiledExplainer()
        self.explanationAvailability = { await explainer.availability() }
        self.explainRecommendation = { request in try await explainer.explain(request) }
    }

    public init(explainer: any MisfiledExplaining) {
        self.explanationAvailability = { await explainer.availability() }
        self.explainRecommendation = { request in try await explainer.explain(request) }
    }

    public func detect(context: DetectionContext) async throws -> [Finding] {
        guard let embeddings = context.documentEmbeddings else { return [] }
        let profiles = FolderProfileBuilder.build(context: context)
        let eligibleProfiles = profiles.values.filter {
            $0.documentPaths.count >= Self.minimumDocumentsPerFolder && $0.centroid != nil
        }
        guard eligibleProfiles.count >= 2 else { return [] }

        let filesByPath = Dictionary(uniqueKeysWithValues: context.files.map { ($0.path, $0) })
        let modelAvailable = await explanationAvailability().isAvailable
        let taxonomy = Set((context.policy?.folderTaxonomy ?? []).map(Self.normalizedFolderName))
        var findings: [Finding] = []

        for file in context.files {
            try Task.checkCancellation()
            guard let vector = embeddings[file.path],
                  let ownProfile = profiles[(file.path as NSString).deletingLastPathComponent],
                  ownProfile.documentPaths.count >= Self.minimumDocumentsPerFolder,
                  let ownCentroid = ownProfile.centroid(excluding: file.path),
                  let ownSimilarity = EmbeddingMath.cosineSimilarity(vector, ownCentroid)
            else { continue }

            var candidates: [(profile: FolderProfile, similarity: Double, score: Double)] = []
            for profile in eligibleProfiles where profile.path != ownProfile.path {
                guard let centroid = profile.centroid,
                      let similarity = EmbeddingMath.cosineSimilarity(vector, centroid)
                else { continue }
                let taxonomyBonus = taxonomy.contains(Self.normalizedFolderName(profile.path)) ? 0.03 : 0
                candidates.append((profile, similarity, similarity + taxonomyBonus))
            }
            guard let best = candidates.max(by: { $0.score < $1.score }),
                  best.similarity >= Self.minimumSuggestedSimilarity,
                  ownSimilarity <= Self.maximumOwnSimilarity,
                  best.similarity - ownSimilarity >= Self.minimumSimilarityGain
            else { continue }

            let nearest = zip(best.profile.documentPaths, best.profile.documentVectors)
                .compactMap { path, candidateVector -> (FileRecord, Double)? in
                    guard let record = filesByPath[path],
                          let similarity = EmbeddingMath.cosineSimilarity(vector, candidateVector)
                    else { return nil }
                    return (record, similarity)
                }
                .sorted { $0.1 > $1.1 }
                .prefix(3)
            guard nearest.count >= 2 else { continue }
            let nearestFiles = nearest.map { FileRef($0.0) }

            let rulesRationale = "Its document embedding is closer to “\((best.profile.path as NSString).lastPathComponent)” "
                + "(\(Self.format(best.similarity))) than its current folder "
                + "(\(Self.format(ownSimilarity))); nearest examples are "
                + nearestFiles.map(\.filename).joined(separator: ", ") + "."
            var rationale = rulesRationale
            var explanationSource = JudgeSource.rules

            if modelAvailable {
                let request = MisfiledExplanationRequest(
                    filename: file.filename,
                    currentFolder: ownProfile.path,
                    suggestedFolder: best.profile.path,
                    nearestFilenames: nearestFiles.map(\.filename),
                    currentSimilarity: ownSimilarity,
                    suggestedSimilarity: best.similarity
                )
                do {
                    let generated = try await explainRecommendation(request)
                    if let validated = generated.validatedRationale(for: request) {
                        rationale = validated
                        explanationSource = .foundationModel
                    }
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    // The deterministic evidence sentence remains available.
                }
            }

            let confidence = min(0.95, 0.55 + (best.similarity - ownSimilarity) * 0.5)
            findings.append(Finding(
                detectorID: Self.id,
                kind: "core.misfiled",
                severity: .medium,
                files: [FileRef(file)] + nearestFiles,
                evidence: .misfiled(
                    currentFolder: ownProfile.path,
                    suggestedFolder: best.profile.path,
                    ownFolderSimilarity: ownSimilarity,
                    suggestedFolderSimilarity: best.similarity,
                    nearestFiles: nearestFiles,
                    explanationJudge: explanationSource
                ),
                explanation: "“\(file.filename)” may be filed in the wrong folder. \(rationale)",
                recommendation: .move(file: FileRef(file), destinationFolder: best.profile.path),
                confidence: confidence,
                stableKeyMaterial: "destination:\(best.profile.path)",
                scanID: context.scanID
            ))
        }

        return findings.sorted { $0.stableKey < $1.stableKey }
    }

    private static func normalizedFolderName(_ path: String) -> String {
        (path as NSString).lastPathComponent
            .replacingOccurrences(of: #"^\d+\s*"#, with: "", options: .regularExpression)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}
