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

        do {
            return try await refreshToken(allowReattest: true)
        } catch let error as AttestationError {
            throw error
        } catch {
            throw AttestationError.unavailable
        }
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
