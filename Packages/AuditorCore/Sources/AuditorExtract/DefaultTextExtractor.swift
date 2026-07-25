import AuditorModels
import Foundation

public enum ExtractionError: Error {
    case unsupportedType(String)
    case unreadable(String)
    case cloudPlaceholder(String)
}

/// Routes files to the right extraction strategy by extension:
/// PDF (text layer → OCR fallback), docx (XML), images (OCR), plain text.
/// Extracted text is transient — callers fingerprint or analyze it, never persist it.
public struct DefaultTextExtractor: TextExtracting {
    public enum Limits {
        /// OCR is expensive; a scanned contract's substance is in the first pages.
        public static let maxOCRPages = 10
        /// Cap on returned text; enough for any analysis we do.
        public static let maxTextCharacters = 2_000_000
        /// Below this many characters a PDF "text layer" is treated as absent
        /// (scanner artifacts often leave a few stray glyphs).
        public static let minMeaningfulTextLayer = 16
    }

    private enum Strategy {
        case pdf
        case docx
        case plainText
        case image
    }

    private static let strategies: [String: Strategy] = [
        "pdf": .pdf,
        "docx": .docx,
        "txt": .plainText, "md": .plainText, "markdown": .plainText, "csv": .plainText,
        "png": .image, "jpg": .image, "jpeg": .image, "heic": .image, "tif": .image, "tiff": .image,
    ]

    /// When false, scanned PDFs yield empty text instead of triggering OCR —
    /// the right default for bulk scans where OCR cost must be opt-in.
    let enableOCRFallback: Bool

    public init(enableOCRFallback: Bool = true) {
        self.enableOCRFallback = enableOCRFallback
    }

    public func canExtract(from record: FileRecord) -> Bool {
        guard !record.isDatalessCloudItem else { return false }
        let ext = (record.filename as NSString).pathExtension.lowercased()
        return Self.strategies[ext] != nil
    }

    public func extractText(from record: FileRecord) async throws -> ExtractedText {
        guard !record.isDatalessCloudItem else {
            throw ExtractionError.cloudPlaceholder(record.path)
        }
        let ext = (record.filename as NSString).pathExtension.lowercased()
        guard let strategy = Self.strategies[ext] else {
            throw ExtractionError.unsupportedType(ext)
        }

        let raw: ExtractedText
        switch strategy {
        case .pdf:
            raw = try await PDFExtractor(enableOCRFallback: enableOCRFallback).extract(from: record.url)
        case .docx:
            raw = ExtractedText(text: try DocxExtractor().extract(from: record.url), usedOCR: false)
        case .plainText:
            raw = ExtractedText(text: try PlainTextExtractor().extract(from: record.url), usedOCR: false)
        case .image:
            raw = ExtractedText(text: try await VisionOCR().recognizeText(inImageAt: record.url), usedOCR: true)
        }

        guard raw.text.count > Limits.maxTextCharacters else { return raw }
        return ExtractedText(text: String(raw.text.prefix(Limits.maxTextCharacters)), usedOCR: raw.usedOCR)
    }
}
