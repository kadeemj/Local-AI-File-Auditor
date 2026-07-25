import Foundation

/// Pure reducer for scan UI state. `ScanSessionModel` owns the MainActor
/// wrapper; tests exercise this type directly without SwiftUI.
public struct ScanSessionState: Sendable {
    public var phase: ScanPhase?
    public var progress: ScanProgress
    public var findings: [Finding]
    public var summary: ScanSummary?
    public var error: ScanError?
    public var isRunning: Bool
    public var scanID: UUID?

    public init(
        phase: ScanPhase? = nil,
        progress: ScanProgress = ScanProgress(),
        findings: [Finding] = [],
        summary: ScanSummary? = nil,
        error: ScanError? = nil,
        isRunning: Bool = false,
        scanID: UUID? = nil
    ) {
        self.phase = phase
        self.progress = progress
        self.findings = findings
        self.summary = summary
        self.error = error
        self.isRunning = isRunning
        self.scanID = scanID
    }

    public mutating func begin(scanID: UUID) {
        self = ScanSessionState(isRunning: true, scanID: scanID)
    }

    public mutating func apply(_ event: ScanEvent) {
        switch event {
        case .phaseChanged(let phase):
            self.phase = phase
            progress.currentPhase = phase
        case .progress(let progress):
            self.progress = progress
            phase = progress.currentPhase
        case .finding(let finding):
            findings.append(finding)
            findings.sort { ($0.severity, $0.confidence) > ($1.severity, $1.confidence) }
        case .completed(let summary):
            self.summary = summary
            isRunning = false
            error = nil
        case .failed(let error):
            self.error = error
            isRunning = false
        }
    }

    public var findingsBySeverity: [(Severity, [Finding])] {
        Severity.allCases.reversed().compactMap { severity in
            let group = findings.filter { $0.severity == severity }
            return group.isEmpty ? nil : (severity, group)
        }
    }

    public var renameFindings: [Finding] {
        findings.filter {
            if case .rename = $0.recommendation { return true }
            return false
        }
    }

    public var expirationFindings: [Finding] {
        findings.filter {
            if case .expiration = $0.evidence { return true }
            return false
        }
    }
}

extension ScanError: Equatable {
    public static func == (lhs: ScanError, rhs: ScanError) -> Bool {
        switch (lhs, rhs) {
        case (.cancelled, .cancelled):
            true
        case (.rootUnreadable(let a), .rootUnreadable(let b)):
            a == b
        case (.storageFailure(let a), .storageFailure(let b)):
            a == b
        default:
            false
        }
    }
}
