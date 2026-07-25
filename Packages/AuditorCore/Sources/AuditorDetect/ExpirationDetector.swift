import AuditorAI
import AuditorModels
import Foundation

struct DetectedDateCandidate: Sendable, Equatable {
    let date: Date
    let matchedText: String
    let context: String
    let matchRangeInContext: NSRange
}

enum DateCandidateExtractor {
    static let contextRadius = 200
    static let maximumCandidatesPerDocument = 24
    private static let maximumRawMatchesPerDocument = 500

    static func candidates(in text: String, calendar: Calendar) throws -> [DetectedDateCandidate] {
        let detector = try NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        let source = text as NSString
        let fullRange = NSRange(location: 0, length: source.length)
        let matches = detector.matches(in: text, options: [], range: fullRange)
        var candidates: [DetectedDateCandidate] = []

        for match in matches.prefix(maximumRawMatchesPerDocument) {
            guard let detectedDate = match.date else { continue }
            let contextStart = max(0, match.range.location - contextRadius)
            let contextEnd = min(source.length, NSMaxRange(match.range) + contextRadius)
            let contextRange = NSRange(location: contextStart, length: contextEnd - contextStart)
            candidates.append(DetectedDateCandidate(
                date: calendar.startOfDay(for: detectedDate),
                matchedText: source.substring(with: match.range),
                context: source.substring(with: contextRange),
                matchRangeInContext: NSRange(
                    location: match.range.location - contextStart,
                    length: match.range.length
                )
            ))
        }

        return candidates
    }
}

enum RulesDateMeaningClassifier {
    private struct Signal {
        let kind: DateMeaningKind
        let phrases: [String]
        let priority: Int
    }

    private static let signals: [Signal] = [
        Signal(
            kind: .cancellationDeadline,
            phrases: [
                "cancellation deadline", "cancel by", "terminate by",
                "notice must be received by", "non-renewal notice",
            ],
            priority: 0
        ),
        Signal(
            kind: .autoRenewal,
            phrases: [
                "automatically renew", "automatic renewal", "auto-renew",
                "auto renew", "renews on", "renewal date",
            ],
            priority: 1
        ),
        Signal(
            kind: .expiration,
            phrases: [
                "expires", "expiration", "expiry", "valid through",
                "in force through", "term ends", "ends on",
            ],
            priority: 2
        ),
        Signal(
            kind: .reportingDeadline,
            phrases: [
                "report due", "reporting deadline", "due by",
                "submit by", "submitted by", "filing deadline",
            ],
            priority: 3
        ),
        Signal(
            kind: .effective,
            phrases: ["effective", "commences", "begins", "start date"],
            priority: 4
        ),
    ]

    private static let obligationTerms = [
        "deadline", "due", "renew", "expire", "expiry", "term", "effective",
        "valid", "notice", "agreement", "contract", "lease", "license",
        "insurance", "coverage", "certificate", "grant", "report",
    ]

    static func isPotentialObligation(_ candidate: DetectedDateCandidate) -> Bool {
        let context = candidate.context.lowercased()
        return obligationTerms.contains { context.contains($0) }
    }

    static func classify(_ candidate: DetectedDateCandidate) -> ValidatedDateMeaning? {
        guard let kind = nearestKind(to: candidate.matchRangeInContext, in: candidate.context) else {
            return nil
        }
        let lowercased = candidate.context.lowercased()
        let renews = (kind == .autoRenewal || kind == .expiration)
            && (lowercased.contains("automatically renew")
                || lowercased.contains("automatic renewal")
                || lowercased.contains("auto-renew")
                || lowercased.contains("auto renew"))

        return ValidatedDateMeaning(
            kind: kind,
            date: candidate.date,
            autoRenews: renews,
            noticePeriodDays: noticePeriodDays(in: candidate.context) ?? 0,
            party: nil
        )
    }

    private static func nearestKind(to dateRange: NSRange, in context: String) -> DateMeaningKind? {
        let source = context as NSString
        var best: (distance: Int, priority: Int, kind: DateMeaningKind)?

        for signal in signals {
            for phrase in signal.phrases {
                var searchRange = NSRange(location: 0, length: source.length)
                while searchRange.length > 0 {
                    let found = source.range(
                        of: phrase,
                        options: [.caseInsensitive, .diacriticInsensitive],
                        range: searchRange
                    )
                    guard found.location != NSNotFound else { break }
                    let distance = rangeDistance(found, dateRange)
                    if distance <= 140 {
                        let candidate = (distance, signal.priority, signal.kind)
                        if best == nil
                            || candidate.0 < best!.distance
                            || (candidate.0 == best!.distance && candidate.1 < best!.priority)
                        {
                            best = candidate
                        }
                    }

                    let nextLocation = NSMaxRange(found)
                    guard nextLocation < source.length else { break }
                    searchRange = NSRange(location: nextLocation, length: source.length - nextLocation)
                }
            }
        }

        return best?.kind
    }

    private static func rangeDistance(_ lhs: NSRange, _ rhs: NSRange) -> Int {
        if NSMaxRange(lhs) < rhs.location { return rhs.location - NSMaxRange(lhs) }
        if NSMaxRange(rhs) < lhs.location { return lhs.location - NSMaxRange(rhs) }
        return 0
    }

    private static func noticePeriodDays(in context: String) -> Int? {
        let patterns = [
            #"(?:at\s+least\s+)?(\d{1,4})\s*(?:-|‑)?\s*days?\s+(?:written\s+)?notice"#,
            #"notice.{0,50}?(\d{1,4})\s*days?"#,
            #"(\d{1,4})\s*days?\s+(?:before|prior\s+to|in\s+advance)"#,
        ]
        let source = context as NSString

        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = expression.firstMatch(
                    in: context,
                    options: [],
                    range: NSRange(location: 0, length: source.length)
                  ),
                  match.numberOfRanges > 1
            else { continue }
            let range = match.range(at: 1)
            guard range.location != NSNotFound,
                  let days = Int(source.substring(with: range)),
                  (0...3650).contains(days)
            else { continue }
            return days
        }

        return nil
    }
}

public struct ExpirationDetector: Detector {
    public static let id = "core.expiration"
    public let displayName = "Dated obligations"
    public let requiredSignals: DetectorSignals = [.textContent, .semanticJudge, .policy]

    static let defaultHorizonDays = 90
    static let actionBufferDays = 14
    static let maximumOverdueDays = 365

    private let judgeAvailability: @Sendable () async -> ModelAvailability
    private let classifyDate: @Sendable (DateMeaningRequest) async throws -> DateMeaning
    private let referenceDate: @Sendable () -> Date
    private let calendar: Calendar

    public init() {
        let judge = FoundationModelDateMeaningJudge()
        self.judgeAvailability = { await judge.availability() }
        self.classifyDate = { request in try await judge.classify(request) }
        self.referenceDate = { Date() }
        self.calendar = Calendar(identifier: .gregorian)
    }

    public init(
        judge: any DateMeaningJudging,
        referenceDate: @escaping @Sendable () -> Date = { Date() },
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) {
        self.judgeAvailability = { await judge.availability() }
        self.classifyDate = { request in try await judge.classify(request) }
        self.referenceDate = referenceDate
        self.calendar = calendar
    }

    public func detect(context: DetectionContext) async throws -> [Finding] {
        guard let extractedText = context.extractedText else { return [] }
        let modelAvailable = await judgeAvailability().isAvailable
        let horizon = context.policy?.expirationHorizonDays ?? Self.defaultHorizonDays
        let today = calendar.startOfDay(for: referenceDate())
        var findings: [Finding] = []

        for file in context.files {
            try Task.checkCancellation()
            guard let text = extractedText[file.path], !text.isEmpty else { continue }

            let analyzedCandidates = try DateCandidateExtractor.candidates(in: text, calendar: calendar)
                .compactMap { candidate -> (DetectedDateCandidate, ValidatedDateMeaning?)? in
                    let detectedDate = calendar.startOfDay(for: candidate.date)
                    let daysUntil = calendar.dateComponents([.day], from: today, to: detectedDate).day ?? Int.max
                    guard daysUntil <= horizon, daysUntil >= -Self.maximumOverdueDays else { return nil }
                    let rulesMeaning = RulesDateMeaningClassifier.classify(candidate)
                    guard rulesMeaning != nil || RulesDateMeaningClassifier.isPotentialObligation(candidate) else {
                        return nil
                    }
                    return (candidate, rulesMeaning)
                }
                .sorted { lhs, rhs in
                    let lhsActionable = lhs.1?.kind.isActionable == true
                    let rhsActionable = rhs.1?.kind.isActionable == true
                    if lhsActionable != rhsActionable { return lhsActionable }
                    return lhs.0.date < rhs.0.date
                }
                .prefix(DateCandidateExtractor.maximumCandidatesPerDocument)

            for (candidate, rulesMeaning) in analyzedCandidates {
                try Task.checkCancellation()

                var meaning = rulesMeaning
                var source = JudgeSource.rules

                if modelAvailable {
                    let request = DateMeaningRequest(
                        filename: file.filename,
                        observedDate: candidate.date,
                        matchedText: candidate.matchedText,
                        context: candidate.context
                    )
                    do {
                        let generated = try await classifyDate(request)
                        if let validated = generated.validated(for: request) {
                            meaning = Self.merge(generated: validated, rules: rulesMeaning)
                            source = .foundationModel
                        }
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        // A rules classification remains fully usable.
                    }
                }

                guard let meaning, meaning.kind.isActionable else { continue }
                let detectedDate = calendar.startOfDay(for: meaning.date)
                let daysUntil = calendar.dateComponents([.day], from: today, to: detectedDate).day ?? Int.max

                let actionDate = Self.actionDate(
                    for: meaning,
                    calendar: calendar,
                    bufferDays: Self.actionBufferDays
                )
                let snippet = Self.evidenceSnippet(candidate.context)
                let finding = Finding(
                    detectorID: Self.id,
                    kind: "core.expiration.\(meaning.kind.rawValue)",
                    severity: Self.severity(
                        detectedDate: detectedDate,
                        actionDate: actionDate,
                        today: today,
                        daysUntil: daysUntil
                    ),
                    files: [FileRef(file)],
                    evidence: .expiration(
                        kind: meaning.kind,
                        detectedDate: detectedDate,
                        actionDate: actionDate,
                        autoRenews: meaning.autoRenews,
                        noticePeriodDays: meaning.noticePeriodDays,
                        party: meaning.party,
                        contextSnippet: snippet,
                        judge: source
                    ),
                    explanation: Self.explanation(
                        filename: file.filename,
                        meaning: meaning,
                        detectedDate: detectedDate,
                        actionDate: actionDate,
                        snippet: snippet,
                        source: source
                    ),
                    recommendation: .scheduleReminder(
                        actionDate: actionDate,
                        note: Self.reminderNote(
                            filename: file.filename,
                            kind: meaning.kind,
                            detectedDate: detectedDate
                        )
                    ),
                    confidence: source == .foundationModel ? 0.84 : 0.70,
                    stableKeyMaterial: "\(meaning.kind.rawValue):\(Self.isoDay(detectedDate, calendar: calendar))",
                    scanID: context.scanID
                )
                findings.append(finding)
            }
        }

        var seen = Set<String>()
        return findings
            .sorted { ($0.severity, $0.stableKey) > ($1.severity, $1.stableKey) }
            .filter { seen.insert($0.stableKey).inserted }
    }

    static func actionDate(
        for meaning: ValidatedDateMeaning,
        calendar: Calendar,
        bufferDays: Int = actionBufferDays
    ) -> Date {
        let noticeDays: Int
        switch meaning.kind {
        case .expiration, .autoRenewal:
            noticeDays = meaning.noticePeriodDays
        case .cancellationDeadline, .reportingDeadline, .effective, .other:
            noticeDays = 0
        }
        return calendar.date(
            byAdding: .day,
            value: -(noticeDays + bufferDays),
            to: calendar.startOfDay(for: meaning.date)
        ) ?? meaning.date
    }

    /// Semantic classification can add meaning and party information, but it
    /// must not erase explicit renewal/notice facts extracted from the text.
    private static func merge(
        generated: ValidatedDateMeaning,
        rules: ValidatedDateMeaning?
    ) -> ValidatedDateMeaning {
        guard let rules else { return generated }
        let resolvedKind = rules.kind.isActionable ? rules.kind : generated.kind
        let supportsRenewal = resolvedKind == .autoRenewal || resolvedKind == .expiration
        return ValidatedDateMeaning(
            kind: resolvedKind,
            date: generated.date,
            autoRenews: supportsRenewal && (generated.autoRenews || rules.autoRenews),
            noticePeriodDays: rules.noticePeriodDays > 0
                ? rules.noticePeriodDays
                : generated.noticePeriodDays,
            party: generated.party ?? rules.party
        )
    }

    private static func severity(
        detectedDate: Date,
        actionDate: Date,
        today: Date,
        daysUntil: Int
    ) -> Severity {
        if detectedDate < today || actionDate <= today || daysUntil <= 30 {
            return .high
        }
        return .medium
    }

    private static func explanation(
        filename: String,
        meaning: ValidatedDateMeaning,
        detectedDate: Date,
        actionDate: Date,
        snippet: String,
        source: JudgeSource
    ) -> String {
        let sourceLabel = source == .foundationModel
            ? "Validated on-device date classification"
            : "Deterministic date-context rules"
        let notice = meaning.noticePeriodDays > 0
            ? " The text states a \(meaning.noticePeriodDays)-day notice period."
            : ""
        let party = meaning.party.map { " Responsible party: \($0)." } ?? ""
        let name = humanName(meaning.kind)
        let article = name.first.map { "aeiou".contains($0.lowercased()) } == true ? "an" : "a"
        let citedSnippet = snippet.last.map { ".!?".contains($0) } == true ? snippet : snippet + "."
        return "“\(filename)” contains \(article) \(name) on "
            + "\(isoDay(detectedDate, calendar: Calendar(identifier: .gregorian))). "
            + "\(sourceLabel) cites: “\(citedSnippet)”\(notice)\(party) "
            + "Recommended action date: \(isoDay(actionDate, calendar: Calendar(identifier: .gregorian)))."
    }

    private static func reminderNote(
        filename: String,
        kind: DateMeaningKind,
        detectedDate: Date
    ) -> String {
        "Review \(humanName(kind)) for \(filename), dated "
            + "\(isoDay(detectedDate, calendar: Calendar(identifier: .gregorian)))."
    }

    private static func evidenceSnippet(_ context: String) -> String {
        let collapsed = context
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return String(collapsed.prefix(400))
    }

    private static func humanName(_ kind: DateMeaningKind) -> String {
        switch kind {
        case .effective: "effective date"
        case .expiration: "document expiration"
        case .autoRenewal: "automatic renewal"
        case .cancellationDeadline: "cancellation deadline"
        case .reportingDeadline: "reporting deadline"
        case .other: "date"
        }
    }

    static func isoDay(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}
