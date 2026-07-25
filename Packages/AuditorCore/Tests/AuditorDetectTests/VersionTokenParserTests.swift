import Foundation
import Testing

@testable import AuditorDetect

@Suite("VersionTokenParser")
struct VersionTokenParserTests {
    struct Row: Sendable, CustomStringConvertible {
        let filename: String
        let stem: String
        var version: Int?
        var copyNumber: Int?
        var looseNumber: Int?
        var isCopy = false
        var conflicted = false
        var statuses: [String] = []
        var dateValue: Int?
        var yearOnly: Int?
        var description: String { filename }

        init(_ filename: String, stem: String, version: Int? = nil, copyNumber: Int? = nil,
             looseNumber: Int? = nil, isCopy: Bool = false, conflicted: Bool = false,
             statuses: [String] = [], dateValue: Int? = nil, yearOnly: Int? = nil) {
            self.filename = filename
            self.stem = stem
            self.version = version
            self.copyNumber = copyNumber
            self.looseNumber = looseNumber
            self.isCopy = isCopy
            self.conflicted = conflicted
            self.statuses = statuses
            self.dateValue = dateValue
            self.yearOnly = yearOnly
        }
    }

    static let table: [Row] = [
        Row("report_v2.docx", stem: "report", version: 2),
        Row("Report V10 FINAL.pdf", stem: "report", version: 10, statuses: ["final"]),
        Row("report version 3.docx", stem: "report", version: 3),
        Row("proposal rev_4.pdf", stem: "proposal", version: 4),
        Row("Policy_FINAL_v2_NEW.pdf", stem: "policy", version: 2, statuses: ["final", "new"]),
        Row("Employee Handbook.docx", stem: "employee handbook"),
        Row("Employee Handbook Final.docx", stem: "employee handbook", statuses: ["final"]),
        Row("Employee Handbook Final 2.docx", stem: "employee handbook", looseNumber: 2, statuses: ["final"]),
        Row("Employee Handbook FINAL APPROVED.docx", stem: "employee handbook", statuses: ["final", "approved"]),
        Row("Copy of Grant Agreement.pdf", stem: "grant agreement", isCopy: true),
        Row("Grant Agreement copy 2.pdf", stem: "grant agreement", copyNumber: 2, isCopy: true),
        Row("Grant Agreement (3).pdf", stem: "grant agreement", copyNumber: 3),
        Row("Budget 2026-07-15.xlsx", stem: "budget", dateValue: 20260715),
        Row("Budget 20260715.xlsx", stem: "budget", dateValue: 20260715),
        Row("minutes 7-15-2026.docx", stem: "minutes", dateValue: 20260715),
        Row("minutes 07/15/2026.docx", stem: "minutes", dateValue: 20260715),
        Row("Q3 report (Kadeem's conflicted copy 2).docx", stem: "q3 report", conflicted: true),
        Row("notes draft.txt", stem: "notes", statuses: ["draft"]),
        Row("old backup notes.txt", stem: "notes", statuses: ["old", "backup"]),
        Row("USE THIS ONE.pdf", stem: "", statuses: ["usethisone"]),
        Row("chapter 1.md", stem: "chapter 1"),
        Row("Chapter 2.md", stem: "chapter 2"),
        Row("invoice 2024.pdf", stem: "invoice", yearOnly: 2024),
        Row("invoice 2025.pdf", stem: "invoice", yearOnly: 2025),
        Row("scan00083.pdf", stem: "scan00083"),
        Row("v2.pdf", stem: "", version: 2),
        Row("Report.v3.2026-01-05.pdf", stem: "report", version: 3, dateValue: 20260105),
        Row("meeting notes final final.docx", stem: "meeting notes", statuses: ["final", "final"]),
        Row("Nov2024 newsletter.pdf", stem: "nov2024 newsletter"),
        Row("archive of records.zip", stem: "of records", statuses: ["archive"]),
        Row("presentation copy.key", stem: "presentation", isCopy: true),
        Row("2026-03-01_Board-Minutes_Lava-Labs_Approved.pdf",
            stem: "board minutes lava labs", statuses: ["approved"], dateValue: 20260301),
    ]

    @Test("token table", arguments: table)
    func parse(row: Row) {
        let tokens = VersionTokenParser.parse(filename: row.filename)

        #expect(tokens.stem == row.stem, "stem")
        #expect(tokens.explicitVersion == row.version, "version")
        #expect(tokens.copyNumber == row.copyNumber, "copyNumber")
        #expect(tokens.looseNumber == row.looseNumber, "looseNumber")
        #expect(tokens.isCopy == row.isCopy, "isCopy")
        #expect(tokens.isConflictedCopy == row.conflicted, "conflicted")
        #expect(tokens.statuses.sorted() == row.statuses.sorted(), "statuses")
        #expect(tokens.dateValue == row.dateValue, "dateValue")
        #expect(tokens.yearOnly == row.yearOnly, "yearOnly")
    }

    @Test("loose numbers stay in the stem without a version signal")
    func chapterGuard() {
        let one = VersionTokenParser.parse(filename: "chapter 1.md")
        let two = VersionTokenParser.parse(filename: "chapter 2.md")
        #expect(one.stem != two.stem, "Chapter 1 and Chapter 2 must never share a stem")
        #expect(!one.hasVersionSignal)
    }
}
