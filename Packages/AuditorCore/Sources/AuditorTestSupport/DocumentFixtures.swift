import AppKit
import CoreText
import Foundation
import PDFKit

/// Generates real documents for extraction tests: PDFs with genuine text layers
/// (Core Text glyph drawing), image-only "scanned" PDFs, bitmap images, and
/// minimal valid docx archives.
public enum DocumentFixtures {
    public enum FixtureError: Error {
        case contextCreationFailed
        case renderFailed
    }

    /// A PDF whose text is a real extractable text layer.
    public static func writePDF(text: String, to url: URL, title: String? = nil, author: String? = nil) throws {
        let data = try pdfData(drawing: { context, mediaBox in
            let attributed = NSAttributedString(
                string: text,
                attributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.black]
            )
            let framesetter = CTFramesetterCreateWithAttributedString(attributed)
            let path = CGPath(rect: mediaBox.insetBy(dx: 50, dy: 50), transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
            CTFrameDraw(frame, context)
        })

        if title != nil || author != nil {
            guard let document = PDFDocument(data: data) else { throw FixtureError.renderFailed }
            var attributes = document.documentAttributes ?? [:]
            if let title { attributes[PDFDocumentAttribute.titleAttribute] = title }
            if let author { attributes[PDFDocumentAttribute.authorAttribute] = author }
            document.documentAttributes = attributes
            guard document.write(to: url) else { throw FixtureError.renderFailed }
        } else {
            try data.write(to: url)
        }
    }

    /// A "scanned" PDF: the text exists only as pixels, so extraction must OCR.
    public static func writeScannedPDF(text: String, to url: URL) throws {
        let image = try renderBitmap(text: text)
        let data = try pdfData(drawing: { context, mediaBox in
            context.draw(image, in: mediaBox)
        })
        try data.write(to: url)
    }

    /// A PNG containing rendered text, for direct image OCR.
    public static func writePNG(text: String, to url: URL) throws {
        let image = try renderBitmap(text: text)
        let rep = NSBitmapImageRep(cgImage: image)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw FixtureError.renderFailed
        }
        try png.write(to: url)
    }

    /// A minimal valid .docx: ZIP with [Content_Types].xml and word/document.xml.
    /// Paragraphs map to <w:p> elements.
    public static func writeDocx(paragraphs: [String], to url: URL) throws {
        let contentTypes = """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
            <Default Extension="xml" ContentType="application/xml"/>
            <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
            </Types>
            """
        let body = paragraphs
            .map { "<w:p><w:r><w:t>\($0.xmlEscaped)</w:t></w:r></w:p>" }
            .joined()
        let document = """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
            <w:body>\(body)</w:body></w:document>
            """

        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("docx-staging-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        try FileManager.default.createDirectory(
            at: staging.appendingPathComponent("word"), withIntermediateDirectories: true)
        try Data(contentTypes.utf8).write(to: staging.appendingPathComponent("[Content_Types].xml"))
        try Data(document.utf8).write(to: staging.appendingPathComponent("word/document.xml"))

        try zipDirectoryContents(of: staging, to: url)
    }

    // MARK: - Internals

    private static func pdfData(drawing: (CGContext, CGRect) -> Void) throws -> Data {
        let pdfData = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else { throw FixtureError.contextCreationFailed }

        context.beginPDFPage(nil)
        drawing(context, mediaBox)
        context.endPDFPage()
        context.closePDF()
        return pdfData as Data
    }

    /// Big black-on-white text so Vision OCR reads it reliably.
    private static func renderBitmap(text: String) throws -> CGImage {
        let size = CGSize(width: 1200, height: 400)
        guard let context = CGContext(
            data: nil, width: Int(size.width), height: Int(size.height),
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw FixtureError.contextCreationFailed }

        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))

        let attributed = NSAttributedString(
            string: text,
            attributes: [.font: NSFont.boldSystemFont(ofSize: 48), .foregroundColor: NSColor.black]
        )
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let path = CGPath(rect: CGRect(origin: .zero, size: size).insetBy(dx: 60, dy: 60), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        CTFrameDraw(frame, context)

        guard let image = context.makeImage() else { throw FixtureError.renderFailed }
        return image
    }

    /// Zips the *contents* of a directory (entries at archive root, as docx requires)
    /// using /usr/bin/zip. Test-support only — never used by the sandboxed app.
    private static func zipDirectoryContents(of directory: URL, to destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = directory
        process.arguments = ["-r", "-X", "-q", destination.path, "."]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw FixtureError.renderFailed }
    }
}

extension String {
    var xmlEscaped: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
