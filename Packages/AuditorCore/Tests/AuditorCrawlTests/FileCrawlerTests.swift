import AuditorModels
import AuditorTestSupport
import Foundation
import Testing

@testable import AuditorCrawl

@Suite("FileCrawler")
struct FileCrawlerTests {
    private func collect(root: URL, rules: SkipRules = SkipRules()) async throws -> [FileRecord] {
        var records: [FileRecord] = []
        for try await batch in FileCrawler().crawl(roots: [root], rules: rules) {
            records.append(contentsOf: batch)
        }
        return records
    }

    @Test("yields every regular file with size and mtime")
    func yieldsRegularFiles() async throws {
        let root = try FixtureBuilder()
            .file("a.pdf", size: 100)
            .file("sub/b.docx", size: 200)
            .file("sub/deep/c.txt", size: 300)
            .build()
        defer { try? FileManager.default.removeItem(at: root) }

        let records = try await collect(root: root)

        #expect(records.count == 3)
        let byName = Dictionary(uniqueKeysWithValues: records.map { ($0.filename, $0) })
        #expect(byName["a.pdf"]?.size == 100)
        #expect(byName["b.docx"]?.size == 200)
        #expect(byName["c.txt"]?.size == 300)
        #expect(records.allSatisfy { $0.mtimeNanoseconds > 0 })
        #expect(records.allSatisfy { $0.fileID != nil })
    }

    @Test("skips hidden files when configured, includes them otherwise")
    func hiddenFiles() async throws {
        let root = try FixtureBuilder()
            .file("visible.txt")
            .file(".hidden.txt")
            .build()
        defer { try? FileManager.default.removeItem(at: root) }

        let skipped = try await collect(root: root, rules: SkipRules(skipHidden: true))
        #expect(skipped.map(\.filename) == ["visible.txt"])

        let included = try await collect(root: root, rules: SkipRules(skipHidden: false))
        #expect(Set(included.map(\.filename)) == ["visible.txt", ".hidden.txt"])
    }

    @Test("skips denylisted directories entirely")
    func denylist() async throws {
        let root = try FixtureBuilder()
            .file("keep.txt")
            .file("node_modules/pkg/index.js")
            .file(".git/config")
            .build()
        defer { try? FileManager.default.removeItem(at: root) }

        // .git is both hidden and denylisted; disable hidden-skipping to prove
        // the denylist alone prunes it.
        let records = try await collect(root: root, rules: SkipRules(skipHidden: false))
        #expect(records.map(\.filename) == ["keep.txt"])
    }

    @Test("does not descend into packages")
    func packages() async throws {
        let root = try FixtureBuilder()
            .file("doc.pdf")
            .file("Fake.app/Contents/MacOS/binary")
            .build()
        defer { try? FileManager.default.removeItem(at: root) }

        let records = try await collect(root: root)
        #expect(records.map(\.filename) == ["doc.pdf"])
    }

    @Test("respects minFileSize (zero-byte files excluded by default)")
    func minSize() async throws {
        let root = try FixtureBuilder()
            .file("empty.txt", size: 0)
            .file("full.txt", size: 5)
            .build()
        defer { try? FileManager.default.removeItem(at: root) }

        let records = try await collect(root: root)
        #expect(records.map(\.filename) == ["full.txt"])
    }

    @Test("does not follow symlinks")
    func symlinks() async throws {
        let root = try FixtureBuilder()
            .file("real.txt", size: 10)
            .build()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("link.txt"),
            withDestinationURL: root.appendingPathComponent("real.txt")
        )

        let records = try await collect(root: root)
        #expect(records.map(\.filename) == ["real.txt"])
    }

    @Test("large trees stream in batches without loss")
    func batching() async throws {
        var builder = FixtureBuilder()
        for i in 0..<1_200 {
            builder = builder.file("dir\(i % 7)/file\(i).txt", size: 8)
        }
        let root = try builder.build()
        defer { try? FileManager.default.removeItem(at: root) }

        var batchCount = 0
        var total = 0
        for try await batch in FileCrawler().crawl(roots: [root], rules: SkipRules()) {
            batchCount += 1
            total += batch.count
        }

        #expect(total == 1_200)
        #expect(batchCount >= 2, "1200 files should arrive in multiple batches")
    }

    @Test("unreadable root throws rootUnreadable")
    func unreadableRoot() async throws {
        let missing = URL(fileURLWithPath: "/nonexistent/folderlint-test-\(UUID().uuidString)")
        await #expect(throws: ScanError.self) {
            _ = try await collect(root: missing)
        }
    }
}
