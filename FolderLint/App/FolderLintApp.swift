import SwiftUI

@main
struct FolderLintApp: App {
    @State private var appModel = AppModel()

    var body: some Scene {
        Window("FolderLint", id: "main") {
            RootView()
                .environment(appModel)
                .frame(minWidth: 900, minHeight: 560)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Scan") {
                Button("Scan Folders") {
                    appModel.startScan()
                }
                .keyboardShortcut("r", modifiers: [.command])
                Button("Mock Scan") {
                    appModel.startScan(useMock: true)
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                Divider()
                Button("Cancel Scan") {
                    appModel.cancelScan()
                }
                .keyboardShortcut(".", modifiers: [.command])
            }
        }

        Settings {
            SettingsView()
                .environment(appModel)
        }
    }
}
