import AuditorHashing
import AuditorModels
import AuditorPolicy
import Foundation

/// Signals a detector needs the engine to compute. The engine only pays for
/// signals that registered detectors declare.
public struct DetectorSignals: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let hashes = DetectorSignals(rawValue: 1 << 0)
    public static let textContent = DetectorSignals(rawValue: 1 << 1)
    public static let embeddings = DetectorSignals(rawValue: 1 << 2)
    public static let semanticJudge = DetectorSignals(rawValue: 1 << 3)
    public static let policy = DetectorSignals(rawValue: 1 << 4)
}

/// Immutable view of a completed crawl, handed to detectors after index freeze.
/// Phase 3 adds extracted-content access; Phase 6 adds embeddings and policy;
/// Phase 7 consumes transient text for contextual expiration detection.
public struct DetectionContext: Sendable {
    public let scanID: UUID
    public let files: [FileRecord]
    /// Populated by the engine when a registered detector requires `.hashes`.
    public let duplicateGroups: [DuplicateGroup]?
    /// Populated (path → fingerprint) when a detector requires `.textContent`.
    public let textFingerprints: [String: TextFingerprint]?
    /// Transient extracted text. Never written to the scan cache or findings.
    public let extractedText: [String: String]?
    /// Transient/persistable sentence vectors keyed by file path.
    public let documentEmbeddings: [String: [Double]]?
    /// Folder-name/path/description vectors keyed by absolute folder path.
    public let folderLabelEmbeddings: [String: [Double]]?
    /// Active governance policy; nil still enables universal filename rules.
    public let policy: Policy?

    public init(
        scanID: UUID,
        files: [FileRecord],
        duplicateGroups: [DuplicateGroup]? = nil,
        textFingerprints: [String: TextFingerprint]? = nil,
        extractedText: [String: String]? = nil,
        documentEmbeddings: [String: [Double]]? = nil,
        folderLabelEmbeddings: [String: [Double]]? = nil,
        policy: Policy? = nil
    ) {
        self.scanID = scanID
        self.files = files
        self.duplicateGroups = duplicateGroups
        self.textFingerprints = textFingerprints
        self.extractedText = extractedText
        self.documentEmbeddings = documentEmbeddings
        self.folderLabelEmbeddings = folderLabelEmbeddings
        self.policy = policy
    }
}

/// The plug-in point for all audits — the five v1 detectors and every future one
/// (sensitive info, metadata completeness, policy packs) implement this.
public protocol Detector: Sendable {
    static var id: String { get }
    var displayName: String { get }
    var requiredSignals: DetectorSignals { get }
    func detect(context: DetectionContext) async throws -> [Finding]
}
