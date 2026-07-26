import AuditorModels
import AuditorReports
import AuditorStore
import Foundation
import SwiftUI

enum PDFReportError: Error, Sendable {
    case rendererFailed
    case emptyDocument
}

/// Renders SwiftUI report pages into a multi-page PDF via `ImageRenderer`.
@MainActor
enum PDFReportRenderer {
    static func data(from report: AuditReport, findingsPerPage: Int = 5) throws -> Data {
        let pages = makePageViews(report: report, findingsPerPage: findingsPerPage)
        guard !pages.isEmpty else { throw PDFReportError.emptyDocument }

        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: ReportPageSize.size)
        guard let consumer = CGDataConsumer(data: data),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else {
            throw PDFReportError.rendererFailed
        }

        for page in pages {
            let renderer = ImageRenderer(content: page)
            renderer.proposedSize = ProposedViewSize(ReportPageSize.size)
            context.beginPDFPage(nil)
            renderer.render { _, renderInContext in
                renderInContext(context)
            }
            context.endPDFPage()
        }
        context.closePDF()

        guard data.length > 0 else { throw PDFReportError.emptyDocument }
        return data as Data
    }

    static func write(_ report: AuditReport, to url: URL, findingsPerPage: Int = 5) throws {
        try data(from: report, findingsPerPage: findingsPerPage).write(to: url, options: .atomic)
    }

    private static func makePageViews(report: AuditReport, findingsPerPage: Int) -> [AnyView] {
        var findingChunks: [(Severity, [Finding])] = []
        for (severity, findings) in report.findingsBySeverity {
            var remaining = findings
            while !remaining.isEmpty {
                findingChunks.append((severity, Array(remaining.prefix(findingsPerPage))))
                remaining = Array(remaining.dropFirst(findingsPerPage))
            }
        }

        var appliedChunks: [[StoredApplyBatch]] = []
        if report.applyBatches.isEmpty {
            appliedChunks = [[]]
        } else {
            var remaining = report.applyBatches
            while !remaining.isEmpty {
                appliedChunks.append(Array(remaining.prefix(4)))
                remaining = Array(remaining.dropFirst(4))
            }
        }

        let totalPages = 1 + findingChunks.count + appliedChunks.count
        var pages: [AnyView] = [AnyView(ReportSummaryPage(report: report))]
        var pageNumber = 2

        for (severity, chunk) in findingChunks {
            pages.append(AnyView(ReportFindingsPage(
                severity: severity,
                findings: chunk,
                pageIndex: pageNumber,
                pageCount: totalPages
            )))
            pageNumber += 1
        }

        for chunk in appliedChunks {
            pages.append(AnyView(ReportAppliedChangesPage(
                batches: chunk,
                pageIndex: pageNumber,
                pageCount: totalPages
            )))
            pageNumber += 1
        }

        return pages
    }
}
