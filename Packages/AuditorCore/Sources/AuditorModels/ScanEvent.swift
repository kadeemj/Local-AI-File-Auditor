import Foundation

public enum ScanPhase: String, Codable, Sendable {
    case enumerating
    case hashing
    case extracting
    case detecting
    case judging
}

public struct ScanProgress: Codable, Sendable {
    public var filesSeen: Int
    public var bytesHashed: Int64
    public var currentPhase: ScanPhase

    public init(filesSeen: Int = 0, bytesHashed: Int64 = 0, currentPhase: ScanPhase = .enumerating) {
        self.filesSeen = filesSeen
        self.bytesHashed = bytesHashed
        self.currentPhase = currentPhase
    }
}

public struct ScanSummary: Codable, Sendable {
    public let scanID: UUID
    public let filesScanned: Int
    public let totalBytes: Int64
    public let cloudPlaceholders: Int
    public let findingsCount: Int
    public let duration: TimeInterval

    public init(
        scanID: UUID,
        filesScanned: Int,
        totalBytes: Int64 = 0,
        cloudPlaceholders: Int = 0,
        findingsCount: Int,
        duration: TimeInterval
    ) {
        self.scanID = scanID
        self.filesScanned = filesScanned
        self.totalBytes = totalBytes
        self.cloudPlaceholders = cloudPlaceholders
        self.findingsCount = findingsCount
        self.duration = duration
    }
}

public enum ScanError: Error, Codable, Sendable {
    case cancelled
    case rootUnreadable(path: String)
    case storageFailure(message: String)
}

/// Streamed from the engine to any frontend (app UI or CLI).
public enum ScanEvent: Sendable {
    case phaseChanged(ScanPhase)
    case progress(ScanProgress)
    case finding(Finding)
    case completed(ScanSummary)
    case failed(ScanError)
}
