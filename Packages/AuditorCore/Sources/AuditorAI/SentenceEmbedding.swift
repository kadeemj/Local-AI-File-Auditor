import Foundation
import NaturalLanguage

public struct SentenceEmbeddingProvider: Sendable {
    public init() {}

    /// Returns an on-device sentence vector. Long documents are bounded because
    /// the first pages carry the strongest classification signal in v1.
    public func vector(for text: String) -> [Double]? {
        let bounded = String(text.prefix(20_000)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard bounded.count >= 16 else { return nil }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(String(bounded.prefix(2_000)))
        let language = recognizer.dominantLanguage ?? .english
        let embedding = NLEmbedding.sentenceEmbedding(for: language)
            ?? NLEmbedding.sentenceEmbedding(for: .english)
        guard let vector = embedding?.vector(for: bounded),
              !vector.isEmpty,
              vector.allSatisfy(\.isFinite)
        else { return nil }
        return vector
    }
}

public enum EmbeddingMath {
    public static func centroid(of vectors: [[Double]]) -> [Double]? {
        guard let dimension = vectors.first?.count, dimension > 0,
              vectors.allSatisfy({ $0.count == dimension && $0.allSatisfy(\.isFinite) })
        else { return nil }

        var result = [Double](repeating: 0, count: dimension)
        for vector in vectors {
            for index in 0..<dimension { result[index] += vector[index] }
        }
        let divisor = Double(vectors.count)
        return result.map { $0 / divisor }
    }

    public static func cosineSimilarity(_ lhs: [Double], _ rhs: [Double]) -> Double? {
        guard !lhs.isEmpty, lhs.count == rhs.count,
              lhs.allSatisfy(\.isFinite), rhs.allSatisfy(\.isFinite)
        else { return nil }

        var dot = 0.0
        var lhsMagnitude = 0.0
        var rhsMagnitude = 0.0
        for index in lhs.indices {
            dot += lhs[index] * rhs[index]
            lhsMagnitude += lhs[index] * lhs[index]
            rhsMagnitude += rhs[index] * rhs[index]
        }
        guard lhsMagnitude > 0, rhsMagnitude > 0 else { return nil }
        return max(-1, min(1, dot / (sqrt(lhsMagnitude) * sqrt(rhsMagnitude))))
    }
}
