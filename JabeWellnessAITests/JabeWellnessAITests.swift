//
//  JabeWellnessAITests.swift
//  JabeWellnessAITests
//
//  Created by Joel Reamosio Abelarde on 5/13/26.
//

import Testing
import Foundation
import DeviceCheck
@testable import JabeWellnessAI

struct JabeWellnessAITests {

    // ChatSession.dominantMood should reflect the mood that occurs most often across
    // the conversation, not just whichever mood the first tagged message happened to have.
    @Test func dominantMoodReflectsMostFrequentMoodNotFirst() async throws {
        let messages = [
            ChatMessage(content: "I'm so anxious about this",       isUser: true,  mood: .anxious, timestamp: Date()),
            ChatMessage(content: "It'll be okay, tell me more",     isUser: false, mood: nil,       timestamp: Date()),
            ChatMessage(content: "Actually I feel great now",       isUser: true,  mood: .happy,    timestamp: Date()),
            ChatMessage(content: "That's wonderful to hear!",       isUser: false, mood: nil,       timestamp: Date()),
            ChatMessage(content: "Yeah I'm really happy about it",  isUser: true,  mood: .happy,    timestamp: Date()),
        ]

        let session = ChatSession(messages: messages)

        #expect(session.dominantMood == .happy)
    }

    @Test func dominantMoodFallsBackToNeutralWhenNoMoodsPresent() async throws {
        let messages = [
            ChatMessage(content: "Hello", isUser: true,  mood: nil, timestamp: Date()),
            ChatMessage(content: "Hi!",   isUser: false, mood: nil, timestamp: Date()),
        ]

        let session = ChatSession(messages: messages)

        #expect(session.dominantMood == .neutral)
    }

    // MARK: - Trial window

    private func date(daysAgo: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
    }

    @Test func trialIsActiveOnTheDayItStarts() async throws {
        let start = date(daysAgo: 0)
        #expect(PremiumManager.isInTrial(start: start, now: Date(), trialDays: 7))
        #expect(PremiumManager.trialDaysRemaining(start: start, now: Date(), trialDays: 7) == 7)
    }

    @Test func trialCountsDownAsDaysElapse() async throws {
        #expect(PremiumManager.trialDaysRemaining(start: date(daysAgo: 3), now: Date(), trialDays: 7) == 4)
        #expect(PremiumManager.isInTrial(start: date(daysAgo: 3), now: Date(), trialDays: 7))
    }

    @Test func trialExpiresOnTheFinalDayAndStaysExpired() async throws {
        #expect(!PremiumManager.isInTrial(start: date(daysAgo: 7),  now: Date(), trialDays: 7))
        #expect(!PremiumManager.isInTrial(start: date(daysAgo: 30), now: Date(), trialDays: 7))
        #expect(PremiumManager.trialDaysRemaining(start: date(daysAgo: 30), now: Date(), trialDays: 7) == 0)
    }

    // A start date in the future means the device clock moved backwards. That must not
    // read as more trial than a fresh install gets.
    @Test func trialNeverReportsMoreDaysThanTheTrialLength() async throws {
        let future = Calendar.current.date(byAdding: .day, value: 90, to: Date()) ?? Date()
        #expect(PremiumManager.trialDaysRemaining(start: future, now: Date(), trialDays: 7) == 7)
    }

    // MARK: - Entitlement state
    //
    // Reported 2026-08-15 on a physical iPhone 11 Pro Max: tapping "Unlock for $3.99" while
    // the free trial was still running completed the purchase, but the paywall neither
    // confirmed it nor closed, so it was tapped three more times. Root cause is that the
    // paywall observes isPremium (= isPurchased || isInTrial), which is ALREADY true for the
    // whole trial and stays true after buying. The value never changes, SwiftUI's .onChange
    // never fires, and nothing on screen moves. The entitlement SOURCE has to be observable,
    // not just the boolean "is this user entitled".

    @Test func buyingDuringTheTrialChangesTheObservedState() async throws {
        let duringTrial = PremiumManager.entitlementState(isPurchased: false, isInTrial: true,  trialDaysRemaining: 5)
        // isInTrial is suppressed the moment isPurchased flips — see PremiumManager.isInTrial.
        let afterBuying = PremiumManager.entitlementState(isPurchased: true,  isInTrial: false, trialDaysRemaining: 0)

        #expect(duringTrial != afterBuying)
        #expect(afterBuying == .purchased)
    }

    // Defensive: even if both facts are somehow true at once, money beats a countdown.
    @Test func aCompletedPurchaseOutranksAnActiveTrial() async throws {
        #expect(PremiumManager.entitlementState(isPurchased: true, isInTrial: true, trialDaysRemaining: 5) == .purchased)
    }

    @Test func anActiveTrialCarriesItsRemainingDays() async throws {
        #expect(PremiumManager.entitlementState(isPurchased: false, isInTrial: true, trialDaysRemaining: 3)
                == .trial(daysRemaining: 3))
    }

    @Test func noPurchaseAndNoTrialIsLocked() async throws {
        #expect(PremiumManager.entitlementState(isPurchased: false, isInTrial: false, trialDaysRemaining: 0) == .locked)
    }

    // The trial anchor has to survive deleting the app, so it lives in the Keychain
    // rather than UserDefaults — a UserDefaults anchor granted a new trial per reinstall.
    // MARK: - Feature gating
    //
    // Until 2026-08-18 nothing in the app consulted entitlement: isPremium and
    // entitlementState were read in three cosmetic places and the $3.99 purchase
    // unlocked nothing. These pin the predicate every gated feature now asks.

    @Test func lockedUsersCannotReachPremiumFeatures() async throws {
        #expect(PremiumManager.isFeatureUnlocked(.locked) == false)
    }

    @Test func trialUsersReachPremiumFeatures() async throws {
        #expect(PremiumManager.isFeatureUnlocked(.trial(daysRemaining: 7)) == true)
        #expect(PremiumManager.isFeatureUnlocked(.trial(daysRemaining: 1)) == true)
    }

    @Test func purchasersReachPremiumFeatures() async throws {
        #expect(PremiumManager.isFeatureUnlocked(.purchased) == true)
    }

    // The gate must agree with the state machine feeding it, or a user can be
    // entitled by one and refused by the other.
    @Test func theGateAgreesWithEveryEntitlementState() async throws {
        let purchased = PremiumManager.entitlementState(isPurchased: true,  isInTrial: false, trialDaysRemaining: 0)
        let trialing  = PremiumManager.entitlementState(isPurchased: false, isInTrial: true,  trialDaysRemaining: 3)
        let locked    = PremiumManager.entitlementState(isPurchased: false, isInTrial: false, trialDaysRemaining: 0)

        #expect(PremiumManager.isFeatureUnlocked(purchased) == true)
        #expect(PremiumManager.isFeatureUnlocked(trialing)  == true)
        #expect(PremiumManager.isFeatureUnlocked(locked)    == false)
    }

    // An expired trial must close the gate. This is the case that would let a
    // non-paying user keep premium forever if the gate read the wrong thing.
    @Test func anExpiredTrialClosesTheGate() async throws {
        let start = Date()
        let elapsed = Calendar.current.date(byAdding: .day, value: 8, to: start) ?? start
        let inTrial = PremiumManager.isInTrial(start: start, now: elapsed, trialDays: 7)
        let state = PremiumManager.entitlementState(isPurchased: false,
                                                    isInTrial: inTrial,
                                                    trialDaysRemaining: 0)

        #expect(inTrial == false)
        #expect(PremiumManager.isFeatureUnlocked(state) == false)
    }

    @Test func trialAnchorRoundTripsThroughTheKeychain() async throws {
        let anchor = date(daysAgo: 2)
        TrialAnchorStore.save(anchor)

        let loaded = try #require(TrialAnchorStore.load())

        // ISO8601 serialization drops sub-second precision.
        #expect(abs(loaded.timeIntervalSince(anchor)) < 1.0)
    }


    //*==================================================================*//
    // MARK: - User-facing error copy
    //*==================================================================*//

    // Everything AIService returns on failure is rendered in the chat transcript as if Jabe
    // said it. Version 1.0.1 shipped "Please check your Groq API key in the Secrets section"
    // to end users, who have no Secrets section and no key. No failure message may name the
    // provider, a credential, or a screen that only the developer can reach.
    private static let forbiddenInUserCopy = [
        "API key", "api key", "Groq", "groq", "Secrets", "secrets", "token", "SecretsStore"
    ]

    @Test func authFailuresDoNotTellUsersToCheckAnAPIKey() async throws {
        for status in [401, 403] {
            let message = AIService.userFacingError(for: status)
            for term in Self.forbiddenInUserCopy {
                #expect(
                    !message.contains(term),
                    "HTTP \(status) copy leaks \"\(term)\" to end users: \(message)"
                )
            }
        }
    }

    @Test func noHTTPFailureMessageLeaksInternalDetails() async throws {
        for status in [400, 401, 403, 404, 429, 500, 502, 503] {
            let message = AIService.userFacingError(for: status)
            for term in Self.forbiddenInUserCopy {
                #expect(
                    !message.contains(term),
                    "HTTP \(status) copy leaks \"\(term)\": \(message)"
                )
            }
        }
    }

    // A failure message that does not say what to do next is as useless as one that gives an
    // impossible instruction. Every branch must be a non-empty sentence.
    @Test func everyFailureMessageIsANonEmptySentence() async throws {
        for status in [400, 401, 403, 404, 429, 500, 503] {
            let message = AIService.userFacingError(for: status)
            #expect(message.count > 20, "HTTP \(status) copy is too terse: \(message)")
            // Sentence-ending punctuation, not a fragment. Not anchored to the final character:
            // Jabe's voice ends some lines on an emoji, which is intentional.
            #expect(message.contains("."), "HTTP \(status) copy is not a sentence: \(message)")
        }
    }

    // Regression guard: the rate-limit wording was already correct and in Jabe's voice.
    // Rewriting the auth copy must not flatten it.
    @Test func rateLimitCopyKeepsItsFriendlyWording() async throws {
        let message = AIService.userFacingError(for: 429)
        #expect(message.contains("breathe"))
        #expect(message.contains("minute"))
    }

    // Since the Worker proxy, 401/403 mean "this device could not be verified", not a bad key, so
    // they get their own sentence — still with no provider, credential or screen named.
    @Test func verificationFailureCopyIsUserSafe() async throws {
        for status in [401, 403] {
            let message = AIService.userFacingError(for: status)
            #expect(message == AIService.verificationFailedMessage)
            #expect(message != AIService.serviceUnavailableMessage)
            for term in Self.forbiddenInUserCopy {
                #expect(!message.contains(term), "HTTP \(status) copy leaks \"\(term)\": \(message)")
            }
        }
    }

    @Test func attestationErrorsMapToTheVerificationMessage() async throws {
        for error in [AttestationError.rejected, .unsupported, .unavailable] {
            #expect(AIService.userFacingError(for: error) == AIService.verificationFailedMessage)
        }
    }

    // The throw path was missed by the first pass at this fix. URLSession throws when offline or
    // timed out, and JSONDecoder throws whenever Groq returns 200 with an unexpected body shape.
    // Both land in JournalViewModel's catch and are rendered as Jabe speaking, so a raw Swift
    // DecodingError string can reach a user in a chat bubble.
    @Test func thrownErrorsDoNotLeakRawSystemDescriptions() async throws {
        struct Broken: Decodable { let required: String }
        var decodingError: Error?
        do { _ = try JSONDecoder().decode(Broken.self, from: Data("{}".utf8)) }
        catch { decodingError = error }
        let thrown = try #require(decodingError)

        let message = AIService.userFacingError(for: thrown)
        for term in Self.forbiddenInUserCopy {
            #expect(!message.contains(term), "thrown-error copy leaks \"\(term)\": \(message)")
        }
        // Compare against the system string itself rather than a hand-typed substring: Foundation
        // renders a curly apostrophe (U+2019), so a literal "couldn't" silently never matches.
        #expect(!message.contains(thrown.localizedDescription),
                "raw system error text reaches the user: \(message)")
        #expect(!message.contains("Decod"), "raw DecodingError type reaches the user: \(message)")
    }

    // Being offline IS actionable, unlike an auth failure — the copy should say so rather than
    // collapsing into the generic service message.
    @Test func offlineErrorsTellTheUserToCheckTheirConnection() async throws {
        let offline = URLError(.notConnectedToInternet)
        let message = AIService.userFacingError(for: offline)
        #expect(message.lowercased().contains("connection") || message.lowercased().contains("offline"),
                "offline copy should mention the connection: \(message)")
    }

    // Server-side outages are the transient case the calm retry copy exists for. They must not
    // surface a raw HTTP status code in a wellness chat bubble.
    @Test func serverErrorsDoNotSurfaceRawStatusCodes() async throws {
        for status in [500, 502, 503, 504] {
            let message = AIService.userFacingError(for: status)
            #expect(!message.contains("HTTP"), "HTTP \(status) copy exposes a status code: \(message)")
            #expect(!message.contains("\(status)"), "HTTP \(status) copy exposes the number: \(message)")
        }
    }

    // 404 is what Groq returns for a decommissioned model id — exactly the 2026-08-16 failure.
    // Telling the user to check Wi-Fi sends them chasing a fault only a new build can fix.
    @Test func modelNotFoundDoesNotBlameTheUsersConnection() async throws {
        let message = AIService.userFacingError(for: 404)
        #expect(!message.lowercased().contains("internet connection"),
                "404 copy misdirects the user to their network: \(message)")
    }

    // A count of exactly 1 read "1 days" everywhere a day count was shown — the streak
    // card's "Best:" line, the Settings trial row, and the paywall header. It was visible
    // in the launch ad's Insights panel before it was caught.
    @Test func aSingleDayIsNotPluralized() async throws {
        #expect(dayCount(1) == "1 day")
    }

    @Test func everyOtherDayCountKeepsThePlural() async throws {
        #expect(dayCount(0) == "0 days")
        #expect(dayCount(2) == "2 days")
        #expect(dayCount(7) == "7 days")
        #expect(dayCount(21) == "21 days")
    }

    // The three call sites embed the result in a sentence, so the helper must supply the
    // number and noun and nothing else — no trailing "left", no leading "Best:".
    @Test func dayCountSuppliesOnlyTheNumberAndNoun() async throws {
        #expect(dayCount(3) == "3 days")
        #expect(!dayCount(3).contains("left"))
        #expect(!dayCount(3).hasSuffix(" "))
    }
}

// MARK: - AttestationManager (fakes only: no network, no App Attest hardware)

final class FakeAttester: DeviceAttesting {
    var isSupported = true
    var generated = 0
    var failAssertionOnce = false
    func generateKey() async throws -> String {
        try await Task.sleep(nanoseconds: 20_000_000)   // suspend so overlapping callers interleave
        generated += 1; return "key-\(generated)"
    }
    func attestKey(_ keyId: String, clientDataHash: Data) async throws -> Data { Data([1]) }
    func generateAssertion(_ keyId: String, clientDataHash: Data) async throws -> Data {
        if failAssertionOnce { failAssertionOnce = false; throw DCError(.invalidKey) }
        return Data([2])
    }
}

final class FakeTransport: AttestationTransport {
    var knownKeys: Set<String> = []
    var attestCalls = 0, tokenCalls = 0
    var tokenToReturn = "tok-1"
    var rejectAttest = false
    func challenge() async throws -> String { try await Task.sleep(nanoseconds: 5_000_000); return "chal" }
    func attest(keyId: String, attestation: Data, challenge: String) async throws {
        attestCalls += 1
        if rejectAttest { throw AttestationTransportError.rejected }
        knownKeys.insert(keyId)
    }
    func token(keyId: String, assertion: Data, challenge: String) async throws -> (token: String, expiresIn: Int) {
        tokenCalls += 1
        try await Task.sleep(nanoseconds: 5_000_000)
        guard knownKeys.contains(keyId) else { throw AttestationTransportError.unknownKey }
        return (tokenToReturn, 900)
    }
}

@MainActor
struct AttestationManagerTests {
    private func makeDefaults() -> UserDefaults {
        let name = "attest-test-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name) ?? .standard
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test func firstUseAttestsOnceThenReturnsToken() async throws {
        let a = FakeAttester(), t = FakeTransport()
        let m = AttestationManager(attester: a, transport: t, defaults: makeDefaults())
        #expect(try await m.validToken() == "tok-1")
        #expect(t.attestCalls == 1)
        #expect(a.generated == 1)
    }

    @Test func cachedTokenIsReusedWithoutNetwork() async throws {
        let a = FakeAttester(), t = FakeTransport()
        let m = AttestationManager(attester: a, transport: t, defaults: makeDefaults())
        _ = try await m.validToken()
        _ = try await m.validToken()
        #expect(t.tokenCalls == 1)
    }

    @Test func expiredTokenIsRefreshedWithoutReattesting() async throws {
        let a = FakeAttester(), t = FakeTransport()
        var clock = Date(timeIntervalSince1970: 1_000)
        let m = AttestationManager(attester: a, transport: t, defaults: makeDefaults(), now: { clock })
        _ = try await m.validToken()
        clock = clock.addingTimeInterval(900)
        t.tokenToReturn = "tok-2"
        #expect(try await m.validToken() == "tok-2")
        #expect(t.attestCalls == 1)
    }

    @Test func unknownKeyTriggersOneReattestNotALoop() async throws {
        let a = FakeAttester(), t = FakeTransport()
        let d = makeDefaults()
        d.set("stale-key", forKey: "jabe.attestKeyId")   // iOS/Worker no longer know it
        let m = AttestationManager(attester: a, transport: t, defaults: d)
        #expect(try await m.validToken() == "tok-1")
        #expect(t.attestCalls == 1)
        #expect(a.generated == 1)
    }

    @Test func invalidKeyFromIOSRegeneratesAndReattests() async throws {
        let a = FakeAttester(), t = FakeTransport()
        let d = makeDefaults()
        let m = AttestationManager(attester: a, transport: t, defaults: d)
        _ = try await m.validToken()                       // attests key-1
        m.invalidateToken()
        a.failAssertionOnce = true                          // iOS deleted the key (reinstall)
        #expect(try await m.validToken() == "tok-1")
        #expect(a.generated == 2)
    }

    @Test func rejectedAttestationFailsClosed() async throws {
        let a = FakeAttester(), t = FakeTransport()
        t.rejectAttest = true
        let m = AttestationManager(attester: a, transport: t, defaults: makeDefaults())
        await #expect(throws: AttestationError.rejected) { _ = try await m.validToken() }
    }

    @Test func unsupportedDeviceFailsClosed() async throws {
        let a = FakeAttester(); a.isSupported = false
        let m = AttestationManager(attester: a, transport: FakeTransport(), defaults: makeDefaults())
        await #expect(throws: AttestationError.unsupported) { _ = try await m.validToken() }
    }

    @Test func concurrentCallsShareOneRefresh() async throws {
        let a = FakeAttester(), t = FakeTransport()
        let m = AttestationManager(attester: a, transport: t, defaults: makeDefaults())
        async let first = m.validToken()
        async let second = m.validToken()
        let (x, y) = try await (first, second)
        #expect(x == "tok-1")
        #expect(y == "tok-1")
        #expect(a.generated == 1)
        #expect(t.attestCalls == 1)
        #expect(t.tokenCalls == 1)
    }
}

// MARK: - WorkerTransport (URLProtocol stub)

final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _handler: ((URLRequest) -> (Int, Data))?
    nonisolated(unsafe) private static var _captured: [URLRequest] = []
    nonisolated(unsafe) private static var _bodies: [Data] = []

    static func respond(_ status: Int, _ body: String) {
        lock.lock(); defer { lock.unlock() }
        _handler = { _ in (status, Data(body.utf8)) }
        _captured = []; _bodies = []
    }
    static var captured: [URLRequest] { lock.lock(); defer { lock.unlock() }; return _captured }
    static var bodies: [Data] { lock.lock(); defer { lock.unlock() }; return _bodies }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var body = Data()
        if let stream = request.httpBodyStream {
            stream.open()
            var buf = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buf, maxLength: buf.count)
                if n <= 0 { break }
                body.append(buf, count: n)
            }
            stream.close()
        } else if let b = request.httpBody {
            body = b
        }
        Self.lock.lock()
        Self._captured.append(request)
        Self._bodies.append(body)
        let handler = Self._handler
        Self.lock.unlock()
        let (status, data) = handler?(request) ?? (500, Data())
        guard let url = request.url,
              let resp = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return
        }
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite(.serialized)
struct WorkerTransportTests {
    private let base = URL(string: "https://worker.example.test")!

    private func makeTransport(_ url: URL? = nil) -> WorkerTransport {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubURLProtocol.self]
        return WorkerTransport(baseURL: url ?? base, session: URLSession(configuration: cfg))
    }

    private func expectURLError<T>(_ code: URLError.Code? = nil, _ op: () async throws -> T) async {
        do {
            _ = try await op()
            Issue.record("expected a throw")
        } catch let e as URLError {
            if let code { #expect(e.code == code) }
        } catch {
            Issue.record("expected URLError, got \(error)")
        }
    }

    private func tokenCall(_ t: WorkerTransport) async throws -> (token: String, expiresIn: Int) {
        try await t.token(keyId: "k", assertion: Data([1]), challenge: "c")
    }

    @Test func challengeParsed() async throws {
        StubURLProtocol.respond(200, #"{"challenge":"abc"}"#)
        let c = try await makeTransport().challenge()
        #expect(c == "abc")
    }

    @Test func challengeMissingFieldThrowsCannotParse() async {
        StubURLProtocol.respond(200, #"{"nope":"x"}"#)
        let t = makeTransport()
        await expectURLError(.cannotParseResponse) { try await t.challenge() }
    }

    @Test func attestSendsPathMethodHeadersAndBody() async throws {
        StubURLProtocol.respond(200, #"{"ok":true}"#)
        let data = Data([0, 1, 2, 250])
        try await makeTransport().attest(keyId: "key-1", attestation: data, challenge: "chal")
        let req = StubURLProtocol.captured.first
        #expect(req?.httpMethod == "POST")
        #expect(req?.url?.path == "/attest")
        #expect(req?.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(req?.timeoutInterval == 30)
        let body = StubURLProtocol.bodies.first ?? Data()
        let obj = try JSONSerialization.jsonObject(with: body) as? [String: String]
        #expect(obj?["keyId"] == "key-1")
        #expect(obj?["attestation"] == data.base64EncodedString())
        #expect(obj?["challenge"] == "chal")
    }

    @Test func challengeUsesChallengePathAndEmptyObjectBody() async throws {
        StubURLProtocol.respond(200, #"{"challenge":"abc"}"#)
        _ = try await makeTransport().challenge()
        #expect(StubURLProtocol.captured.first?.url?.path == "/attest/challenge")
        #expect(StubURLProtocol.captured.first?.httpMethod == "POST")
        let obj = try JSONSerialization.jsonObject(with: StubURLProtocol.bodies.first ?? Data()) as? [String: Any]
        #expect(obj?.isEmpty == true)
    }

    @Test func tokenSendsAssertionBodyAndParses() async throws {
        StubURLProtocol.respond(200, #"{"token":"tok","expiresIn":600}"#)
        let data = Data([9, 8, 7])
        let r = try await makeTransport().token(keyId: "k2", assertion: data, challenge: "c2")
        #expect(r.token == "tok")
        #expect(r.expiresIn == 600)
        #expect(StubURLProtocol.captured.first?.url?.path == "/token")
        let obj = try JSONSerialization.jsonObject(with: StubURLProtocol.bodies.first ?? Data()) as? [String: String]
        #expect(obj?["keyId"] == "k2")
        #expect(obj?["assertion"] == data.base64EncodedString())
        #expect(obj?["challenge"] == "c2")
    }

    @Test func tokenExpiresInDefaultsTo900() async throws {
        StubURLProtocol.respond(200, #"{"token":"tok"}"#)
        let r = try await tokenCall(makeTransport())
        #expect(r.expiresIn == 900)
    }

    @Test func tokenNonJSON200ThrowsCannotParse() async {
        StubURLProtocol.respond(200, "not json at all")
        let t = makeTransport()
        await expectURLError(.cannotParseResponse) { try await tokenCall(t) }
    }

    @Test func unknownKeyMapsToUnknownKey() async {
        StubURLProtocol.respond(401, #"{"error":"unknown_key"}"#)
        let t = makeTransport()
        do {
            _ = try await tokenCall(t)
            Issue.record("expected throw")
        } catch let e as AttestationTransportError {
            #expect(e == .unknownKey)
        } catch {
            Issue.record("wrong error \(error)")
        }
    }

    @Test func rejectedBodiesMapToRejected() async {
        for body in [#"{"error":"attestation_rejected"}"#, #"{"error":"assertion_rejected"}"#] {
            StubURLProtocol.respond(403, body)
            let t = makeTransport()
            do {
                _ = try await tokenCall(t)
                Issue.record("expected throw")
            } catch let e as AttestationTransportError {
                #expect(e == .rejected)
            } catch {
                Issue.record("wrong error \(error)")
            }
        }
    }

    @Test func otherFailuresAreBadServerResponse() async {
        let cases: [(Int, String)] = [
            (403, #"{"error":"bad_challenge"}"#),
            (401, #"{"error":"something_else"}"#),
            (401, "garbage"),
            (403, "garbage"),
            (400, #"{"error":"bad_request"}"#),
            (413, ""),
            (429, #"{"error":"rate_limited"}"#),
            (503, #"{"error":"unavailable"}"#),
        ]
        for (status, body) in cases {
            StubURLProtocol.respond(status, body)
            let t = makeTransport()
            await expectURLError(.badServerResponse) { try await tokenCall(t) }
        }
    }

    @Test func baseURLPathAppendedWithAndWithoutTrailingSlash() async throws {
        for s in ["https://worker.example.test", "https://worker.example.test/", "https://worker.example.test/v1/"] {
            StubURLProtocol.respond(200, #"{"challenge":"abc"}"#)
            _ = try await makeTransport(URL(string: s)).challenge()
            let path = StubURLProtocol.captured.first?.url?.path
            let expected = s.hasSuffix("/v1/") ? "/v1/attest/challenge" : "/attest/challenge"
            #expect(path == expected)
        }
    }
}
