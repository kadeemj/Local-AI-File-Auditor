import AuditorModels
import AuditorReports
import AuditorStore
import SwiftUI

/// Letter-sized report pages rendered into a multi-page PDF.
enum ReportPageSize {
    static let width: CGFloat = 612
    static let height: CGFloat = 792
    static var size: CGSize { CGSize(width: width, height: height) }
}

struct ReportSummaryPage: View {
    let report: AuditReport

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Spacer().frame(height: 28)
            Text(report.title)
                .font(.system(size: 28, weight: .semibold))
            Text("Generated \(report.generatedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 10) {
                metric("Policy", report.policyName ?? "Universal rules only")
                metric("Folders", report.folderPaths.isEmpty ? "—" : report.folderPaths.joined(separator: "\n"))
                if let files = report.filesScanned {
                    metric("Files scanned", "\(files)")
                }
                if let bytes = report.totalBytes {
                    metric("Total size", ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                }
                if let duration = report.scanDuration {
                    metric("Scan duration", String(format: "%.2fs", duration))
                }
                metric("Findings", "\(report.findings.count) total · \(report.criticalAndHighCount) critical/high")
                metric("Applied changes", "\(report.appliedOperationCount) operation(s) still applied")
            }
            .padding(.top, 28)

            Spacer()
            footerNote
        }
        .padding(48)
        .frame(width: ReportPageSize.width, height: ReportPageSize.height, alignment: .topLeading)
        .background(Color.white)
    }

    private var header: some View {
        HStack {
            Text("FolderLint")
                .font(.system(size: 14, weight: .bold))
            Spacer()
            Text("Confidential audit artifact")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footerNote: some View {
        Text("All analysis ran on-device. FolderLint never deletes files; applied changes are journaled and undoable.")
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
    }
}

struct ReportFindingsPage: View {
    let severity: Severity
    let findings: [Finding]
    let pageIndex: Int
    let pageCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Findings — \(ReportFormatting.severityLabel(severity).capitalized)")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                Text("Page \(pageIndex) of \(pageCount)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            ForEach(findings) { finding in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(ReportFormatting.severityLabel(finding.severity).uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.08), in: Capsule())
                        Text(finding.kind)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(finding.decision.rawValue)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Text(finding.explanation)
                        .font(.system(size: 12, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(ReportFormatting.recommendationText(finding.recommendation))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(finding.files.map(\.path).joined(separator: "\n"))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 6)
                Divider()
            }
            Spacer(minLength: 0)
        }
        .padding(40)
        .frame(width: ReportPageSize.width, height: ReportPageSize.height, alignment: .topLeading)
        .background(Color.white)
    }
}

struct ReportAppliedChangesPage: View {
    let batches: [StoredApplyBatch]
    let pageIndex: Int
    let pageCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Applied Changes Log")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                Text("Page \(pageIndex) of \(pageCount)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            if batches.isEmpty {
                Text("No applied changes in this report period.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(batches) { batch in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(batch.performedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.system(size: 12, weight: .semibold))
                            Spacer()
                            Text(batch.isUndone ? "UNDONE" : "APPLIED")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(batch.isUndone ? .secondary : .primary)
                        }
                        ForEach(batch.entries) { entry in
                            Text("\(entry.operation.uppercased())  \(entry.originalPath) → \(entry.newPath)")
                                .font(.system(size: 9, design: .monospaced))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 4)
                    Divider()
                }
            }
            Spacer(minLength: 0)
        }
        .padding(40)
        .frame(width: ReportPageSize.width, height: ReportPageSize.height, alignment: .topLeading)
        .background(Color.white)
    }
}
