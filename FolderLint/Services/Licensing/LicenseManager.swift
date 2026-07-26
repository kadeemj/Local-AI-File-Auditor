import Foundation
import Observation

/// Owns trial + license lifecycle. Degraded mode keeps past results viewable
/// with Scan/Apply disabled.
@Observable
@MainActor
final class LicenseManager {
    private(set) var status: LicenseStatus
    private(set) var lastError: String?
    private(set) var lastNetworkCallAt: Date?
    private(set) var isBusy = false

    private let store: any SecureStore
    private let backend: any LicensingBackend
    private let now: () -> Date
    private let instanceNameProvider: () -> String

    init(
        store: any SecureStore = KeychainStore(),
        backend: (any LicensingBackend)? = nil,
        now: @escaping () -> Date = Date.init,
        instanceNameProvider: @escaping () -> String = { Host.current().localizedName ?? "Mac" }
    ) {
        self.store = store
        self.backend = backend ?? Self.defaultBackend()
        self.now = now
        self.instanceNameProvider = instanceNameProvider
        self.status = LicenseStatus(phase: .trialExpired, daysRemaining: 0, snapshot: nil, detail: "Loading…")
        self.lastNetworkCallAt = Self.readDate(LicensingKeys.lastNetworkCallAt, from: store)
        refreshStatus()
    }

    var capabilities: LicensingCapabilities {
        if status.canScan {
            return .full
        }
        return .degraded
    }

    /// Starts the 14-day offline trial the first time onboarding completes.
    @discardableResult
    func startTrialIfNeeded() -> Bool {
        if (try? store.data(forKey: LicensingKeys.trialStartedAt)) != nil {
            refreshStatus()
            return false
        }
        // Don't start a trial if already licensed.
        if loadSnapshot() != nil {
            refreshStatus()
            return false
        }
        try? writeDate(now(), forKey: LicensingKeys.trialStartedAt)
        refreshStatus()
        return true
    }

    func activate(licenseKey: String) async {
        let trimmed = licenseKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            lastError = "Enter a license key."
            return
        }
        isBusy = true
        lastError = nil
        defer { isBusy = false }

        do {
            let result = try await backend.activate(.init(
                licenseKey: trimmed,
                instanceName: instanceNameProvider()
            ))
            noteNetworkCall()
            guard result.rawValidOrActivated else {
                lastError = result.errorMessage ?? "Activation failed."
                return
            }
            if result.snapshot.status == "expired" || result.snapshot.status == "disabled" {
                lastError = "This license is \(result.snapshot.status)."
                return
            }
            try persist(snapshot: result.snapshot, validatedAt: now())
            mergeUnlockedPolicies(result.snapshot.unlockedPolicyIDs)
            refreshStatus()
        } catch {
            lastError = (error as? LicensingBackendError).map(Self.describe) ?? error.localizedDescription
        }
    }

    /// Validates when online and due (≥24h since last check). Offline uses grace.
    func validateIfNeeded(force: Bool = false) async {
        guard let snapshot = loadSnapshot() else {
            refreshStatus()
            return
        }
        let lastValidated = readDate(LicensingKeys.lastValidatedAt)
        if !force, !TrialClock.shouldValidate(lastValidated: lastValidated, now: now()) {
            refreshStatus()
            return
        }

        isBusy = true
        lastError = nil
        defer { isBusy = false }

        do {
            let result = try await backend.validate(.init(
                licenseKey: snapshot.licenseKey,
                instanceID: snapshot.instanceID
            ))
            noteNetworkCall()
            if result.rawValidOrActivated,
               result.snapshot.status != "expired",
               result.snapshot.status != "disabled" {
                try persist(snapshot: result.snapshot, validatedAt: now())
                mergeUnlockedPolicies(result.snapshot.unlockedPolicyIDs)
            } else {
                // Remote says invalid — clear licensed state; trial may still apply.
                try clearLicense()
                lastError = result.errorMessage ?? "License is no longer valid."
            }
            refreshStatus()
        } catch {
            // Stay in grace / licensed based on lastValidatedAt.
            lastError = nil
            refreshStatus()
        }
    }

    func deactivate() async {
        guard let snapshot = loadSnapshot() else { return }
        isBusy = true
        lastError = nil
        defer { isBusy = false }

        do {
            try await backend.deactivate(.init(
                licenseKey: snapshot.licenseKey,
                instanceID: snapshot.instanceID
            ))
            noteNetworkCall()
            try clearLicense()
            refreshStatus()
        } catch {
            lastError = (error as? LicensingBackendError).map(Self.describe) ?? error.localizedDescription
        }
    }

    func refreshStatus() {
        if let snapshot = loadSnapshot() {
            let lastValidated = readDate(LicensingKeys.lastValidatedAt) ?? now()
            if let expires = snapshot.expiresAt, expires < now() {
                status = LicenseStatus(
                    phase: .expired,
                    daysRemaining: 0,
                    snapshot: snapshot,
                    detail: "Subscription or license length ended."
                )
                return
            }
            let graceLeft = TrialClock.graceDaysRemaining(lastValidated: lastValidated, now: now())
            let due = TrialClock.shouldValidate(lastValidated: lastValidated, now: now())
            if due && !TrialClock.isWithinGrace(lastValidated: lastValidated, now: now()) {
                status = LicenseStatus(
                    phase: .expired,
                    daysRemaining: 0,
                    snapshot: snapshot,
                    detail: "Offline grace ended. Connect to re-validate your license."
                )
            } else if due {
                status = LicenseStatus(
                    phase: .grace,
                    daysRemaining: graceLeft,
                    snapshot: snapshot,
                    detail: "Working offline. Re-validation due within \(graceLeft) day(s)."
                )
            } else {
                status = LicenseStatus(
                    phase: .licensed,
                    daysRemaining: nil,
                    snapshot: snapshot,
                    detail: "Activated on this Mac · limit \(snapshot.activationLimit.map(String.init) ?? "—")"
                )
            }
            return
        }

        if let trialStart = readDate(LicensingKeys.trialStartedAt) {
            if TrialClock.isTrialActive(start: trialStart, now: now()) {
                let displayDays = TrialClock.daysRemaining(from: trialStart, now: now())
                status = LicenseStatus(
                    phase: .trial,
                    daysRemaining: displayDays,
                    snapshot: nil,
                    detail: "\(TrialClock.trialLengthDays)-day offline trial"
                )
            } else {
                status = LicenseStatus(
                    phase: .trialExpired,
                    daysRemaining: 0,
                    snapshot: nil,
                    detail: "Trial ended. Enter a license key to continue scanning."
                )
            }
            return
        }

        status = LicenseStatus(
            phase: .trialExpired,
            daysRemaining: 0,
            snapshot: nil,
            detail: "Start FolderLint to begin your trial, or enter a license key."
        )
    }

    func unlockedPolicyIDs() -> Set<String> {
        var ids = Set(loadStringArray(LicensingKeys.unlockedPolicyPacks))
        if let snapshot = loadSnapshot() {
            ids.formUnion(snapshot.unlockedPolicyIDs)
        }
        // Trial and licensed base unlock both current packs.
        if status.canScan {
            ids.formUnion(["nonprofit", "small-business"])
        }
        return ids
    }

    // MARK: - Persistence helpers

    private func persist(snapshot: LicenseSnapshot, validatedAt: Date) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try store.setData(encoder.encode(snapshot), forKey: LicensingKeys.snapshotJSON)
        try store.setData(Data(snapshot.licenseKey.utf8), forKey: LicensingKeys.licenseKey)
        try store.setData(Data(snapshot.instanceID.utf8), forKey: LicensingKeys.instanceID)
        try writeDate(validatedAt, forKey: LicensingKeys.lastValidatedAt)
    }

    private func clearLicense() throws {
        try store.removeValue(forKey: LicensingKeys.snapshotJSON)
        try store.removeValue(forKey: LicensingKeys.licenseKey)
        try store.removeValue(forKey: LicensingKeys.instanceID)
        try store.removeValue(forKey: LicensingKeys.lastValidatedAt)
    }

    private func loadSnapshot() -> LicenseSnapshot? {
        guard let data = try? store.data(forKey: LicensingKeys.snapshotJSON) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(LicenseSnapshot.self, from: data)
    }

    private func mergeUnlockedPolicies(_ ids: [String]) {
        var current = Set(loadStringArray(LicensingKeys.unlockedPolicyPacks))
        current.formUnion(ids)
        let joined = current.sorted().joined(separator: ",")
        try? store.setData(Data(joined.utf8), forKey: LicensingKeys.unlockedPolicyPacks)
    }

    private func loadStringArray(_ key: String) -> [String] {
        guard let data = try? store.data(forKey: key),
              let string = String(data: data, encoding: .utf8),
              !string.isEmpty
        else { return [] }
        return string.split(separator: ",").map(String.init)
    }

    private func noteNetworkCall() {
        let stamp = now()
        lastNetworkCallAt = stamp
        try? writeDate(stamp, forKey: LicensingKeys.lastNetworkCallAt)
    }

    private func writeDate(_ date: Date, forKey key: String) throws {
        let data = withUnsafeBytes(of: date.timeIntervalSince1970) { Data($0) }
        try store.setData(data, forKey: key)
    }

    private func readDate(_ key: String) -> Date? {
        Self.readDate(key, from: store)
    }

    private static func readDate(_ key: String, from store: any SecureStore) -> Date? {
        guard let data = try? store.data(forKey: key), data.count == MemoryLayout<Double>.size else {
            return nil
        }
        let interval = data.withUnsafeBytes { $0.load(as: Double.self) }
        return Date(timeIntervalSince1970: interval)
    }

    private static func describe(_ error: LicensingBackendError) -> String {
        switch error {
        case .invalidResponse: "Unexpected response from the license server."
        case .remote(let message): message
        case .network(let message): "Network error: \(message)"
        }
    }

    private static func defaultBackend() -> any LicensingBackend {
        if AppPreferences.useMockLicensing {
            return MockLicensingBackend()
        }
        return LemonSqueezyClient()
    }
}
