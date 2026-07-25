import AuditorModels
import AuditorPolicy
import Foundation

enum FilenameCapitalizationStyle: Hashable {
    case lowercase
    case uppercase
    case titleCase
    case mixed
}

enum FilenamePolicyRules {
    static let maximumFilenameLength = 120

    static func analyze(files: [FileRecord], policy: Policy?) -> [String: [FilenamePolicyViolation]] {
        let template = policy?.namingTemplate.flatMap { try? NamingTemplate($0) }
        let dominantStyles = dominantCapitalizationStyles(in: files)
        var result: [String: [FilenamePolicyViolation]] = [:]

        for file in files {
            let directory = (file.path as NSString).deletingLastPathComponent
            let violations = violations(
                for: file,
                template: template,
                expectedCapitalization: dominantStyles[directory]
            )
            if !violations.isEmpty { result[file.path] = violations }
        }
        return result
    }

    static func violations(
        for file: FileRecord,
        template: NamingTemplate?,
        expectedCapitalization: FilenameCapitalizationStyle?
    ) -> [FilenamePolicyViolation] {
        let filename = file.filename
        let stem = (filename as NSString).deletingPathExtension
        let normalizedStem = stem
            .lowercased()
            .replacingOccurrences(of: #"[_\-.]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        var violations: [FilenamePolicyViolation] = []

        if let template, template.match(filename: filename) == nil {
            violations.append(FilenamePolicyViolation(
                ruleID: "naming.template-mismatch",
                explanation: "Does not match the active naming template “\(template.source)”."
            ))
            if template.slots.contains(.date), !containsISODate(stem) {
                violations.append(FilenamePolicyViolation(
                    ruleID: "naming.missing-date",
                    explanation: "The template requires a valid YYYY-MM-DD date."
                ))
            }
        }

        if isGenericName(normalizedStem) {
            violations.append(FilenamePolicyViolation(
                ruleID: "universal.generic-name",
                explanation: "The filename is generic and does not identify the document."
            ))
        }

        if filename.count > maximumFilenameLength {
            violations.append(FilenamePolicyViolation(
                ruleID: "universal.excessive-length",
                explanation: "The filename is \(filename.count) characters; the policy limit is \(maximumFilenameLength)."
            ))
        }

        if containsIllegalCharacters(filename) {
            violations.append(FilenamePolicyViolation(
                ruleID: "universal.illegal-characters",
                explanation: "Contains characters unsafe across common cloud and NAS filesystems."
            ))
        }

        if hasVersionLabelSmell(normalizedStem) {
            violations.append(FilenamePolicyViolation(
                ruleID: "universal.version-label-smell",
                explanation: "Contains an unreliable version label such as repeated “final” or “use this one”."
            ))
        }

        if let expectedCapitalization {
            let style = capitalizationStyle(stem)
            if style != .mixed, style != expectedCapitalization {
                violations.append(FilenamePolicyViolation(
                    ruleID: "universal.capitalization-inconsistent",
                    explanation: "Capitalization differs from most filenames in this folder."
                ))
            }
        }

        return violations
    }

    private static func containsISODate(_ stem: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: #"\b\d{4}-\d{2}-\d{2}\b"#),
              let match = regex.firstMatch(in: stem, range: NSRange(stem.startIndex..., in: stem)),
              let range = Range(match.range, in: stem)
        else { return false }
        return NamingTemplate.date(from: String(stem[range])) != nil
    }

    private static func isGenericName(_ normalizedStem: String) -> Bool {
        let patterns = [
            #"^(?:scan|document|file|untitled|new document)\s*\d*$"#,
            #"^img\s*\d+$"#,
            #"^dsc\s*\d+$"#,
            #"^screenshot(?:\s+\d.*)?$"#,
        ]
        return patterns.contains {
            normalizedStem.range(of: $0, options: .regularExpression) != nil
        }
    }

    private static func containsIllegalCharacters(_ filename: String) -> Bool {
        let unsafe = CharacterSet(charactersIn: #"<>:"/\|?*"#).union(.controlCharacters)
        return filename.unicodeScalars.contains { unsafe.contains($0) }
    }

    private static func hasVersionLabelSmell(_ normalizedStem: String) -> Bool {
        if normalizedStem.contains("use this one") || normalizedStem.contains("final final") {
            return true
        }
        let words = normalizedStem.split(separator: " ").map(String.init)
        for label in ["final", "draft", "new", "latest"] where words.filter({ $0 == label }).count > 1 {
            return true
        }
        return false
    }

    private static func dominantCapitalizationStyles(in files: [FileRecord]) -> [String: FilenameCapitalizationStyle] {
        var counts: [String: [FilenameCapitalizationStyle: Int]] = [:]
        for file in files {
            let directory = (file.path as NSString).deletingLastPathComponent
            let stem = (file.filename as NSString).deletingPathExtension
            let style = capitalizationStyle(stem)
            guard style != .mixed else { continue }
            counts[directory, default: [:]][style, default: 0] += 1
        }

        var result: [String: FilenameCapitalizationStyle] = [:]
        for (directory, styleCounts) in counts {
            let total = styleCounts.values.reduce(0, +)
            guard total >= 3, let dominant = styleCounts.max(by: { $0.value < $1.value }),
                  dominant.value >= 2, Double(dominant.value) / Double(total) >= 0.6
            else { continue }
            result[directory] = dominant.key
        }
        return result
    }

    private static func capitalizationStyle(_ stem: String) -> FilenameCapitalizationStyle {
        let words = stem
            .split(whereSeparator: { !$0.isLetter })
            .map(String.init)
            .filter { !$0.isEmpty }
        guard !words.isEmpty else { return .mixed }
        if words.allSatisfy({ $0 == $0.lowercased() }) { return .lowercase }
        if words.allSatisfy({ $0 == $0.uppercased() }) { return .uppercase }
        if words.allSatisfy({
            guard let first = $0.first else { return false }
            return first.isUppercase && $0.dropFirst() == Substring($0.dropFirst().lowercased())
        }) {
            return .titleCase
        }
        return .mixed
    }
}

public struct FilenamePolicyDetector: Detector {
    public static let id = "core.filenamePolicy"
    public let displayName = "Filename policy"
    public let requiredSignals: DetectorSignals = [.policy]

    public init() {}

    public func detect(context: DetectionContext) async throws -> [Finding] {
        let analyses = FilenamePolicyRules.analyze(files: context.files, policy: context.policy)
        return context.files.compactMap { file in
            guard let violations = analyses[file.path], !violations.isEmpty else { return nil }
            let ruleList = violations.map(\.explanation).joined(separator: " ")
            return Finding(
                detectorID: Self.id,
                kind: "core.filenamePolicy",
                severity: violations.contains(where: { $0.ruleID == "universal.illegal-characters" }) ? .medium : .low,
                files: [FileRef(file)],
                evidence: .filenamePolicy(
                    template: context.policy?.namingTemplate,
                    violations: violations,
                    proposedName: nil,
                    judge: nil
                ),
                explanation: "“\(file.filename)” violates \(violations.count) filename rule"
                    + (violations.count == 1 ? ": " : "s: ") + ruleList,
                recommendation: .review(note: "Review this filename against the cited rules."),
                confidence: 1,
                stableKeyMaterial: violations.map(\.ruleID).sorted().joined(separator: "|"),
                scanID: context.scanID
            )
        }
        .sorted { $0.stableKey < $1.stableKey }
    }
}
