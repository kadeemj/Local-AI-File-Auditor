import CoreGraphics
import Foundation
import Vision

/// On-device text recognition via the Vision framework (the modern async API).
/// Vision OCR runs locally on every Apple Silicon Mac — unlike Foundation Models
/// it does not require Apple Intelligence.
struct VisionOCR {
    func recognizeText(in image: CGImage) async throws -> String {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let observations = try await request.perform(on: image)
        return observations
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }

    func recognizeText(inImageAt url: URL) async throws -> String {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw ExtractionError.unreadable(url.path)
        }
        return try await recognizeText(in: image)
    }
}
