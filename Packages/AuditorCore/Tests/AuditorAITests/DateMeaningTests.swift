import AuditorModels
import Foundation
import Testing

@testable import AuditorAI

@Suite("DateMeaning")
struct DateMeaningTests {
    @Test("request strips paths and bounds the evidence window")
    func privacyBoundary() {
        let request = DateMeaningRequest(
            filename: "/Users/client/private/contract.pdf",
            observedDate: day(2026, 8, 31),
            matchedText: String(repeating: "date", count: 40),
            context: String(repeating: "x", count: 1_000)
        )
        #expect(request.filename == "contract.pdf")
        #expect(request.matchedText.count == 100)
        #expect(request.context.count == 600)
        #expect(!request.prompt.contains("/Users/client/private"))
    }

    @Test("validation requires exact kind, date, and coherent renewal semantics")
    func strictValidation() {
        let request = DateMeaningRequest(
            filename: "contract.pdf",
            observedDate: day(2026, 8, 31),
            matchedText: "August 31, 2026",
            context: "The contract expires on August 31, 2026 after 30 days written notice from Licensee."
        )
        let valid = DateMeaning(
            kind: "expiration",
            date: "2026-08-31",
            autoRenews: false,
            noticePeriodDays: 30,
            party: "Licensee"
        )
        #expect(valid.validated(for: request)?.kind == .expiration)

        let inventedDate = DateMeaning(
            kind: "expiration",
            date: "2026-09-01",
            autoRenews: false,
            noticePeriodDays: 30,
            party: ""
        )
        #expect(inventedDate.validated(for: request) == nil)

        let incoherentRenewal = DateMeaning(
            kind: "reportingDeadline",
            date: "2026-08-31",
            autoRenews: true,
            noticePeriodDays: 0,
            party: ""
        )
        #expect(incoherentRenewal.validated(for: request) == nil)

        let unsupportedNotice = DateMeaning(
            kind: "expiration",
            date: "2026-08-31",
            autoRenews: false,
            noticePeriodDays: 90,
            party: ""
        )
        #expect(unsupportedNotice.validated(for: request) == nil)

        let unsupportedParty = DateMeaning(
            kind: "expiration",
            date: "2026-08-31",
            autoRenews: false,
            noticePeriodDays: 0,
            party: "Invented Organization"
        )
        #expect(unsupportedParty.validated(for: request) == nil)
    }

    @Test("Foundation Models date-meaning smoke test",
          .enabled(if: ModelAvailability.current().isAvailable))
    func liveDateMeaningSmokeTest() async throws {
        let request = DateMeaningRequest(
            filename: "Agreement.pdf",
            observedDate: day(2026, 9, 30),
            matchedText: "September 30, 2026",
            context: """
                This agreement automatically renews on September 30, 2026 unless
                Licensee provides 60 days written notice.
                """
        )
        let meaning = try await FoundationModelDateMeaningJudge().classify(request)
        #expect(meaning.validated(for: request) != nil)
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
