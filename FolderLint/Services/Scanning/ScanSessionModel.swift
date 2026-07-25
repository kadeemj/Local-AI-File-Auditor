import AuditorEngine
import AuditorModels
import Foundation
import Observation

/// Consumes an `AsyncStream<ScanEvent>` (mock or live engine) into UI state.
@Observable
@MainActor
final class ScanSessionModel {
    private(set) var state = ScanSessionState()
    private var activeHandle: ScanHandle?
    private var consumeTask: Task<Void, Never>?

    var isRunning: Bool { state.isRunning }
    var findings: [Finding] { state.findings }
    var progress: ScanProgress { state.progress }
    var phase: ScanPhase? { state.phase }
    var summary: ScanSummary? { state.summary }
    var error: ScanError? { state.error }

    func start(events: AsyncStream<ScanEvent>, scanID: UUID = UUID()) {
        cancel()
        state.begin(scanID: scanID)
        consumeTask = Task { [weak self] in
            for await event in events {
                guard let self, !Task.isCancelled else { return }
                self.state.apply(event)
            }
        }
    }

    func start(using handle: ScanHandle) {
        cancel()
        activeHandle = handle
        state.begin(scanID: handle.scanID)
        consumeTask = Task { [weak self] in
            for await event in handle.events {
                guard let self, !Task.isCancelled else { return }
                self.state.apply(event)
            }
        }
    }

    func cancel() {
        activeHandle?.cancel()
        activeHandle = nil
        consumeTask?.cancel()
        consumeTask = nil
        if state.isRunning {
            state.apply(.failed(.cancelled))
        }
    }

    func setDecision(_ decision: DecisionState, for findingID: UUID) {
        state.setDecision(decision, for: findingID)
    }

    func setDecision(_ decision: DecisionState, forFindingIDs ids: [UUID]) {
        state.setDecision(decision, forFindingIDs: ids)
    }
}

enum MockScanStream {
    /// Builds a disposable on-disk fixture so mock findings can be approved and applied.
    static func make(findingCount: Int = 4) throws -> (scanID: UUID, root: URL, events: AsyncStream<ScanEvent>) {
        let scanID = UUID()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("folderlint-mock-\(UUID().uuidString)", isDirectory: true)
        let grants = root.appendingPathComponent("Grants", isDirectory: true)
        let board = root.appendingPathComponent("Board", isDirectory: true)
        let programs = root.appendingPathComponent("Programs", isDirectory: true)
        let finance = root.appendingPathComponent("Finance", isDirectory: true)
        try FileManager.default.createDirectory(at: grants, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: board, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: programs, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: finance, withIntermediateDirectories: true)

        let agreement = grants.appendingPathComponent("Agreement.pdf")
        let agreementCopy = grants.appendingPathComponent("Agreement copy.pdf")
        let scanPDF = board.appendingPathComponent("scan001.pdf")
        let invoice = programs.appendingPathComponent("invoice-april.pdf")
        let financeSibling = finance.appendingPathComponent("2026-04-01_Invoice_Vendor_Paid.pdf")

        let agreementBytes = Data("%PDF-1.4 mock agreement body".utf8)
        try agreementBytes.write(to: agreement)
        try agreementBytes.write(to: agreementCopy)
        try Data("%PDF-1.4 board minutes scan".utf8).write(to: scanPDF)
        try Data("%PDF-1.4 invoice april".utf8).write(to: invoice)
        try Data("%PDF-1.4 paid invoice".utf8).write(to: financeSibling)

        let (stream, continuation) = AsyncStream.makeStream(of: ScanEvent.self)
        Task {
            continuation.yield(.phaseChanged(.enumerating))
            continuation.yield(.progress(ScanProgress(filesSeen: 5, bytesHashed: 0, currentPhase: .enumerating)))
            try? await Task.sleep(for: .milliseconds(30))
            continuation.yield(.phaseChanged(.detecting))

            let samples = mockFindings(scanID: scanID, root: root, count: findingCount)
            for finding in samples {
                try? await Task.sleep(for: .milliseconds(20))
                continuation.yield(.finding(finding))
            }

            continuation.yield(.completed(ScanSummary(
                scanID: scanID,
                filesScanned: 5,
                totalBytes: 200,
                cloudPlaceholders: 0,
                findingsCount: samples.count,
                duration: 0.2
            )))
            continuation.finish()
        }

        return (scanID, root, stream)
    }

    private static func mockFindings(scanID: UUID, root: URL, count: Int) -> [Finding] {
        func ref(_ url: URL) -> FileRef {
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            return FileRef(
                path: url.path,
                size: (attrs?[.size] as? NSNumber)?.int64Value ?? 0,
                modifiedAt: (attrs?[.modificationDate] as? Date) ?? Date()
            )
        }

        let agreement = ref(root.appendingPathComponent("Grants/Agreement.pdf"))
        let agreementCopy = ref(root.appendingPathComponent("Grants/Agreement copy.pdf"))
        let scanPDF = ref(root.appendingPathComponent("Board/scan001.pdf"))
        let invoice = ref(root.appendingPathComponent("Programs/invoice-april.pdf"))
        let financeSibling = ref(root.appendingPathComponent("Finance/2026-04-01_Invoice_Vendor_Paid.pdf"))
        let financeFolder = root.appendingPathComponent("Finance").path

        let templates: [(Severity, String, RecommendedAction, Evidence, [FileRef])] = [
            (
                .high,
                "Two files share identical content.",
                .keepCanonical(keep: agreement, archive: [agreementCopy]),
                .duplicateSet(contentHash: "mock-hash", wastedBytes: agreementCopy.size),
                [agreement, agreementCopy]
            ),
            (
                .medium,
                "Filename does not match the active naming template.",
                .rename(file: scanPDF, proposedName: "2026-03-01_Minutes_Board_Draft.pdf"),
                .filenamePolicy(
                    template: "YYYY-MM-DD_{DocType}_{Org}_{Status}",
                    violations: [.init(ruleID: "genericName", explanation: "Generic scanner name")],
                    proposedName: "2026-03-01_Minutes_Board_Draft.pdf",
                    judge: .rules
                ),
                [scanPDF]
            ),
            (
                .high,
                "Contract auto-renews; action date is approaching.",
                .scheduleReminder(actionDate: Date().addingTimeInterval(86400 * 14), note: "Review renewal"),
                .expiration(
                    kind: .autoRenewal,
                    detectedDate: Date().addingTimeInterval(86400 * 90),
                    actionDate: Date().addingTimeInterval(86400 * 14),
                    autoRenews: true,
                    noticePeriodDays: 60,
                    party: "Acme Vendor",
                    contextSnippet: "…shall automatically renew unless either party provides sixty (60) days written notice…",
                    judge: .rules
                ),
                [agreement]
            ),
            (
                .medium,
                "Document looks closer to Finance than its current folder.",
                .move(file: invoice, destinationFolder: financeFolder),
                .misfiled(
                    currentFolder: root.appendingPathComponent("Programs").path,
                    suggestedFolder: financeFolder,
                    ownFolderSimilarity: 0.21,
                    suggestedFolderSimilarity: 0.78,
                    nearestFiles: [financeSibling],
                    explanationJudge: .rules
                ),
                [invoice]
            ),
        ]

        return (0..<min(count, templates.count)).map { index in
            let sample = templates[index]
            return Finding(
                detectorID: "mock",
                kind: "mock.finding.\(index)",
                severity: sample.0,
                files: sample.4,
                evidence: sample.3,
                explanation: sample.1,
                recommendation: sample.2,
                confidence: 0.9,
                stableKeyMaterial: "mock-\(index)-\(root.lastPathComponent)",
                scanID: scanID
            )
        }
    }
}
