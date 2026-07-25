import AuditorModels
import AuditorPolicy
import Foundation
import Testing

@testable import AuditorDetect

private func filenameRecord(_ path: String) -> FileRecord {
    FileRecord(path: path, size: 100, mtimeNanoseconds: 1_700_000_000_000_000_000)
}

@Suite("FilenamePolicyDetector")
struct FilenamePolicyDetectorTests {
    private let policy = Policy(
        id: "test",
        displayName: "Test Policy",
        namingTemplate: "YYYY-MM-DD_{DocType}_{Org}_{Status}"
    )

    @Test("a compliant filename has no finding")
    func compliantFilename() async throws {
        let file = filenameRecord("/docs/2026-07-25_Board-Minutes_Lava-Labs_Approved.pdf")
        let findings = try await FilenamePolicyDetector().detect(
            context: DetectionContext(scanID: UUID(), files: [file], policy: policy)
        )
        #expect(findings.isEmpty)
    }

    @Test("violations cite exact deterministic rules")
    func citesRules() async throws {
        let file = filenameRecord("/docs/scan001 final final?.pdf")
        let findings = try await FilenamePolicyDetector().detect(
            context: DetectionContext(scanID: UUID(), files: [file], policy: policy)
        )

        let finding = try #require(findings.first)
        guard case .filenamePolicy(let template, let violations, _, _) = finding.evidence else {
            Issue.record("expected filenamePolicy evidence"); return
        }
        #expect(template == policy.namingTemplate)
        let ids = Set(violations.map(\.ruleID))
        #expect(ids.contains("naming.template-mismatch"))
        #expect(ids.contains("naming.missing-date"))
        #expect(ids.contains("universal.illegal-characters"))
        #expect(ids.contains("universal.version-label-smell"))
        #expect(!finding.explanation.isEmpty)
    }

    @Test("universal rules work with no active policy")
    func universalRulesOnly() async throws {
        let file = filenameRecord("/docs/IMG_0042.jpg")
        let findings = try await FilenamePolicyDetector().detect(
            context: DetectionContext(scanID: UUID(), files: [file])
        )
        let finding = try #require(findings.first)
        guard case .filenamePolicy(_, let violations, _, _) = finding.evidence else {
            Issue.record("expected filenamePolicy evidence"); return
        }
        #expect(violations.map(\.ruleID) == ["universal.generic-name"])
    }

    @Test("capitalization outlier is compared within its folder")
    func capitalizationConsistency() async throws {
        let files = [
            filenameRecord("/docs/Board Minutes.pdf"),
            filenameRecord("/docs/Grant Report.pdf"),
            filenameRecord("/docs/Annual Budget.pdf"),
            filenameRecord("/docs/LEGAL AGREEMENT.pdf"),
        ]
        let findings = try await FilenamePolicyDetector().detect(
            context: DetectionContext(scanID: UUID(), files: files)
        )

        let finding = try #require(findings.first { $0.files[0].filename == "LEGAL AGREEMENT.pdf" })
        guard case .filenamePolicy(_, let violations, _, _) = finding.evidence else {
            Issue.record("expected filenamePolicy evidence"); return
        }
        #expect(violations.map(\.ruleID).contains("universal.capitalization-inconsistent"))
    }
}
