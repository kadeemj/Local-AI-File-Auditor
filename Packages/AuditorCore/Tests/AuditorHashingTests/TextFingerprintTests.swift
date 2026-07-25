import Foundation
import Testing

@testable import AuditorHashing

private let contractText = """
    This Services Agreement is entered into as of July 1, 2026 between Lava Labs LLC \
    and the Client. The term of this agreement shall be twelve months, renewing \
    automatically unless either party provides sixty days written notice of cancellation. \
    Fees are due net thirty from the date of each invoice. Either party may terminate \
    for material breach with thirty days notice and opportunity to cure.
    """

@Suite("TextFingerprint")
struct TextFingerprintTests {
    @Test("identical text → identical fingerprint")
    func identical() throws {
        let a = try #require(TextFingerprint.compute(from: contractText))
        let b = try #require(TextFingerprint.compute(from: contractText))
        #expect(a.estimatedJaccard(with: b) == 1.0)
    }

    @Test("case and whitespace differences do not matter (the OCR lesson)")
    func normalization() throws {
        let a = try #require(TextFingerprint.compute(from: contractText))
        let mangled = contractText.uppercased()
            .replacingOccurrences(of: " ", with: "   ")
            .replacingOccurrences(of: ",", with: " ,\n")
        let b = try #require(TextFingerprint.compute(from: mangled))
        #expect(a.estimatedJaccard(with: b) > 0.95)
    }

    @Test("a footer change stays highly similar; different documents do not")
    func discrimination() throws {
        let a = try #require(TextFingerprint.compute(from: contractText))
        let withFooter = try #require(TextFingerprint.compute(from: contractText + " Page 1 of 1 — printed copy."))
        #expect(a.estimatedJaccard(with: withFooter) > 0.8)

        let unrelated = try #require(TextFingerprint.compute(from: """
            Board meeting minutes for the March session. Attendees reviewed the quarterly \
            financial statements and approved the revised conflict of interest policy. \
            The development committee reported on the spring fundraising gala results.
            """))
        #expect(a.estimatedJaccard(with: unrelated) < 0.2)
    }

    @Test("too-short text refuses to fingerprint")
    func tooShort() {
        #expect(TextFingerprint.compute(from: "short note") == nil)
    }
}

@Suite("ContentDuplicateFinder")
struct ContentDuplicateFinderTests {
    @Test("groups same-text docs, leaves distinct docs alone")
    func grouping() throws {
        let base = contractText
        let resaved = base.uppercased()  // different bytes, same words
        let withFooter = base + " Confidential — internal distribution only."
        let unrelated = """
            Volunteer onboarding checklist: background check completed, orientation \
            session attended, confidentiality agreement signed, emergency contact \
            recorded, and assigned mentor introduced during the first week.
            """

        let fingerprints: [String: TextFingerprint] = [
            "/a/agreement.pdf": TextFingerprint.compute(from: base)!,
            "/b/agreement-export.docx": TextFingerprint.compute(from: resaved)!,
            "/c/agreement-stamped.pdf": TextFingerprint.compute(from: withFooter)!,
            "/d/volunteers.docx": TextFingerprint.compute(from: unrelated)!,
        ]

        let sets = ContentDuplicateFinder(threshold: 0.8).duplicateSets(in: fingerprints)

        #expect(sets.count == 1)
        let set = try #require(sets.first)
        #expect(Set(set.paths) == ["/a/agreement.pdf", "/b/agreement-export.docx", "/c/agreement-stamped.pdf"])
        #expect(set.minimumSimilarity >= 0.8)
    }
}
