import Foundation

/// txt/md/csv reading with encoding fallback: UTF-8 first, then legacy Latin-1
/// (which cannot fail — every byte sequence is valid), so old documents never
/// abort a scan.
struct PlainTextExtractor {
    func extract(from url: URL) throws -> String {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ExtractionError.unreadable(url.path)
        }

        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        return String(data: data, encoding: .isoLatin1) ?? ""
    }
}
