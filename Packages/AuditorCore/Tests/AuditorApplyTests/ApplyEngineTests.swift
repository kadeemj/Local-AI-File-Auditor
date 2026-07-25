import AuditorModels
import AuditorStore
import AuditorTestSupport
import Foundation
import Testing

@testable import AuditorApply

@Suite("ApplyEngine")
struct ApplyEngineTests {
    @Test("plan/apply/undo round-trip restores byte-identical tree")
    func roundTrip() throws {
        let root = try FixtureBuilder()
            .file("keep.txt", content: Data("canonical".utf8))
            .file("extra.txt", content: Data("duplicate".utf8))
            .file("scan001.pdf", content: Data("%PDF-rename".utf8))
            .build()
        defer { try? FileManager.default.removeItem(at: root) }

        let db = try AuditorDatabase.inMemory()
        let engine = ApplyEngine(database: db)

        let keep = fileRef(root.appendingPathComponent("keep.txt"))
        let extra = fileRef(root.appendingPathComponent("extra.txt"))
        let rename = fileRef(root.appendingPathComponent("scan001.pdf"))

        let findings = [
            Finding(
                detectorID: "dup",
                kind: "core.duplicateSet.exact",
                severity: .medium,
                files: [keep, extra],
                evidence: .duplicateSet(contentHash: "abc", wastedBytes: 9),
                explanation: "Duplicate set",
                recommendation: .keepCanonical(keep: keep, archive: [extra]),
                stableKeyMaterial: "abc",
                scanID: UUID()
            ),
            Finding(
                detectorID: "rename",
                kind: "core.filenamePolicy.generic",
                severity: .medium,
                files: [rename],
                evidence: .note("generic"),
                explanation: "Generic name",
                recommendation: .rename(file: rename, proposedName: "2026-01-01_Report_Org_Final.pdf"),
                stableKeyMaterial: "rename",
                scanID: UUID()
            ),
        ]

        let plan = engine.plan(findings: findings)
        #expect(plan.conflicts.isEmpty)
        #expect(plan.operations.count == 2)
        #expect(plan.isAppliable)

        let result = try engine.apply(plan)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("_Archive/extra.txt").path))
        #expect(!FileManager.default.fileExists(atPath: extra.path))
        #expect(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("2026-01-01_Report_Org_Final.pdf").path
        ))
        #expect(!FileManager.default.fileExists(atPath: rename.path))

        let batches = try db.loadApplyBatches()
        #expect(batches.count == 1)
        #expect(batches[0].batchID == result.batchID)
        #expect(batches[0].isUndone == false)

        try engine.undo(batchID: result.batchID)

        #expect(FileManager.default.fileExists(atPath: extra.path))
        #expect(FileManager.default.fileExists(atPath: rename.path))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("_Archive/extra.txt").path))
        #expect(try Data(contentsOf: URL(fileURLWithPath: extra.path)) == Data("duplicate".utf8))
        #expect(try Data(contentsOf: URL(fileURLWithPath: rename.path)) == Data("%PDF-rename".utf8))

        let undone = try db.loadApplyBatches()
        #expect(undone[0].isUndone)
    }

    @Test("destination collision is a planning conflict")
    func destinationCollision() throws {
        let root = try FixtureBuilder()
            .file("a.txt", content: Data("a".utf8))
            .file("taken.txt", content: Data("taken".utf8))
            .build()
        defer { try? FileManager.default.removeItem(at: root) }

        let engine = ApplyEngine(database: try AuditorDatabase.inMemory())
        let file = fileRef(root.appendingPathComponent("a.txt"))
        let finding = Finding(
            detectorID: "rename",
            kind: "core.filenamePolicy.generic",
            severity: .low,
            files: [file],
            evidence: .note("x"),
            explanation: "rename into existing name",
            recommendation: .rename(file: file, proposedName: "taken.txt"),
            stableKeyMaterial: "collision",
            scanID: UUID()
        )

        let plan = engine.plan(findings: [finding])
        #expect(plan.operations.isEmpty)
        #expect(plan.conflicts.contains { $0.reason == .destinationExists })
        #expect(throws: ApplyError.planHasConflicts(1)) {
            try engine.apply(plan)
        }
    }

    @Test("changed-since-scan refuses apply")
    func changedSinceScan() throws {
        let root = try FixtureBuilder()
            .file("doc.txt", content: Data("original".utf8))
            .build()
        defer { try? FileManager.default.removeItem(at: root) }

        let url = root.appendingPathComponent("doc.txt")
        var file = fileRef(url)
        // Stale snapshot: pretend the scan saw a different size.
        file = FileRef(path: file.path, size: file.size + 99, modifiedAt: file.modifiedAt)

        let engine = ApplyEngine(database: try AuditorDatabase.inMemory())
        let finding = Finding(
            detectorID: "rename",
            kind: "core.filenamePolicy.generic",
            severity: .low,
            files: [file],
            evidence: .note("x"),
            explanation: "stale",
            recommendation: .rename(file: file, proposedName: "renamed.txt"),
            stableKeyMaterial: "stale",
            scanID: UUID()
        )

        let plan = engine.plan(findings: [finding])
        #expect(plan.conflicts.contains { $0.reason == .changedSinceScan })
    }

    @Test("undo refuses when an applied file changed afterward")
    func changedSinceApplyBlocksUndo() throws {
        let root = try FixtureBuilder()
            .file("doc.txt", content: Data("body".utf8))
            .build()
        defer { try? FileManager.default.removeItem(at: root) }

        let db = try AuditorDatabase.inMemory()
        let engine = ApplyEngine(database: db)
        let file = fileRef(root.appendingPathComponent("doc.txt"))
        let finding = Finding(
            detectorID: "rename",
            kind: "core.filenamePolicy.generic",
            severity: .low,
            files: [file],
            evidence: .note("x"),
            explanation: "rename",
            recommendation: .rename(file: file, proposedName: "renamed.txt"),
            stableKeyMaterial: "r",
            scanID: UUID()
        )

        let plan = engine.plan(findings: [finding])
        let result = try engine.apply(plan)

        let renamed = root.appendingPathComponent("renamed.txt")
        try Data("mutated".utf8).write(to: renamed)
        // Touch mtime into the future so journal snapshot no longer matches.
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(120)],
            ofItemAtPath: renamed.path
        )

        #expect(throws: ApplyError.changedSinceApply(path: renamed.path)) {
            try engine.undo(batchID: result.batchID)
        }
    }

    @Test("journal batches survive database relaunch")
    func journalSurvivesRelaunch() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("folderlint-apply-db-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let root = try FixtureBuilder()
            .file("doc.txt", content: Data("persist".utf8))
            .build()
        defer { try? FileManager.default.removeItem(at: root) }

        let dbPath = dir.appendingPathComponent("auditor.sqlite").path
        let batchID: UUID
        do {
            let db = try AuditorDatabase(path: dbPath)
            let engine = ApplyEngine(database: db)
            let file = fileRef(root.appendingPathComponent("doc.txt"))
            let finding = Finding(
                detectorID: "rename",
                kind: "core.filenamePolicy.generic",
                severity: .low,
                files: [file],
                evidence: .note("x"),
                explanation: "rename",
                recommendation: .rename(file: file, proposedName: "kept.txt"),
                stableKeyMaterial: "p",
                scanID: UUID()
            )
            let result = try engine.apply(engine.plan(findings: [finding]))
            batchID = result.batchID
        }

        let reopened = try AuditorDatabase(path: dbPath)
        let batches = try reopened.loadApplyBatches()
        #expect(batches.count == 1)
        #expect(batches[0].batchID == batchID)
        #expect(batches[0].operationCount == 1)

        try ApplyEngine(database: reopened).undo(batchID: batchID)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("doc.txt").path))
    }

    @Test("move recommendation plans into the destination folder")
    func moveRecommendation() throws {
        let root = try FixtureBuilder()
            .file("Programs/invoice.pdf", content: Data("inv".utf8))
            .directory("Finance")
            .build()
        defer { try? FileManager.default.removeItem(at: root) }

        let engine = ApplyEngine(database: try AuditorDatabase.inMemory())
        let file = fileRef(root.appendingPathComponent("Programs/invoice.pdf"))
        let finding = Finding(
            detectorID: "misfiled",
            kind: "core.misfiled",
            severity: .medium,
            files: [file],
            evidence: .note("misfiled"),
            explanation: "Wrong folder",
            recommendation: .move(
                file: file,
                destinationFolder: root.appendingPathComponent("Finance").path
            ),
            stableKeyMaterial: "m",
            scanID: UUID()
        )

        let plan = engine.plan(findings: [finding])
        #expect(plan.conflicts.isEmpty)
        #expect(plan.operations.count == 1)
        #expect(plan.operations[0].kind == .move)
        #expect(plan.operations[0].newPath.hasSuffix("/Finance/invoice.pdf"))

        _ = try engine.apply(plan)
        #expect(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Finance/invoice.pdf").path
        ))
    }
}

private func fileRef(_ url: URL) -> FileRef {
    let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
    let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
    let mtime = (attrs?[.modificationDate] as? Date) ?? Date()
    return FileRef(path: url.path, size: size, modifiedAt: mtime)
}
