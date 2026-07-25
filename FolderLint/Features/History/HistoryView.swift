import AuditorStore
import SwiftUI

struct HistoryView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Applied batches")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Refresh") { appModel.reloadHistory() }
            }
            .padding(20)

            if appModel.applyBatches.isEmpty {
                ContentUnavailableView(
                    "No Applied Changes",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("After you apply approved findings, batches appear here with per-batch Undo.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(appModel.applyBatches) { batch in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(batch.performedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.headline)
                                Spacer()
                                if batch.isUndone {
                                    Text("Undone")
                                        .font(.caption.weight(.bold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                                } else {
                                    Button("Undo") {
                                        appModel.undoBatch(batch)
                                    }
                                }
                            }
                            Text("\(batch.operationCount) operation\(batch.operationCount == 1 ? "" : "s")")
                                .foregroundStyle(.secondary)
                            ForEach(batch.entries) { entry in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.operation.uppercased())
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(.secondary)
                                    Text("\(entry.originalPath) → \(entry.newPath)")
                                        .font(.caption.monospaced())
                                        .textSelection(.enabled)
                                        .lineLimit(2)
                                }
                                .padding(.top, 2)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
                .listStyle(.inset)
            }

            if let status = appModel.statusMessage {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .navigationTitle("History")
        .onAppear { appModel.reloadHistory() }
    }
}
