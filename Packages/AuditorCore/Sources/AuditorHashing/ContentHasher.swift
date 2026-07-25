import AuditorModels
import Foundation

public struct HashDigest: Codable, Sendable, Hashable {
    public let hex: String
    public init(hex: String) { self.hex = hex }
}

/// Staged hashing contract. Phase 2 provides the CryptoKit SHA-256 implementation:
/// partial = SHA-256(first 64 KB ∥ last 64 KB ∥ size), full = streaming SHA-256
/// in 1 MiB chunks with F_NOCACHE.
public protocol ContentHasher: Sendable {
    func partialHash(of url: URL, size: Int64) async throws -> HashDigest
    func fullHash(of url: URL) async throws -> HashDigest
}
