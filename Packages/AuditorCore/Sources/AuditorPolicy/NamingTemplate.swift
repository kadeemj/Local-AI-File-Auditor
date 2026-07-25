import Foundation

public enum NamingSlot: String, Codable, CaseIterable, Sendable {
    case date = "Date"
    case docType = "DocType"
    case organization = "Org"
    case status = "Status"
    case title = "Title"
}

public struct NamingValues: Sendable, Equatable {
    public var date: Date?
    public var docType: String?
    public var organization: String?
    public var status: String?
    public var title: String?

    public init(
        date: Date? = nil,
        docType: String? = nil,
        organization: String? = nil,
        status: String? = nil,
        title: String? = nil
    ) {
        self.date = date
        self.docType = docType
        self.organization = organization
        self.status = status
        self.title = title
    }

    func value(for slot: NamingSlot) -> String? {
        switch slot {
        case .date:
            guard let date else { return nil }
            return NamingTemplate.isoDateFormatter.string(from: date)
        case .docType:
            return docType
        case .organization:
            return organization
        case .status:
            return status
        case .title:
            return title
        }
    }
}

public enum NamingTemplateError: Error, Sendable, Equatable {
    case empty
    case tooLong
    case illegalCharacter(Character)
    case unbalancedPlaceholder
    case unknownSlot(String)
    case duplicateSlot(NamingSlot)
    case adjacentSlots
    case noSlots
    case missingValue(NamingSlot)
    case invalidDate(String)
}

public struct NamingTemplate: Sendable, Equatable {
    enum Component: Sendable, Equatable {
        case literal(String)
        case slot(NamingSlot)
    }

    public let source: String
    let components: [Component]

    public var slots: [NamingSlot] {
        components.compactMap {
            if case .slot(let slot) = $0 { return slot }
            return nil
        }
    }

    public init(_ source: String) throws {
        guard !source.isEmpty else { throw NamingTemplateError.empty }
        guard source.count <= 200 else { throw NamingTemplateError.tooLong }
        for illegal in ["/", "\\", ":", "\0"] where source.contains(illegal) {
            throw NamingTemplateError.illegalCharacter(Character(illegal))
        }

        var parsed: [Component] = []
        var literal = ""
        var seen: Set<NamingSlot> = []
        var index = source.startIndex

        func flushLiteral() {
            guard !literal.isEmpty else { return }
            parsed.append(.literal(literal))
            literal = ""
        }

        while index < source.endIndex {
            if source[index...].hasPrefix("YYYY-MM-DD") {
                flushLiteral()
                try Self.append(slot: .date, to: &parsed, seen: &seen)
                index = source.index(index, offsetBy: 10)
                continue
            }

            let character = source[index]
            if character == "{" {
                flushLiteral()
                guard let close = source[index...].firstIndex(of: "}") else {
                    throw NamingTemplateError.unbalancedPlaceholder
                }
                let nameStart = source.index(after: index)
                let name = String(source[nameStart..<close])
                guard let slot = Self.slot(named: name) else {
                    throw NamingTemplateError.unknownSlot(name)
                }
                try Self.append(slot: slot, to: &parsed, seen: &seen)
                index = source.index(after: close)
                continue
            }
            if character == "}" {
                throw NamingTemplateError.unbalancedPlaceholder
            }

            literal.append(character)
            index = source.index(after: index)
        }
        flushLiteral()

        guard !seen.isEmpty else { throw NamingTemplateError.noSlots }
        self.source = source
        self.components = parsed
    }

    public func render(values: NamingValues, fileExtension: String) throws -> String {
        var stem = ""
        for component in components {
            switch component {
            case .literal(let literal):
                stem += literal
            case .slot(let slot):
                guard let raw = values.value(for: slot), !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw NamingTemplateError.missingValue(slot)
                }
                if slot == .date {
                    guard Self.date(from: raw) != nil else { throw NamingTemplateError.invalidDate(raw) }
                    stem += raw
                } else {
                    stem += Self.sanitizeSlotValue(raw)
                }
            }
        }

        let ext = fileExtension.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return ext.isEmpty ? stem : "\(stem).\(ext.lowercased())"
    }

    public func match(filename: String) -> NamingValues? {
        let stem = (filename as NSString).deletingPathExtension
        var pattern = "^"
        for component in components {
            switch component {
            case .literal(let literal):
                pattern += NSRegularExpression.escapedPattern(for: literal)
            case .slot(.date):
                pattern += #"(\d{4}-\d{2}-\d{2})"#
            case .slot:
                pattern += "(.+?)"
            }
        }
        pattern += "$"

        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: stem, range: NSRange(stem.startIndex..., in: stem)),
              match.range == NSRange(stem.startIndex..., in: stem)
        else { return nil }

        var values = NamingValues()
        var captureIndex = 1
        for slot in slots {
            let range = match.range(at: captureIndex)
            guard range.location != NSNotFound, let swiftRange = Range(range, in: stem) else { return nil }
            let value = String(stem[swiftRange])
            switch slot {
            case .date:
                guard let date = Self.date(from: value) else { return nil }
                values.date = date
            case .docType:
                values.docType = value
            case .organization:
                values.organization = value
            case .status:
                values.status = value
            case .title:
                values.title = value
            }
            captureIndex += 1
        }
        return values
    }

    public static let isoDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter
    }()

    public static func date(from string: String) -> Date? {
        isoDateFormatter.date(from: string)
    }

    public static func sanitizeSlotValue(_ value: String) -> String {
        let folded = value.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
        var result = ""
        var pendingSeparator = false

        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "&" || scalar == "+" {
                if pendingSeparator, !result.isEmpty { result.append("-") }
                result.unicodeScalars.append(scalar)
                pendingSeparator = false
            } else if scalar == "-" || scalar == "_" || CharacterSet.whitespacesAndNewlines.contains(scalar) {
                pendingSeparator = !result.isEmpty
            }
        }

        return String(result.prefix(80)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private static func slot(named name: String) -> NamingSlot? {
        NamingSlot.allCases.first { $0.rawValue.caseInsensitiveCompare(name) == .orderedSame }
    }

    private static func append(
        slot: NamingSlot,
        to components: inout [Component],
        seen: inout Set<NamingSlot>
    ) throws {
        if seen.contains(slot) { throw NamingTemplateError.duplicateSlot(slot) }
        if case .slot = components.last { throw NamingTemplateError.adjacentSlots }
        seen.insert(slot)
        components.append(.slot(slot))
    }
}
