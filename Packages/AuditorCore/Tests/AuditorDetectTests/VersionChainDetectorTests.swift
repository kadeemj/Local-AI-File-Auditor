import AuditorAI
import AuditorModels
import Foundation
import Testing

@testable import AuditorDetect

private func rec(_ path: String, size: Int64 = 1_000, mtimeDaysAgo: Int = 0) -> FileRecord {
    FileRecord(
        path: path,
        size: size,
        mtimeNanoseconds: Int64((Date().timeIntervalSince1970 - Double(mtimeDaysAgo) * 86_400) * 1e9)
    )
}

private enum MockJudgeError: Error {
    case unexpectedCall
    case refused
}

private struct MockJudge: VersionChainJudging {
    let modelAvailability: ModelAvailability
    let response: @Sendable (VersionChainJudgeRequest) async throws -> VersionChainJudgment

    init(
        availability: ModelAvailability = .available,
        response: @escaping @Sendable (VersionChainJudgeRequest) async throws -> VersionChainJudgment
    ) {
        self.modelAvailability = availability
        self.response = response
    }

    func availability() async -> ModelAvailability { modelAvailability }

    func judge(_ request: VersionChainJudgeRequest) async throws -> VersionChainJudgment {
        try await response(request)
    }
}

private let rulesOnlyJudge = MockJudge(availability: .unavailable(reason: "unit test")) { _ in
    throw MockJudgeError.unexpectedCall
}

private func detect(
    _ files: [FileRecord],
    judge: any VersionChainJudging = rulesOnlyJudge
) async throws -> [Finding] {
    try await VersionChainDetector(judge: judge)
        .detect(context: DetectionContext(scanID: UUID(), files: files))
}

@Suite("VersionChainDetector")
struct VersionChainDetectorTests {
    @Test("explicit version chain: keep highest version")
    func versionNumbersWin() async throws {
        let findings = try await detect([
            rec("/d/report_v1.docx", mtimeDaysAgo: 30),
            rec("/d/report_v2.docx", mtimeDaysAgo: 20),
            rec("/d/report_v3.docx", mtimeDaysAgo: 10),
        ])

        let finding = try #require(findings.first)
        guard case .keepCanonical(let keep, let archive) = finding.recommendation else {
            Issue.record("expected keepCanonical"); return
        }
        #expect(keep.filename == "report_v3.docx")
        #expect(archive.count == 2)
        #expect(finding.confidence >= 0.6)
    }

    @Test("version number beats modification time, with reduced confidence")
    func contradictionPenalty() async throws {
        let straight = try await detect([
            rec("/d/plan_v1.docx", mtimeDaysAgo: 10),
            rec("/d/plan_v2.docx", mtimeDaysAgo: 1),
        ])
        let contradicted = try await detect([
            rec("/d/plan_v1.docx", mtimeDaysAgo: 1),   // v1 touched recently
            rec("/d/plan_v2.docx", mtimeDaysAgo: 10),
        ])

        let straightFinding = try #require(straight.first)
        let contradictedFinding = try #require(contradicted.first)

        guard case .keepCanonical(let keep, _) = contradictedFinding.recommendation else {
            Issue.record("expected keepCanonical"); return
        }
        #expect(keep.filename == "plan_v2.docx", "version number wins over mtime")
        #expect(contradictedFinding.confidence < straightFinding.confidence)
    }

    @Test("the brief's handbook chain: FINAL APPROVED wins")
    func handbookChain() async throws {
        let findings = try await detect([
            rec("/hr/Employee Handbook.docx", mtimeDaysAgo: 90),
            rec("/hr/Employee Handbook Final.docx", mtimeDaysAgo: 60),
            rec("/hr/Employee Handbook Final 2.docx", mtimeDaysAgo: 30),
            rec("/hr/Employee Handbook FINAL APPROVED.docx", mtimeDaysAgo: 5),
        ])

        let finding = try #require(findings.first)
        guard case .keepCanonical(let keep, let archive) = finding.recommendation else {
            Issue.record("expected keepCanonical"); return
        }
        #expect(keep.filename == "Employee Handbook FINAL APPROVED.docx")
        #expect(archive.count == 3)
    }

    @Test("conflicted copies rank below the canonical file")
    func conflictedCopy() async throws {
        let findings = try await detect([
            rec("/d/Q3 report.docx", mtimeDaysAgo: 5),
            rec("/d/Q3 report (Kadeem's conflicted copy 2).docx", mtimeDaysAgo: 1),
        ])

        let finding = try #require(findings.first)
        guard case .keepCanonical(let keep, _) = finding.recommendation else {
            Issue.record("expected keepCanonical"); return
        }
        #expect(keep.filename == "Q3 report.docx", "sync conflict never wins, even if newer")
    }

    @Test("false-positive guards: chapters, annual invoices, exports")
    func falsePositiveGuards() async throws {
        // Different stems — never clustered.
        let chapters = try await detect([rec("/b/chapter 1.md"), rec("/b/chapter 2.md")])
        #expect(chapters.isEmpty)

        // Bare years only — distinct annual documents, confidence capped below threshold.
        let invoices = try await detect([rec("/f/invoice 2024.pdf"), rec("/f/invoice 2025.pdf")])
        #expect(invoices.isEmpty)

        // Same stem, different extension — an export, not a version chain.
        let exports = try await detect([rec("/d/report final.docx"), rec("/d/report final.pdf")])
        #expect(exports.isEmpty)

        // Different directories — never clustered in v1.
        let dirs = try await detect([rec("/a/report_v1.docx"), rec("/b/report_v2.docx")])
        #expect(dirs.isEmpty)
    }

    @Test("dated filename chain ranks by date")
    func datedChain() async throws {
        let findings = try await detect([
            rec("/m/Budget 2026-05-01.xlsx", mtimeDaysAgo: 80),
            rec("/m/Budget 2026-07-15.xlsx", mtimeDaysAgo: 3),
        ])

        let finding = try #require(findings.first)
        guard case .keepCanonical(let keep, _) = finding.recommendation else {
            Issue.record("expected keepCanonical"); return
        }
        #expect(keep.filename == "Budget 2026-07-15.xlsx")
    }

    @Test("finding carries evidence, explanation, and rules judge")
    func findingShape() async throws {
        let findings = try await detect([
            rec("/d/policy_v1.pdf", mtimeDaysAgo: 10),
            rec("/d/policy_v2.pdf", mtimeDaysAgo: 1),
        ])

        let finding = try #require(findings.first)
        #expect(finding.kind == "core.versionChain")
        #expect(!finding.explanation.isEmpty)
        guard case .versionChain(let ranked, let stem, let signals, _, let judge) = finding.evidence else {
            Issue.record("expected versionChain evidence"); return
        }
        #expect(ranked.first == "policy_v2.pdf")
        #expect(stem == "policy")
        #expect(!signals.isEmpty)
        #expect(judge == .rules)
    }

    @Test("ambiguous clusters use a valid semantic permutation")
    func semanticRanking() async throws {
        let judge = MockJudge { request in
            #expect(request.candidates.map(\.filename) == ["policy_v2.pdf", "policy_v1.pdf"])
            return VersionChainJudgment(
                canonicalIndex: 1,
                stalenessRanking: [1, 0],
                confidence: 0.74,
                rationale: "The older modification date is offset by the explicit review context."
            )
        }
        let findings = try await detect([
            rec("/d/policy_v1.pdf", mtimeDaysAgo: 10),
            rec("/d/policy_v2.pdf", mtimeDaysAgo: 1),
        ], judge: judge)

        let finding = try #require(findings.first)
        guard case .keepCanonical(let keep, let archive) = finding.recommendation else {
            Issue.record("expected keepCanonical"); return
        }
        #expect(keep.filename == "policy_v1.pdf")
        #expect(archive.map(\.filename) == ["policy_v2.pdf"])
        #expect(finding.confidence == 0.74)
        guard case .versionChain(let ranked, _, let signals, _, let source) = finding.evidence else {
            Issue.record("expected versionChain evidence"); return
        }
        #expect(ranked == ["policy_v1.pdf", "policy_v2.pdf"])
        #expect(signals.last?.contains("on-device judgment") == true)
        #expect(source == .foundationModel)
    }

    @Test("malformed semantic permutations fall back to rules")
    func malformedPermutationFallback() async throws {
        let judge = MockJudge { _ in
            VersionChainJudgment(
                canonicalIndex: 0,
                stalenessRanking: [0, 0],
                confidence: 0.9,
                rationale: "Duplicate output index."
            )
        }
        let findings = try await detect([
            rec("/d/policy_v1.pdf", mtimeDaysAgo: 10),
            rec("/d/policy_v2.pdf", mtimeDaysAgo: 1),
        ], judge: judge)

        let finding = try #require(findings.first)
        guard case .keepCanonical(let keep, _) = finding.recommendation else {
            Issue.record("expected keepCanonical"); return
        }
        #expect(keep.filename == "policy_v2.pdf")
        guard case .versionChain(_, _, _, _, let source) = finding.evidence else {
            Issue.record("expected versionChain evidence"); return
        }
        #expect(source == .rules)
    }

    @Test("generation errors fall back to rules")
    func generationErrorFallback() async throws {
        let judge = MockJudge { _ in throw MockJudgeError.refused }
        let findings = try await detect([
            rec("/d/policy_v1.pdf", mtimeDaysAgo: 10),
            rec("/d/policy_v2.pdf", mtimeDaysAgo: 1),
        ], judge: judge)

        let finding = try #require(findings.first)
        guard case .versionChain(_, _, _, _, let source) = finding.evidence else {
            Issue.record("expected versionChain evidence"); return
        }
        #expect(source == .rules)
    }

    @Test("the semantic judge can rescue the lower edge of the ambiguous band")
    func semanticJudgeRescuesLowRuleConfidence() async throws {
        let judge = MockJudge { _ in
            VersionChainJudgment(
                canonicalIndex: 1,
                stalenessRanking: [1, 0],
                confidence: 0.68,
                rationale: "The final filename indicates the authoritative copy."
            )
        }
        // Status difference raises rules confidence to 0.6, then >3× size
        // divergence lowers it to 0.4: semantic-only territory.
        let findings = try await detect([
            rec("/d/plan draft.pdf", size: 1_000, mtimeDaysAgo: 10),
            rec("/d/plan final.pdf", size: 4_001, mtimeDaysAgo: 1),
        ], judge: judge)

        let finding = try #require(findings.first)
        #expect(finding.confidence == 0.68)
        guard case .versionChain(_, _, _, _, let source) = finding.evidence else {
            Issue.record("expected versionChain evidence"); return
        }
        #expect(source == .foundationModel)
    }
}
