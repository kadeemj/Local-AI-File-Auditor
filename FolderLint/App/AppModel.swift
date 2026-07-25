import AuditorEngine
import AuditorModels
import AuditorPolicy
import AuditorStore
import Foundation
import Observation

/// Root dependency container for the SwiftUI app.
@Observable
@MainActor
final class AppModel {
    enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
        case dashboard
        case findings
        case renames
        case expirations
        case history
        case reports

        var id: String { rawValue }

        var title: String {
            switch self {
            case .dashboard: "Dashboard"
            case .findings: "Findings"
            case .renames: "Renames"
            case .expirations: "Expirations"
            case .history: "History"
            case .reports: "Reports"
            }
        }

        var systemImage: String {
            switch self {
            case .dashboard: "square.grid.2x2"
            case .findings: "list.bullet.rectangle"
            case .renames: "pencil"
            case .expirations: "calendar.badge.exclamationmark"
            case .history: "clock.arrow.circlepath"
            case .reports: "doc.richtext"
            }
        }
    }

    let database: AuditorDatabase
    let engine: AuditorEngine
    let folders: FolderAccessManager
    let scanSession: ScanSessionModel

    var needsOnboarding: Bool
    var selectedSidebar: SidebarItem = .dashboard
    var selectedPolicyID: String?
    var availablePolicies: [Policy] = []
    var statusMessage: String?

    init(
        database: AuditorDatabase? = nil,
        engine: AuditorEngine? = nil,
        skipOnboardingForPreviews: Bool = false
    ) {
        let db: AuditorDatabase
        if let database {
            db = database
        } else {
            db = (try? Self.openApplicationDatabase()) ?? (try! AuditorDatabase.inMemory())
        }
        self.database = db
        self.engine = engine ?? AuditorEngine(database: db)
        self.folders = FolderAccessManager(database: db)
        self.scanSession = ScanSessionModel()
        self.needsOnboarding = skipOnboardingForPreviews ? false : !AppPreferences.didCompleteOnboarding
        self.selectedPolicyID = AppPreferences.activePolicyID
        self.availablePolicies = Self.loadBundledPolicies()
    }

    var selectedPolicy: Policy? {
        availablePolicies.first { $0.id == selectedPolicyID }
    }

    func completeOnboarding(policyID: String?) {
        selectedPolicyID = policyID
        AppPreferences.activePolicyID = policyID
        AppPreferences.didCompleteOnboarding = true
        needsOnboarding = false
    }

    func setPolicyID(_ policyID: String?) {
        selectedPolicyID = policyID
        AppPreferences.activePolicyID = policyID
    }

    func startScan(useMock: Bool? = nil) {
        let mock = useMock ?? AppPreferences.useMockScan
        statusMessage = nil

        if mock {
            let mock = MockScanStream.make()
            scanSession.start(events: mock.events, scanID: mock.scanID)
            statusMessage = "Running mock scan…"
            return
        }

        let usable = folders.folders.filter { !$0.isStale }
        guard !usable.isEmpty else {
            statusMessage = "Add a folder before scanning."
            return
        }

        var tokens: [FolderAccessManager.AccessToken] = []
        var rootPaths: [String] = []
        do {
            for folder in usable {
                let token = try folders.beginAccess(to: folder)
                tokens.append(token)
                rootPaths.append(token.url.path)
            }
        } catch SecurityScopedBookmark.BookmarkError.staleNeedsRegrant {
            tokens.forEach { $0.end() }
            statusMessage = "A folder grant is stale. Restore access from Settings → Folders."
            return
        } catch {
            tokens.forEach { $0.end() }
            statusMessage = "Unable to open a granted folder: \(error.localizedDescription)"
            return
        }

        var rules = SkipRules()
        if let mode = usable.first?.cloudMode {
            rules.cloudMode = mode
        }

        Task {
            let handle = await engine.startScan(ScanConfiguration(
                rootPaths: rootPaths,
                skipRules: rules,
                policyID: selectedPolicyID
            ))
            scanSession.start(using: handle)
            statusMessage = "Scanning \(rootPaths.count) folder\(rootPaths.count == 1 ? "" : "s")…"

            // Keep security scopes alive for the duration of the scan.
            while scanSession.isRunning {
                try? await Task.sleep(for: .milliseconds(200))
            }
            tokens.forEach { $0.end() }
            if let error = scanSession.error {
                statusMessage = "Scan failed: \(String(describing: error))"
            } else if let summary = scanSession.summary {
                statusMessage = "Scan complete — \(summary.findingsCount) finding\(summary.findingsCount == 1 ? "" : "s")."
            }
        }
    }

    func cancelScan() {
        scanSession.cancel()
        statusMessage = "Scan cancelled."
    }

    private static func openApplicationDatabase() throws -> AuditorDatabase {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("FolderLint", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return try AuditorDatabase(path: support.appendingPathComponent("auditor.sqlite").path)
    }

    private static func loadBundledPolicies() -> [Policy] {
        let loader = PolicyLoader()
        return ["nonprofit", "small-business"].compactMap { id in
            try? loader.loadBundledPolicy(id: id)
        }
    }
}
