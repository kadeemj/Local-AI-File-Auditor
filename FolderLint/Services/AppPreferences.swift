import Foundation

/// Lightweight app preferences persisted outside the scan database.
@MainActor
enum AppPreferences {
    private static let defaults = UserDefaults.standard
    private static let onboardingKey = "folderlint.didCompleteOnboarding"
    private static let policyKey = "folderlint.activePolicyID"
    private static let useMockScanKey = "folderlint.useMockScan"

    static var didCompleteOnboarding: Bool {
        get { defaults.bool(forKey: onboardingKey) }
        set { defaults.set(newValue, forKey: onboardingKey) }
    }

    /// Bundled policy id (`nonprofit`, `small-business`) or `nil` for universal rules.
    static var activePolicyID: String? {
        get {
            let value = defaults.string(forKey: policyKey)
            return (value?.isEmpty == false) ? value : nil
        }
        set {
            if let newValue, !newValue.isEmpty {
                defaults.set(newValue, forKey: policyKey)
            } else {
                defaults.removeObject(forKey: policyKey)
            }
        }
    }

    /// Debug/dev escape hatch: drive `ScanSessionModel` from a deterministic mock stream.
    static var useMockScan: Bool {
        get { defaults.bool(forKey: useMockScanKey) }
        set { defaults.set(newValue, forKey: useMockScanKey) }
    }
}
