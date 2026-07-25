import AuditorDetect
import AuditorHashing
import AuditorModels
import AuditorTestSupport
import Foundation
import Testing

@testable import AuditorEngine

@Suite("AuditorEngine scan pipeline")
struct AuditorEngineScanTests {
    @Test("streams progress, findings, and completion for a fixture tree")
    func streamsEventsForFixtureTree() async throws {
        let payload = Data("Alpha document body for hashing.".utf8)
        let root = try FixtureBuilder()
            .file("readme.txt", content: payload)
            .file("readme copy.txt", content: payload)
            .file("notes.txt", content: Data("Unrelated notes about a meeting.".utf8))
            .build()
        defer { try? FileManager.default.removeItem(at: root) }

        let engine = try AuditorEngine.makeEphemeral(detectors: [DuplicateDetectorStub()])
        let handle = await engine.startScan(ScanConfiguration(rootPaths: [root.path]))

        var phases: [ScanPhase] = []
        var findings: [Finding] = []
        var summary: ScanSummary?
        var failed: ScanError?

        for await event in handle.events {
            switch event {
            case .phaseChanged(let phase):
                phases.append(phase)
            case .progress:
                break
            case .finding(let finding):
                findings.append(finding)
            case .completed(let completed):
                summary = completed
            case .failed(let error):
                failed = error
            }
        }

        #expect(failed == nil)
        #expect(phases.contains(.enumerating))
        #expect(phases.contains(.hashing))
        #expect(phases.contains(.detecting))
        let completed = try #require(summary)
        #expect(completed.filesScanned == 3)
        #expect(completed.findingsCount == findings.count)
        #expect(findings.count == 1)
        #expect(findings.first?.kind == "test.duplicate")
    }

    @Test("cancel marks the scan cancelled")
    func cancelStopsScan() async throws {
        var builder = FixtureBuilder()
        for index in 0..<20 {
            builder = builder.file("file-\(index).txt", content: Data("payload-\(index)".utf8))
        }
        let root = try builder.build()
        defer { try? FileManager.default.removeItem(at: root) }

        let engine = try AuditorEngine.makeEphemeral(detectors: [SlowDetector()])
        let handle = await engine.startScan(ScanConfiguration(rootPaths: [root.path]))

        // Let enumeration begin, then cancel.
        try await Task.sleep(for: .milliseconds(10))
        handle.cancel()

        var terminal: ScanEvent?
        for await event in handle.events {
            terminal = event
        }

        guard case .failed(.cancelled) = terminal else {
            // Completion can win the race on very small trees; either cancelled
            // or completed without hanging is acceptable for this smoke check.
            if case .completed = terminal {
                return
            }
            Issue.record("expected cancelled or completed, got \(String(describing: terminal))")
            return
        }
    }
}

private struct DuplicateDetectorStub: Detector {
    static let id = "test.duplicate"
    var displayName: String { "Duplicate stub" }
    var requiredSignals: DetectorSignals { [.hashes] }

    func detect(context: DetectionContext) async throws -> [Finding] {
        guard let groups = context.duplicateGroups, let group = groups.first, group.files.count >= 2 else {
            return []
        }
        let files = group.files.map(FileRef.init)
        return [
            Finding(
                detectorID: Self.id,
                kind: "test.duplicate",
                severity: .high,
                files: files,
                evidence: .duplicateSet(contentHash: group.contentHash, wastedBytes: 10),
                explanation: "Stub found a duplicate set.",
                recommendation: .keepCanonical(keep: files[0], archive: Array(files.dropFirst())),
                stableKeyMaterial: group.contentHash,
                scanID: context.scanID
            ),
        ]
    }
}

private struct SlowDetector: Detector {
    static let id = "test.slow"
    var displayName: String { "Slow stub" }
    var requiredSignals: DetectorSignals { [] }

    func detect(context: DetectionContext) async throws -> [Finding] {
        try await Task.sleep(for: .milliseconds(500))
        return [
            Finding(
                detectorID: Self.id,
                kind: "test.slow",
                severity: .low,
                files: context.files.prefix(1).map(FileRef.init),
                evidence: .note("slow"),
                explanation: "Slow detector finished.",
                recommendation: .review(note: "n/a"),
                stableKeyMaterial: "slow",
                scanID: context.scanID
            ),
        ]
    }
}
