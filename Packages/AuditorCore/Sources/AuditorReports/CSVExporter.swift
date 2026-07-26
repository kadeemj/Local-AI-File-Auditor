import Foundation

/// Flat CSV exporter for findings — the consultant/auditor artifact.
public enum CSVExporter {
    public static let headerColumns: [String] = [
        "severity",
        "kind",
        "decision",
        "confidence",
        "explanation",
        "recommendation",
        "files",
        "evidence",
        "detector_id",
        "stable_key",
        "scan_id",
        "created_at",
    ]

    public static func string(from report: AuditReport) -> String {
        var lines: [String] = [headerColumns.joined(separator: ",")]
        let sorted = report.findings.sorted { ($0.severity, $0.confidence) > ($1.severity, $1.confidence) }
        for finding in sorted {
            let row: [String] = [
                ReportFormatting.severityLabel(finding.severity),
                finding.kind,
                finding.decision.rawValue,
                String(format: "%.2f", finding.confidence),
                finding.explanation,
                ReportFormatting.recommendationText(finding.recommendation),
                finding.files.map(\.path).joined(separator: " | "),
                ReportFormatting.evidenceText(finding.evidence),
                finding.detectorID,
                finding.stableKey,
                finding.scanID.uuidString,
                ReportFormatting.isoDate(finding.createdAt),
            ]
            lines.append(row.map(escape).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public static func data(from report: AuditReport) -> Data {
        Data(string(from: report).utf8)
    }

    public static func write(_ report: AuditReport, to url: URL) throws {
        try data(from: report).write(to: url, options: .atomic)
    }

    /// RFC 4180-style field escaping.
    public static func escape(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }
}
