import AuditorApply
import AuditorCrawl
import AuditorDetect
import AuditorModels
import AuditorStore
import Foundation

public struct ScanHandle: Sendable {
    public let scanID: UUID
    public let events: AsyncStream<ScanEvent>
    private let onCancel: @Sendable () -> Void

    public init(scanID: UUID, events: AsyncStream<ScanEvent>, onCancel: @escaping @Sendable () -> Void) {
        self.scanID = scanID
        self.events = events
        self.onCancel = onCancel
    }

    public func cancel() { onCancel() }
}

/// Orchestrates crawl → hash/extract → detect → persist, streaming ScanEvents.
/// Full pipeline lands across Phases 1–7; this scaffold establishes the surface
/// the app and CLI program against.
public actor AuditorEngine {
    private let database: AuditorDatabase
    private let detectors: [any Detector]

    public init(database: AuditorDatabase, detectors: [any Detector]) {
        self.database = database
        self.detectors = detectors
    }

    public func startScan(_ config: ScanConfiguration) -> ScanHandle {
        let scanID = UUID()
        let (stream, continuation) = AsyncStream.makeStream(of: ScanEvent.self)
        continuation.yield(.failed(.storageFailure(message: "scan pipeline not yet implemented (Phase 1)")))
        continuation.finish()
        return ScanHandle(scanID: scanID, events: stream, onCancel: {})
    }
}
