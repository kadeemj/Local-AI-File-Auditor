import AppKit
import Foundation
import PDFKit

/// PDF text extraction: embedded text layer first (fast, exact); when the layer
/// is absent or trivially small — a scanned document — fall back to Vision OCR
/// on rendered pages, capped at `Limits.maxOCRPages`.
struct PDFExtractor {
    let enableOCRFallback: Bool

    init(enableOCRFallback: Bool = true) {
        self.enableOCRFallback = enableOCRFallback
    }

    func extract(from url: URL) async throws -> ExtractedText {
        guard let document = PDFDocument(url: url) else {
            throw ExtractionError.unreadable(url.path)
        }

        let layerText = (document.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if layerText.count >= DefaultTextExtractor.Limits.minMeaningfulTextLayer {
            return ExtractedText(text: layerText, usedOCR: false)
        }
        guard enableOCRFallback else {
            return ExtractedText(text: "", usedOCR: false)
        }

        // Scanned document: render pages and OCR them.
        let ocr = VisionOCR()
        var pageTexts: [String] = []
        let pageCount = min(document.pageCount, DefaultTextExtractor.Limits.maxOCRPages)

        for index in 0..<pageCount {
            try Task.checkCancellation()
            guard let page = document.page(at: index) else { continue }
            guard let image = render(page: page) else { continue }
            let text = try await ocr.recognizeText(in: image)
            if !text.isEmpty { pageTexts.append(text) }
        }

        return ExtractedText(
            text: pageTexts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines),
            usedOCR: true
        )
    }

    /// ~150–200 dpi equivalent: enough for reliable OCR without huge bitmaps.
    private func render(page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        let scale = min(1700 / max(bounds.width, 1), 4.0)
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let thumbnail = page.thumbnail(of: size, for: .mediaBox)
        var rect = CGRect(origin: .zero, size: thumbnail.size)
        return thumbnail.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}
