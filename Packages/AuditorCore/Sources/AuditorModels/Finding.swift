import CryptoKit
import Foundation

public enum Severity: Int, Codable, Sendable, Comparable, CaseIterable {
    case low = 0
    case medium = 1
    case high = 2
    case critical = 3

    public static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Lifecycle of a finding. `applied`/`undone` are reached only through the
/// ApplyEngine's journaled workflow — findings themselves never touch files.
public enum DecisionState: String, Codable, Sendable {
    case pending
    case approved
    case dismissed
    case applied
    case undone
}

/// What the user is advised to do. FolderLint never deletes: "archive" means
/// moving aside (e.g. into `_Archive/`), and every action requires approval.
public enum RecommendedAction: Codable, Sendable, Hashable {
    case keepCanonical(keep: FileRef, archive: [FileRef])
    case rename(file: FileRef, proposedName: String)
    case move(file: FileRef, destinationFolder: String)
    case scheduleReminder(actionDate: Date, note: String)
    case review(note: String)
}

/// Machine-checkable support for a finding. Grows a case per detector;
/// the paired `explanation` string on `Finding` is the human-readable side.
public enum Evidence: Codable, Sendable {
    case duplicateSet(contentHash: String, wastedBytes: Int64)
    case contentDuplicateSet(estimatedSimilarity: Double, wastedBytes: Int64)
    case versionChain(rankedFilenames: [String], stem: String, signals: [String], confidence: Double, judge: JudgeSource)
    case note(String)
}

/// Who produced a semantic judgment, so the UI can disclose it.
public enum JudgeSource: String, Codable, Sendable {
    case rules
    case foundationModel
}

public struct Finding: Codable, Sendable, Identifiable {
    public let id: UUID
    public let detectorID: String
    /// Namespaced kind, e.g. "core.duplicateSet.exact".
    public let kind: String
    public let severity: Severity
    public let files: [FileRef]
    public let evidence: Evidence
    /// Human-readable rationale. Every finding must explain itself —
    /// never bare "AI thinks this file is wrong".
    public let explanation: String
    public let recommendation: RecommendedAction
    /// 0...1; deterministic findings use 1.0.
    public let confidence: Double
    /// The only mutable field.
    public var decision: DecisionState
    /// Deterministic identity across scans so user decisions survive rescans.
    public let stableKey: String
    public let scanID: UUID
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        detectorID: String,
        kind: String,
        severity: Severity,
        files: [FileRef],
        evidence: Evidence,
        explanation: String,
        recommendation: RecommendedAction,
        confidence: Double = 1.0,
        decision: DecisionState = .pending,
        stableKeyMaterial: String,
        scanID: UUID,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.detectorID = detectorID
        self.kind = kind
        self.severity = severity
        self.files = files
        self.evidence = evidence
        self.explanation = explanation
        self.recommendation = recommendation
        self.confidence = confidence
        self.decision = decision
        self.stableKey = Finding.stableKey(kind: kind, paths: files.map(\.path), material: stableKeyMaterial)
        self.scanID = scanID
        self.createdAt = createdAt
    }

    /// SHA-256 over (kind + sorted paths + a detector-chosen content signal, such as a
    /// content hash or ranking digest). Paths are sorted so member order never matters.
    public static func stableKey(kind: String, paths: [String], material: String) -> String {
        let joined = ([kind] + paths.sorted() + [material]).joined(separator: "\u{1F}")
        let digest = SHA256.hash(data: Data(joined.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
