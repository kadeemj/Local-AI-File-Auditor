import AuditorAI
import AuditorModels
import Foundation
import Testing

@testable import AuditorDetect

private enum ExplanationTestError: Error {
    case unexpectedCall
}

private struct MockMisfiledExplainer: MisfiledExplaining {
    let modelAvailability: ModelAvailability
    let response: @Sendable (MisfiledExplanationRequest) async throws -> MisfiledExplanation

    init(
        availability: ModelAvailability = .available,
        response: @escaping @Sendable (MisfiledExplanationRequest) async throws -> MisfiledExplanation
    ) {
        self.modelAvailability = availability
        self.response = response
    }

    func availability() async -> ModelAvailability { modelAvailability }
    func explain(_ request: MisfiledExplanationRequest) async throws -> MisfiledExplanation {
        try await response(request)
    }
}

private func misfiledRecord(_ path: String) -> FileRecord {
    FileRecord(path: path, size: 100, mtimeNanoseconds: 1)
}

@Suite("MisfiledDetector")
struct MisfiledDetectorTests {
    @Test("flags only with a strong alternate profile and nearest-file evidence")
    func detectsMisfiledDocument() async throws {
        let files = [
            misfiledRecord("/root/Finance/budget.txt"),
            misfiledRecord("/root/Finance/invoice.txt"),
            misfiledRecord("/root/Finance/expenses.txt"),
            misfiledRecord("/root/Governance/bylaws.txt"),
            misfiledRecord("/root/Governance/minutes.txt"),
            misfiledRecord("/root/Governance/policy.txt"),
            misfiledRecord("/root/Governance/misfiled-budget.txt"),
        ]
        let vectors: [String: [Double]] = [
            "/root/Finance/budget.txt": [1.0, 0.0],
            "/root/Finance/invoice.txt": [0.98, 0.02],
            "/root/Finance/expenses.txt": [0.97, 0.03],
            "/root/Governance/bylaws.txt": [0.0, 1.0],
            "/root/Governance/minutes.txt": [0.02, 0.98],
            "/root/Governance/policy.txt": [0.01, 0.99],
            "/root/Governance/misfiled-budget.txt": [1.0, 0.0],
        ]
        let explainer = MockMisfiledExplainer { request in
            #expect(request.suggestedFolder == "Finance")
            #expect(request.nearestFilenames.count == 3)
            return MisfiledExplanation(
                rationale: "Finance is the stronger destination because invoice.txt is one of the closest content matches."
            )
        }
        let findings = try await MisfiledDetector(explainer: explainer).detect(context: DetectionContext(
            scanID: UUID(),
            files: files,
            documentEmbeddings: vectors
        ))

        let finding = try #require(findings.first {
            $0.files.first?.filename == "misfiled-budget.txt"
        })
        guard case .move(let file, let destination) = finding.recommendation else {
            Issue.record("expected move"); return
        }
        #expect(file.filename == "misfiled-budget.txt")
        #expect(destination == "/root/Finance")
        guard case .misfiled(
            let current,
            let suggested,
            let ownSimilarity,
            let suggestedSimilarity,
            let nearest,
            let source
        ) = finding.evidence else {
            Issue.record("expected misfiled evidence"); return
        }
        #expect(current == "/root/Governance")
        #expect(suggested == "/root/Finance")
        #expect(suggestedSimilarity > ownSimilarity)
        #expect(nearest.count == 3)
        #expect(source == .foundationModel)
        #expect(!finding.explanation.isEmpty)
    }

    @Test("rules explanation survives unavailable Foundation Models")
    func rulesExplanationFallback() async throws {
        let files = [
            misfiledRecord("/a/x1.txt"), misfiledRecord("/a/x2.txt"), misfiledRecord("/a/x3.txt"),
            misfiledRecord("/b/y1.txt"), misfiledRecord("/b/y2.txt"), misfiledRecord("/b/y3.txt"),
            misfiledRecord("/b/wrong.txt"),
        ]
        let vectors: [String: [Double]] = [
            "/a/x1.txt": [1, 0], "/a/x2.txt": [1, 0], "/a/x3.txt": [1, 0],
            "/b/y1.txt": [0, 1], "/b/y2.txt": [0, 1], "/b/y3.txt": [0, 1],
            "/b/wrong.txt": [1, 0],
        ]
        let explainer = MockMisfiledExplainer(availability: .unavailable(reason: "test")) { _ in
            throw ExplanationTestError.unexpectedCall
        }
        let findings = try await MisfiledDetector(explainer: explainer).detect(context: DetectionContext(
            scanID: UUID(),
            files: files,
            documentEmbeddings: vectors
        ))

        let finding = try #require(findings.first { $0.files.first?.filename == "wrong.txt" })
        guard case .misfiled(_, _, _, _, let nearest, let source) = finding.evidence else {
            Issue.record("expected misfiled evidence"); return
        }
        #expect(nearest.count == 3)
        #expect(source == .rules)
        #expect(finding.explanation.contains("nearest examples"))
    }

    @Test("insufficient folder evidence produces no recommendation")
    func insufficientEvidence() async throws {
        let files = [
            misfiledRecord("/a/x1.txt"),
            misfiledRecord("/b/y1.txt"),
            misfiledRecord("/b/y2.txt"),
            misfiledRecord("/b/wrong.txt"),
        ]
        let vectors = Dictionary(uniqueKeysWithValues: files.map { ($0.path, [1.0, 0.0]) })
        let findings = try await MisfiledDetector(explainer: MockMisfiledExplainer(
            availability: .unavailable(reason: "test")
        ) { _ in throw ExplanationTestError.unexpectedCall }).detect(context: DetectionContext(
            scanID: UUID(),
            files: files,
            documentEmbeddings: vectors
        ))
        #expect(findings.isEmpty)
    }
}
