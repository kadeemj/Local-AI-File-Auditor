import AuditorModels
import SwiftUI

struct FindingsListView: View {
    @Environment(AppModel.self) private var appModel
    @State private var selectedID: Finding.ID?
    @State private var severityFilter: Severity?

    private var filtered: [Finding] {
        let all = appModel.scanSession.findings
        guard let severityFilter else { return all }
        return all.filter { $0.severity == severityFilter }
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                filterBar
                Divider()
                List(filtered, selection: $selectedID) { finding in
                    FindingRowView(finding: finding, compact: true)
                        .tag(finding.id)
                }
                .listStyle(.inset)
            }
            .frame(minWidth: 320)

            Group {
                if let finding = filtered.first(where: { $0.id == selectedID }) ?? filtered.first {
                    FindingDetailView(finding: finding)
                } else {
                    ContentUnavailableView(
                        "No Finding Selected",
                        systemImage: "list.bullet.rectangle",
                        description: Text("Run a scan to review evidence-backed recommendations.")
                    )
                }
            }
            .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Findings")
    }

    private var filterBar: some View {
        HStack {
            Picker("Severity", selection: $severityFilter) {
                Text("All").tag(Severity?.none)
                ForEach(Severity.allCases.reversed(), id: \.self) { severity in
                    Text(severity.label).tag(Optional(severity))
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Spacer()
            Text("\(filtered.count)")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(12)
    }
}

struct RenamesListView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        FindingCategoryList(
            title: "Renames",
            emptySystemImage: "pencil",
            emptyDescription: "Filename policy and rename suggestions appear here.",
            findings: appModel.scanSession.state.renameFindings
        )
    }
}

struct ExpirationsListView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        FindingCategoryList(
            title: "Expirations",
            emptySystemImage: "calendar.badge.exclamationmark",
            emptyDescription: "Dated obligations within the policy horizon appear here.",
            findings: appModel.scanSession.state.expirationFindings
        )
    }
}

private struct FindingCategoryList: View {
    let title: String
    let emptySystemImage: String
    let emptyDescription: String
    let findings: [Finding]
    @State private var selectedID: Finding.ID?

    var body: some View {
        HSplitView {
            List(findings, selection: $selectedID) { finding in
                FindingRowView(finding: finding, compact: true)
                    .tag(finding.id)
            }
            .listStyle(.inset)
            .frame(minWidth: 300)

            Group {
                if let finding = findings.first(where: { $0.id == selectedID }) ?? findings.first {
                    FindingDetailView(finding: finding)
                } else {
                    ContentUnavailableView(title, systemImage: emptySystemImage, description: Text(emptyDescription))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(title)
    }
}

struct FindingRowView: View {
    let finding: Finding
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                SeverityBadge(severity: finding.severity)
                Text(finding.kind)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("\(Int(finding.confidence * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            Text(finding.explanation)
                .font(compact ? .body : .body.weight(.medium))
                .lineLimit(compact ? 2 : 4)
            if let first = finding.files.first {
                Text(first.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}

struct FindingDetailView: View {
    let finding: Finding

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    SeverityBadge(severity: finding.severity)
                    Text(finding.kind)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(finding.decision.rawValue.capitalized)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                }

                Text(finding.explanation)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)

                labeled("Recommendation", recommendationText)
                labeled("Evidence", evidenceText)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Files")
                        .font(.headline)
                    ForEach(finding.files, id: \.path) { file in
                        Text(file.path)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                    }
                }

                Text("Apply / undo arrives in Phase 9. This shell is audit-only.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
        }
    }

    private var recommendationText: String {
        switch finding.recommendation {
        case .keepCanonical(let keep, let archive):
            "Keep \(keep.filename); archive \(archive.map(\.filename).joined(separator: ", "))."
        case .rename(let file, let proposed):
            "Rename \(file.filename) → \(proposed)"
        case .move(let file, let destination):
            "Move \(file.filename) to \(destination)"
        case .scheduleReminder(let date, let note):
            "Remind on \(date.formatted(date: .abbreviated, time: .omitted)): \(note)"
        case .review(let note):
            note
        }
    }

    private var evidenceText: String {
        switch finding.evidence {
        case .duplicateSet(let hash, let wasted):
            return "Exact hash \(hash.prefix(12))… · \(ByteCountFormatter.string(fromByteCount: wasted, countStyle: .file)) reclaimable"
        case .contentDuplicateSet(let similarity, let wasted):
            return "Content similarity \(String(format: "%.0f%%", similarity * 100)) · \(ByteCountFormatter.string(fromByteCount: wasted, countStyle: .file)) reclaimable"
        case .versionChain(let ranked, let stem, let signals, let confidence, let judge):
            return "Stem “\(stem)” · \(ranked.joined(separator: " > ")) · \(signals.joined(separator: ", ")) · \(Int(confidence * 100))% (\(judge.rawValue))"
        case .filenamePolicy(let template, let violations, let proposed, let judge):
            let rules = violations.map(\.ruleID).joined(separator: ", ")
            return "Template \(template ?? "—") · rules \(rules) · proposed \(proposed ?? "—") · \(judge?.rawValue ?? "rules")"
        case .misfiled(let current, let suggested, let own, let other, let nearest, let judge):
            return "From \(current) → \(suggested) (own \(String(format: "%.2f", own)), suggested \(String(format: "%.2f", other))); nearest: \(nearest.map(\.filename).joined(separator: ", ")) [\(judge.rawValue)]"
        case .expiration(let kind, let detected, let action, let autoRenews, let notice, let party, let snippet, let judge):
            return "\(kind.rawValue) \(detected.formatted(date: .abbreviated, time: .omitted)); action \(action.formatted(date: .abbreviated, time: .omitted)); notice \(notice)d; autoRenew \(autoRenews); party \(party ?? "—"); \(judge.rawValue)\n“\(snippet)”"
        case .note(let note):
            return note
        }
    }

    private func labeled(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(body)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct SeverityBadge: View {
    let severity: Severity

    var body: some View {
        Text(severity.label.uppercased())
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(severity.color)
            .background(severity.color.opacity(0.15), in: Capsule())
    }
}

extension Severity {
    var label: String {
        switch self {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        case .critical: "Critical"
        }
    }

    var color: Color {
        switch self {
        case .low: .secondary
        case .medium: .orange
        case .high: .red
        case .critical: .purple
        }
    }
}
