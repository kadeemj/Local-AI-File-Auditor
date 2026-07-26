import AuditorReports
import SwiftUI

struct ReportsView: View {
    @Environment(AppModel.self) private var appModel

    private var report: AuditReport {
        appModel.makeAuditReport()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                summaryCards
                exportActions
                previewNotes
            }
            .padding(24)
            .frame(maxWidth: 820, alignment: .leading)
        }
        .navigationTitle("Reports")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Audit Reports")
                .font(.largeTitle.weight(.semibold))
            Text("Export a consultant-ready CSV or PDF of the current findings and applied-change log. Reports stay on this Mac.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var summaryCards: some View {
        HStack(spacing: 12) {
            card("Findings", "\(report.findings.count)")
            card("Critical / High", "\(report.criticalAndHighCount)")
            card("Applied ops", "\(report.appliedOperationCount)")
            card("Folders", "\(report.folderPaths.count)")
        }
    }

    private func card(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title.weight(.semibold).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private var exportActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Export")
                .font(.title3.weight(.semibold))
            HStack(spacing: 12) {
                Button("Export CSV…") {
                    appModel.exportCSV()
                }
                .keyboardShortcut("e", modifiers: [.command])

                Button("Export PDF…") {
                    appModel.exportPDF()
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(report.findings.isEmpty && report.applyBatches.isEmpty)
            }

            if report.findings.isEmpty {
                Text("Run a scan first to populate findings. You can still export an applied-changes PDF after applying.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var previewNotes: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What’s included")
                .font(.title3.weight(.semibold))
            Text("• CSV — one row per finding with severity, evidence, recommendation, paths, and decision state")
            Text("• PDF — summary page, findings by severity, and the applied-changes journal")
            Text("• Policy: \(report.policyName ?? "Universal rules only")")
            if let files = report.filesScanned {
                Text("• Last scan: \(files) files")
            }
            if let status = appModel.statusMessage {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
        }
        .font(.body)
        .foregroundStyle(.primary)
    }
}
