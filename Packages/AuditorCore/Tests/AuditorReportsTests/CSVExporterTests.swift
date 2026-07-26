import AuditorModels
import AuditorStore
import Foundation
import Testing

@testable import AuditorReports

@Suite("CSVExporter")
struct CSVExporterTests {
    @Test("emits header and one row per finding with escaped fields")
    func emitsEscapedRows() {
        let file = FileRef(
            path: "/docs/Grant, Agreement.pdf",
            size: 10,
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let finding = Finding(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            detectorID: "core.filename",
            kind: "core.filenamePolicy.generic",
            severity: .medium,
            files: [file],
            evidence: .note("says \"generic\""),
            explanation: "Filename is too generic, really.",
            recommendation: .rename(file: file, proposedName: "2026-01-01_Report_Org_Final.pdf"),
            confidence: 0.9,
            stableKeyMaterial: "generic",
            scanID: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let csv = CSVExporter.string(from: AuditReport(findings: [finding]))
        let lines = csv.split(whereSeparator: \.isNewline).filter { !$0.isEmpty }

        #expect(String(lines[0]) == CSVExporter.headerColumns.joined(separator: ","))
        #expect(lines.count == 2)
        #expect(csv.contains("medium"))
        #expect(csv.contains("core.filenamePolicy.generic"))
        #expect(csv.contains("\"/docs/Grant, Agreement.pdf\""))
        #expect(csv.contains("\"says \"\"generic\"\"\""))
        #expect(csv.contains("Rename"))
    }

    @Test("writes UTF-8 data to disk")
    func writesFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("folderlint-report-\(UUID().uuidString).csv")
        defer { try? FileManager.default.removeItem(at: url) }

        let finding = Finding(
            detectorID: "d",
            kind: "k",
            severity: .low,
            files: [FileRef(path: "/a.txt", size: 1, modifiedAt: Date())],
            evidence: .note("n"),
            explanation: "e",
            recommendation: .review(note: "review"),
            stableKeyMaterial: "s",
            scanID: UUID()
        )
        try CSVExporter.write(AuditReport(findings: [finding]), to: url)
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.hasPrefix("severity,"))
        #expect(text.contains("/a.txt"))
    }

    @Test("report summary counts severity and applied ops")
    func summaryCounts() {
        let file = FileRef(path: "/a.pdf", size: 1, modifiedAt: Date())
        let high = Finding(
            detectorID: "d",
            kind: "k",
            severity: .high,
            files: [file],
            evidence: .note("n"),
            explanation: "e",
            recommendation: .review(note: "r"),
            stableKeyMaterial: "h",
            scanID: UUID()
        )
        let low = Finding(
            detectorID: "d",
            kind: "k2",
            severity: .low,
            files: [file],
            evidence: .note("n"),
            explanation: "e",
            recommendation: .review(note: "r"),
            stableKeyMaterial: "l",
            scanID: UUID()
        )
        let batchID = UUID()
        let batch = StoredApplyBatch(
            batchID: batchID,
            performedAt: Date(),
            undoneAt: nil,
            operationCount: 2,
            entries: [
                StoredJournalEntry(
                    batchID: batchID,
                    findingID: UUID(),
                    operation: "rename",
                    originalPath: "/a",
                    newPath: "/b",
                    performedAt: Date()
                ),
                StoredJournalEntry(
                    batchID: batchID,
                    findingID: UUID(),
                    operation: "move",
                    originalPath: "/c",
                    newPath: "/d",
                    performedAt: Date()
                ),
            ]
        )
        let report = AuditReport(findings: [high, low], applyBatches: [batch])
        #expect(report.criticalAndHighCount == 1)
        #expect(report.appliedOperationCount == 2)
        #expect(report.findingsBySeverity.map(\.0) == [.high, .low])
    }

    @Test("escape quotes and commas")
    func escapeRules() {
        #expect(CSVExporter.escape("plain") == "plain")
        #expect(CSVExporter.escape("a,b") == "\"a,b\"")
        #expect(CSVExporter.escape("say \"hi\"") == "\"say \"\"hi\"\"\"")
    }
}
