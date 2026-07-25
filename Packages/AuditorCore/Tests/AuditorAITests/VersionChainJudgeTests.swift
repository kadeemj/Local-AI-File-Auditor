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
}
