import SwiftUI

@main
struct FolderLintApp: App {
    @State private var appModel = AppModel()

    var body: some Scene {
        Window("FolderLint", id: "main") {
            RootView()
                .environment(appModel)
                .frame(minWidth: 800, minHeight: 520)
        }

        Settings {
            SettingsView()
                .environment(appModel)
        }
    }
}
