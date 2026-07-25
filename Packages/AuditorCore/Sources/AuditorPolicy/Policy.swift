import AuditorModels
import Foundation

/// A governance policy: naming template, folder taxonomy, and audit horizons.
/// Bundled templates (nonprofit, small business) are JSON resources in `Templates/`;
/// organizations can supply their own file.
public struct Policy: Codable, Sendable, Identifiable {
    public let id: String
    public let displayName: String
    /// Naming template DSL, e.g. "YYYY-MM-DD_{DocType}_{Org}_{Status}".
    /// Parsed and rendered by `NamingTemplate`.
    public let namingTemplate: String?
    /// Recommended top-level folder taxonomy, compared against — never forced onto —
    /// the organization's existing structure.
    public let folderTaxonomy: [String]
    /// Days ahead an expiring document becomes a finding.
    public let expirationHorizonDays: Int

    public init(
        id: String,
        displayName: String,
        namingTemplate: String?,
        folderTaxonomy: [String] = [],
        expirationHorizonDays: Int = 90
    ) {
        self.id = id
        self.displayName = displayName
        self.namingTemplate = namingTemplate
        self.folderTaxonomy = folderTaxonomy
        self.expirationHorizonDays = expirationHorizonDays
    }
}

public enum PolicyError: Error, Sendable, Equatable {
    case templateNotFound(String)
    case invalidPolicy(String)
}

public struct PolicyLoader: Sendable {
    public init() {}

    /// Loads a bundled policy template by id (e.g. "nonprofit", "small-business").
    public func loadBundledPolicy(id: String) throws -> Policy {
        guard let url = Bundle.module.url(forResource: id, withExtension: "json", subdirectory: "Templates") else {
            throw PolicyError.templateNotFound(id)
        }
        let policy = try JSONDecoder().decode(Policy.self, from: Data(contentsOf: url))
        try validate(policy)
        return policy
    }

    public func loadPolicy(from url: URL) throws -> Policy {
        let policy = try JSONDecoder().decode(Policy.self, from: Data(contentsOf: url))
        try validate(policy)
        return policy
    }

    public func validate(_ policy: Policy) throws {
        guard !policy.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PolicyError.invalidPolicy("id must not be empty")
        }
        guard !policy.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PolicyError.invalidPolicy("displayName must not be empty")
        }
        guard (1...3_650).contains(policy.expirationHorizonDays) else {
            throw PolicyError.invalidPolicy("expirationHorizonDays must be between 1 and 3650")
        }
        if let source = policy.namingTemplate {
            do {
                _ = try NamingTemplate(source)
            } catch {
                throw PolicyError.invalidPolicy("invalid namingTemplate: \(error)")
            }
        }
        let normalizedTaxonomy = policy.folderTaxonomy.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        guard !normalizedTaxonomy.contains(""), Set(normalizedTaxonomy).count == normalizedTaxonomy.count else {
            throw PolicyError.invalidPolicy("folderTaxonomy entries must be non-empty and unique")
        }
    }
}
