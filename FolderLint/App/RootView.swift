import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        Group {
            if appModel.needsOnboarding {
                OnboardingView()
            } else {
                MainSplitView()
            }
        }
    }
}

struct MainSplitView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var appModel = appModel
        NavigationSplitView {
            List(selection: $appModel.selectedSidebar) {
                ForEach(AppModel.SidebarItem.allCases) { item in
                    Label(item.title, systemImage: item.systemImage)
                        .tag(item)
                }
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 240)
            .safeAreaInset(edge: .bottom) {
                sidebarFooter
            }
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            ToolbarItemGroup {
                if appModel.scanSession.isRunning {
                    ProgressView()
                        .controlSize(.small)
                    Button("Cancel Scan") { appModel.cancelScan() }
                } else {
                    Button("Scan", systemImage: "play.fill") {
                        appModel.startScan()
                    }
                    .help("Scan granted folders with the active policy")
                }
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch appModel.selectedSidebar {
        case .dashboard:
            DashboardView()
        case .findings:
            FindingsListView()
        case .renames:
            RenamesListView()
        case .expirations:
            ExpirationsListView()
        case .apply:
            ApplyReviewView()
        case .history:
            HistoryView()
        case .reports:
            PlaceholderFeatureView(
                title: "Reports",
                systemImage: "doc.richtext",
                message: "CSV and PDF audit reports arrive in Phase 10."
            )
        }
    }

    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            Text(appModel.selectedPolicy?.displayName ?? "Universal rules")
                .font(.caption.weight(.medium))
            Text("\(appModel.folders.folders.count) folder\(appModel.folders.folders.count == 1 ? "" : "s") granted")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
