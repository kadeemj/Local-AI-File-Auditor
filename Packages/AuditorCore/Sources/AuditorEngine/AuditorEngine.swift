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

/// Orchestrates crawl → hash/extract → detect, streaming `ScanEvent`s to the
/// app UI and CLI. Persistence of findings/cache is wired in later phases;
/// extracted text is never written to disk.
public actor AuditorEngine {
    private let database: AuditorDatabase
    private let detectors: [any Detector]

    public init(database: AuditorDatabase, detectors: [any Detector]? = nil) {
        self.database = database
        self.detectors = detectors ?? ScanPipeline.defaultDetectors
    }

    /// Convenience for UI/tests that do not need a durable database yet.
    public static func makeEphemeral(detectors: [any Detector]? = nil) throws -> AuditorEngine {
        try AuditorEngine(database: .inMemory(), detectors: detectors)
    }

    public func startScan(_ config: ScanConfiguration) -> ScanHandle {
        let scanID = UUID()
        let (stream, continuation) = AsyncStream.makeStream(of: ScanEvent.self)
        let state = ScanCancellation()
        let detectors = self.detectors

        let task = Task {
            await ScanPipeline.run(
                config: config,
                scanID: scanID,
                detectors: detectors,
                yield: { event in
                    continuation.yield(event)
                },
                isCancelled: { state.isCancelled || Task.isCancelled }
            )
            continuation.finish()
        }

        continuation.onTermination = { _ in
            state.cancel()
            task.cancel()
        }

        return ScanHandle(scanID: scanID, events: stream) {
            state.cancel()
            task.cancel()
        }
    }
}

private final class ScanCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}
