import Foundation
import Testing
@testable import FolderLint

@Suite("SecurityScopedBookmark")
struct SecurityScopedBookmarkTests {
    @Test("creates and resolves an app-scoped bookmark for a temp folder")
    func roundTrip() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("folderlint-bookmark-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let data = try SecurityScopedBookmark.create(from: root)
        #expect(!data.isEmpty)

        let resolution = try SecurityScopedBookmark.resolve(data)
        #expect(resolution.url.standardizedFileURL.path == root.standardizedFileURL.path)
    }
}

@Suite("ScanSessionModel")
@MainActor
struct ScanSessionModelTests {
    @Test("consumes a mock AsyncStream into findings")
    func consumesMockStream() async {
        let model = ScanSessionModel()
        let mock = MockScanStream.make(findingCount: 3)
        model.start(events: mock.events, scanID: mock.scanID)

        for _ in 0..<50 {
            if !model.isRunning, model.summary != nil { break }
            try? await Task.sleep(for: .milliseconds(40))
        }

        #expect(model.isRunning == false)
        #expect(model.findings.count == 3)
        #expect(model.summary?.findingsCount == 3)
        #expect(model.error == nil)
    }
}
