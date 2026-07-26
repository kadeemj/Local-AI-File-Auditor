import AuditorPolicy
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var appModel
    @State private var selectedPolicyID: String?
    @State private var useMockScan = AppPreferences.useMockScan

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
            foldersTab
                .tabItem { Label("Folders", systemImage: "folder") }
            policyTab
                .tabItem { Label("Policy", systemImage: "list.clipboard") }
            LicenseSettingsView()
                .environment(appModel)
                .tabItem { Label("License", systemImage: "key") }
            PlaceholderFeatureView(
                title: "Updates",
                systemImage: "arrow.triangle.2.circlepath",
                message: "Sparkle update checks arrive in Phase 12."
            )
            .tabItem { Label("Updates", systemImage: "arrow.triangle.2.circlepath") }
            privacyTab
                .tabItem { Label("Privacy", systemImage: "hand.raised") }
        }
        .padding(20)
        .frame(width: 560, height: 420)
        .onAppear {
            selectedPolicyID = appModel.selectedPolicyID
        }
    }

    private var generalTab: some View {
        Form {
            Toggle("Use mock scan stream", isOn: $useMockScan)
                .onChange(of: useMockScan) { _, newValue in
                    AppPreferences.useMockScan = newValue
                }
            Text("Mock scans drive the dashboard from a deterministic AsyncStream without touching disk.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Reset onboarding") {
                AppPreferences.didCompleteOnboarding = false
                appModel.needsOnboarding = true
            }
        }
    }

    private var foldersTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Granted folders")
                    .font(.headline)
                Spacer()
                Button("Add Folder…") {
                    _ = appModel.folders.presentFolderPicker()
                }
            }

            if appModel.folders.folders.isEmpty {
                Text("No folders granted. FolderLint cannot read anything you have not selected.")
                    .foregroundStyle(.secondary)
            } else {
                List {
                    ForEach(appModel.folders.folders) { folder in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(folder.displayName).fontWeight(.medium)
                                    if folder.isStale {
                                        Text("Stale")
                                            .font(.caption2.weight(.bold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.orange.opacity(0.2), in: Capsule())
                                    }
                                }
                                Text(folder.path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if folder.isStale {
                                Button("Restore…") {
                                    _ = appModel.folders.regrant(folder)
                                }
                            }
                            Button("Remove", role: .destructive) {
                                appModel.folders.removeFolder(folder)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }

            if let error = appModel.folders.lastError {
                Text(error).foregroundStyle(.red).font(.caption)
            }
        }
    }

    private var policyTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Active policy")
                    .font(.headline)
                PolicyPicker(
                    selectedPolicyID: $selectedPolicyID,
                    policies: appModel.availablePolicies,
                    includeNone: true
                )
                .onChange(of: selectedPolicyID) { _, newValue in
                    appModel.setPolicyID(newValue)
                }
            }
        }
    }

    private var privacyTab: some View {
        Form {
            Text("Network policy")
                .font(.headline)
            Text("FolderLint may contact only api.lemonsqueezy.com (licensing) and the Sparkle appcast host (updates). There is no telemetry or crash SDK.")
                .foregroundStyle(.secondary)
            if let last = appModel.licenseManager.lastNetworkCallAt {
                LabeledContent("Last license network call") {
                    Text(last.formatted(date: .abbreviated, time: .shortened))
                }
            } else {
                Text("No license network calls yet.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Text("See docs/NETWORK_POLICY.md in the repository for the auditable claim.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}
