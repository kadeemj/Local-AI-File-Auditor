import AuditorModels
import AuditorTestSupport
import Foundation
import Testing

@testable import AuditorExtract

private func record(for url: URL, dataless: Bool = false) -> FileRecord {
    let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
    let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 1
    return FileRecord(path: url.path, size: size, mtimeNanoseconds: 1, isDatalessCloudItem: dataless)
}

@Suite("DefaultTextExtractor")
struct TextExtractorTests {
    let extractor = DefaultTextExtractor()

    @Test("PDF with a text layer extracts without OCR")
    func pdfTextLayer() async throws {
        let dir = try FixtureBuilder().build()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("agreement.pdf")
        try DocumentFixtures.writePDF(
            text: "This Cleaning Services Agreement expires on September 30, 2026.",
            to: url
        )

        let result = try await extractor.extractText(from: record(for: url))

        #expect(result.usedOCR == false)
        #expect(result.text.contains("Cleaning Services Agreement"))
        #expect(result.text.contains("September 30, 2026"))
    }

    @Test("scanned PDF falls back to Vision OCR")
    func scannedPDF() async throws {
        let dir = try FixtureBuilder().build()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("scan00083.pdf")
        try DocumentFixtures.writeScannedPDF(text: "GRANT AGREEMENT 2026", to: url)

        let result = try await extractor.extractText(from: record(for: url))

        #expect(result.usedOCR == true)
        // OCR whitespace is unstable ("GRANTAGREEMENT") — compare without spaces.
        let normalized = result.text.uppercased().replacingOccurrences(of: " ", with: "")
        #expect(normalized.contains("GRANTAGREEMENT"))
        #expect(normalized.contains("2026"))
    }

    @Test("PNG image goes straight to OCR")
    func imageOCR() async throws {
        let dir = try FixtureBuilder().build()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("receipt.png")
        try DocumentFixtures.writePNG(text: "INVOICE TOTAL 450 DOLLARS", to: url)

        let result = try await extractor.extractText(from: record(for: url))

        #expect(result.usedOCR == true)
        #expect(result.text.uppercased().contains("INVOICE"))
    }

    @Test("docx extracts paragraphs as text lines")
    func docx() async throws {
        let dir = try FixtureBuilder().build()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("handbook.docx")
        try DocumentFixtures.writeDocx(
            paragraphs: ["Employee Handbook", "Section 1: Conduct & Ethics", "All staff must comply."],
            to: url
        )

        let result = try await extractor.extractText(from: record(for: url))

        #expect(result.usedOCR == false)
        #expect(result.text.contains("Employee Handbook"))
        #expect(result.text.contains("Conduct & Ethics"), "XML entities must be decoded")
        let lines = result.text.split(separator: "\n")
        #expect(lines.count == 3, "each w:p is one line")
    }

    @Test("plain text reads UTF-8 and falls back for legacy encodings")
    func plainText() async throws {
        let dir = try FixtureBuilder().build()
        defer { try? FileManager.default.removeItem(at: dir) }

        let utf8 = dir.appendingPathComponent("notes.txt")
        try Data("Café budget für 2026".utf8).write(to: utf8)
        let utf8Result = try await extractor.extractText(from: record(for: utf8))
        #expect(utf8Result.text.contains("Café budget für 2026"))

        let latin1 = dir.appendingPathComponent("legacy.txt")
        try "Résumé".data(using: .isoLatin1)!.write(to: latin1)
        let latinResult = try await extractor.extractText(from: record(for: latin1))
        #expect(latinResult.text.contains("sum"), "legacy encoding must not throw")
    }

    @Test("canExtract: supported types yes, cloud placeholders and unknown types no")
    func canExtractRules() {
        func rec(_ name: String, dataless: Bool = false) -> FileRecord {
            FileRecord(path: "/x/\(name)", size: 10, mtimeNanoseconds: 1, isDatalessCloudItem: dataless)
        }
        #expect(extractor.canExtract(from: rec("a.pdf")))
        #expect(extractor.canExtract(from: rec("b.docx")))
        #expect(extractor.canExtract(from: rec("c.txt")))
        #expect(extractor.canExtract(from: rec("d.png")))
        #expect(!extractor.canExtract(from: rec("e.sketch")))
        #expect(!extractor.canExtract(from: rec("f.pdf", dataless: true)), "never open cloud placeholders")
    }

    @Test("output is capped to the text budget")
    func textCap() async throws {
        let dir = try FixtureBuilder().build()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("huge.txt")
        let huge = String(repeating: "governance ", count: 300_000)  // ~3.3 MB
        try Data(huge.utf8).write(to: url)

        let result = try await extractor.extractText(from: record(for: url))
        #expect(result.text.count <= DefaultTextExtractor.Limits.maxTextCharacters)
    }
}

@Suite("MetadataReader")
struct MetadataReaderTests {
    @Test("reads PDF title and author attributes")
    func pdfAttributes() async throws {
        let dir = try FixtureBuilder().build()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("titled.pdf")
        try DocumentFixtures.writePDF(
            text: "body", to: url,
            title: "2026 Cybersecurity Services Agreement",
            author: "Lava Labs"
        )

        let metadata = MetadataReader().read(from: record(for: url))

        #expect(metadata?.title == "2026 Cybersecurity Services Agreement")
        #expect(metadata?.author == "Lava Labs")
    }

    @Test("PDF without attributes reports empty metadata, not nil crash")
    func missingAttributes() async throws {
        let dir = try FixtureBuilder().build()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("bare.pdf")
        try DocumentFixtures.writePDF(text: "no attributes here", to: url)

        let metadata = MetadataReader().read(from: record(for: url))

        #expect(metadata != nil)
        #expect(metadata?.title == nil)
    }
}
