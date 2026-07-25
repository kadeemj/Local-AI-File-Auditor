import Foundation

/// MinHash signature over word shingles of normalized text. Two documents with
/// the same words in the same order — regardless of file format, metadata,
/// producer app, or byte layout — get near-identical signatures, which is how
/// content-level duplicates (Word export vs PDF, rescan vs original) are found.
///
/// Text is normalized aggressively (lowercased, non-alphanumerics collapsed)
/// because OCR whitespace is unstable — "GRANTAGREEMENT" vs "GRANT AGREEMENT"
/// must not defeat matching at the shingle level.
public struct TextFingerprint: Codable, Sendable, Equatable {
    public static let signatureLength = 128
    static let shingleSize = 5
    static let minimumWords = 8

    public let signature: [UInt64]

    /// Returns nil for texts too short to fingerprint meaningfully.
    public static func compute(from text: String) -> TextFingerprint? {
        let words = normalize(text)
        guard words.count >= minimumWords else { return nil }

        // Word shingles; short docs fall back to smaller windows implicitly
        // because minimumWords ≥ shingleSize.
        var shingleHashes: Set<UInt64> = []
        let windows = max(1, words.count - shingleSize + 1)
        for start in 0..<windows {
            let shingle = words[start..<min(start + shingleSize, words.count)].joined(separator: " ")
            shingleHashes.insert(fnv1a(shingle))
        }

        var signature = [UInt64](repeating: .max, count: signatureLength)
        for base in shingleHashes {
            for lane in 0..<signatureLength {
                let value = splitmix64(base ^ Self.seeds[lane])
                if value < signature[lane] { signature[lane] = value }
            }
        }
        return TextFingerprint(signature: signature)
    }

    public func estimatedJaccard(with other: TextFingerprint) -> Double {
        var matches = 0
        for lane in 0..<Self.signatureLength where signature[lane] == other.signature[lane] {
            matches += 1
        }
        return Double(matches) / Double(Self.signatureLength)
    }

    // MARK: - Internals

    static func normalize(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    static let seeds: [UInt64] = {
        var seeds: [UInt64] = []
        var state: UInt64 = 0xF01DE12A_C0FFEE00
        for _ in 0..<signatureLength {
            state = splitmix64(state)
            seeds.append(state)
        }
        return seeds
    }()
}

@inline(__always)
func splitmix64(_ input: UInt64) -> UInt64 {
    var z = input &+ 0x9E3779B97F4A7C15
    z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
    z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
    return z ^ (z >> 31)
}

@inline(__always)
func fnv1a(_ string: String) -> UInt64 {
    var hash: UInt64 = 0xCBF29CE484222325
    for byte in string.utf8 {
        hash ^= UInt64(byte)
        hash = hash &* 0x100000001B3
    }
    return hash
}
