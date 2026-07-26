import SwiftUI

struct LicenseSettingsView: View {
    @Environment(AppModel.self) private var appModel
    @State private var licenseKey = ""
    @State private var useMockLicensing = AppPreferences.useMockLicensing

    private var manager: LicenseManager { appModel.licenseManager }

    var body: some View {
        Form {
            Section {
                LabeledContent("Status") {
                    Text(manager.status.shortLabel)
                        .foregroundStyle(manager.status.canScan ? Color.primary : Color.red)
                }
                Text(manager.status.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let email = manager.status.snapshot?.customerEmail {
                    LabeledContent("Account", value: email)
                }
                if let limit = manager.status.snapshot?.activationLimit {
                    LabeledContent("Activation limit", value: "\(manager.status.snapshot?.activationUsage ?? 0) / \(limit)")
                }
            }

            Section("Activate") {
                SecureField("License key", text: $licenseKey)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Activate") {
                        Task { await manager.activate(licenseKey: licenseKey) }
                    }
                    .disabled(manager.isBusy || licenseKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.defaultAction)

                    if manager.status.phase == .licensed || manager.status.phase == .grace {
                        Button("Deactivate This Mac", role: .destructive) {
                            Task { await manager.deactivate() }
                        }
                        .disabled(manager.isBusy)
                    }

                    Button("Validate Now") {
                        Task { await manager.validateIfNeeded(force: true) }
                    }
                    .disabled(manager.isBusy || manager.status.snapshot == nil)
                }
                if AppPreferences.useMockLicensing {
                    Text("Mock licensing is on. Try key `TEST-PRO` or `TEST-PACK-NONPROFIT`.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Trial") {
                Text("New installs get a \(TrialClock.trialLengthDays)-day offline trial when onboarding completes. Licensed copies keep working offline for \(TrialClock.offlineGraceDays) days between validations.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if manager.status.phase == .trialExpired || manager.status.phase == .expired {
                    Text("Scan and Apply are disabled. Past findings, history, and reports remain available.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            #if DEBUG
            Section("Developer") {
                Toggle("Use mock Lemon Squeezy backend", isOn: $useMockLicensing)
                    .onChange(of: useMockLicensing) { _, newValue in
                        AppPreferences.useMockLicensing = newValue
                    }
                Text("Restart the app after toggling the backend.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            #endif

            if let error = manager.lastError {
                Section {
                    Text(error)
                        .foregroundStyle(Color.red)
                        .font(.caption)
                }
            }
        }
    }
}
