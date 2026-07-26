import AuditorModels
import AuditorReports
import Foundation
import Testing
@testable import FolderLint

@Suite("PDFReportRenderer")
@MainActor
struct PDFReportRendererTests {
    @Test("renders a multi-page PDF with summary, findings, and applied log")
    func rendersPDF() throws {
        let file = FileRef(path: "/docs/a.pdf", size: 12, modifiedAt: Date())
        let finding = Finding(
            detectorID: "test",
            kind: "core.filenamePolicy.generic",
            severity: .medium,
            files: [file],
            evidence: .note("generic"),
            explanation: "Filename is too generic.",
            recommendation: .rename(file: file, proposedName: "2026-01-01_Report_Org_Final.pdf"),
            stableKeyMaterial: "pdf-test",
            scanID: UUID()
        )
        let report = AuditReport(
            title: "FolderLint Test Report",
            policyName: "Nonprofit File Governance",
            folderPaths: ["/docs"],
            filesScanned: 3,
            totalBytes: 100,
            scanDuration: 0.2,
            findings: [finding]
        )

        let data = try PDFReportRenderer.data(from: report)
        #expect(data.count > 1_000)
        // PDF magic header
        #expect(String(data: data.prefix(4), encoding: .utf8) == "%PDF")

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("folderlint-test-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        try PDFReportRenderer.write(report, to: url)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }
}
