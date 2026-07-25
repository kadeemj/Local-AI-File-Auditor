import Foundation
import Testing

@testable import AuditorPolicy

@Suite("PolicyLoader")
struct PolicyLoaderTests {
    @Test("bundled templates load", arguments: ["nonprofit", "small-business"])
    func bundledTemplatesLoad(id: String) throws {
        let policy = try PolicyLoader().loadBundledPolicy(id: id)
        #expect(policy.id == id)
        #expect(policy.namingTemplate?.isEmpty == false)
        #expect(policy.folderTaxonomy.count == 8)
        #expect(policy.expirationHorizonDays > 0)
    }

    @Test("unknown template throws templateNotFound")
    func unknownTemplateThrows() {
        #expect(throws: PolicyError.self) {
            _ = try PolicyLoader().loadBundledPolicy(id: "does-not-exist")
        }
    }

    @Test("naming template parses, matches, and renders deterministically")
    func namingTemplateRoundTrip() throws {
        let template = try NamingTemplate("YYYY-MM-DD_{DocType}_{Org}_{Status}")
        let date = try #require(NamingTemplate.date(from: "2026-07-25"))
        let rendered = try template.render(
            values: NamingValues(
                date: date,
                docType: "Board Minutes",
                organization: "Láva Labs",
                status: "Final Approved"
            ),
            fileExtension: ".PDF"
        )

        #expect(rendered == "2026-07-25_Board-Minutes_Lava-Labs_Final-Approved.pdf")
        let matched = try #require(template.match(filename: rendered))
        #expect(matched.docType == "Board-Minutes")
        #expect(matched.organization == "Lava-Labs")
        #expect(matched.status == "Final-Approved")
    }

    @Test("template validation rejects ambiguous and unsafe forms")
    func invalidNamingTemplates() {
        #expect(throws: NamingTemplateError.self) {
            _ = try NamingTemplate("{DocType}{Org}")
        }
        #expect(throws: NamingTemplateError.self) {
            _ = try NamingTemplate("{Unknown}")
        }
        #expect(throws: NamingTemplateError.self) {
            _ = try NamingTemplate("../{DocType}")
        }
        #expect(throws: NamingTemplateError.self) {
            _ = try NamingTemplate("{Status}_{Status}")
        }
    }

    @Test("policy validation rejects invalid horizons and duplicate taxonomy")
    func invalidPolicyValidation() {
        let loader = PolicyLoader()
        #expect(throws: PolicyError.self) {
            try loader.validate(Policy(
                id: "bad",
                displayName: "Bad",
                namingTemplate: "{DocType}",
                folderTaxonomy: ["Finance", "finance"],
                expirationHorizonDays: 0
            ))
        }
    }
}
