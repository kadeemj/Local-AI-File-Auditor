import AuditorModels
import AuditorTestSupport
import CryptoKit
import Foundation
import Testing

@testable import AuditorHashing

@Suite("SHA256Hasher")
struct SHA256HasherTests {
    @Test("full hash matches CryptoKit over the same bytes")
    func fullHashVector() async throws {
        let content = Data("FolderLint hash vector".utf8)
        let root = try FixtureBuilder().file("vector.bin", content: content).build()
        defer { try? FileManager.default.removeItem(at: root) }

        let digest = try await SHA256Hasher().fullHash(of: root.appendingPathComponent("vector.bin"))
        let expected = SHA256.hash(data: content).map { String(format: "%02x", $0) }.joined()
        #expect(digest.hex == expected)
    }

    @Test("partial hash reads head+tail: identical ends collide, full hash differs")
    func partialVsFull() async throws {
        // 300 KB files: same first/last 64 KB, different middle byte.
        var a = Data(repeating: 0xAB, count: 300 * 1024)
        var b = a
        b[150 * 1024] = 0xCD

        let root = try FixtureBuilder()
            .file("a.bin", content: a)
            .file("b.bin", content: b)
            .build()
        defer { try? FileManager.default.removeItem(at: root) }

        let hasher = SHA256Hasher()
        let urlA = root.appendingPathComponent("a.bin")
        let urlB = root.appendingPathComponent("b.bin")

        let partialA = try await hasher.partialHash(of: urlA, size: Int64(a.count))
        let partialB = try await hasher.partialHash(of: urlB, size: Int64(b.count))
        #expect(partialA == partialB, "partial hash covers only head+tail+size")

        let fullA = try await hasher.fullHash(of: urlA)
        let fullB = try await hasher.fullHash(of: urlB)
        #expect(fullA != fullB)
    }
}

@Suite("StagedHashPipeline")
struct StagedHashPipelineTests {
    private func records(in root: URL) async throws -> [FileRecord] {
        var out: [FileRecord] = []
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey, .fileResourceIdentifierKey]
        let contents = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: Array(keys))
        for url in contents {
            let values = try url.resourceValues(forKeys: keys)
            out.append(FileRecord(
                path: url.path,
                size: Int64(values.fileSize ?? 0),
                mtimeNanoseconds: Int64((values.contentModificationDate ?? .now).timeIntervalSince1970 * 1e9),
                fileID: values.fileResourceIdentifier.map { "\($0)" }
            ))
        }
        return out
    }

    @Test("groups identical content under different names; leaves unique files alone")
    func groupsDuplicates() async throws {
        let shared = Data("identical signed agreement bytes".utf8)
        let root = try FixtureBuilder()
            .file("Grant Agreement Signed.pdf", content: shared)
            .file("Copy of Grant Agreement.pdf", content: shared)
            .file("Grant Agreement Final.pdf", content: shared)
            .file("unrelated.pdf", content: Data("something else entirely present".utf8))
            .build()
        defer { try? FileManager.default.removeItem(at: root) }

        let groups = try await StagedHashPipeline().duplicateGroups(in: try await records(in: root), rules: SkipRules())

        #expect(groups.count == 1)
        #expect(groups.first?.files.count == 3)
        #expect(groups.first.map { Set($0.files.map(\.filename)) } ==
                ["Grant Agreement Signed.pdf", "Copy of Grant Agreement.pdf", "Grant Agreement Final.pdf"])
    }

    @Test("same size but different content is not a duplicate")
    func sizeCollisionOnly() async throws {
        let root = try FixtureBuilder()
            .file("x.txt", content: Data("AAAAAAAAAA".utf8))
            .file("y.txt", content: Data("BBBBBBBBBB".utf8))
            .build()
        defer { try? FileManager.default.removeItem(at: root) }

        let groups = try await StagedHashPipeline().duplicateGroups(in: try await records(in: root), rules: SkipRules())
        #expect(groups.isEmpty)
    }

    @Test("hardlinks are one file, not duplicates")
    func hardlinks() async throws {
        let root = try FixtureBuilder()
            .file("original.txt", content: Data("hardlinked content here".utf8))
            .build()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.linkItem(
            at: root.appendingPathComponent("original.txt"),
            to: root.appendingPathComponent("link.txt")
        )

        let groups = try await StagedHashPipeline().duplicateGroups(in: try await records(in: root), rules: SkipRules())
        #expect(groups.isEmpty, "a hardlink shares its file ID and must not count as a duplicate")
    }

    @Test("cloud placeholders are never hashed")
    func datalessExcluded() async throws {
        let shared = Data("cloud content".utf8)
        let root = try FixtureBuilder()
            .file("local.txt", content: shared)
            .build()
        defer { try? FileManager.default.removeItem(at: root) }

        var recs = try await records(in: root)
        // Simulate a dataless twin of the same size that must be skipped, not opened.
        recs.append(FileRecord(
            path: root.appendingPathComponent("ghost.txt").path,
            size: Int64(shared.count),
            mtimeNanoseconds: 1,
            isDatalessCloudItem: true
        ))

        let groups = try await StagedHashPipeline().duplicateGroups(in: recs, rules: SkipRules())
        #expect(groups.isEmpty)
    }
}
