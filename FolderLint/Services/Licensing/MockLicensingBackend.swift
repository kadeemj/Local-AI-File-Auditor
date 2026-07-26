import Foundation

/// Deterministic backend for tests and local dogfooding.
/// Activate any key; keys prefixed with `TEST-FAIL-` or `TEST-EXPIRED-` simulate failures.
struct MockLicensingBackend: LicensingBackend {
    var activationLimit: Int = 5

    func activate(_ request: LicenseActivationRequest) async throws -> LicensingAPIResult {
        if request.licenseKey.hasPrefix("TEST-FAIL") {
            throw LicensingBackendError.remote("This license key has reached the activation limit.")
        }
        let expired = request.licenseKey.hasPrefix("TEST-EXPIRED")
        let snapshot = makeSnapshot(
            key: request.licenseKey,
            instanceID: UUID().uuidString,
            status: expired ? "expired" : "active",
            expiresAt: expired ? Date().addingTimeInterval(-86_400) : nil
        )
        return LicensingAPIResult(snapshot: snapshot, rawValidOrActivated: !expired, errorMessage: expired ? "expired" : nil)
    }

    func validate(_ request: LicenseValidationRequest) async throws -> LicensingAPIResult {
        if request.licenseKey.hasPrefix("TEST-FAIL") {
            throw LicensingBackendError.remote("Invalid license key.")
        }
        let expired = request.licenseKey.hasPrefix("TEST-EXPIRED")
        let snapshot = makeSnapshot(
            key: request.licenseKey,
            instanceID: request.instanceID ?? UUID().uuidString,
            status: expired ? "expired" : "active",
            expiresAt: expired ? Date().addingTimeInterval(-86_400) : nil
        )
        return LicensingAPIResult(snapshot: snapshot, rawValidOrActivated: !expired, errorMessage: nil)
    }

    func deactivate(_ request: LicenseDeactivationRequest) async throws {
        if request.licenseKey.hasPrefix("TEST-FAIL") {
            throw LicensingBackendError.remote("Unable to deactivate.")
        }
    }

    private func makeSnapshot(key: String, instanceID: String, status: String, expiresAt: Date?) -> LicenseSnapshot {
        let product: String
        let variant: String
        if key.uppercased().contains("PACK-NONPROFIT") {
            product = "Nonprofit Policy Pack"
            variant = "Nonprofit"
        } else if key.uppercased().contains("PACK-SMALL") {
            product = "Small Business Policy Pack"
            variant = "Small Business"
        } else {
            product = "FolderLint Professional"
            variant = "Professional"
        }
        return LicenseSnapshot(
            licenseKey: key,
            instanceID: instanceID,
            status: status,
            activationLimit: activationLimit,
            activationUsage: 1,
            productName: product,
            variantName: variant,
            expiresAt: expiresAt,
            customerEmail: "test@example.com",
            unlockedPolicyIDs: PolicyPackCatalog.policiesUnlocked(productName: product, variantName: variant)
        )
    }
}
