import AuditorModels
import SwiftUI

struct DashboardView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                metrics
                recentFindings
            }
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Dashboard")
                    .font(.largeTitle.weight(.semibold))
                Text(subtitle)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            scanControls
        }
    }

    private var subtitle: String {
        if appModel.scanSession.isRunning {
            let phase = appModel.scanSession.phase?.rawValue ?? "working"
            return "Scan in progress — \(phase), \(appModel.scanSession.progress.filesSeen) files seen"
        }
        if let summary = appModel.scanSession.summary {
            return "Last scan: \(summary.filesScanned) files · \(summary.findingsCount) findings · \(String(format: "%.1fs", summary.duration))"
        }
        return "Audit-only by default. Recommendations include evidence; nothing is changed until you approve."
    }

    private var scanControls: some View {
        HStack(spacing: 10) {
            if appModel.scanSession.isRunning {
                Button("Cancel") { appModel.cancelScan() }
            } else {
                Button("Scan Folders") { appModel.startScan() }
                    .keyboardShortcut("r", modifiers: [.command])
                Button("Mock Scan") { appModel.startScan(useMock: true) }
                    .help("Disposable on-disk fixture with apply-ready findings")
            }
            if !appModel.scanSession.state.actionableApprovedFindings.isEmpty {
                Button("Review Apply") { appModel.selectedSidebar = .apply }
            }
        }
    }

    private var metrics: some View {
        let findings = appModel.scanSession.findings
        return HStack(spacing: 12) {
            metricCard("Findings", "\(findings.count)", systemImage: "list.bullet.rectangle")
            metricCard("Critical / High", "\(findings.filter { $0.severity >= .high }.count)", systemImage: "exclamationmark.triangle")
            metricCard("Renames", "\(appModel.scanSession.state.renameFindings.count)", systemImage: "pencil")
            metricCard("Expirations", "\(appModel.scanSession.state.expirationFindings.count)", systemImage: "calendar")
        }
    }

    private func metricCard(_ title: String, _ value: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
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

    private var recentFindings: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Top findings")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button("View all") {
                    appModel.selectedSidebar = .findings
                }
                .disabled(appModel.scanSession.findings.isEmpty)
            }

            if appModel.scanSession.findings.isEmpty {
                Text(appModel.scanSession.isRunning ? "Collecting findings…" : "No findings yet. Run a scan to populate this list.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 20)
            } else {
                ForEach(appModel.scanSession.findings.prefix(8)) { finding in
                    FindingRowView(finding: finding, compact: true)
                }
            }

            if let status = appModel.statusMessage {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
    }
}
