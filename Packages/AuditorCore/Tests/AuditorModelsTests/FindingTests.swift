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
}
