import AuditorAI
import AuditorModels
import AuditorPolicy
import Foundation
import Testing

@testable import AuditorDetect

private enum IdentityTestError: Error {
    case unexpectedCall
    case refused
}

private struct MockIdentityJudge: DocumentIdentityJudging {
    let modelAvailability: ModelAvailability
    let response: @Sendable (DocumentIdentityRequest) async throws -> DocumentIdentity

    init(
        availability: ModelAvailability = .available,
        response: @escaping @Sendable (DocumentIdentityRequest) async throws -> DocumentIdentity
    ) {
        self.modelAvailability = availability
        self.response = response
    }

    func availability() async -> ModelAvailability { modelAvailability }
    func identify(_ request: DocumentIdentityRequest) async throws -> DocumentIdentity {
        try await response(request)
    }
}

private func renameRecord(_ path: String, date: Date) -> FileRecord {
    FileRecord(
        path: path,
        size: 1_000,
        mtimeNanoseconds: Int64(date.timeIntervalSince1970 * 1_000_000_000),
        createdAt: date
    )
}

@Suite("RenameSuggester")
struct RenameSuggesterTests {
    private let policy = Policy(
        id: "nonprofit",
        displayName: "Nonprofit",
        namingTemplate: "YYYY-MM-DD_{DocType}_{Org}_{Status}"
    )

    @Test("validated identity fields are rendered only through the policy template")
    func semanticRename() async throws {
        let date = try #require(NamingTemplate.date(from: "2026-07-25"))
        let file = renameRecord("/Inbox/scan001.pdf", date: date)
        let judge = MockIdentityJudge { request in
            #expect(request.filename == "scan001.pdf")
            return DocumentIdentity(
                docType: "Grant Agreement",
                organization: "Community Arts Network",
                date: "2026-07-15",
                status: "Approved",
                titleSummary: "Youth Program"
            )
        }
        let findings = try await RenameSuggester(judge: judge).detect(context: DetectionContext(
            scanID: UUID(),
            files: [file],
            extractedText: [file.path: "Grant agreement with Community Arts Network"],
            policy: policy
        ))

        let finding = try #require(findings.first)
        guard case .rename(_, let proposedName) = finding.recommendation else {
            Issue.record("expected rename"); return
        }
        #expect(proposedName == "2026-07-15_Grant-Agreement_Community-Arts-Network_Approved.pdf")
        guard case .filenamePolicy(_, let violations, let evidenceName, let source) = finding.evidence else {
            Issue.record("expected filenamePolicy evidence"); return
        }
        #expect(violations.map(\.ruleID).contains("universal.generic-name"))
        #expect(evidenceName == proposedName)
        #expect(source == .foundationModel)
    }

    @Test("unavailable model uses deterministic metadata fallback")
    func rulesFallback() async throws {
        let date = try #require(NamingTemplate.date(from: "2026-07-25"))
        let file = renameRecord("/04 Legal/contract draft.pdf", date: date)
        let judge = MockIdentityJudge(availability: .unavailable(reason: "test")) { _ in
            throw IdentityTestError.unexpectedCall
        }
        let findings = try await RenameSuggester(judge: judge).detect(context: DetectionContext(
            scanID: UUID(),
            files: [file],
            policy: policy
        ))

        let finding = try #require(findings.first)
        guard case .rename(_, let proposedName) = finding.recommendation else {
            Issue.record("expected rename"); return
        }
        #expect(proposedName == "2026-07-25_Contract_Legal_Draft.pdf")
        guard case .filenamePolicy(_, _, _, let source) = finding.evidence else {
            Issue.record("expected filenamePolicy evidence"); return
        }
        #expect(source == .rules)
    }

    @Test("generation failure falls back without dropping the recommendation")
    func generationFailureFallback() async throws {
        let date = try #require(NamingTemplate.date(from: "2026-07-25"))
        let file = renameRecord("/Finance/invoice final.pdf", date: date)
        let judge = MockIdentityJudge { _ in throw IdentityTestError.refused }
        let findings = try await RenameSuggester(judge: judge).detect(context: DetectionContext(
            scanID: UUID(),
            files: [file],
            extractedText: [file.path: "Invoice number 42"],
            policy: policy
        ))
        #expect(findings.count == 1)
        guard case .filenamePolicy(_, _, _, let source) = findings[0].evidence else {
            Issue.record("expected filenamePolicy evidence"); return
        }
        #expect(source == .rules)
    }

    @Test("no naming template means no rename recommendation")
    func noTemplate() async throws {
        let date = try #require(NamingTemplate.date(from: "2026-07-25"))
        let file = renameRecord("/Inbox/scan001.pdf", date: date)
        let findings = try await RenameSuggester(judge: MockIdentityJudge { _ in
            throw IdentityTestError.unexpectedCall
        }).detect(context: DetectionContext(
            scanID: UUID(),
            files: [file],
            policy: Policy(id: "none", displayName: "None", namingTemplate: nil)
        ))
        #expect(findings.isEmpty)
    }
}
