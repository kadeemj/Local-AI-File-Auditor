import AppKit
import AuditorApply
import AuditorEngine
import AuditorModels
import AuditorPolicy
import AuditorReports
import AuditorStore
import Foundation
import Observation
import UniformTypeIdentifiers

/// Root dependency container for the SwiftUI app.
@Observable
@MainActor
final class AppModel {
    enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
        case dashboard
        case findings
        case renames
        case expirations
        case apply
        case history
        case reports

        var id: String { rawValue }

        var title: String {
            switch self {
            case .dashboard: "Dashboard"
            case .findings: "Findings"
            case .renames: "Renames"
            case .expirations: "Expirations"
            case .apply: "Apply"
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
            case .apply: "checkmark.seal"
            case .history: "clock.arrow.circlepath"
            case .reports: "doc.richtext"
            }
        }
    }

    let database: AuditorDatabase
    let engine: AuditorEngine
    let applyEngine: ApplyEngine
    let folders: FolderAccessManager
    let scanSession: ScanSessionModel
    let licenseManager: LicenseManager
    let updater: UpdaterService

    var needsOnboarding: Bool
    var selectedSidebar: SidebarItem = .dashboard
    var selectedPolicyID: String?
    var availablePolicies: [Policy] = []
    var statusMessage: String?
    var applyBatches: [StoredApplyBatch] = []
    var draftPlan: ApplyPlan?
    /// Retained so mock-scan fixture trees stay on disk for apply/undo dogfooding.
    private(set) var mockFixtureRoot: URL?

    init(
        database: AuditorDatabase? = nil,
        engine: AuditorEngine? = nil,
        licenseManager: LicenseManager? = nil,
        updater: UpdaterService? = nil,
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
        self.applyEngine = ApplyEngine(database: db)
        self.folders = FolderAccessManager(database: db)
        self.scanSession = ScanSessionModel()
        self.licenseManager = licenseManager ?? LicenseManager()
        // One updater per process. Tests/previews pass a non-starting instance.
        self.updater = updater ?? UpdaterService(startingUpdater: !skipOnboardingForPreviews)
        self.needsOnboarding = skipOnboardingForPreviews ? false : !AppPreferences.didCompleteOnboarding
        self.selectedPolicyID = AppPreferences.activePolicyID
        self.availablePolicies = Self.loadBundledPolicies()
        reloadHistory()
        Task { await self.licenseManager.validateIfNeeded() }
    }

    var selectedPolicy: Policy? {
        availablePolicies.first { $0.id == selectedPolicyID }
    }

    var canScan: Bool { licenseManager.capabilities.canScan }

    func completeOnboarding(policyID: String?) {
        selectedPolicyID = policyID
        AppPreferences.activePolicyID = policyID
        AppPreferences.didCompleteOnboarding = true
        _ = licenseManager.startTrialIfNeeded()
        needsOnboarding = false
    }

    func setPolicyID(_ policyID: String?) {
        selectedPolicyID = policyID
        AppPreferences.activePolicyID = policyID
    }

    func startScan(useMock: Bool? = nil) {
        guard canScan else {
            statusMessage = licenseManager.status.detail
            return
        }
        let mock = useMock ?? AppPreferences.useMockScan
        statusMessage = nil
        draftPlan = nil

        if mock {
            do {
                if let previous = mockFixtureRoot {
                    try? FileManager.default.removeItem(at: previous)
                }
                let mock = try MockScanStream.make()
                mockFixtureRoot = mock.root
                scanSession.start(events: mock.events, scanID: mock.scanID)
                statusMessage = "Running mock scan on disposable fixture…"
            } catch {
                statusMessage = "Unable to build mock fixture: \(error.localizedDescription)"
            }
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

    func approve(_ finding: Finding) {
        guard finding.decision == .pending || finding.decision == .dismissed else { return }
        scanSession.setDecision(.approved, for: finding.id)
        refreshDraftPlan()
        statusMessage = "Approved — review the Apply tab before changing files."
    }

    func dismiss(_ finding: Finding) {
        guard finding.decision == .pending || finding.decision == .approved else { return }
        scanSession.setDecision(.dismissed, for: finding.id)
        refreshDraftPlan()
        statusMessage = "Finding dismissed."
    }

    func resetDecision(_ finding: Finding) {
        guard finding.decision == .approved || finding.decision == .dismissed else { return }
        scanSession.setDecision(.pending, for: finding.id)
        refreshDraftPlan()
    }

    func refreshDraftPlan() {
        let approved = scanSession.state.actionableApprovedFindings
        draftPlan = approved.isEmpty ? nil : applyEngine.plan(findings: approved)
    }

    func applyApproved() {
        guard licenseManager.capabilities.canApply else {
            statusMessage = "Apply is disabled until your license or trial is active."
            return
        }
        refreshDraftPlan()
        guard let plan = draftPlan else {
            statusMessage = "No approved file changes to apply."
            return
        }
        guard plan.isAppliable else {
            statusMessage = "Resolve \(plan.conflicts.count) conflict\(plan.conflicts.count == 1 ? "" : "s") before applying."
            selectedSidebar = .apply
            return
        }

        let tokens = beginAccessForPaths(plan.operations.flatMap { [$0.originalPath, $0.newPath] })
        defer { tokens.forEach { $0.end() } }

        do {
            let result = try applyEngine.apply(plan)
            scanSession.setDecision(.applied, forFindingIDs: result.findingIDs)
            draftPlan = nil
            reloadHistory()
            statusMessage = "Applied \(result.appliedOperations.count) change\(result.appliedOperations.count == 1 ? "" : "s"). Undo from History."
            selectedSidebar = .history
        } catch {
            statusMessage = "Apply failed: \(error)"
        }
    }

    func undoBatch(_ batch: StoredApplyBatch) {
        guard !batch.isUndone else { return }
        let tokens = beginAccessForPaths(batch.entries.flatMap { [$0.originalPath, $0.newPath] })
        defer { tokens.forEach { $0.end() } }

        do {
            try applyEngine.undo(batchID: batch.batchID)
            let findingIDs = batch.entries.map(\.findingID)
            scanSession.setDecision(.undone, forFindingIDs: findingIDs)
            reloadHistory()
            statusMessage = "Undid batch of \(batch.operationCount) change\(batch.operationCount == 1 ? "" : "s")."
        } catch {
            statusMessage = "Undo failed: \(error)"
        }
    }

    func reloadHistory() {
        applyBatches = (try? database.loadApplyBatches()) ?? []
    }

    func makeAuditReport() -> AuditReport {
        reloadHistory()
        var folderPaths = folders.folders.map(\.path)
        if let mockFixtureRoot {
            folderPaths.append(mockFixtureRoot.path)
        }
        return AuditReport(
            generatedAt: Date(),
            policyName: selectedPolicy?.displayName,
            folderPaths: folderPaths,
            filesScanned: scanSession.summary?.filesScanned,
            totalBytes: scanSession.summary?.totalBytes,
            scanDuration: scanSession.summary?.duration,
            findings: scanSession.findings,
            applyBatches: applyBatches
        )
    }

    func exportCSV() {
        let report = makeAuditReport()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = defaultExportName(extension: "csv")
        panel.canCreateDirectories = true
        panel.title = "Export Findings CSV"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try CSVExporter.write(report, to: url)
            statusMessage = "CSV exported to \(url.lastPathComponent)."
        } catch {
            statusMessage = "CSV export failed: \(error.localizedDescription)"
        }
    }

    func exportPDF() {
        let report = makeAuditReport()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = defaultExportName(extension: "pdf")
        panel.canCreateDirectories = true
        panel.title = "Export Audit PDF"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try PDFReportRenderer.write(report, to: url)
            statusMessage = "PDF exported to \(url.lastPathComponent)."
        } catch {
            statusMessage = "PDF export failed: \(error.localizedDescription)"
        }
    }

    private func defaultExportName(extension fileExtension: String) -> String {
        let day = ReportFormatting.isoDay(Date())
        let policy = selectedPolicyID ?? "universal"
        return "FolderLint-Audit-\(policy)-\(day).\(fileExtension)"
    }

    func previewFile(at path: String) {
        let url = URL(fileURLWithPath: path)
        let tokens = beginAccessForPaths([path])
        // Keep scope alive briefly while Quick Look loads; panel retains the URL.
        QuickLookPresenter.preview(url: url)
        Task {
            try? await Task.sleep(for: .seconds(2))
            tokens.forEach { $0.end() }
        }
    }

    private func beginAccessForPaths(_ paths: [String]) -> [FolderAccessManager.AccessToken] {
        var tokens: [FolderAccessManager.AccessToken] = []
        // Mock fixtures live outside sandbox grants; security-scope begin is best-effort.
        for folder in folders.folders where !folder.isStale {
            let folderPath = folder.path.hasSuffix("/") ? folder.path : folder.path + "/"
            let touchesFolder = paths.contains { path in
                path == folder.path || path.hasPrefix(folderPath)
            }
            guard touchesFolder else { continue }
            if let token = try? folders.beginAccess(to: folder) {
                tokens.append(token)
            }
        }
        return tokens
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
