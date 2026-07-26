import Foundation

/// Lemon Squeezy License API client. All HTTP goes through `NetworkClient`
/// so the network-policy build gate stays intact.
struct LemonSqueezyClient: LicensingBackend {
    private let network: NetworkClient
    private let baseURL = URL(string: "https://api.lemonsqueezy.com/v1/licenses")!

    init(network: NetworkClient = NetworkClient()) {
        self.network = network
    }

    func activate(_ request: LicenseActivationRequest) async throws -> LicensingAPIResult {
        let data = try await post(path: "activate", fields: [
            "license_key": request.licenseKey,
            "instance_name": request.instanceName,
        ])
        return try decodeActivation(data, fallbackKey: request.licenseKey)
    }

    func validate(_ request: LicenseValidationRequest) async throws -> LicensingAPIResult {
        var fields = ["license_key": request.licenseKey]
        if let instanceID = request.instanceID {
            fields["instance_id"] = instanceID
        }
        let data = try await post(path: "validate", fields: fields)
        return try decodeValidation(data, fallbackKey: request.licenseKey, fallbackInstance: request.instanceID)
    }

    func deactivate(_ request: LicenseDeactivationRequest) async throws {
        let data = try await post(path: "deactivate", fields: [
            "license_key": request.licenseKey,
            "instance_id": request.instanceID,
        ])
        struct Response: Decodable {
            let deactivated: Bool?
            let error: String?
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        if let error = decoded.error, !(decoded.deactivated ?? false) {
            throw LicensingBackendError.remote(error)
        }
    }

    private func post(path: String, fields: [String: String]) async throws -> Data {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody(fields)

        do {
            let (data, response) = try await network.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                if let remote = try? JSONDecoder().decode(ErrorBody.self, from: data), let message = remote.error {
                    throw LicensingBackendError.remote(message)
                }
                throw LicensingBackendError.remote("HTTP \(http.statusCode)")
            }
            return data
        } catch let error as LicensingBackendError {
            throw error
        } catch let error as NetworkClient.NetworkPolicyViolation {
            throw LicensingBackendError.network(String(describing: error))
        } catch {
            throw LicensingBackendError.network(error.localizedDescription)
        }
    }

    private func formBody(_ fields: [String: String]) -> Data {
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: "-._~"))
        let pairs = fields.map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(k)=\(v)"
        }
        return Data(pairs.joined(separator: "&").utf8)
    }

    private struct ErrorBody: Decodable { let error: String? }

    private struct ActivateBody: Decodable {
        let activated: Bool?
        let error: String?
        let license_key: LicenseKeyBody?
        let instance: InstanceBody?
        let meta: MetaBody?
    }

    private struct ValidateBody: Decodable {
        let valid: Bool?
        let error: String?
        let license_key: LicenseKeyBody?
        let instance: InstanceBody?
        let meta: MetaBody?
    }

    private struct LicenseKeyBody: Decodable {
        let status: String?
        let key: String?
        let activation_limit: Int?
        let activation_usage: Int?
        let expires_at: String?
    }

    private struct InstanceBody: Decodable {
        let id: String?
        let name: String?
    }

    private struct MetaBody: Decodable {
        let product_name: String?
        let variant_name: String?
        let customer_email: String?
    }

    private func decodeActivation(_ data: Data, fallbackKey: String) throws -> LicensingAPIResult {
        let body = try JSONDecoder().decode(ActivateBody.self, from: data)
        if let error = body.error, body.activated != true {
            throw LicensingBackendError.remote(error)
        }
        guard let license = body.license_key, let instanceID = body.instance?.id else {
            throw LicensingBackendError.invalidResponse
        }
        let snapshot = makeSnapshot(
            key: license.key ?? fallbackKey,
            instanceID: instanceID,
            license: license,
            meta: body.meta
        )
        return LicensingAPIResult(snapshot: snapshot, rawValidOrActivated: body.activated ?? true, errorMessage: body.error)
    }

    private func decodeValidation(
        _ data: Data,
        fallbackKey: String,
        fallbackInstance: String?
    ) throws -> LicensingAPIResult {
        let body = try JSONDecoder().decode(ValidateBody.self, from: data)
        if let error = body.error, body.valid != true {
            throw LicensingBackendError.remote(error)
        }
        guard let license = body.license_key else {
            throw LicensingBackendError.invalidResponse
        }
        let instanceID = body.instance?.id ?? fallbackInstance ?? ""
        let snapshot = makeSnapshot(
            key: license.key ?? fallbackKey,
            instanceID: instanceID,
            license: license,
            meta: body.meta
        )
        return LicensingAPIResult(snapshot: snapshot, rawValidOrActivated: body.valid ?? false, errorMessage: body.error)
    }

    private func makeSnapshot(
        key: String,
        instanceID: String,
        license: LicenseKeyBody,
        meta: MetaBody?
    ) -> LicenseSnapshot {
        LicenseSnapshot(
            licenseKey: key,
            instanceID: instanceID,
            status: license.status ?? "active",
            activationLimit: license.activation_limit,
            activationUsage: license.activation_usage,
            productName: meta?.product_name,
            variantName: meta?.variant_name,
            expiresAt: license.expires_at.flatMap(Self.parseLSDate),
            customerEmail: meta?.customer_email,
            unlockedPolicyIDs: PolicyPackCatalog.policiesUnlocked(
                productName: meta?.product_name,
                variantName: meta?.variant_name
            )
        )
    }

    private static func parseLSDate(_ string: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: string) { return date }
        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        return basic.date(from: string)
    }
}
