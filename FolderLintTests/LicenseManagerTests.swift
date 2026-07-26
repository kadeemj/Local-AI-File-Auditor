import Foundation
import Testing
@testable import FolderLint

@Suite("TrialClock")
struct TrialClockTests {
    @Test("fourteen-day trial counts down and expires")
    func trialCountdown() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(TrialClock.isTrialActive(start: start, now: start))
        #expect(TrialClock.daysRemaining(from: start, now: start) == 14)
        #expect(TrialClock.isTrialActive(start: start, now: start.addingTimeInterval(13 * 86_400)))
        #expect(TrialClock.daysRemaining(from: start, now: start.addingTimeInterval(13 * 86_400)) == 1)
        #expect(!TrialClock.isTrialActive(start: start, now: start.addingTimeInterval(14 * 86_400)))
        #expect(TrialClock.daysRemaining(from: start, now: start.addingTimeInterval(14 * 86_400)) == 0)
    }

    @Test("offline grace lasts thirty days after last validation")
    func offlineGrace() {
        let validated = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(TrialClock.isWithinGrace(lastValidated: validated, now: validated.addingTimeInterval(29 * 86_400)))
        #expect(TrialClock.graceDaysRemaining(lastValidated: validated, now: validated.addingTimeInterval(29 * 86_400)) == 1)
        #expect(!TrialClock.isWithinGrace(lastValidated: validated, now: validated.addingTimeInterval(30 * 86_400)))
    }

    @Test("validation is due after twenty-four hours")
    func validateInterval() {
        let last = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(!TrialClock.shouldValidate(lastValidated: last, now: last.addingTimeInterval(23 * 3600)))
        #expect(TrialClock.shouldValidate(lastValidated: last, now: last.addingTimeInterval(24 * 3600)))
        #expect(TrialClock.shouldValidate(lastValidated: nil, now: last))
    }
}

@Suite("PolicyPackCatalog")
struct PolicyPackCatalogTests {
    @Test("maps product names to bundled policy ids")
    func mapsNames() {
        #expect(PolicyPackCatalog.policiesUnlocked(productName: "Nonprofit Policy Pack", variantName: nil) == ["nonprofit"])
        #expect(PolicyPackCatalog.policiesUnlocked(productName: "Small Business Policy Pack", variantName: nil) == ["small-business"])
        #expect(Set(PolicyPackCatalog.policiesUnlocked(productName: "FolderLint Professional", variantName: "Pro")) == ["nonprofit", "small-business"])
    }
}

@Suite("LicenseManager")
@MainActor
struct LicenseManagerTests {
    @Test("starts a trial and allows scanning")
    func startsTrial() {
        let store = InMemorySecureStoreBox()
        let manager = LicenseManager(store: store, backend: MockLicensingBackend(), now: { Date(timeIntervalSince1970: 1_700_000_000) })
        #expect(manager.startTrialIfNeeded())
        #expect(manager.status.phase == .trial)
        #expect(manager.status.canScan)
        #expect(manager.capabilities.canScan)
        #expect(!manager.startTrialIfNeeded())
    }

    @Test("expired trial disables scan while keeping degraded capabilities")
    func expiredTrialDegrades() {
        let store = InMemorySecureStoreBox()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let manager = LicenseManager(store: store, backend: MockLicensingBackend(), now: { start })
        _ = manager.startTrialIfNeeded()

        let later = LicenseManager(
            store: store,
            backend: MockLicensingBackend(),
            now: { start.addingTimeInterval(15 * 86_400) }
        )
        #expect(later.status.phase == .trialExpired)
        #expect(!later.status.canScan)
        #expect(later.capabilities == .degraded)
        #expect(later.capabilities.canExportReports)
    }

    @Test("activate transitions to licensed")
    func activateLicenses() async {
        let store = InMemorySecureStoreBox()
        let manager = LicenseManager(store: store, backend: MockLicensingBackend(), now: { Date(timeIntervalSince1970: 1_700_000_000) })
        await manager.activate(licenseKey: "TEST-PRO-123")
        #expect(manager.lastError == nil)
        #expect(manager.status.phase == .licensed)
        #expect(manager.status.snapshot?.variantName == "Professional")
        #expect(manager.status.canScan)
    }

    @Test("activation failure surfaces remote error")
    func activateFailure() async {
        let manager = LicenseManager(
            store: InMemorySecureStoreBox(),
            backend: MockLicensingBackend(),
            now: { Date() }
        )
        await manager.activate(licenseKey: "TEST-FAIL-LIMIT")
        #expect(manager.lastError != nil)
        #expect(manager.status.phase != .licensed)
    }

    @Test("offline grace after stale validation")
    func offlineGracePhase() async {
        let store = InMemorySecureStoreBox()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let manager = LicenseManager(store: store, backend: MockLicensingBackend(), now: { t0 })
        await manager.activate(licenseKey: "TEST-PRO")
        #expect(manager.status.phase == .licensed)

        let dayTwo = LicenseManager(
            store: store,
            backend: MockLicensingBackend(),
            now: { t0.addingTimeInterval(2 * 86_400) }
        )
        #expect(dayTwo.status.phase == .grace)
        #expect(dayTwo.status.canScan)

        let dayThirtyOne = LicenseManager(
            store: store,
            backend: MockLicensingBackend(),
            now: { t0.addingTimeInterval(31 * 86_400) }
        )
        #expect(dayThirtyOne.status.phase == .expired)
        #expect(!dayThirtyOne.status.canScan)
    }

    @Test("deactivate clears license and falls back to trial if active")
    func deactivate() async {
        let store = InMemorySecureStoreBox()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let manager = LicenseManager(store: store, backend: MockLicensingBackend(), now: { now })
        _ = manager.startTrialIfNeeded()
        await manager.activate(licenseKey: "TEST-PRO")
        await manager.deactivate()
        #expect(manager.status.phase == .trial)
        #expect(manager.status.canScan)
    }

    @Test("policy pack key unlocks bundled policy ids")
    func policyPackUnlock() async {
        let manager = LicenseManager(
            store: InMemorySecureStoreBox(),
            backend: MockLicensingBackend(),
            now: { Date() }
        )
        await manager.activate(licenseKey: "TEST-PACK-NONPROFIT")
        #expect(manager.unlockedPolicyIDs().contains("nonprofit"))
    }
}
