import AuditorModels
import Foundation

/// Enumerates user-selected roots and yields `FileRecord` batches.
/// Full implementation lands in Phase 1: `FileManager.enumerator` with prefetched
/// resource keys, skip rules, hardlink dedupe, and the cloud-mode dataless gate.
public struct FileCrawler: Sendable {
    public init() {}

    public func crawl(roots: [URL], rules: SkipRules) -> AsyncThrowingStream<[FileRecord], Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: Unimplemented.phase1)
        }
    }
}

enum Unimplemented: Error {
    case phase1
}
