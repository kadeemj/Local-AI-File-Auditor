import Foundation
import ZIPFoundation

/// Extracts text from .docx (a ZIP containing word/document.xml) without Word.
/// XMLParser walks the document: <w:t> runs are text, </w:p> ends a paragraph,
/// <w:tab/> and <w:br/> map to their characters.
struct DocxExtractor {
    func extract(from url: URL) throws -> String {
        let archive: Archive
        do {
            archive = try Archive(url: url, accessMode: .read)
        } catch {
            throw ExtractionError.unreadable("\(url.path): not a ZIP archive")
        }
        guard let entry = archive["word/document.xml"] else {
            throw ExtractionError.unreadable("\(url.path): missing word/document.xml")
        }

        var xmlData = Data()
        _ = try archive.extract(entry) { xmlData.append($0) }

        let collector = TextCollector()
        let parser = XMLParser(data: xmlData)
        parser.delegate = collector
        guard parser.parse() else {
            throw ExtractionError.unreadable("\(url.path): malformed document.xml")
        }
        return collector.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private final class TextCollector: NSObject, XMLParserDelegate {
        private(set) var text = ""
        private var insideTextRun = false

        func parser(
            _ parser: XMLParser, didStartElement elementName: String,
            namespaceURI: String?, qualifiedName: String?, attributes: [String: String]
        ) {
            switch elementName {
            case "w:t": insideTextRun = true
            case "w:tab": text.append("\t")
            case "w:br": text.append("\n")
            default: break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if insideTextRun { text.append(string) }
        }

        func parser(
            _ parser: XMLParser, didEndElement elementName: String,
            namespaceURI: String?, qualifiedName: String?
        ) {
            switch elementName {
            case "w:t": insideTextRun = false
            case "w:p": text.append("\n")
            default: break
            }
        }
    }
}
