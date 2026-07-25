import AuditorApply
import AuditorModels
import SwiftUI

struct ApplyReviewView: View {
    @Environment(AppModel.self) private var appModel

    private var plan: ApplyPlan? { appModel.draftPlan }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if let plan {
                    if plan.operations.isEmpty && plan.conflicts.isEmpty {
                        Text("Approved findings have no file mutations (reminders/reviews only).")
                            .foregroundStyle(.secondary)
                    } else {
                        operationsSection(plan)
                        if !plan.conflicts.isEmpty {
                            conflictsSection(plan)
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "Nothing to Apply",
                        systemImage: "checkmark.seal",
                        description: Text("Approve rename, move, or archive recommendations from Findings, then preview them here.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 240)
                }
            }
            .padding(24)
            .frame(maxWidth: 820, alignment: .leading)
        }
        .navigationTitle("Apply")
        .onAppear { appModel.refreshDraftPlan() }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Review & Apply")
                    .font(.largeTitle.weight(.semibold))
                Text("Journal is written before any rename or move. FolderLint never deletes — archive means move into `_Archive/`.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Refresh Plan") { appModel.refreshDraftPlan() }
            Button("Apply \(plan?.operations.count ?? 0) Change\((plan?.operations.count ?? 0) == 1 ? "" : "s")") {
                appModel.applyApproved()
            }
            .disabled(!(plan?.isAppliable ?? false))
            .keyboardShortcut(.defaultAction)
        }
    }

    private func operationsSection(_ plan: ApplyPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Proposed operations")
                .font(.title3.weight(.semibold))
            ForEach(plan.operations) { operation in
                VStack(alignment: .leading, spacing: 4) {
                    Text(operation.kind.rawValue.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.accentColor)
                    Text(operation.originalPath)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                    Image(systemName: "arrow.down")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(operation.newPath)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
            }
        }
    }

    private func conflictsSection(_ plan: ApplyPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Conflicts — must resolve before apply")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.red)
            ForEach(plan.conflicts) { conflict in
                VStack(alignment: .leading, spacing: 4) {
                    Text(conflict.reason.rawValue)
                        .font(.caption.weight(.bold))
                    Text(conflict.detail)
                        .foregroundStyle(.secondary)
                    Text(conflict.operation.originalPath)
                        .font(.caption.monospaced())
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.red.opacity(0.08))
                )
            }
        }
    }
}
