import Foundation

struct LicenseActivationRequest: Sendable {
    let licenseKey: String
    let instanceName: String
}

struct LicenseValidationRequest: Sendable {
    let licenseKey: String
    let instanceID: String?
}

struct LicenseDeactivationRequest: Sendable {
    let licenseKey: String
    let instanceID: String
}

struct LicensingAPIResult: Sendable {
    let snapshot: LicenseSnapshot
    let rawValidOrActivated: Bool
    let errorMessage: String?
}

enum LicensingBackendError: Error, Sendable, Equatable {
    case invalidResponse
    case remote(String)
    case network(String)
}

/// Escape hatch so a future Paddle (or other) backend can replace Lemon Squeezy
/// without rewriting `LicenseManager`.
protocol LicensingBackend: Sendable {
    func activate(_ request: LicenseActivationRequest) async throws -> LicensingAPIResult
    func validate(_ request: LicenseValidationRequest) async throws -> LicensingAPIResult
    func deactivate(_ request: LicenseDeactivationRequest) async throws
}
