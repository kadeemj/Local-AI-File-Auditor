import AuditorModels
import Foundation

public struct ExtractedText: Sendable {
    public let text: String
    /// True when the text came from OCR rather than an embedded text layer.
    public let usedOCR: Bool

    public init(text: String, usedOCR: Bool) {
        self.text = text
        self.usedOCR = usedOCR
    }
}

/// Shared text-extraction contract for content-aware detectors.
/// Phase 3 implements: PDFKit text layer → Vision OCR fallback → docx/xlsx unzip.
/// Extracted text is never persisted — only fingerprints and findings evidence.
public protocol TextExtracting: Sendable {
    func canExtract(from record: FileRecord) -> Bool
    func extractText(from record: FileRecord) async throws -> ExtractedText
}
