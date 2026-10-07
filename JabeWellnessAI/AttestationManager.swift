import Foundation
import CryptoKit
import DeviceCheck

protocol DeviceAttesting {
    var isSupported: Bool { get }
    func generateKey() async throws -> String
    func attestKey(_ keyId: String, clientDataHash: Data) async throws -> Data
    func generateAssertion(_ keyId: String, clientDataHash: Data) async throws -> Data
}

protocol AttestationTransport {
    func challenge() async throws -> String
    func attest(keyId: String, attestation: Data, challenge: String) async throws
    func token(keyId: String, assertion: Data, challenge: String) async throws -> (token: String, expiresIn: Int)
}

enum AttestationTransportError: Error { case unknownKey, rejected }
enum AttestationError: Error { case unsupported, rejected, unavailable }

/// Real App Attest. Not available on the simulator or on devices that don't support it.
struct SystemDeviceAttester: DeviceAttesting {
    private let service = DCAppAttestService.shared
    var isSupported: Bool { service.isSupported }
    func generateKey() async throws -> String { try await service.generateKey() }
    func attestKey(_ keyId: String, clientDataHash: Data) async throws -> Data {
        try await service.attestKey(keyId, clientDataHash: clientDataHash)
    }
    func generateAssertion(_ keyId: String, clientDataHash: Data) async throws -> Data {
        try await service.generateAssertion(keyId, clientDataHash: clientDataHash)
    }
}

/// Owns the App Attest key id and a short-lived Worker token.
///
/// The key id lives in UserDefaults, not the Keychain: iOS deletes App Attest keys when the app is
/// uninstalled, but Keychain items survive uninstall, so a Keychain copy would point at a key that
/// no longer exists. UserDefaults is wiped with the app, which keeps the two in step.
@MainActor
final class AttestationManager {

    static let keyIdDefaultsKey = "jabe.attestKeyId"

    private let attester: DeviceAttesting
    private let transport: AttestationTransport
    private let defaults: UserDefaults
    private let now: () -> Date
    private var cachedToken: String?
    private var tokenExpiry: Date = .distantPast
    private var inFlight: Task<String, Error>?

    init(attester: DeviceAttesting,
         transport: AttestationTransport,
         defaults: UserDefaults = .standard,
         now: @escaping () -> Date = Date.init) {
        self.attester = attester
        self.transport = transport
        self.defaults = defaults
        self.now = now
    }

    func invalidateToken() {
        cachedToken = nil
        tokenExpiry = .distantPast
    }

    /// A token good for at least another minute, refreshing (and attesting, if needed) on demand.
    func validToken() async throws -> String {
        if let token = cachedToken, now() < tokenExpiry.addingTimeInterval(-60) { return token }
        guard attester.isSupported else { throw AttestationError.unsupported }

        // Coalesce: concurrent callers join one refresh. Separate refreshes would each take a counter
        // from the same key and the Worker rejects out-of-order counters (spurious .rejected).
        if let running = inFlight { return try await running.value }
        let task = Task { [self] () throws -> String in
            do {
                return try await refreshToken(allowReattest: true)
            } catch let error as AttestationError {
                throw error
            } catch {
                throw AttestationError.unavailable
            }
        }
        inFlight = task
        defer { inFlight = nil }
        return try await task.value
    }

    private func refreshToken(allowReattest: Bool) async throws -> String {
        let keyId = try await currentKeyId()
        do {
            let challenge = try await transport.challenge()
            let assertion = try await attester.generateAssertion(keyId, clientDataHash: Self.hash(challenge))
            let result = try await transport.token(keyId: keyId, assertion: assertion, challenge: challenge)
            cachedToken = result.token
            tokenExpiry = now().addingTimeInterval(TimeInterval(result.expiresIn))
            return result.token
        } catch AttestationTransportError.unknownKey where allowReattest {
            defaults.removeObject(forKey: Self.keyIdDefaultsKey)       // Worker lost it: start over once
            return try await refreshToken(allowReattest: false)
        } catch let error as DCError where error.code == .invalidKey && allowReattest {
            defaults.removeObject(forKey: Self.keyIdDefaultsKey)       // iOS deleted it: start over once
            return try await refreshToken(allowReattest: false)
        } catch AttestationTransportError.rejected where allowReattest {
            defaults.removeObject(forKey: Self.keyIdDefaultsKey)       // counter/key out of step: start over once
            return try await refreshToken(allowReattest: false)
        } catch AttestationTransportError.rejected {
            throw AttestationError.rejected
        }
    }

    private func currentKeyId() async throws -> String {
        if let existing = defaults.string(forKey: Self.keyIdDefaultsKey) { return existing }
        let keyId = try await attester.generateKey()
        let challenge = try await transport.challenge()
        let attestation = try await attester.attestKey(keyId, clientDataHash: Self.hash(challenge))
        do {
            try await transport.attest(keyId: keyId, attestation: attestation, challenge: challenge)
        } catch AttestationTransportError.rejected {
            throw AttestationError.rejected
        }
        defaults.set(keyId, forKey: Self.keyIdDefaultsKey)
        return keyId
    }

    private static func hash(_ challenge: String) -> Data {
        Data(SHA256.hash(data: Data(challenge.utf8)))
    }
}

/// HTTP transport to the Jabe Worker. Only 401 `unknown_key` and 403 `attestation_rejected` /
/// `assertion_rejected` are definitive; everything else non-200 (including a transient
/// 403 `bad_challenge`) surfaces as a plain URLError so the manager treats it as "unavailable".
struct WorkerTransport: AttestationTransport {
    let baseURL: URL
    let session: URLSession

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    private struct ErrorBody: Decodable { let error: String }

    private func post(_ path: String, _ json: [String: String]) async throws -> Data {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: json)
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if http.statusCode == 200 { return data }
        let code = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error
        switch (http.statusCode, code) {
        case (401, "unknown_key"):
            throw AttestationTransportError.unknownKey
        case (403, "attestation_rejected"), (403, "assertion_rejected"):
            throw AttestationTransportError.rejected
        default:
            throw URLError(.badServerResponse)
        }
    }

    private func object(_ data: Data) throws -> [String: Any] {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw URLError(.cannotParseResponse)
        }
        return obj
    }

    func challenge() async throws -> String {
        let obj = try object(try await post("attest/challenge", [:]))
        guard let c = obj["challenge"] as? String else { throw URLError(.cannotParseResponse) }
        return c
    }

    func attest(keyId: String, attestation: Data, challenge: String) async throws {
        _ = try await post("attest", ["keyId": keyId, "attestation": attestation.base64EncodedString(), "challenge": challenge])
    }

    func token(keyId: String, assertion: Data, challenge: String) async throws -> (token: String, expiresIn: Int) {
        let obj = try object(try await post("token", ["keyId": keyId, "assertion": assertion.base64EncodedString(), "challenge": challenge]))
        guard let t = obj["token"] as? String else { throw URLError(.cannotParseResponse) }
        return (t, (obj["expiresIn"] as? Int) ?? 900)
    }
}
