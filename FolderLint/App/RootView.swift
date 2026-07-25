import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("FolderLint")
                .font(.largeTitle.bold())
            Text("A private document-governance auditor.\nYour files never leave this Mac.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Text("Scaffold build — onboarding and scanning arrive in Phase 8.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(40)
    }
}

struct SettingsView: View {
    var body: some View {
        Form {
            Text("Settings arrive in Phase 8.")
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 420, height: 200)
    }
}
