import Foundation
import Testing

@testable import AuditorModels

@Suite("Finding model")
struct FindingTests {
    @Test("severity orders low < medium < high < critical")
    func severityOrdering() {
        #expect(Severity.low < .medium)
        #expect(Severity.medium < .high)
        #expect(Severity.high < .critical)
        #expect(Severity.allCases.sorted() == [.low, .medium, .high, .critical])
    }

    @Test("stableKey is order-independent over paths and deterministic")
    func stableKeyDeterminism() {
        let a = Finding.stableKey(kind: "core.duplicateSet.exact", paths: ["/a/x.pdf", "/b/y.pdf"], material: "abc123")
        let b = Finding.stableKey(kind: "core.duplicateSet.exact", paths: ["/b/y.pdf", "/a/x.pdf"], material: "abc123")
        #expect(a == b)

        let differentMaterial = Finding.stableKey(kind: "core.duplicateSet.exact", paths: ["/a/x.pdf", "/b/y.pdf"], material: "zzz999")
        #expect(a != differentMaterial)

        let differentKind = Finding.stableKey(kind: "core.versionChain", paths: ["/a/x.pdf", "/b/y.pdf"], material: "abc123")
        #expect(a != differentKind)
    }

    @Test("Finding round-trips through Codable")
    func findingCodable() throws {
        let file = FileRef(path: "/tmp/report.pdf", size: 1234, modifiedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let finding = Finding(
            detectorID: "core.duplicates",
            kind: "core.duplicateSet.exact",
            severity: .medium,
            files: [file],
            evidence: .duplicateSet(contentHash: "deadbeef", wastedBytes: 1234),
            explanation: "Two files share identical content (SHA-256 verified).",
            recommendation: .keepCanonical(keep: file, archive: []),
            stableKeyMaterial: "deadbeef",
            scanID: UUID()
        )

        let data = try JSONEncoder().encode(finding)
        let decoded = try JSONDecoder().decode(Finding.self, from: data)

        #expect(decoded.stableKey == finding.stableKey)
        #expect(decoded.kind == finding.kind)
        #expect(decoded.decision == .pending)
        #expect(decoded.files == finding.files)
    }

    @Test("semantic detector evidence payloads round-trip through persisted JSON")
    func phaseSixEvidenceCodable() throws {
        let nearest = FileRef(path: "/tmp/Finance/budget.pdf", size: 200, modifiedAt: Date(timeIntervalSince1970: 2))
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let filenameEvidence = Evidence.filenamePolicy(
            template: "YYYY-MM-DD_{DocType}_{Org}_{Status}",
            violations: [
                FilenamePolicyViolation(ruleID: "universal.generic-name", explanation: "Generic name."),
            ],
            proposedName: "2026-07-25_Report_Org_Approved.pdf",
            judge: .foundationModel
        )
        let decodedFilename = try decoder.decode(Evidence.self, from: encoder.encode(filenameEvidence))
        guard case .filenamePolicy(let template, let violations, let proposedName, let judge) = decodedFilename else {
            Issue.record("expected filenamePolicy evidence"); return
        }
        #expect(template == "YYYY-MM-DD_{DocType}_{Org}_{Status}")
        #expect(violations.first?.ruleID == "universal.generic-name")
        #expect(proposedName == "2026-07-25_Report_Org_Approved.pdf")
        #expect(judge == .foundationModel)

        let misfiledEvidence = Evidence.misfiled(
            currentFolder: "/tmp/Governance",
            suggestedFolder: "/tmp/Finance",
            ownFolderSimilarity: 0.4,
            suggestedFolderSimilarity: 0.8,
            nearestFiles: [nearest],
            explanationJudge: .rules
        )
        let decodedMisfiled = try decoder.decode(Evidence.self, from: encoder.encode(misfiledEvidence))
        guard case .misfiled(_, let destination, _, let similarity, let nearestFiles, let source) = decodedMisfiled else {
            Issue.record("expected misfiled evidence"); return
        }
        #expect(destination == "/tmp/Finance")
        #expect(similarity == 0.8)
        #expect(nearestFiles == [nearest])
        #expect(source == .rules)

        let detected = Date(timeIntervalSince1970: 1_788_134_400)
        let action = Date(timeIntervalSince1970: 1_784_332_800)
        let expirationEvidence = Evidence.expiration(
            kind: .autoRenewal,
            detectedDate: detected,
            actionDate: action,
            autoRenews: true,
            noticePeriodDays: 30,
            party: "Licensee",
            contextSnippet: "The agreement automatically renews.",
            judge: .foundationModel
        )
        let decodedExpiration = try decoder.decode(Evidence.self, from: encoder.encode(expirationEvidence))
        guard case .expiration(
            let kind,
            let detectedDate,
            let actionDate,
            let autoRenews,
            let noticeDays,
            let party,
            _,
            let expirationSource
        ) = decodedExpiration else {
            Issue.record("expected expiration evidence"); return
        }
        #expect(kind == .autoRenewal)
        #expect(detectedDate == detected)
        #expect(actionDate == action)
        #expect(autoRenews)
        #expect(noticeDays == 30)
        #expect(party == "Licensee")
        #expect(expirationSource == .foundationModel)
    }
}
