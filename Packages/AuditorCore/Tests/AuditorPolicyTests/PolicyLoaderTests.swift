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
}
