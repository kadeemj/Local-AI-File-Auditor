import Foundation

public struct ContentDuplicateSet: Sendable {
    public let paths: [String]
    /// The weakest pairwise link in the set — the honest number to show users.
    public let minimumSimilarity: Double
}

/// Groups fingerprints into content-duplicate sets using LSH banding
/// (32 bands × 4 rows over the 128-lane signature) to find candidate pairs
/// without O(n²) comparisons, then verifies each candidate against the
/// similarity threshold and merges verified pairs with union-find.
public struct ContentDuplicateFinder: Sendable {
    let threshold: Double

    public init(threshold: Double = 0.85) {
        self.threshold = threshold
    }

    public func duplicateSets(in fingerprints: [String: TextFingerprint]) -> [ContentDuplicateSet] {
        let entries = fingerprints.sorted { $0.key < $1.key }  // deterministic order
        guard entries.count >= 2 else { return [] }

        // LSH banding: candidates share at least one identical band.
        let bands = 32
        let rowsPerBand = TextFingerprint.signatureLength / bands
        var buckets: [UInt64: [Int]] = [:]
        for (index, entry) in entries.enumerated() {
            for band in 0..<bands {
                var hash: UInt64 = UInt64(band) &* 0x9E3779B97F4A7C15
                for row in 0..<rowsPerBand {
                    hash = splitmix64(hash ^ entry.value.signature[band * rowsPerBand + row])
                }
                buckets[hash, default: []].append(index)
            }
        }

        // Verify candidates; union verified pairs.
        var parent = Array(0..<entries.count)
        func find(_ x: Int) -> Int {
            var root = x
            while parent[root] != root { root = parent[root] }
            var current = x
            while parent[current] != root {
                let next = parent[current]
                parent[current] = root
                current = next
            }
            return root
        }
        func union(_ a: Int, _ b: Int) { parent[find(a)] = find(b) }

        var verifiedPairs: Set<[Int]> = []
        for bucket in buckets.values where bucket.count > 1 && bucket.count <= 64 {
            for i in 0..<bucket.count {
                for j in (i + 1)..<bucket.count {
                    let pair = [min(bucket[i], bucket[j]), max(bucket[i], bucket[j])]
                    guard !verifiedPairs.contains(pair) else { continue }
                    verifiedPairs.insert(pair)
                    let similarity = entries[pair[0]].value.estimatedJaccard(with: entries[pair[1]].value)
                    if similarity >= threshold { union(pair[0], pair[1]) }
                }
            }
        }

        // Collect sets ≥ 2 with their weakest verified pairwise similarity.
        var groups: [Int: [Int]] = [:]
        for index in 0..<entries.count {
            groups[find(index), default: []].append(index)
        }

        return groups.values.filter { $0.count >= 2 }.map { members in
            var minimum = 1.0
            for i in 0..<members.count {
                for j in (i + 1)..<members.count {
                    minimum = min(minimum, entries[members[i]].value.estimatedJaccard(with: entries[members[j]].value))
                }
            }
            return ContentDuplicateSet(paths: members.map { entries[$0].key }, minimumSimilarity: minimum)
        }
        .sorted { $0.paths[0] < $1.paths[0] }
    }
}
