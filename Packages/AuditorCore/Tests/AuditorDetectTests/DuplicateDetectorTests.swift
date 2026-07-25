import AuditorHashing
import AuditorModels
import Foundation
import Testing

@testable import AuditorDetect

@Suite("DuplicateDetector")
struct DuplicateDetectorTests {
    private func record(_ path: String, size: Int64 = 1_000, createdDaysAgo: Int = 10) -> FileRecord {
        FileRecord(
            path: path,
            size: size,
            mtimeNanoseconds: 1_700_000_000_000_000_000,
            createdAt: .daysAgo0(createdDaysAgo)
        )
    }

    @Test("emits one finding per duplicate set with wasted bytes and explanation")
    func findingShape() async throws {
        let group = DuplicateGroup(
            contentHash: "cafe01",
            files: [
                record("/docs/Grant Agreement Signed.pdf"),
                record("/docs/Copy of Grant Agreement.pdf"),
                record("/docs/Grant Agreement (1).pdf"),
            ],
            isPartialOnly: false
        )
        let context = DetectionContext(scanID: UUID(), files: group.files, duplicateGroups: [group])

        let findings = try await DuplicateDetector().detect(context: context)

        #expect(findings.count == 1)
        let finding = try #require(findings.first)
        #expect(finding.kind == "core.duplicateSet.exact")
        #expect(finding.severity == .medium)
        #expect(finding.files.count == 3)
        #expect(!finding.explanation.isEmpty)
        if case .duplicateSet(let hash, let wasted) = finding.evidence {
            #expect(hash == "cafe01")
            #expect(wasted == 2_000, "wasted = (n-1) × size")
        } else {
            Issue.record("expected duplicateSet evidence")
        }
    }

    @Test("keeper avoids copy-tokened names and Downloads")
    func keeperChoice() async throws {
        let group = DuplicateGroup(
            contentHash: "beef02",
            files: [
                record("/Users/k/Downloads/Grant Agreement.pdf"),
                record("/docs/Copy of Grant Agreement.pdf"),
                record("/docs/Grant Agreement.pdf"),
            ],
            isPartialOnly: false
        )
        let context = DetectionContext(scanID: UUID(), files: group.files, duplicateGroups: [group])

        let finding = try #require(try await DuplicateDetector().detect(context: context).first)
        guard case .keepCanonical(let keep, let archive) = finding.recommendation else {
            Issue.record("expected keepCanonical recommendation")
            return
        }
        #expect(keep.path == "/docs/Grant Agreement.pdf")
        #expect(archive.count == 2)
    }

    @Test("stableKey survives file-order changes (keyed on content hash)")
    func stableKeyIdentity() async throws {
        let files = [record("/a/x.pdf"), record("/b/y.pdf")]
        let forward = DuplicateGroup(contentHash: "0123", files: files, isPartialOnly: false)
        let reversed = DuplicateGroup(contentHash: "0123", files: files.reversed(), isPartialOnly: false)

        let f1 = try #require(try await DuplicateDetector().detect(
            context: DetectionContext(scanID: UUID(), files: files, duplicateGroups: [forward])).first)
        let f2 = try #require(try await DuplicateDetector().detect(
            context: DetectionContext(scanID: UUID(), files: files, duplicateGroups: [reversed])).first)

        #expect(f1.stableKey == f2.stableKey)
    }
}

extension Date {
    static func daysAgo0(_ days: Int) -> Date { Date(timeIntervalSinceNow: -Double(days) * 86_400) }
}
