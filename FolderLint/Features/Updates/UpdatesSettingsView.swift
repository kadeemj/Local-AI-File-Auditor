import SwiftUI

struct UpdatesSettingsView: View {
    @Environment(AppModel.self) private var appModel

    private var updater: UpdaterService { appModel.updater }

    var body: some View {
        Form {
            Section {
                LabeledContent("Feed") {
                    Text(updater.feedURL?.host() ?? "not configured")
                        .foregroundStyle(.secondary)
                }
                Toggle("Automatically check for updates", isOn: Binding(
                    get: { updater.automaticallyChecksForUpdates },
                    set: { updater.automaticallyChecksForUpdates = $0 }
                ))
                Text("FolderLint asks on first opportunity whether you want automatic checks. Checks contact only the appcast host listed in Privacy / NETWORK_POLICY.md — never your files.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Check for Updates…") {
                    updater.checkForUpdates()
                }
                .disabled(!updater.canCheckForUpdates)
                if let error = updater.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Color.red)
                }
            }

            Section("Release pipeline") {
                Text("Ship builds with `make release VERSION=x.y.z` (archive → exportArchive → notarize → staple → DMG → appcast). Never codesign with --deep.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
