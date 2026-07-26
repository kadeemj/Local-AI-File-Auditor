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
                if !appModel.canScan {
                    Text(appModel.licenseManager.status.shortLabel)
                        .foregroundStyle(.secondary)
                }
                if appModel.scanSession.isRunning {
                    ProgressView()
                        .controlSize(.small)
                    Button("Cancel Scan") { appModel.cancelScan() }
                } else {
                    Button("Scan", systemImage: "play.fill") {
                        appModel.startScan()
                    }
                    .disabled(!appModel.canScan)
                    .help(appModel.canScan
                          ? "Scan granted folders with the active policy"
                          : appModel.licenseManager.status.detail)
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
            ReportsView()
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
            Text(appModel.licenseManager.status.shortLabel)
                .font(.caption2)
                .foregroundStyle(appModel.canScan ? Color.secondary : Color.orange)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
