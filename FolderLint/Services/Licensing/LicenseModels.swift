import Foundation

enum LicensingKeys {
    static let trialStartedAt = "trial.startedAt"
    static let licenseKey = "license.key"
    static let instanceID = "license.instanceID"
    static let lastValidatedAt = "license.lastValidatedAt"
    static let snapshotJSON = "license.snapshotJSON"
    static let unlockedPolicyPacks = "license.unlockedPolicyPacks"
    static let lastNetworkCallAt = "license.lastNetworkCallAt"
}

/// Snapshot persisted after a successful activate/validate.
struct LicenseSnapshot: Codable, Sendable, Equatable {
    var licenseKey: String
    var instanceID: String
    var status: String
    var activationLimit: Int?
    var activationUsage: Int?
    var productName: String?
    var variantName: String?
    var expiresAt: Date?
    var customerEmail: String?
    /// Policy template IDs unlocked by this license / pack keys.
    var unlockedPolicyIDs: [String]

    var displayName: String {
        if let variantName, !variantName.isEmpty { return variantName }
        if let productName, !productName.isEmpty { return productName }
        return "Licensed"
    }
}

enum LicensePhase: String, Sendable, Equatable {
    case trial
    case trialExpired
    case licensed
    case grace
    case expired
    case deactivated
}

struct LicenseStatus: Sendable, Equatable {
    var phase: LicensePhase
    var daysRemaining: Int?
    var snapshot: LicenseSnapshot?
    var detail: String

    var canScan: Bool {
        switch phase {
        case .trial, .licensed, .grace: true
        case .trialExpired, .expired, .deactivated: false
        }
    }

    var isDegraded: Bool { !canScan }

    var shortLabel: String {
        switch phase {
        case .trial:
            if let daysRemaining { return "Trial — \(daysRemaining) day\(daysRemaining == 1 ? "" : "s") left" }
            return "Trial"
        case .trialExpired: return "Trial expired"
        case .licensed: return snapshot?.displayName ?? "Licensed"
        case .grace:
            if let daysRemaining { return "Offline grace — \(daysRemaining) day\(daysRemaining == 1 ? "" : "s") left" }
            return "Offline grace"
        case .expired: return "License expired"
        case .deactivated: return "Deactivated"
        }
    }
}

struct LicensingCapabilities: Sendable, Equatable {
    var canScan: Bool
    var canApply: Bool
    var canExportReports: Bool
    var availablePolicyIDs: Set<String>?

    static let full = LicensingCapabilities(
        canScan: true,
        canApply: true,
        canExportReports: true,
        availablePolicyIDs: nil
    )

    static let degraded = LicensingCapabilities(
        canScan: false,
        canApply: false,
        canExportReports: true,
        availablePolicyIDs: nil
    )
}

enum TrialClock {
    static let trialLengthDays = 14
    static let offlineGraceDays = 30
    static let validateIntervalHours = 24

    static func trialEnd(from start: Date, lengthDays: Int = trialLengthDays) -> Date {
        Calendar.current.date(byAdding: .day, value: lengthDays, to: start) ?? start
    }

    static func daysRemaining(from start: Date, now: Date = Date(), lengthDays: Int = trialLengthDays) -> Int {
        let end = trialEnd(from: start, lengthDays: lengthDays)
        if now >= end { return 0 }
        let seconds = end.timeIntervalSince(now)
        return max(1, Int(ceil(seconds / 86_400)))
    }

    static func isTrialActive(start: Date, now: Date = Date(), lengthDays: Int = trialLengthDays) -> Bool {
        now < trialEnd(from: start, lengthDays: lengthDays)
    }

    static func graceDaysRemaining(lastValidated: Date, now: Date = Date(), graceDays: Int = offlineGraceDays) -> Int {
        let end = Calendar.current.date(byAdding: .day, value: graceDays, to: lastValidated) ?? lastValidated
        if now >= end { return 0 }
        let seconds = end.timeIntervalSince(now)
        return max(1, Int(ceil(seconds / 86_400)))
    }

    static func isWithinGrace(lastValidated: Date, now: Date = Date(), graceDays: Int = offlineGraceDays) -> Bool {
        now < (Calendar.current.date(byAdding: .day, value: graceDays, to: lastValidated) ?? lastValidated)
    }

    static func shouldValidate(lastValidated: Date?, now: Date = Date(), intervalHours: Int = validateIntervalHours) -> Bool {
        guard let lastValidated else { return true }
        return now.timeIntervalSince(lastValidated) >= Double(intervalHours) * 3600
    }
}

enum PolicyPackCatalog {
    /// Maps Lemon Squeezy product/variant name fragments to bundled policy IDs.
    static let unlockRules: [(needle: String, policies: [String])] = [
        ("small business", ["small-business"]),
        ("small-business", ["small-business"]),
        ("folderlint professional", ["nonprofit", "small-business"]),
        ("folderlint consultant", ["nonprofit", "small-business"]),
        ("folderlint business", ["nonprofit", "small-business"]),
    ]

    static func policiesUnlocked(productName: String?, variantName: String?) -> [String] {
        let haystack = [productName, variantName]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")

        // Named one-time policy packs unlock only their template.
        if haystack.contains("nonprofit") && haystack.contains("pack") {
            return ["nonprofit"]
        }
        if (haystack.contains("small business") || haystack.contains("small-business"))
            && haystack.contains("pack") {
            return ["small-business"]
        }

        var unlocked = Set<String>()
        for rule in unlockRules where haystack.contains(rule.needle) {
            unlocked.formUnion(rule.policies)
        }
        // Base personal/team licenses unlock both current bundled packs.
        if haystack.contains("folderlint") || haystack.contains("personal") || haystack.contains("team") {
            unlocked.formUnion(["nonprofit", "small-business"])
        }
        return Array(unlocked).sorted()
    }
}
