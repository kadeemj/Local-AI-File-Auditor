import AuditorModels
import EventKit
import Foundation

public enum ExpirationExportDestination: String, Codable, Sendable {
    case calendar
    case reminders
}

public struct ExpirationExportPayload: Sendable, Equatable {
    public let findingID: UUID
    public let title: String
    public let observedDate: Date
    public let actionDate: Date
    public let notes: String

    public init(finding: Finding) throws {
        guard case .expiration(
            let kind,
            let detectedDate,
            let actionDate,
            _,
            _,
            let party,
            _,
            _
        ) = finding.evidence else {
            throw ExpirationExportError.notExpirationFinding
        }

        self.findingID = finding.id
        self.title = "FolderLint: \(Self.humanName(kind)) — \(finding.files.first?.filename ?? "document")"
        self.observedDate = detectedDate
        self.actionDate = actionDate
        self.notes = [
            finding.explanation,
            party.map { "Responsible party: \($0)" },
            "FolderLint finding: \(finding.id.uuidString)",
        ].compactMap { $0 }.joined(separator: "\n")
    }

    private static func humanName(_ kind: DateMeaningKind) -> String {
        switch kind {
        case .effective: "effective date"
        case .expiration: "expiration"
        case .autoRenewal: "automatic renewal"
        case .cancellationDeadline: "cancellation deadline"
        case .reportingDeadline: "reporting deadline"
        case .other: "dated obligation"
        }
    }
}

public struct ExpirationExportReceipt: Sendable, Equatable {
    public let destination: ExpirationExportDestination
    public let calendarItemIdentifier: String
    public let exportedAt: Date

    public init(
        destination: ExpirationExportDestination,
        calendarItemIdentifier: String,
        exportedAt: Date = Date()
    ) {
        self.destination = destination
        self.calendarItemIdentifier = calendarItemIdentifier
        self.exportedAt = exportedAt
    }
}

public enum ExpirationExportError: Error, Sendable, Equatable {
    case notExpirationFinding
    case permissionDenied(ExpirationExportDestination)
    case noDefaultCalendar(ExpirationExportDestination)
}

public protocol ExpirationEventWriting: Sendable {
    func writeCalendarEvent(_ payload: ExpirationExportPayload) async throws -> String
    func writeReminder(_ payload: ExpirationExportPayload) async throws -> String
}

/// An export occurs only when this method is called from an explicit user
/// action. Scanning and finding creation never request EventKit permission.
public struct ExpirationEventExporter: Sendable {
    private let writer: any ExpirationEventWriting

    public init(writer: any ExpirationEventWriting = EventKitExpirationWriter()) {
        self.writer = writer
    }

    public func export(
        finding: Finding,
        to destination: ExpirationExportDestination
    ) async throws -> ExpirationExportReceipt {
        let payload = try ExpirationExportPayload(finding: finding)
        let identifier: String
        switch destination {
        case .calendar:
            identifier = try await writer.writeCalendarEvent(payload)
        case .reminders:
            identifier = try await writer.writeReminder(payload)
        }
        return ExpirationExportReceipt(
            destination: destination,
            calendarItemIdentifier: identifier
        )
    }
}

public actor EventKitExpirationWriter: ExpirationEventWriting {
    private let eventStore: EKEventStore
    private var calendar: Calendar

    public init(
        eventStore: EKEventStore = EKEventStore(),
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) {
        self.eventStore = eventStore
        self.calendar = calendar
    }

    public func writeCalendarEvent(_ payload: ExpirationExportPayload) async throws -> String {
        guard try await eventStore.requestWriteOnlyAccessToEvents() else {
            throw ExpirationExportError.permissionDenied(.calendar)
        }
        guard let destination = eventStore.defaultCalendarForNewEvents else {
            throw ExpirationExportError.noDefaultCalendar(.calendar)
        }

        let event = EKEvent(eventStore: eventStore)
        event.calendar = destination
        event.title = payload.title
        event.notes = payload.notes
        event.isAllDay = true
        event.startDate = calendar.startOfDay(for: payload.observedDate)
        event.endDate = calendar.date(byAdding: .day, value: 1, to: event.startDate)
        let relativeOffset = payload.actionDate.timeIntervalSince(event.startDate)
        if relativeOffset <= 0 {
            event.addAlarm(EKAlarm(relativeOffset: relativeOffset))
        }

        try eventStore.save(event, span: .thisEvent, commit: true)
        return event.calendarItemIdentifier
    }

    public func writeReminder(_ payload: ExpirationExportPayload) async throws -> String {
        guard try await eventStore.requestFullAccessToReminders() else {
            throw ExpirationExportError.permissionDenied(.reminders)
        }
        guard let destination = eventStore.defaultCalendarForNewReminders() else {
            throw ExpirationExportError.noDefaultCalendar(.reminders)
        }

        let reminder = EKReminder(eventStore: eventStore)
        reminder.calendar = destination
        reminder.title = payload.title
        reminder.notes = payload.notes
        var due = calendar.dateComponents([.year, .month, .day], from: payload.actionDate)
        due.calendar = calendar
        due.timeZone = calendar.timeZone
        reminder.dueDateComponents = due

        try eventStore.save(reminder, commit: true)
        return reminder.calendarItemIdentifier
    }
}
