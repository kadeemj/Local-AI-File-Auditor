import Foundation
import Testing

@testable import AuditorAI

@Suite("VersionChainJudgment")
struct VersionChainJudgmentTests {
    @Test("accepts only a complete canonical-first permutation")
    func validatesPermutation() {
        let valid = VersionChainJudgment(
            canonicalIndex: 2,
            stalenessRanking: [2, 0, 1],
            confidence: 0.8,
            rationale: "v3 is the highest explicit version."
        )
        #expect(valid.isValid(candidateCount: 3))

        let duplicate = VersionChainJudgment(
            canonicalIndex: 0,
            stalenessRanking: [0, 0, 1],
            confidence: 0.8,
            rationale: "Invalid duplicate."
        )
        #expect(!duplicate.isValid(candidateCount: 3))

        let missing = VersionChainJudgment(
            canonicalIndex: 0,
            stalenessRanking: [0, 1],
            confidence: 0.8,
            rationale: "Invalid missing index."
        )
        #expect(!missing.isValid(candidateCount: 3))

        let canonicalMismatch = VersionChainJudgment(
            canonicalIndex: 1,
            stalenessRanking: [0, 1, 2],
            confidence: 0.8,
            rationale: "Invalid canonical position."
        )
        #expect(!canonicalMismatch.isValid(candidateCount: 3))
    }

    @Test("rejects malformed confidence and rationale")
    func validatesScalarFields() {
        let nonFinite = VersionChainJudgment(
            canonicalIndex: 0,
            stalenessRanking: [0, 1],
            confidence: .nan,
            rationale: "A rationale."
        )
        #expect(!nonFinite.isValid(candidateCount: 2))

        let emptyRationale = VersionChainJudgment(
            canonicalIndex: 0,
            stalenessRanking: [0, 1],
            confidence: 0.7,
            rationale: " \n "
        )
        #expect(!emptyRationale.isValid(candidateCount: 2))
    }

    @Test("semantic input strips full paths and contains no document content")
    func privacyBoundary() {
        let request = VersionChainJudgeRequest(
            stem: "policy",
            candidates: [
                VersionChainCandidate(
                    index: 0,
                    filename: "/Users/private-client/contracts/policy_v1.pdf",
                    sizeBytes: 1_000,
                    modifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
                    createdAt: nil
                ),
                VersionChainCandidate(
                    index: 1,
                    filename: "policy_v2.pdf",
                    sizeBytes: 1_100,
                    modifiedAt: Date(timeIntervalSince1970: 1_710_000_000),
                    createdAt: nil
                ),
            ]
        )

        #expect(request.candidates[0].filename == "policy_v1.pdf")
        #expect(!request.prompt.contains("/Users/private-client"))
        #expect(request.prompt.contains("policy_v1.pdf"))
    }

    @Test("sentence embeddings and vector math are available on device")
    func sentenceEmbeddings() throws {
        let provider = SentenceEmbeddingProvider()
        let grant = try #require(provider.vector(for: "Grant funding report for youth education programs."))
        let finance = try #require(provider.vector(for: "Quarterly finance budget and expense reconciliation."))
        #expect(grant.count == finance.count)
        #expect(grant.count > 100)
        let selfSimilarity = try #require(EmbeddingMath.cosineSimilarity(grant, grant))
        #expect(abs(selfSimilarity - 1) < 0.000_001)
        #expect(EmbeddingMath.cosineSimilarity(grant, finance) != nil)
    }

    @Test("document identity input strips paths and bounds transient text")
    func documentIdentityPrivacyBoundary() {
        let request = DocumentIdentityRequest(
            filename: "/Users/client/private/contract.pdf",
            modifiedAt: Date(),
            createdAt: nil,
            text: String(repeating: "x", count: 20_000)
        )
        #expect(request.filename == "contract.pdf")
        #expect(request.text.count == 12_000)
        #expect(!request.prompt.contains("/Users/client/private"))
    }

    @Test("misfiled explanations must cite real evidence and the correct mechanism")
    func misfiledExplanationValidation() {
        let request = MisfiledExplanationRequest(
            filename: "budget.txt",
            currentFolder: "/root/Governance",
            suggestedFolder: "/root/Finance",
            nearestFilenames: ["invoice.txt", "expenses.txt"],
            currentSimilarity: 0.4,
            suggestedSimilarity: 0.8
        )
        let valid = MisfiledExplanation(
            rationale: "Finance is a stronger match because invoice.txt has similar document content."
        )
        #expect(valid.validatedRationale(for: request) != nil)

        let wrongMechanism = MisfiledExplanation(
            rationale: "Finance wins based on filename similarity to invoice.txt."
        )
        #expect(wrongMechanism.validatedRationale(for: request) == nil)

        let missingNearestEvidence = MisfiledExplanation(
            rationale: "Finance is the strongest destination."
        )
        #expect(missingNearestEvidence.validatedRationale(for: request) == nil)
    }

    @Test("Foundation Models structured-generation smoke test",
          .enabled(if: ModelAvailability.current().isAvailable))
    func liveFoundationModelsSmokeTest() async throws {
        let request = VersionChainJudgeRequest(
            stem: "report",
            candidates: [
                VersionChainCandidate(
                    index: 0,
                    filename: "report_v1.pdf",
                    sizeBytes: 1_000,
                    modifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
                    createdAt: nil
                ),
                VersionChainCandidate(
                    index: 1,
                    filename: "report_v2_FINAL.pdf",
                    sizeBytes: 1_100,
                    modifiedAt: Date(timeIntervalSince1970: 1_710_000_000),
                    createdAt: nil
                ),
            ]
        )

        let judgment = try await FoundationModelVersionChainJudge().judge(request)
        #expect(judgment.confidence.isFinite)
        #expect(!judgment.rationale.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @Test("Foundation Models document identity smoke test",
          .enabled(if: ModelAvailability.current().isAvailable))
    func liveDocumentIdentitySmokeTest() async throws {
        let request = DocumentIdentityRequest(
            filename: "scan001.pdf",
            modifiedAt: Date(timeIntervalSince1970: 1_710_000_000),
            createdAt: nil,
            text: """
                GRANT AGREEMENT
                Between Lava Labs Foundation and Community Arts Network.
                Effective July 15, 2026. Status: Approved.
                """
        )
        let identity = try await FoundationModelDocumentIdentityJudge().identify(request)
        #expect(identity.isStructurallyValid())
        #expect(!identity.docType.isEmpty || !identity.titleSummary.isEmpty)
    }
}
