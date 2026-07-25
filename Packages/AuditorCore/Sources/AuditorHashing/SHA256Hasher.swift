import CryptoKit
import Foundation

/// CryptoKit SHA-256. Apple Silicon has SHA-2 hardware instructions, so hashing
/// is disk-bound regardless of algorithm — and "cryptographically verified
/// duplicates" is a claim marketing can make.
public struct SHA256Hasher: ContentHasher {
    static let partialChunk = 64 * 1024
    static let streamChunk = 1 << 20

    public init() {}

    /// SHA-256 over (first 64 KB ∥ last 64 KB ∥ file size). One or two reads.
    public func partialHash(of url: URL, size: Int64) async throws -> HashDigest {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        let head = try handle.read(upToCount: Self.partialChunk) ?? Data()
        hasher.update(data: head)

        if size > Int64(Self.partialChunk) {
            let tailOffset = max(Int64(Self.partialChunk), size - Int64(Self.partialChunk))
            try handle.seek(toOffset: UInt64(tailOffset))
            let tail = try handle.read(upToCount: Self.partialChunk) ?? Data()
            hasher.update(data: tail)
        }

        withUnsafeBytes(of: size.littleEndian) { hasher.update(bufferPointer: $0) }
        return HashDigest(hex: hasher.finalize().hexEncoded)
    }

    /// Streaming SHA-256 in 1 MiB chunks. F_NOCACHE keeps a bulk scan from
    /// evicting the unified buffer cache; cancellation is checked per chunk.
    public func fullHash(of url: URL) async throws -> HashDigest {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        _ = fcntl(handle.fileDescriptor, F_NOCACHE, 1)

        var hasher = SHA256()
        while true {
            try Task.checkCancellation()
            guard let chunk = try handle.read(upToCount: Self.streamChunk), !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return HashDigest(hex: hasher.finalize().hexEncoded)
    }
}

extension SHA256.Digest {
    var hexEncoded: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
