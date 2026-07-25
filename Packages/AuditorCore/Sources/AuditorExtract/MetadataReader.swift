import AuditorModels
import Foundation
import PDFKit

/// Embedded document attributes. v1 reads PDFs (PDFKit `documentAttributes`);
/// consumed by the rename suggester and, post-validation, a metadata detector.
public struct DocumentMetadata: Codable, Sendable {
    public let title: String?
    public let author: String?
    public let subject: String?
    public let keywords: [String]
    public let creationDate: Date?
    public let modificationDate: Date?
    public let producer: String?
    public let creatorApplication: String?
}

public struct MetadataReader: Sendable {
    public init() {}

    /// Returns nil when the file type carries no readable metadata.
    public func read(from record: FileRecord) -> DocumentMetadata? {
        guard (record.filename as NSString).pathExtension.lowercased() == "pdf",
              !record.isDatalessCloudItem,
              let document = PDFDocument(url: record.url)
        else { return nil }

        let attributes = document.documentAttributes ?? [:]

        // Keywords may be an array or a comma/semicolon-separated string.
        let keywords: [String]
        switch attributes[PDFDocumentAttribute.keywordsAttribute] {
        case let array as [String]:
            keywords = array
        case let string as String:
            keywords = string
                .components(separatedBy: CharacterSet(charactersIn: ",;"))
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        default:
            keywords = []
        }

        return DocumentMetadata(
            title: attributes[PDFDocumentAttribute.titleAttribute] as? String,
            author: attributes[PDFDocumentAttribute.authorAttribute] as? String,
            subject: attributes[PDFDocumentAttribute.subjectAttribute] as? String,
            keywords: keywords,
            creationDate: attributes[PDFDocumentAttribute.creationDateAttribute] as? Date,
            modificationDate: attributes[PDFDocumentAttribute.modificationDateAttribute] as? Date,
            producer: attributes[PDFDocumentAttribute.producerAttribute] as? String,
            creatorApplication: attributes[PDFDocumentAttribute.creatorAttribute] as? String
        )
    }
}
