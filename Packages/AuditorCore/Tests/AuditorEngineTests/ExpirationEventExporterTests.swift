import AuditorModels
import Foundation
import Testing

@testable import AuditorEngine

@Suite("ExpirationEventExporter")
struct ExpirationEventExporterTests {
    @Test("exports only after an explicit destination call")
    func exportsToSelectedDestination() async throws {
        let writer = RecordingExpirationWriter()
        let exporter = ExpirationEventExporter(writer: writer)
        let finding = makeExpirationFinding()

        let receipt = try await exporter.export(finding: finding, to: .calendar)

        #expect(receipt.destination == .calendar)
        #expect(receipt.calendarItemIdentifier == "calendar-item")
        let payload = await writer.calendarPayload
        #expect(payload?.findingID == finding.id)
        #expect(payload?.title.contains("automatic renewal") == true)
        #expect(await writer.reminderPayload == nil)
    }

    @Test("routes reminder export without touching Calendar")
    func exportsReminder() async throws {
        let writer = RecordingExpirationWriter()
        let exporter = ExpirationEventExporter(writer: writer)

        let receipt = try await exporter.export(finding: makeExpirationFinding(), to: .reminders)

        #expect(receipt.destination == .reminders)
        #expect(receipt.calendarItemIdentifier == "reminder-item")
        #expect(await writer.calendarPayload == nil)
        #expect(await writer.reminderPayload != nil)
    }

    @Test("rejects findings that are not dated obligations")
    func rejectsOtherFindings() async {
        let exporter = ExpirationEventExporter(writer: RecordingExpirationWriter())
        let file = FileRef(path: "/tmp/notes.txt", size: 1, modifiedAt: Date())
        let finding = Finding(
            detectorID: "test",
            kind: "test.note",
            severity: .low,
            files: [file],
            evidence: .note("not an expiration"),
            explanation: "Nothing to schedule.",
            recommendation: .review(note: "Review"),
            stableKeyMaterial: "note",
            scanID: UUID()
        )

        await #expect(throws: ExpirationExportError.notExpirationFinding) {
            try await exporter.export(finding: finding, to: .reminders)
        }
    }

    private func makeExpirationFinding() -> Finding {
        let detected = Date(timeIntervalSince1970: 1_788_134_400)
        let action = Date(timeIntervalSince1970: 1_784_332_800)
        let file = FileRef(path: "/tmp/Agreement.pdf", size: 100, modifiedAt: Date())
        return Finding(
            detectorID: "core.expiration",
            kind: "core.expiration.autoRenewal",
            severity: .high,
            files: [file],
            evidence: .expiration(
                kind: .autoRenewal,
                detectedDate: detected,
                actionDate: action,
                autoRenews: true,
                noticePeriodDays: 30,
                party: "Licensee",
                contextSnippet: "The agreement automatically renews.",
                judge: .rules
            ),
            explanation: "The agreement automatically renews.",
            recommendation: .scheduleReminder(actionDate: action, note: "Review renewal."),
            stableKeyMaterial: "renewal",
            scanID: UUID()
        )
    }
}

private actor RecordingExpirationWriter: ExpirationEventWriting {
    private(set) var calendarPayload: ExpirationExportPayload?
    private(set) var reminderPayload: ExpirationExportPayload?

    func writeCalendarEvent(_ payload: ExpirationExportPayload) async throws -> String {
        calendarPayload = payload
        return "calendar-item"
    }

    func writeReminder(_ payload: ExpirationExportPayload) async throws -> String {
        reminderPayload = payload
        return "reminder-item"
    }
}
