import AuditorPolicy
import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var appModel
    @State private var step: Step = .privacy
    @State private var selectedPolicyID: String? = "nonprofit"

    private enum Step: Int {
        case privacy
        case folder
        case policy
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .frame(minWidth: 640, minHeight: 420)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("FolderLint")
                    .font(.title2.weight(.semibold))
                Text(stepTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("Step \(step.rawValue + 1) of 3")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(20)
    }

    private var stepTitle: String {
        switch step {
        case .privacy: "Private by design"
        case .folder: "Choose a folder to audit"
        case .policy: "Pick a governance policy"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .privacy:
            OnboardingPrivacyPane()
        case .folder:
            OnboardingFolderPane()
        case .policy:
            OnboardingPolicyPane(selectedPolicyID: $selectedPolicyID, policies: appModel.availablePolicies)
        }
    }

    private var footer: some View {
        HStack {
            if step != .privacy {
                Button("Back") {
                    withAnimation { step = Step(rawValue: step.rawValue - 1) ?? .privacy }
                }
            }
            Spacer()
            Button(primaryTitle) {
                advance()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!canAdvance)
        }
        .padding(20)
    }

    private var primaryTitle: String {
        switch step {
        case .privacy: "Continue"
        case .folder: "Continue"
        case .policy: "Start FolderLint"
        }
    }

    private var canAdvance: Bool {
        switch step {
        case .privacy, .policy:
            true
        case .folder:
            appModel.folders.hasUsableFolder
        }
    }

    private func advance() {
        switch step {
        case .privacy:
            withAnimation { step = .folder }
        case .folder:
            withAnimation { step = .policy }
        case .policy:
            appModel.completeOnboarding(policyID: selectedPolicyID)
        }
    }
}

private struct OnboardingPrivacyPane: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Grammarly for your files and folders")
                .font(.title3.weight(.semibold))
            Text("FolderLint audits the folders you already have. It does not replace Finder, never imports files into a proprietary library, and never deletes anything.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 12) {
                privacyRow("lock.shield", "All analysis runs on this Mac")
                privacyRow("hand.raised", "Only folders you select are readable — enforced by App Sandbox")
                privacyRow("network.slash", "Network access is limited to license checks and updates")
                privacyRow("eye", "Every recommendation includes evidence and an explanation")
            }
            .padding(.top, 8)
        }
        .padding(28)
        .frame(maxWidth: 520, alignment: .leading)
    }

    private func privacyRow(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .frame(width: 20)
                .foregroundStyle(Color.accentColor)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct OnboardingFolderPane: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Grant folder access")
                .font(.title3.weight(.semibold))
            Text("macOS will only let FolderLint read folders you pick here. Grants persist across relaunches via security-scoped bookmarks.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                _ = appModel.folders.presentFolderPicker()
            } label: {
                Label("Select Folder…", systemImage: "folder.badge.plus")
            }
            .controlSize(.large)

            if appModel.folders.folders.isEmpty {
                Text("No folders granted yet.")
                    .foregroundStyle(.tertiary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(appModel.folders.folders) { folder in
                        HStack {
                            Image(systemName: folder.isStale ? "exclamationmark.triangle" : "checkmark.circle.fill")
                                .foregroundStyle(folder.isStale ? Color.orange : Color.green)
                            VStack(alignment: .leading) {
                                Text(folder.displayName).fontWeight(.medium)
                                Text(folder.path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                .padding(.top, 4)
            }

            if let error = appModel.folders.lastError {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
        .padding(28)
        .frame(maxWidth: 560, alignment: .leading)
    }
}

private struct OnboardingPolicyPane: View {
    @Binding var selectedPolicyID: String?
    let policies: [Policy]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose a policy pack")
                .font(.title3.weight(.semibold))
            Text("Policies supply a naming template and folder taxonomy. You can change this later in Settings.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            PolicyPicker(selectedPolicyID: $selectedPolicyID, policies: policies, includeNone: true)
        }
        .padding(28)
        .frame(maxWidth: 560, alignment: .leading)
    }
}
