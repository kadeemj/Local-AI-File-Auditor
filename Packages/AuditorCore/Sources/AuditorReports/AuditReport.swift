import AuditorModels
import AuditorStore
import Foundation

/// Snapshot used to render CSV/PDF consultant artifacts.
public struct AuditReport: Sendable {
    public let title: String
    public let generatedAt: Date
    public let policyName: String?
    public let folderPaths: [String]
    public let filesScanned: Int?
    public let totalBytes: Int64?
    public let scanDuration: TimeInterval?
    public let findings: [Finding]
    public let applyBatches: [StoredApplyBatch]

    public init(
        title: String = "FolderLint Audit Report",
        generatedAt: Date = Date(),
        policyName: String? = nil,
        folderPaths: [String] = [],
        filesScanned: Int? = nil,
        totalBytes: Int64? = nil,
        scanDuration: TimeInterval? = nil,
        findings: [Finding],
        applyBatches: [StoredApplyBatch] = []
    ) {
        self.title = title
        self.generatedAt = generatedAt
        self.policyName = policyName
        self.folderPaths = folderPaths
        self.filesScanned = filesScanned
        self.totalBytes = totalBytes
        self.scanDuration = scanDuration
        self.findings = findings
        self.applyBatches = applyBatches
    }

    public var findingsBySeverity: [(Severity, [Finding])] {
        Severity.allCases.reversed().compactMap { severity in
            let group = findings.filter { $0.severity == severity }
            return group.isEmpty ? nil : (severity, group)
        }
    }

    public var criticalAndHighCount: Int {
        findings.filter { $0.severity >= .high }.count
    }

    public var appliedOperationCount: Int {
        applyBatches.filter { !$0.isUndone }.reduce(0) { $0 + $1.operationCount }
    }
}

/// Human-readable recommendation / evidence strings shared by CSV and PDF.
public enum ReportFormatting {
    public static func severityLabel(_ severity: Severity) -> String {
        switch severity {
        case .low: "low"
        case .medium: "medium"
        case .high: "high"
        case .critical: "critical"
        }
    }

    public static func recommendationText(_ action: RecommendedAction) -> String {
        switch action {
        case .keepCanonical(let keep, let archive):
            "Keep \(keep.filename); archive \(archive.map(\.filename).joined(separator: ", "))"
        case .rename(let file, let proposed):
            "Rename \(file.filename) → \(proposed)"
        case .move(let file, let destination):
            "Move \(file.filename) to \(destination)"
        case .scheduleReminder(let date, let note):
            "Remind \(isoDate(date)): \(note)"
        case .review(let note):
            note
        }
    }

    public static func evidenceText(_ evidence: Evidence) -> String {
        switch evidence {
        case .duplicateSet(let hash, let wasted):
            return "exact hash \(hash.prefix(16))…; reclaim \(wasted) bytes"
        case .contentDuplicateSet(let similarity, let wasted):
            return "content similarity \(String(format: "%.0f%%", similarity * 100)); reclaim \(wasted) bytes"
        case .versionChain(let ranked, let stem, let signals, let confidence, let judge):
            return "stem \(stem); \(ranked.joined(separator: " > ")); \(signals.joined(separator: ", ")); \(Int(confidence * 100))% (\(judge.rawValue))"
        case .filenamePolicy(let template, let violations, let proposed, let judge):
            let rules = violations.map(\.ruleID).joined(separator: "; ")
            return "template \(template ?? "—"); rules \(rules); proposed \(proposed ?? "—"); \(judge?.rawValue ?? "rules")"
        case .misfiled(let current, let suggested, let own, let other, let nearest, let judge):
            return "from \(current) → \(suggested); own \(String(format: "%.2f", own)) / suggested \(String(format: "%.2f", other)); nearest \(nearest.map(\.filename).joined(separator: ", ")); \(judge.rawValue)"
        case .expiration(let kind, let detected, let action, let autoRenews, let notice, let party, let snippet, let judge):
            return "\(kind.rawValue) \(isoDate(detected)); action \(isoDate(action)); notice \(notice)d; autoRenew \(autoRenews); party \(party ?? "—"); \(judge.rawValue); \(snippet)"
        case .note(let note):
            return note
        }
    }

    public static func isoDate(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    public static func isoDay(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.string(from: date)
    }
}
