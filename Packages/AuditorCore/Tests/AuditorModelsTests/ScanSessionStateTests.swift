import AuditorModels
import Foundation
import Testing

@Suite("ScanSessionState")
struct ScanSessionStateTests {
    @Test("applies mock stream events into dashboard state")
    func appliesMockStream() {
        var state = ScanSessionState()
        let scanID = UUID()
        state.begin(scanID: scanID)

        state.apply(.phaseChanged(.enumerating))
        state.apply(.progress(ScanProgress(filesSeen: 12, bytesHashed: 0, currentPhase: .enumerating)))

        let file = FileRef(path: "/docs/a.pdf", size: 10, modifiedAt: Date())
        let finding = Finding(
            detectorID: "test",
            kind: "core.filenamePolicy.generic",
            severity: .medium,
            files: [file],
            evidence: .note("generic name"),
            explanation: "Filename is too generic.",
            recommendation: .rename(file: file, proposedName: "2026-01-01_Report_Org_Final.pdf"),
            stableKeyMaterial: "generic",
            scanID: scanID
        )
        state.apply(.finding(finding))
        state.apply(.completed(ScanSummary(
            scanID: scanID,
            filesScanned: 12,
            totalBytes: 4_096,
            findingsCount: 1,
            duration: 0.4
        )))

        #expect(state.isRunning == false)
        #expect(state.findings.count == 1)
        #expect(state.renameFindings.count == 1)
        #expect(state.summary?.filesScanned == 12)
        #expect(state.phase == .enumerating || state.progress.filesSeen == 12)
    }

    @Test("failed events clear the running flag")
    func failedClearsRunning() {
        var state = ScanSessionState()
        state.begin(scanID: UUID())
        state.apply(.failed(.cancelled))
        #expect(state.isRunning == false)
        #expect(state.error == .cancelled)
    }

    @Test("approve filters actionable file mutations")
    func approveFiltersMutations() {
        var state = ScanSessionState()
        let scanID = UUID()
        let file = FileRef(path: "/docs/a.pdf", size: 10, modifiedAt: Date())
        let rename = Finding(
            detectorID: "test",
            kind: "core.filenamePolicy.generic",
            severity: .medium,
            files: [file],
            evidence: .note("generic"),
            explanation: "Rename me",
            recommendation: .rename(file: file, proposedName: "ok.pdf"),
            stableKeyMaterial: "r",
            scanID: scanID
        )
        let reminder = Finding(
            detectorID: "test",
            kind: "core.expiration",
            severity: .high,
            files: [file],
            evidence: .note("exp"),
            explanation: "Remind",
            recommendation: .scheduleReminder(actionDate: Date(), note: "n"),
            stableKeyMaterial: "e",
            scanID: scanID
        )
        state.apply(.finding(rename))
        state.apply(.finding(reminder))
        state.setDecision(.approved, for: rename.id)
        state.setDecision(.approved, for: reminder.id)

        #expect(state.approvedFindings.count == 2)
        #expect(state.actionableApprovedFindings.count == 1)
        #expect(rename.recommendation.isFileMutation)
        #expect(!reminder.recommendation.isFileMutation)
    }
}
