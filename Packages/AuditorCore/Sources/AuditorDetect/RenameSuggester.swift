import AuditorAI
import AuditorModels
import AuditorPolicy
import Foundation

enum RulesOnlyDocumentIdentity {
    private static let documentTypes: [(keywords: [String], name: String)] = [
        (["board minutes", "meeting minutes", "minutes"], "Board Minutes"),
        (["grant agreement", "agreement"], "Agreement"),
        (["contract"], "Contract"),
        (["invoice"], "Invoice"),
        (["budget"], "Budget"),
        (["policy"], "Policy"),
        (["proposal"], "Proposal"),
        (["report"], "Report"),
        (["handbook"], "Handbook"),
        (["receipt"], "Receipt"),
    ]

    static func build(for file: FileRecord) -> DocumentIdentity {
        let stem = (file.filename as NSString).deletingPathExtension
        let normalized = stem
            .lowercased()
            .replacingOccurrences(of: #"[_\-.]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        let tokens = VersionTokenParser.parse(filename: file.filename)

        let docType = documentTypes.first { entry in
            entry.keywords.contains { normalized.contains($0) }
        }?.name ?? inferredTypeFromExtension(file.filename)

        let date: String
        if let value = tokens.dateValue {
            date = String(format: "%04d-%02d-%02d", value / 10_000, (value / 100) % 100, value % 100)
        } else {
            let timestamp = file.createdAt
                ?? Date(timeIntervalSince1970: Double(file.mtimeNanoseconds) / 1_000_000_000)
            date = NamingTemplate.isoDateFormatter.string(from: timestamp)
        }

        let parent = ((file.path as NSString).deletingLastPathComponent as NSString).lastPathComponent
            .replacingOccurrences(of: #"^\d+\s*"#, with: "", options: .regularExpression)
        let organization = parent.isEmpty ? "Organization" : parent
        let status = tokens.statuses.max {
            (VersionTokenParser.statusRanks[$0] ?? 0) < (VersionTokenParser.statusRanks[$1] ?? 0)
        }
        .map(titleCaseStatus) ?? "Current"
        let title = tokens.stem.isEmpty ? stem : tokens.stem

        return DocumentIdentity(
            docType: docType,
            organization: organization,
            date: date,
            status: status,
            titleSummary: title
        )
    }

    private static func inferredTypeFromExtension(_ filename: String) -> String {
        switch (filename as NSString).pathExtension.lowercased() {
        case "jpg", "jpeg", "png", "heic", "tiff", "tif":
            return "Image"
        case "csv", "xlsx":
            return "Spreadsheet"
        case "md", "txt":
            return "Notes"
        default:
            return "Document"
        }
    }

    private static func titleCaseStatus(_ status: String) -> String {
        switch status {
        case "usethisone": return "Current"
        case "wip": return "Draft"
        case "bak": return "Backup"
        default: return status.capitalized
        }
    }
}

public struct RenameSuggester: Detector {
    public static let id = "core.rename"
    public let displayName = "Filename recommendations"
    public let requiredSignals: DetectorSignals = [.policy, .textContent, .semanticJudge]

    private let judgeAvailability: @Sendable () async -> ModelAvailability
    private let identifyDocument: @Sendable (DocumentIdentityRequest) async throws -> DocumentIdentity

    public init() {
        let judge = FoundationModelDocumentIdentityJudge()
        self.judgeAvailability = { await judge.availability() }
        self.identifyDocument = { request in try await judge.identify(request) }
    }

    public init(judge: any DocumentIdentityJudging) {
        self.judgeAvailability = { await judge.availability() }
        self.identifyDocument = { request in try await judge.identify(request) }
    }

    public func detect(context: DetectionContext) async throws -> [Finding] {
        guard let templateSource = context.policy?.namingTemplate,
              let template = try? NamingTemplate(templateSource)
        else { return [] }

        let analyses = FilenamePolicyRules.analyze(files: context.files, policy: context.policy)
        let semanticAvailable = await judgeAvailability().isAvailable
        var findings: [Finding] = []

        for file in context.files {
            try Task.checkCancellation()
            guard let violations = analyses[file.path], !violations.isEmpty else { continue }

            let fallback = RulesOnlyDocumentIdentity.build(for: file)
            var identity = fallback
            var source = JudgeSource.rules

            if semanticAvailable, let text = context.extractedText?[file.path], !text.isEmpty {
                let request = DocumentIdentityRequest(
                    filename: file.filename,
                    modifiedAt: Date(
                        timeIntervalSince1970: Double(file.mtimeNanoseconds) / 1_000_000_000
                    ),
                    createdAt: file.createdAt,
                    text: text
                )
                do {
                    let generated = try await identifyDocument(request)
                    if generated.isStructurallyValid() {
                        let merged = Self.merge(generated: generated, fallback: fallback)
                        if merged != fallback {
                            identity = merged
                            source = .foundationModel
                        }
                    }
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    // Rules-only identity remains fully usable.
                }
            }

            let values = NamingValues(
                date: NamingTemplate.date(from: identity.date),
                docType: identity.docType,
                organization: identity.organization,
                status: identity.status,
                title: identity.titleSummary
            )
            let fileExtension = (file.filename as NSString).pathExtension
            guard let proposedName = try? template.render(values: values, fileExtension: fileExtension),
                  proposedName.caseInsensitiveCompare(file.filename) != .orderedSame
            else { continue }

            let identityEvidence = [
                identity.docType,
                identity.organization,
                identity.date,
                identity.status,
            ].filter { !$0.isEmpty }.joined(separator: ", ")
            let sourceExplanation = source == .foundationModel
                ? "On-device identity fields (\(identityEvidence)) were validated and rendered through the active template."
                : "Filename and filesystem metadata supplied the fallback fields (\(identityEvidence)), rendered through the active template."

            findings.append(Finding(
                detectorID: Self.id,
                kind: "core.filenamePolicy.rename",
                severity: .low,
                files: [FileRef(file)],
                evidence: .filenamePolicy(
                    template: template.source,
                    violations: violations,
                    proposedName: proposedName,
                    judge: source
                ),
                explanation: "“\(file.filename)” fails \(violations.count) cited filename rule"
                    + (violations.count == 1 ? ". " : "s. ") + sourceExplanation,
                recommendation: .rename(file: FileRef(file), proposedName: proposedName),
                confidence: source == .foundationModel ? 0.78 : 0.55,
                stableKeyMaterial: "template:\(template.source)",
                scanID: context.scanID
            ))
        }

        return findings.sorted { $0.stableKey < $1.stableKey }
    }

    private static func merge(generated: DocumentIdentity, fallback: DocumentIdentity) -> DocumentIdentity {
        DocumentIdentity(
            docType: usable(generated.docType) ?? fallback.docType,
            organization: usable(generated.organization) ?? fallback.organization,
            date: NamingTemplate.date(from: generated.date) == nil ? fallback.date : generated.date,
            status: usable(generated.status) ?? fallback.status,
            titleSummary: usable(generated.titleSummary) ?? fallback.titleSummary
        )
    }

    private static func usable(_ value: String) -> String? {
        let sanitized = NamingTemplate.sanitizeSlotValue(value)
        return sanitized.isEmpty ? nil : value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
