import Foundation

/// Everything version-ish parsed out of a filename, plus the normalized stem
/// (what remains once version noise is removed). Files in the same directory
/// with the same extension and the same stem form a version-family candidate.
public struct VersionTokens: Sendable, Equatable {
    public var explicitVersion: Int?     // v2, ver3, version 4, rev 5
    public var copyNumber: Int?          // (1), copy 2
    public var looseNumber: Int?         // trailing counter next to other signals: "Final 2"
    public var isCopy = false            // "copy", "Copy of"
    public var isConflictedCopy = false  // Dropbox/OneDrive sync conflicts
    public var statuses: [String] = []   // final, draft, approved, old, backup…
    public var statusRank = 0            // max rank across statuses (see table)
    public var dateValue: Int?           // yyyymmdd from a full date in the name
    public var yearOnly: Int?            // bare year token when no full date
    public var stem = ""                 // normalized remainder
    public var rawTokens: [String] = []  // matched fragments, for evidence display

    /// True when anything at all marks this file as a version/derivative.
    /// A bare year does NOT count — "invoice 2024"/"invoice 2025" are different
    /// documents, not versions (the ranker caps such clusters separately).
    public var hasVersionSignal: Bool {
        explicitVersion != nil || copyNumber != nil || looseNumber != nil
            || isCopy || isConflictedCopy || !statuses.isEmpty || dateValue != nil
    }
}

public enum VersionTokenParser {
    /// Positive = likely current; negative = likely stale/derivative.
    static let statusRanks: [String: Int] = [
        "signed": 5, "executed": 5,
        "approved": 4,
        "final": 3,
        "latest": 2, "current": 2, "usethisone": 2,
        "updated": 1, "revised": 1, "edited": 1, "new": 1,
        "draft": -2, "wip": -2,
        "old": -3, "backup": -3, "bak": -3, "archived": -3, "archive": -3,
    ]

    public static func parse(filename: String) -> VersionTokens {
        // Normalize separators to spaces first: `\b` treats "_" as a word
        // character, so "Policy_FINAL_v2" would otherwise hide every token.
        var working = ((filename as NSString).deletingPathExtension)
            .replacingOccurrences(of: #"[._\-]+"#, with: " ", options: .regularExpression)
        var tokens = VersionTokens()

        // Order matters: broad multi-word patterns first so their fragments
        // don't get misread by narrower patterns.

        // Sync-conflict markers: "(Kadeem's conflicted copy 2)", "conflicted copy".
        consume(#"\(?[^()]*conflicted copy(?: \d+)?\)?"#, from: &working) { _, raw in
            tokens.isConflictedCopy = true
            tokens.rawTokens.append(raw)
        }

        // Full dates. ISO first (2026-07-15, 2026.07.15, 20260715)…
        consume(#"\b(20\d{2})[-._ ]?(0[1-9]|1[0-2])[-._ ]?(0[1-9]|[12]\d|3[01])\b"#, from: &working) { groups, raw in
            if let y = groups[1], let m = groups[2], let d = groups[3],
               tokens.dateValue == nil {
                tokens.dateValue = Int(y)! * 10_000 + Int(m)! * 100 + Int(d)!
                tokens.rawTokens.append(raw)
            }
        }
        // …then US style (7-15-2026, 07/15/2026 — separators already spaced).
        consume(#"\b(0?[1-9]|1[0-2])[/ ](0?[1-9]|[12]\d|3[01])[/ ](20\d{2})\b"#, from: &working) { groups, raw in
            if let m = groups[1], let d = groups[2], let y = groups[3],
               tokens.dateValue == nil {
                tokens.dateValue = Int(y)! * 10_000 + Int(m)! * 100 + Int(d)!
                tokens.rawTokens.append(raw)
            }
        }

        // Explicit versions: v2, ver_3, version-4, rev5, revision 6.
        consume(#"\b(?:v|ver|version|rev|revision)[ ._-]?(\d{1,4})\b"#, from: &working) { groups, raw in
            if let value = groups[1].flatMap({ Int($0) }) {
                tokens.explicitVersion = max(tokens.explicitVersion ?? Int.min, value)
                tokens.rawTokens.append(raw)
            }
        }

        // "Copy of X" prefix, "X copy", "X copy 2".
        consume(#"\bcopy\s+of\b"#, from: &working) { _, raw in
            tokens.isCopy = true
            tokens.rawTokens.append(raw)
        }
        consume(#"\bcopy(?:[ _-]*(\d{1,3}))?\b"#, from: &working) { groups, raw in
            tokens.isCopy = true
            if let value = groups[1].flatMap({ Int($0) }) {
                tokens.copyNumber = max(tokens.copyNumber ?? 0, value)
            }
            tokens.rawTokens.append(raw)
        }

        // Finder's " (2)" counters.
        consume(#"\((\d{1,3})\)"#, from: &working) { groups, raw in
            if let value = groups[1].flatMap({ Int($0) }) {
                tokens.copyNumber = max(tokens.copyNumber ?? 0, value)
                tokens.rawTokens.append(raw)
            }
        }

        // Status words (collect all; "final final" just matches twice).
        consume(#"\b(final|approved|signed|executed|latest|current|updated|revised|edited|new|draft|wip|old|backup|bak|archived|archive|use[ _-]?this[ _-]?one)\b"#, from: &working) { groups, raw in
            if let word = groups[1]?.lowercased() {
                let key = word.replacingOccurrences(of: "[ _-]", with: "", options: .regularExpression)
                tokens.statuses.append(key)
                tokens.rawTokens.append(raw)
            }
        }
        tokens.statusRank = tokens.statuses.compactMap { statusRanks[$0] }.max() ?? 0

        // Bare year (only when no full date was found).
        if tokens.dateValue == nil {
            consume(#"\b(20\d{2})\b"#, from: &working) { groups, raw in
                if let value = groups[1].flatMap({ Int($0) }), tokens.yearOnly == nil {
                    tokens.yearOnly = value
                    tokens.rawTokens.append(raw)
                }
            }
        }

        // Loose trailing counters ("Handbook Final 2") — consumed ONLY when the
        // filename already carries another version signal. Otherwise the number
        // stays in the stem, which is what keeps "Chapter 1"/"Chapter 2" from
        // ever clustering as versions of each other.
        if tokens.hasVersionSignal {
            consume(#"\b(\d{1,2})\b"#, from: &working) { groups, raw in
                if let value = groups[1].flatMap({ Int($0) }) {
                    tokens.looseNumber = max(tokens.looseNumber ?? 0, value)
                    tokens.rawTokens.append(raw)
                }
            }
        }

        tokens.stem = working
            .lowercased()
            .replacingOccurrences(of: #"[._\-,()\[\]{}#]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)

        return tokens
    }

    /// Runs `pattern` case-insensitively over `working`, invoking `handler` with
    /// capture groups (index 0 = whole match) per match, then blanks the matched
    /// ranges so later patterns can't re-read them.
    private static func consume(
        _ pattern: String,
        from working: inout String,
        handler: ([String?], String) -> Void
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return }
        let matches = regex.matches(in: working, range: NSRange(working.startIndex..., in: working))
        guard !matches.isEmpty else { return }

        let source = working as NSString
        var result = working as NSString
        for match in matches.reversed() {
            var groups: [String?] = []
            for index in 0..<match.numberOfRanges {
                let range = match.range(at: index)
                groups.append(range.location == NSNotFound ? nil : source.substring(with: range))
            }
            handler(groups, source.substring(with: match.range))
            result = result.replacingCharacters(in: match.range, with: " ") as NSString
        }
        working = result as String
    }
}
