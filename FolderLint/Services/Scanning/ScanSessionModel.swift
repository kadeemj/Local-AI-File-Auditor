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
}

enum MockScanStream {
    /// Deterministic stream for UI development and tests before/without a real folder grant.
    static func make(findingCount: Int = 5) -> (scanID: UUID, events: AsyncStream<ScanEvent>) {
        let scanID = UUID()
        let (stream, continuation) = AsyncStream.makeStream(of: ScanEvent.self)

        Task {
            continuation.yield(.phaseChanged(.enumerating))
            for filesSeen in [10, 40, 80] {
                try? await Task.sleep(for: .milliseconds(40))
                continuation.yield(.progress(ScanProgress(
                    filesSeen: filesSeen,
                    bytesHashed: 0,
                    currentPhase: .enumerating
                )))
            }

            continuation.yield(.phaseChanged(.hashing))
            continuation.yield(.progress(ScanProgress(
                filesSeen: 80,
                bytesHashed: 12_000_000,
                currentPhase: .hashing
            )))
            try? await Task.sleep(for: .milliseconds(40))

            continuation.yield(.phaseChanged(.detecting))
            let samples = mockFindings(scanID: scanID, count: findingCount)
            for finding in samples {
                try? await Task.sleep(for: .milliseconds(20))
                continuation.yield(.finding(finding))
            }

            continuation.yield(.completed(ScanSummary(
                scanID: scanID,
                filesScanned: 80,
                totalBytes: 12_000_000,
                cloudPlaceholders: 2,
                findingsCount: samples.count,
                duration: 0.35
            )))
            continuation.finish()
        }

        return (scanID, stream)
    }

    private static func mockFindings(scanID: UUID, count: Int) -> [Finding] {
        let templates: [(Severity, String, RecommendedAction, Evidence)] = [
            (
                .high,
                "Two files share identical content.",
                .keepCanonical(
                    keep: FileRef(path: "/Grants/Agreement.pdf", size: 100, modifiedAt: Date()),
                    archive: [FileRef(path: "/Grants/Agreement copy.pdf", size: 100, modifiedAt: Date())]
                ),
                .duplicateSet(contentHash: "abc", wastedBytes: 100)
            ),
            (
                .medium,
                "Filename does not match the active naming template.",
                .rename(
                    file: FileRef(path: "/Board/scan001.pdf", size: 50, modifiedAt: Date()),
                    proposedName: "2026-03-01_Minutes_Board_Draft.pdf"
                ),
                .filenamePolicy(
                    template: "YYYY-MM-DD_{DocType}_{Org}_{Status}",
                    violations: [.init(ruleID: "genericName", explanation: "Generic scanner name")],
                    proposedName: "2026-03-01_Minutes_Board_Draft.pdf",
                    judge: .rules
                )
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
                    contextSnippet: "…shall automatically renew for successive one-year terms unless either party provides sixty (60) days written notice…",
                    judge: .rules
                )
            ),
            (
                .medium,
                "Document looks closer to Finance than its current folder.",
                .move(
                    file: FileRef(path: "/Programs/invoice-april.pdf", size: 40, modifiedAt: Date()),
                    destinationFolder: "/Finance"
                ),
                .misfiled(
                    currentFolder: "/Programs",
                    suggestedFolder: "/Finance",
                    ownFolderSimilarity: 0.21,
                    suggestedFolderSimilarity: 0.78,
                    nearestFiles: [
                        FileRef(path: "/Finance/2026-04-01_Invoice_Vendor_Paid.pdf", size: 40, modifiedAt: Date()),
                    ],
                    explanationJudge: .rules
                )
            ),
            (
                .low,
                "Version family detected; keep the highest-ranked copy.",
                .keepCanonical(
                    keep: FileRef(path: "/Policies/Handbook_v3_FINAL.pdf", size: 200, modifiedAt: Date()),
                    archive: [FileRef(path: "/Policies/Handbook_v2.pdf", size: 180, modifiedAt: Date())]
                ),
                .versionChain(
                    rankedFilenames: ["Handbook_v3_FINAL.pdf", "Handbook_v2.pdf"],
                    stem: "Handbook",
                    signals: ["explicit version", "status word"],
                    confidence: 0.91,
                    judge: .rules
                )
            ),
        ]

        return (0..<count).map { index in
            let sample = templates[index % templates.count]
            let path = "/Mock/file-\(index).pdf"
            let file = FileRef(path: path, size: Int64(100 + index), modifiedAt: Date())
            return Finding(
                detectorID: "mock",
                kind: "mock.finding.\(index)",
                severity: sample.0,
                files: [file],
                evidence: sample.3,
                explanation: sample.1,
                recommendation: sample.2,
                confidence: 0.9,
                stableKeyMaterial: "mock-\(index)",
                scanID: scanID
            )
        }
    }
}
