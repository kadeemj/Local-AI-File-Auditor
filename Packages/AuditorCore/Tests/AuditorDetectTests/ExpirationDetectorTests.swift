import AuditorAI
import AuditorModels
import AuditorPolicy
import Foundation
import Testing

@testable import AuditorDetect

private enum DateJudgeTestError: Error {
    case unexpectedCall
}

private struct MockDateMeaningJudge: DateMeaningJudging {
    let modelAvailability: ModelAvailability
    let response: @Sendable (DateMeaningRequest) async throws -> DateMeaning

    init(
        availability: ModelAvailability = .available,
        response: @escaping @Sendable (DateMeaningRequest) async throws -> DateMeaning
    ) {
        self.modelAvailability = availability
        self.response = response
    }

    func availability() async -> ModelAvailability { modelAvailability }
    func classify(_ request: DateMeaningRequest) async throws -> DateMeaning {
        try await response(request)
    }
}

@Suite("ExpirationDetector")
struct ExpirationDetectorTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private var policy: Policy {
        Policy(
            id: "test",
            displayName: "Test",
            namingTemplate: nil,
            expirationHorizonDays: 90
        )
    }

    @Test("rules classify automatic renewal and compute notice plus buffer")
    func rulesAutoRenewal() async throws {
        let file = record("/Legal/Agreement.txt")
        let judge = MockDateMeaningJudge(availability: .unavailable(reason: "test")) { _ in
            throw DateJudgeTestError.unexpectedCall
        }
        let detector = ExpirationDetector(
            judge: judge,
            referenceDate: { self.day(2026, 7, 25) },
            calendar: calendar
        )
        let findings = try await detector.detect(context: DetectionContext(
            scanID: UUID(),
            files: [file],
            extractedText: [
                file.path: """
                    This agreement automatically renews on September 30, 2026 unless
                    Licensee gives at least 60 days written notice.
                    """,
            ],
            policy: policy
        ))

        let finding = try #require(findings.first)
        #expect(findings.count == 1)
        #expect(finding.kind == "core.expiration.autoRenewal")
        #expect(finding.severity == .high)
        guard case .expiration(
            let kind,
            let detectedDate,
            let actionDate,
            let autoRenews,
            let noticeDays,
            _,
            let snippet,
            let source
        ) = finding.evidence else {
            Issue.record("expected expiration evidence"); return
        }
        #expect(kind == .autoRenewal)
        #expect(detectedDate == day(2026, 9, 30))
        #expect(actionDate == day(2026, 7, 18))
        #expect(autoRenews)
        #expect(noticeDays == 60)
        #expect(snippet.contains("automatically renews"))
        #expect(source == .rules)
    }

    @Test("an effective date alone is not an actionable finding")
    func effectiveDateIsNotActionable() async throws {
        let file = record("/Legal/Policy.txt")
        let detector = ExpirationDetector(
            judge: MockDateMeaningJudge(availability: .unavailable(reason: "test")) { _ in
                throw DateJudgeTestError.unexpectedCall
            },
            referenceDate: { self.day(2026, 7, 25) },
            calendar: calendar
        )
        let findings = try await detector.detect(context: DetectionContext(
            scanID: UUID(),
            files: [file],
            extractedText: [file.path: "This policy is effective August 15, 2026."],
            policy: policy
        ))
        #expect(findings.isEmpty)
    }

    @Test("validated model meaning handles a semantically ambiguous deadline")
    func semanticDeadline() async throws {
        let file = record("/Private/Clients/filing.txt")
        let judge = MockDateMeaningJudge { request in
            #expect(request.filename == "filing.txt")
            #expect(!request.context.contains("/Private/Clients"))
            return DateMeaning(
                kind: "reportingDeadline",
                date: "2026-10-01",
                autoRenews: false,
                noticePeriodDays: 0,
                party: "Program Director"
            )
        }
        let detector = ExpirationDetector(
            judge: judge,
            referenceDate: { self.day(2026, 7, 25) },
            calendar: calendar
        )
        let findings = try await detector.detect(context: DetectionContext(
            scanID: UUID(),
            files: [file],
            extractedText: [
                file.path: "The annual compliance deadline is October 1, 2026 for the Program Director.",
            ],
            policy: policy
        ))

        let finding = try #require(findings.first)
        guard case .expiration(let kind, _, let actionDate, _, _, let party, _, let source) = finding.evidence else {
            Issue.record("expected expiration evidence"); return
        }
        #expect(kind == .reportingDeadline)
        #expect(actionDate == day(2026, 9, 17))
        #expect(party == "Program Director")
        #expect(source == .foundationModel)
    }

    @Test("invalid model output falls back to deterministic evidence")
    func invalidModelFallsBack() async throws {
        let file = record("/Legal/License.txt")
        let judge = MockDateMeaningJudge { _ in
            DateMeaning(
                kind: "expiration",
                date: "2027-01-01",
                autoRenews: false,
                noticePeriodDays: 0,
                party: ""
            )
        }
        let detector = ExpirationDetector(
            judge: judge,
            referenceDate: { self.day(2026, 7, 25) },
            calendar: calendar
        )
        let findings = try await detector.detect(context: DetectionContext(
            scanID: UUID(),
            files: [file],
            extractedText: [file.path: "The license expires on August 31, 2026."],
            policy: policy
        ))

        let finding = try #require(findings.first)
        guard case .expiration(_, _, _, _, _, _, _, let source) = finding.evidence else {
            Issue.record("expected expiration evidence"); return
        }
        #expect(source == .rules)
    }

    @Test("model classification cannot erase an explicit rules notice period")
    func semanticMergePreservesNotice() async throws {
        let file = record("/Legal/Agreement.txt")
        let judge = MockDateMeaningJudge { _ in
            DateMeaning(
                kind: "autoRenewal",
                date: "2026-09-30",
                autoRenews: true,
                noticePeriodDays: 0,
                party: ""
            )
        }
        let detector = ExpirationDetector(
            judge: judge,
            referenceDate: { self.day(2026, 7, 25) },
            calendar: calendar
        )
        let findings = try await detector.detect(context: DetectionContext(
            scanID: UUID(),
            files: [file],
            extractedText: [
                file.path: """
                    The agreement automatically renews on September 30, 2026 unless
                    Licensee gives at least 60 days written notice.
                    """,
            ],
            policy: policy
        ))

        let finding = try #require(findings.first)
        guard case .expiration(_, _, let actionDate, _, let noticeDays, _, _, let source) = finding.evidence else {
            Issue.record("expected expiration evidence"); return
        }
        #expect(noticeDays == 60)
        #expect(actionDate == day(2026, 7, 18))
        #expect(source == .foundationModel)
    }

    @Test("model classification cannot suppress an explicit actionable rules date")
    func semanticMergePreservesActionableKind() async throws {
        let file = record("/Legal/License.txt")
        let judge = MockDateMeaningJudge { _ in
            DateMeaning(
                kind: "effective",
                date: "2026-08-31",
                autoRenews: false,
                noticePeriodDays: 0,
                party: ""
            )
        }
        let detector = ExpirationDetector(
            judge: judge,
            referenceDate: { self.day(2026, 7, 25) },
            calendar: calendar
        )
        let findings = try await detector.detect(context: DetectionContext(
            scanID: UUID(),
            files: [file],
            extractedText: [file.path: "The license expires on August 31, 2026."],
            policy: policy
        ))

        #expect(findings.count == 1)
        #expect(findings.first?.kind == "core.expiration.expiration")
    }

    @Test("future obligations outside the policy horizon are omitted")
    func respectsHorizon() async throws {
        let file = record("/Legal/Lease.txt")
        let detector = ExpirationDetector(
            judge: MockDateMeaningJudge(availability: .unavailable(reason: "test")) { _ in
                throw DateJudgeTestError.unexpectedCall
            },
            referenceDate: { self.day(2026, 7, 25) },
            calendar: calendar
        )
        let findings = try await detector.detect(context: DetectionContext(
            scanID: UUID(),
            files: [file],
            extractedText: [file.path: "The lease expires on December 31, 2026."],
            policy: policy
        ))
        #expect(findings.isEmpty)
    }

    @Test("irrelevant earlier dates do not hide a later expiration")
    func prioritizesRelevantDates() async throws {
        let file = record("/Legal/Long Contract.txt")
        let history = (1...30)
            .map { "Meeting \($0) occurred on January \($0), 2020." }
            .joined(separator: "\n")
        let text = history + "\nThe contract expires on August 31, 2026."
        let detector = ExpirationDetector(
            judge: MockDateMeaningJudge(availability: .unavailable(reason: "test")) { _ in
                throw DateJudgeTestError.unexpectedCall
            },
            referenceDate: { self.day(2026, 7, 25) },
            calendar: calendar
        )
        let findings = try await detector.detect(context: DetectionContext(
            scanID: UUID(),
            files: [file],
            extractedText: [file.path: text],
            policy: policy
        ))

        #expect(findings.count == 1)
        #expect(findings.first?.kind == "core.expiration.expiration")
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func record(_ path: String) -> FileRecord {
        FileRecord(
            path: path,
            size: 1_000,
            mtimeNanoseconds: Int64(day(2026, 7, 25).timeIntervalSince1970 * 1_000_000_000)
        )
    }
}
