//
//  JabeWellnessAITests.swift
//  JabeWellnessAITests
//
//  Created by Joel Reamosio Abelarde on 5/13/26.
//

import Testing
import Foundation
import DeviceCheck
import AVFoundation
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
    var rejectTokenTimes = 0
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
        if rejectTokenTimes > 0 { rejectTokenTimes -= 1; throw AttestationTransportError.rejected }
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

    @Test func rejectedTokenReattestsOnceAndRecovers() async throws {
        let a = FakeAttester(), t = FakeTransport()
        let m = AttestationManager(attester: a, transport: t, defaults: makeDefaults())
        _ = try await m.validToken()                       // attests key-1
        m.invalidateToken()
        t.rejectTokenTimes = 1                              // counter desync: /token 403s once
        #expect(try await m.validToken() == "tok-1")
        #expect(a.generated == 2)                           // threw the key away and attested a fresh one
        #expect(t.attestCalls == 2)
    }

    @Test func persistentlyRejectedTokenStopsAfterOneReattest() async throws {
        let a = FakeAttester(), t = FakeTransport()
        let m = AttestationManager(attester: a, transport: t, defaults: makeDefaults())
        _ = try await m.validToken()
        m.invalidateToken()
        t.rejectTokenTimes = 99
        await #expect(throws: AttestationError.rejected) { _ = try await m.validToken() }
        #expect(a.generated == 2)                           // exactly one retry, no loop
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

// MARK: - Review prompt gate

struct ReviewPromptGateTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func days(_ n: Int) -> Date { Calendar.current.date(byAdding: .day, value: -n, to: now) ?? now }

    private func ask(streak: Int = 3, install: Date? = nil, last: Date? = nil,
                     lastVersion: String? = nil, version: String = "1.0.2") -> Bool {
        ReviewPromptGate.shouldAsk(longestStreak: streak, installDate: install ?? days(10),
                                   lastAsked: last, lastAskedVersion: lastVersion,
                                   currentVersion: version, now: now)
    }

    @Test func asksWhenEveryConditionIsMet() { #expect(ask()) }

    @Test func doesNotAskBeforeAThreeDayStreak() { #expect(!ask(streak: 2)) }

    @Test func doesNotAskInTheFirstWeek() { #expect(!ask(install: days(6))) }

    @Test func asksOnceTheInstallIsSevenDaysOld() { #expect(ask(install: days(7))) }

    @Test func doesNotAskWithoutAnInstallDate() {
        #expect(!ReviewPromptGate.shouldAsk(longestStreak: 5, installDate: nil, lastAsked: nil,
                                            lastAskedVersion: nil, currentVersion: "1.0.2", now: now))
    }

    @Test func doesNotAskAgainWithin120Days() {
        #expect(!ask(last: days(119), lastVersion: "1.0.1"))
        #expect(ask(last: days(120), lastVersion: "1.0.1"))
    }

    @Test func doesNotAskTwiceForTheSameVersion() {
        #expect(!ask(last: days(200), lastVersion: "1.0.2"))
    }

    @Test func askIfEligibleRecordsTheAskAndAsksOnlyOnce() {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(5, forKey: "mm_longestStreak")
        var asked = 0

        ReviewPrompt.askIfEligible(defaults: defaults, installDate: days(10), version: "1.0.2", now: now) { asked += 1 }
        ReviewPrompt.askIfEligible(defaults: defaults, installDate: days(10), version: "1.0.2", now: now) { asked += 1 }

        #expect(asked == 1)
        #expect(defaults.string(forKey: "mm_reviewLastVersion") == "1.0.2")
    }

    @Test func askIfEligibleStaysQuietBelowTheStreak() {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(1, forKey: "mm_longestStreak")
        var asked = 0

        ReviewPrompt.askIfEligible(defaults: defaults, installDate: days(10), version: "1.0.2", now: now) { asked += 1 }

        #expect(asked == 0)
        #expect(defaults.object(forKey: "mm_reviewLastAsked") == nil)
    }
}

// MARK: - AIService error paths
//
// Chat and Weekly Insight each retry once on a 401 (the cached token was refused) and map
// every other failure onto user-facing copy. Until 2026-10-10 none of that was exercised: these
// stub the Worker through an injected URLSession. Own stub class, so this suite cannot race
// WorkerTransportTests over StubURLProtocol's shared handler.

final class SequenceStubURLProtocol: URLProtocol, @unchecked Sendable {
    enum Reply { case http(Int, String), fail(URLError.Code) }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var _queue: [Reply] = []
    nonisolated(unsafe) private static var _captured: [URLRequest] = []
    nonisolated(unsafe) private static var _bodies: [Data] = []

    static func queue(_ replies: Reply...) {
        lock.lock(); defer { lock.unlock() }
        _queue = replies; _captured = []; _bodies = []
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
        let reply = Self._queue.isEmpty ? .http(500, "") : Self._queue.removeFirst()
        Self.lock.unlock()

        switch reply {
        case .fail(let code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        case .http(let status, let body):
            guard let url = request.url,
                  let resp = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil) else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return
            }
            client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}

@Suite(.serialized)
struct AIServiceErrorPathTests {
    private let okBody = #"{"choices":[{"message":{"content":"  You're doing well.  "}}]}"#

    private func makeService() -> AIService {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [SequenceStubURLProtocol.self]
        return AIService(session: URLSession(configuration: cfg))
    }

    private func sendChat(_ service: AIService) async throws -> String {
        let history = [ChatMessage(content: "I feel anxious", isUser: true, mood: .anxious, timestamp: Date())]
        return try await service.send(history: history, mood: .anxious)
    }

    private func insight(_ service: AIService) async -> String {
        await service.generateWeeklyInsight(sessions: [], journal: [])
    }

    // MARK: Chat

    @Test func chatRetriesOnceAfter401AndReturnsTheReply() async throws {
        SequenceStubURLProtocol.queue(.http(401, ""), .http(200, okBody))
        let reply = try await sendChat(makeService())
        #expect(reply == "You're doing well.")
        #expect(SequenceStubURLProtocol.captured.count == 2)
        #expect(SequenceStubURLProtocol.captured.allSatisfy { $0.url?.path == "/chat" })
    }

    @Test func chatShowsVerificationCopyWhenTheRetryIsAlsoRefused() async throws {
        SequenceStubURLProtocol.queue(.http(401, ""), .http(401, ""))
        let reply = try await sendChat(makeService())
        #expect(reply == AIService.verificationFailedMessage)
        #expect(SequenceStubURLProtocol.captured.count == 2, "exactly one retry, never a loop")
    }

    @Test func chatDoesNotRetryARateLimit() async throws {
        SequenceStubURLProtocol.queue(.http(429, ""))
        let reply = try await sendChat(makeService())
        #expect(reply.contains("need a moment to breathe"))
        #expect(SequenceStubURLProtocol.captured.count == 1)
    }

    @Test func chatShowsServiceCopyOnAnOutage() async throws {
        SequenceStubURLProtocol.queue(.http(502, ""))
        let reply = try await sendChat(makeService())
        #expect(reply == AIService.serviceUnavailableMessage)
        #expect(SequenceStubURLProtocol.captured.count == 1)
    }

    // Offline and a malformed 200 both throw; JournalViewModel maps the error with
    // userFacingError(for:), so assert the mapping the user actually sees.
    @Test func chatOfflineThrowsAndMapsToOfflineCopy() async {
        SequenceStubURLProtocol.queue(.fail(.notConnectedToInternet))
        do {
            _ = try await sendChat(makeService())
            Issue.record("expected a throw")
        } catch {
            #expect(AIService.userFacingError(for: error) == AIService.offlineMessage)
        }
    }

    @Test func chatMalformed200ThrowsAndMapsToServiceCopy() async {
        SequenceStubURLProtocol.queue(.http(200, #"{"unexpected":true}"#))
        do {
            _ = try await sendChat(makeService())
            Issue.record("expected a throw")
        } catch {
            #expect(AIService.userFacingError(for: error) == AIService.serviceUnavailableMessage)
        }
    }

    // A long chat used to grow past the Worker's 20,000-character body cap; every later
    // message in that conversation then 413'd and showed the outage copy. Only the recent
    // tail is sent now, so the request stays small however long the conversation gets.
    @Test func longChatRequestStaysUnderTheWorkerCap() async throws {
        SequenceStubURLProtocol.queue(.http(200, okBody))
        let long = (0..<200).map { i in
            ChatMessage(content: String(repeating: "word ", count: 40) + "#\(i)", isUser: i % 2 == 0, mood: nil, timestamp: Date())
        }
        _ = try await makeService().send(history: long, mood: .neutral)
        let body = SequenceStubURLProtocol.bodies.first ?? Data()
        #expect(body.count < 20_000)
        let obj = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let msgs = obj?["messages"] as? [[String: String]] ?? []
        #expect(msgs.first?["role"] == "system")
        #expect(msgs.last?["content"]?.hasSuffix("#199") == true, "the newest message is always sent")
    }

    // MARK: Weekly Insight — fails silently to "" so the card can fall back

    @Test func insightRetriesOnceAfter401AndReturnsTheText() async {
        SequenceStubURLProtocol.queue(.http(401, ""), .http(200, okBody))
        #expect(await insight(makeService()) == "You're doing well.")
        #expect(SequenceStubURLProtocol.captured.count == 2)
        #expect(SequenceStubURLProtocol.captured.allSatisfy { $0.url?.path == "/insight" })
    }

    @Test func insightIsEmptyWhenTheRetryIsAlsoRefused() async {
        SequenceStubURLProtocol.queue(.http(401, ""), .http(401, ""))
        #expect(await insight(makeService()) == "")
        #expect(SequenceStubURLProtocol.captured.count == 2)
    }

    @Test func insightIsEmptyOnOutageOfflineOrMalformedBody() async {
        SequenceStubURLProtocol.queue(.http(500, ""))
        #expect(await insight(makeService()) == "")
        SequenceStubURLProtocol.queue(.fail(.notConnectedToInternet))
        #expect(await insight(makeService()) == "")
        SequenceStubURLProtocol.queue(.http(200, #"{"unexpected":true}"#))
        #expect(await insight(makeService()) == "")
    }
}

struct RecentHistoryTests {
    private func msg(_ text: String, user: Bool = true) -> ChatMessage {
        ChatMessage(content: text, isUser: user, mood: nil, timestamp: Date())
    }

    @Test func shortHistoryIsSentWhole() {
        let h = [msg("a"), msg("b", user: false), msg("c")]
        #expect(AIService.recentHistory(h, maxChars: 100).map(\.content) == ["a", "b", "c"])
    }

    @Test func keepsTheNewestMessagesThatFitInOrder() {
        let h = [msg("1111"), msg("2222", user: false), msg("3333"), msg("4444", user: false)]
        #expect(AIService.recentHistory(h, maxChars: 9).map(\.content) == ["3333", "4444"])
    }

    @Test func alwaysKeepsTheNewestMessageEvenIfItAloneIsOverBudget() {
        let h = [msg("old"), msg(String(repeating: "x", count: 50))]
        #expect(AIService.recentHistory(h, maxChars: 10).count == 1)
        #expect(AIService.recentHistory(h, maxChars: 10).first?.content.count == 50)
    }

    @Test func emptyHistoryStaysEmpty() {
        #expect(AIService.recentHistory([], maxChars: 10).isEmpty)
    }
}

// MARK: - SafetyChecker

// A match replaces the AI reply with the 988 / Crisis Text Line response, so the list has two jobs:
// catch indirect and differently-typed crisis language, and leave everyday venting to the AI.
struct SafetyCheckerTests {

    // Indirect ideation that the original 13 phrases let through to the model.
    @Test(arguments: [
        "I don't see the point anymore",
        "everyone would be better off without me",
        "I wish I was dead",
        "honestly I wish I wasn't here",
        "I don't want to be here anymore",
        "I have nothing to live for",
        "life isn't worth living",
        "I'd rather be dead",
        "I want to go to sleep and never wake up",
        "I've been feeling suicidal",
        "I keep cutting myself",
        "I want to unalive myself",
        "I took an overdose",
    ])
    func flagsIndirectCrisisLanguage(_ text: String) {
        #expect(SafetyChecker().containsRisk(text))
    }

    // Whole-word matching must not lose inflected forms that the old substring search caught
    // ("self-harming" contains "self-harm"), nor common -ing/-ed forms of the listed phrases.
    @Test(arguments: [
        "I've been self-harming again",
        "I self harmed last night",
        "I'm thinking about killing myself",
        "I keep hurting myself",
        "I wanted to die",
    ])
    func flagsInflectedForms(_ text: String) {
        #expect(SafetyChecker().containsRisk(text))
    }

    // The iPhone keyboard types a curly apostrophe (U+2019) by default, and people often drop the
    // apostrophe entirely; neither may stop an existing phrase from matching.
    @Test(arguments: [
        "I don\u{2019}t want to live",
        "i dont want to live anymore",
        "I can\u{2019}t go on like this",
        "I  WANT   TO DIE",
    ])
    func matchesRegardlessOfApostropheStyleCaseOrSpacing(_ text: String) {
        #expect(SafetyChecker().containsRisk(text))
    }

    // Round 5 (Joel, 2026-11-17): his exact answer to the breathing coach, and the same sentence with
    // other apostrophes, punctuation and capitals. "kill myself" must match in every form.
    @Test(arguments: [
        "I am not good want to kill myself",
        "I\u{2019}m not good, want to KILL MYSELF!!",
        "i'm not good... want to kill myself.",
        "I AM NOT GOOD WANT TO KILL MYSELF",
        "I am not good \u{2014} want to kill-myself",
    ])
    func joelsBreathingAnswerIsACrisis(_ text: String) {
        #expect(SafetyChecker().containsRisk(text))
        #expect(["kill myself", "kill-myself"].contains(SafetyChecker().matchedPhrase(text) ?? ""))
    }

    // Common phrasings, especially from dictation ("do not" instead of "don't", "my self" as two
    // words), that the list missed before round 5.
    @Test(arguments: [
        "I want to kill my self",
        "I do not want to live anymore",
        "I don't want to be alive",
        "i do not want to be alive",
    ])
    func flagsDictatedPhrasings(_ text: String) {
        #expect(SafetyChecker().containsRisk(text))
    }

    // Everyday figures of speech must still reach the AI rather than get the crisis response.
    @Test(arguments: [
        "I'm dying to see the new movie",
        "this traffic is killing me",
        "there's no point arguing with my boss",
        "I'm better off without caffeine",
        "I want to sleep early tonight",
        "I had a really rough day at work",
        "I never wake up on time",
        "we're spending it with family this weekend",
        "I need to kill my self-doubt",
        "I'm good, ready to breathe",
    ])
    func leavesEverydayFiguresOfSpeechAlone(_ text: String) {
        #expect(!SafetyChecker().containsRisk(text))
    }
}

// MARK: - EmotionDetector

// The detected mood tags the message, drives the header emoji, and feeds the mood chart and Weekly
// Insight, so a wrong mood is visible and sticky. Every misfire a user reports goes in here first.
struct EmotionDetectorTests {

    // Ordinary sentences that used to read as angry or sad because a mood word was only the START of
    // another word ("made" → mad, "mission" → miss, "crystal" → cry) or a word with a non-mood sense.
    @Test(arguments: [
        "I made pancakes for breakfast",
        "Good morning! I made it to work on time",
        "I'm done with my homework",
        "I watched a mission impossible movie",
        "I bought a crystal vase",
        "The content of the email was long",
        "We watched car racing on TV",
        "I'm embracing thoughts of gratitude today",
        "No racing thoughts tonight, finally calm",
    ])
    func everydaySentencesStayNeutral(_ text: String) {
        #expect(EmotionDetector().detectEmotion(from: text) == .neutral)
    }

    // Real mood language, including inflected forms, must still be detected.
    @Test(arguments: [
        ("I'm so angry at him", MoodType.angry),
        ("I hated today", .angry),
        ("I feel anxious about tomorrow", .anxious),
        ("I'm panicking about the exam", .anxious),
        ("my thoughts are racing tonight", .anxious),
        ("I've been crying all night", .sad),
        ("there is so much sadness in me", .sad),
        ("I'm happy today", .happy),
        ("I feel fearful", .anxious),
        ("I'm so happy😊", .happy),
        ("feeling sad😭", .sad),
        ("I cried all night", .sad),
    ])
    func realMoodLanguageIsStillDetected(_ text: String, _ mood: MoodType) {
        #expect(EmotionDetector().detectEmotion(from: text) == mood)
    }

    // "I'm happy I made dinner" scored happy 1, angry 1 and the winner was random. A sentence with one
    // real mood word must get that mood.
    @Test func aRealMoodWordIsNotOutvotedByAFalseOne() {
        #expect(EmotionDetector().detectEmotion(from: "I'm happy I made dinner") == .happy)
    }

    // Ties resolve in list order (happy, sad, anxious, angry), never at random.
    @Test func tiesResolveInListOrderNotAtRandom() {
        #expect(EmotionDetector().detectEmotion(from: "I'm sad and angry") == .sad)
        #expect(EmotionDetector().detectEmotion(from: "I miss my mom but I'm happy today") == .happy)
    }

    // A word listed both as itself and as keyword + ending ("overthinking", "crying") counts once,
    // or one anxious word outvotes one happy word.
    @Test func aWordCountsOnceEvenIfListedTwice() {
        #expect(EmotionDetector().detectEmotion(from: "I'm overthinking but honestly happy") == .happy)
    }

    // The iPhone keyboard types "don’t" with a curly apostrophe; the negation must still apply.
    @Test func curlyApostropheNegationStillNegates() {
        #expect(EmotionDetector().detectEmotion(from: "I don\u{2019}t feel happy") == .neutral)
    }
}

// MARK: - Crisis resources by region

// 988 reaches only the US and Canada. Everyone else must see a line that works where they are, and
// every message must still tell people outside that country what to do.
struct CrisisResourcesTests {

    private func response(_ region: String?) -> String {
        SafetyChecker().crisisResponse(forRegion: region)
    }

    @Test func unitedStatesGets988AndCrisisTextLine() {
        #expect(response("US").contains("988"))
        #expect(response("US").contains("741741"))
    }

    @Test(arguments: ["PR", "GU", "VI", "AS", "MP"])
    func usTerritoriesGet988(_ region: String) {
        #expect(response(region).contains("988"))
    }

    @Test func canadaGets988ButNotTheUSOnlyTextLine() {
        #expect(response("CA").contains("988"))
        #expect(!response("CA").contains("741741"))
    }

    @Test(arguments: [
        ("PH", "1553"), ("GB", "116 123"), ("IE", "116 123"), ("AU", "13 11 14"), ("NZ", "1737"),
        ("IN", "14416"), ("SG", "1767"), ("MY", "15555"), ("ZA", "0800 567 567"),
    ])
    func countriesOutside988GetTheirOwnLineAndNot988(_ region: String, _ number: String) {
        #expect(response(region).contains(number))
        #expect(!response(region).contains("988"))
    }

    @Test(arguments: ["FR", "DE", "JP", "BR"])
    func unlistedCountriesGetTheDirectoryFallbackAndNot988(_ region: String) {
        #expect(response(region).contains("findahelpline.com"))
        #expect(response(region).contains("local emergency number"))
        #expect(!response(region).contains("988"))
    }

    @Test func noRegionGetsTheFallback() {
        #expect(response(nil).contains("findahelpline.com"))
    }

    // The Region setting can be wrong (travel, expats), so every listed country also says what to do elsewhere.
    @Test(arguments: ["US", "CA", "PH", "GB", "AU"])
    func everyCountryMessageCarriesTheElsewhereLine(_ region: String) {
        #expect(response(region).contains("local emergency number"))
    }

    @Test func onboardingLineFollowsTheRegionToo() {
        #expect(SafetyChecker.crisisLine(forRegion: "US").contains("988"))
        #expect(SafetyChecker.crisisLine(forRegion: "PH").contains("1553"))
        #expect(!SafetyChecker.crisisLine(forRegion: "PH").contains("988"))
        #expect(SafetyChecker.crisisLine(forRegion: "FR").contains("local emergency number"))
    }
}

// MARK: - Crisis messages skip mood detection

// Joel's rule (2026-10-11): a message that triggers the crisis response is not mood-tagged. The
// detector would read "I am sad today … I am thinking to kill myself" as Sad, put Sad on the header,
// and count the exchange in the mood chart; a crisis is not a mood data point.
@MainActor
struct CrisisMessageMoodTests {

    private let crisisText = "Good day. I am sad today, due to full of problems, I am thinking to kill myself."

    @Test func crisisMessageIsTaggedNeutralEvenWithAMoodWord() async {
        let vm = JournalViewModel()
        vm.currentInput = crisisText
        await vm.send()
        #expect(vm.messages.first?.isUser == true)
        #expect(vm.messages.first?.mood == .neutral)
    }

    @Test func crisisMessageLeavesTheHeaderMoodAsItWas() async {
        let vm = JournalViewModel()
        vm.currentMood = .happy
        vm.currentInput = crisisText
        await vm.send()
        #expect(vm.currentMood == .happy)
    }

    @Test func crisisReplyCarriesNoMood() async {
        let vm = JournalViewModel()
        vm.currentInput = crisisText
        await vm.send()
        #expect(vm.messages.count == 2)
        #expect(vm.messages.last?.isUser == false)
        #expect(vm.messages.last?.mood == nil)
    }
}

// MARK: - Voice-guided Box Breathing

// Round 4 (Joel, 2026-11-16, real-iPhone test): every phase is 3 s; Alex speaks one warm line per phase,
// near Apple's normal speed with a little more energy, and no long pauses inside a phrase.
struct BreathingCueScriptTests {

    @Test func phasesRunInBoxBreathingOrder() {
        #expect(BreathingPhase.allCases == [.inhale, .holdAfterInhale, .exhale, .holdAfterExhale])
        #expect(BreathingPhase.allCases.map(\.label) == ["Inhale", "Hold", "Exhale", "Hold"])
    }

    // Only the breathing phases are checked against the sensor; the holds are not.
    @Test func onlyInhaleAndExhaleExpectABreath() {
        #expect(BreathingPhase.allCases.map(\.expectedBreath) == [.inhaling, nil, .exhaling, nil])
    }

    @Test func everyPhaseIsThreeSeconds() {
        #expect(BreathingPhase.allCases.map(\.seconds) == [3, 3, 3, 3])
        #expect(BreathingCueScript.cycleSeconds == 12)
        #expect(BreathingCueScript.cycles == 4)
        #expect(BreathingCueScript.header == "Inhale 3s · Hold 3s · Exhale 3s · Hold 3s")
    }

    @Test func eachPhaseIsOneWarmLineCountingToThree() {
        #expect(BreathingCueScript.cue(for: .inhale)          == "Breathe in, two, three.")
        #expect(BreathingCueScript.cue(for: .holdAfterInhale) == "Gently hold, two, three.")
        #expect(BreathingCueScript.cue(for: .exhale)          == "Now breathe out, two, three.")
        #expect(BreathingCueScript.cue(for: .holdAfterExhale) == "And hold, two, three.")
    }

    // Round 4: the ellipses made long gaps inside a phrase; commas give short, natural ones.
    @Test func noLongPausesInsideAnyLine() {
        let lines = BreathingCueScript.allSpokenLines(name: "Sam")
        #expect(!lines.isEmpty)
        #expect(lines.allSatisfy { !$0.contains("…") && !$0.contains("...") })
    }

    // Round 5, item 6: the intro screen. Alex introduces herself and says she'll guide the breathing.
    @Test func greetsByFirstNameWhenKnownOtherwiseHiThere() {
        #expect(BreathingCueScript.opening(name: nil)
                == "Hi there, I'm Alex. I'll guide your breathing today. How are you feeling right now?")
        #expect(BreathingCueScript.opening(name: "Sam")
                == "Hi Sam, I'm Alex. I'll guide your breathing today. How are you feeling right now?")
        #expect(BreathingCueScript.opening(name: "  ") == BreathingCueScript.opening(name: nil))
    }

    @Test func conversationLinesAreWarm() {
        #expect(BreathingCueScript.coachName     == "Alex")
        #expect(BreathingCueScript.thanks        == "Thank you for sharing that with me.")
        #expect(BreathingCueScript.readyQuestion == "Are you ready to start?")
        #expect(BreathingCueScript.readyAgain    == "Take your time. Just say yes when you'd like to start.")
        #expect(BreathingCueScript.declined      == "That's completely okay. I'll be right here whenever you'd like to breathe together.")
    }

    // Round 5, item 3: the phone is held in the hands, never rested on the body.
    @Test func calibrationLinesAskForNaturalBreathing() {
        #expect(BreathingCueScript.settle         == "Let's get comfortable first. Hold your phone gently in both hands, close to you, and keep it as still as you can.")
        #expect(BreathingCueScript.calibrate      == "Now breathe in and out naturally, and I'll follow along with you.")
        #expect(BreathingCueScript.calibrateAgain == "I couldn't quite feel your breathing yet, and that's okay. Let's try once more. Hold your phone gently and still, and breathe in and out naturally.")
        #expect(BreathingCueScript.letsBegin      == "Lovely, I can feel your breathing. Let's take a slow breath in together.")
    }

    @Test func neverAsksToRestThePhoneOnTheBody() {
        let everything = BreathingCueScript.allSpokenLines(name: "Sam") + [BreathingCueScript.pauseTip, BreathingCueScript.betaLabel]
        for word in ["chest", "belly", "on your body", "radiation"] {
            #expect(everything.allSatisfy { !$0.lowercased().contains(word) }, "\(word)")
        }
        #expect(BreathingCueScript.pauseTip == "Tip: hold your phone gently and keep it still while you breathe.")
    }

    // Round 5, item 4: breath detection is approximate, so it carries a small Beta label.
    @Test func breathDetectionIsLabelledBeta() {
        #expect(BreathingCueScript.betaLabel == "Breath detection")
        #expect(BreathingCueScript.betaTag == "BETA")
    }

    // Round 5, item 6: placeholder portrait until Joel picks one.
    @Test func placeholderPortraitIsTheLetterA() {
        #expect(BreathingCueScript.portraitInitial == "A")
    }

    // Round 4, item 6: the pause line Joel asked for, and no "three misses" ending any more.
    @Test func pauseLineAndEndings() {
        #expect(BreathingCueScript.pause == "Let's rest for a moment. Breathe in with me whenever you're ready, and we'll continue from here.")
        #expect(BreathingCueScript.congratulations
                == "Wonderful, you've completed your breathing for today. Thank you for taking this time for yourself.")
        #expect(BreathingCueScript.anotherRound      == "Would you like to do another round?")
        #expect(BreathingCueScript.anotherRoundAgain == "Just say yes if you'd like another round, or no if you're all done.")
        #expect(BreathingCueScript.goAgain           == "Lovely, let's go again together.")
        #expect(BreathingCueScript.goodbye           == "That's okay. Thank you for breathing with me today. See you again tomorrow.")
    }

    // Round 4, item 2: no "I'm ready" button. A refused microphone gets a plain request to allow it.
    @Test func cannotHearAsksToAllowTheMicrophoneInSettings() {
        let refused = BreathingCueScript.cannotHear(permissionRefused: true)
        #expect(refused.contains("Settings"))
        #expect(refused.contains("Microphone"))
        #expect(!refused.contains("I'm ready"))
        #expect(!BreathingCueScript.cannotHear(permissionRefused: false).contains("I'm ready"))
    }

    @Test func listensAboutEightSeconds() {
        #expect(BreathingCueScript.listenSeconds == 8)
    }

    @Test func voiceChoiceIsAlexOrMenAndRemembered() {
        #expect(BreathingVoiceChoice.storageKey == "breathingVoiceGender")
        #expect(BreathingVoiceChoice.defaultChoice == .alex)
        #expect(BreathingVoiceChoice.alex.label == "Alex")
        #expect(BreathingVoiceChoice.men.label == "Men")
    }

    // Round 4, item 1: Apple's normal speed (0.5), pitch 1.05 for a little energy, no added gaps.
    @Test func voiceIsNormalSpeedWithALittleMoreEnergy() {
        #expect(BreathingCueScript.voiceRate == AVSpeechUtteranceDefaultSpeechRate)
        #expect(BreathingCueScript.voiceRate == 0.5)
        #expect(BreathingCueScript.voicePitch == 1.05)
        #expect(BreathingCueScript.voiceLanguage == "en-US")
    }

    @Test func everyUtteranceUsesTheseSettings() {
        let u = BreathingCueScript.utterance("Breathe in, two, three.", voice: nil)
        #expect(u.speechString == "Breathe in, two, three.")
        #expect(u.rate == 0.5)
        #expect(u.pitchMultiplier == 1.05)
        #expect(u.preUtteranceDelay == 0)
        #expect(u.postUtteranceDelay == 0)
    }
}

// The talk around the exercise. Before: how you feel, then ready (yes starts, no ends gently, no
// answer asks once more). After a finished session (round 4, item 3): "Would you like to do another
// round?" Yes goes again, no says goodbye, no answer asks once more, then goodbye.
struct BreathingConversationTests {

    @Test func startsByAskingHowYouFeel() {
        #expect(BreathingConversation.firstStep == .askFeeling)
    }

    @Test func anAnswerToHowYouFeelIsThankedThenTheReadyQuestion() {
        #expect(BreathingConversation.next(after: .askFeeling, .feelingHeard) == .askReady(attempt: 1, thankFirst: true))
        #expect(BreathingConversation.next(after: .askFeeling, .feelingSilent) == .askReady(attempt: 1, thankFirst: false))
    }

    @Test func readyYesBeginsNoEndsGently() {
        #expect(BreathingConversation.next(after: .askReady(attempt: 1, thankFirst: true), .ready(.yes)) == .begin)
        #expect(BreathingConversation.next(after: .askReady(attempt: 1, thankFirst: false), .ready(.no)) == .endGently)
    }

    @Test func noAnswerToReadyAsksOnceMoreThenEndsGently() {
        let second = BreathingConversation.next(after: .askReady(attempt: 1, thankFirst: true), .ready(nil))
        #expect(second == .askReady(attempt: 2, thankFirst: false))
        #expect(BreathingConversation.next(after: second, .ready(nil)) == .endGently)
    }

    @Test func afterASessionAlexAsksForAnotherRound() {
        #expect(BreathingConversation.afterSession == .askAnotherRound(attempt: 1))
    }

    @Test func anotherRoundYesGoesAgainNoSaysGoodbye() {
        #expect(BreathingConversation.next(after: .askAnotherRound(attempt: 1), .ready(.yes)) == .goAgain)
        #expect(BreathingConversation.next(after: .askAnotherRound(attempt: 2), .ready(.yes)) == .goAgain)
        #expect(BreathingConversation.next(after: .askAnotherRound(attempt: 1), .ready(.no)) == .goodbye)
    }

    @Test func noAnswerToAnotherRoundAsksOnceMoreThenGoodbye() {
        let second = BreathingConversation.next(after: .askAnotherRound(attempt: 1), .ready(nil))
        #expect(second == .askAnotherRound(attempt: 2))
        #expect(BreathingConversation.next(after: second, .ready(nil)) == .goodbye)
    }

    // Round 5, item 1: a crisis answer stops everything, from any step, and nothing follows it.
    @Test func aCrisisAnswerStopsTheConversationFromAnyStep() {
        let steps: [BreathingConversation.Step] = [.askFeeling, .askReady(attempt: 1, thankFirst: true),
                                                   .askAnotherRound(attempt: 1), .begin, .goAgain]
        for step in steps { #expect(BreathingConversation.next(after: step, .crisis) == .crisis) }
        #expect(BreathingConversation.next(after: .crisis, .ready(.yes)) == .crisis)
        #expect(BreathingConversation.next(after: .crisis, .feelingHeard) == .crisis)
    }

    @Test func eventsThatDoNotFitTheStepChangeNothing() {
        #expect(BreathingConversation.next(after: .askFeeling, .ready(.yes)) == .askFeeling)
        #expect(BreathingConversation.next(after: .begin, .feelingHeard) == .begin)
        #expect(BreathingConversation.next(after: .goodbye, .ready(.yes)) == .goodbye)
    }
}

// The ready check listens for a spoken answer. "Not ready" must never count as yes, and a word that
// merely contains "yes" ("yesterday") must not start the exercise.
struct ReadyAnswerTests {

    @Test(arguments: ["yes", "Yes", "YES", "yeah", "Yeah.", "yes please", "Yes, please!", "sure",
                      "Sure thing", "ready", "I'm ready", "READY", "yep", "okay", "ok let's go"])
    func recognisesYes(_ said: String) {
        #expect(ReadyAnswer.parse(said) == .yes)
    }

    @Test(arguments: ["no", "No.", "NO", "nope", "not yet", "no thanks", "I'm not ready", "not really",
                      "nah", "maybe later", "don't want to"])
    func recognisesNo(_ said: String) {
        #expect(ReadyAnswer.parse(said) == .no)
    }

    @Test(arguments: ["", "   ", "hmm", "yesterday was hard", "I already told you", "what"])
    func ignoresAnythingElse(_ said: String) {
        #expect(ReadyAnswer.parse(said) == nil)
    }
}

// Voice: Alex is the best installed US-English female voice (Premium, then Enhanced, then standard).
// Men: Aaron when installed, otherwise the best other male en-US voice, current voices before the old
// MacinTalk ones. Never a novelty voice, the user's Personal Voice, or the child voice "Junior".
struct BreathingVoicePickerTests {

    private func voice(_ name: String, gender: AVSpeechSynthesisVoiceGender, quality: AVSpeechSynthesisVoiceQuality = .default,
                       language: String = "en-US", legacy: Bool = false, novelty: Bool = false, personal: Bool = false) -> BreathingVoiceCandidate {
        let id = legacy ? "com.apple.speech.synthesis.voice.\(name)" : "com.apple.voice.compact.\(language).\(name)"
        return BreathingVoiceCandidate(identifier: id, name: name, language: language, gender: gender,
                                       quality: quality, isNovelty: novelty, isPersonal: personal)
    }

    private var simulatorSet: [BreathingVoiceCandidate] {
        [voice("Samantha", gender: .female), voice("Fred", gender: .male, legacy: true),
         voice("Ralph", gender: .unspecified, legacy: true), voice("Junior", gender: .unspecified, legacy: true),
         voice("Kathy", gender: .unspecified, legacy: true), voice("Zarvox", gender: .male, legacy: true, novelty: true)]
    }

    @Test func alexPrefersPremiumThenEnhancedThenStandard() {
        let standard = voice("Samantha", gender: .female)
        let enhanced = voice("Ava (Enhanced)", gender: .female, quality: .enhanced)
        let premium  = voice("Zoe (Premium)", gender: .female, quality: .premium)
        #expect(BreathingVoicePicker.pick(.alex, from: [standard, enhanced, premium])?.name == "Zoe (Premium)")
        #expect(BreathingVoicePicker.pick(.alex, from: [standard, enhanced])?.name == "Ava (Enhanced)")
        #expect(BreathingVoicePicker.pick(.alex, from: [standard])?.name == "Samantha")
    }

    @Test func alexOnTheSimulatorSetIsSamantha() {
        #expect(BreathingVoicePicker.pick(.alex, from: simulatorSet)?.name == "Samantha")
    }

    @Test func alexNeverPicksAMaleNoveltyPersonalOrOtherLanguageVoice() {
        let pick = BreathingVoicePicker.pick(.alex, from: [
            voice("Aaron", gender: .male, quality: .premium),
            voice("Bubbles", gender: .female, quality: .premium, novelty: true),
            voice("Me", gender: .female, quality: .premium, personal: true),
            voice("Kate", gender: .female, quality: .premium, language: "en-GB"),
        ])
        #expect(pick == nil)
    }

    @Test func menGetsAaronWhenInstalled() {
        let pick = BreathingVoicePicker.pick(.men, from: simulatorSet + [voice("Aaron", gender: .male)])
        #expect(pick?.name == "Aaron")
    }

    @Test func menFallsBackToACurrentMaleVoiceBeforeAnOldOne() {
        let pick = BreathingVoicePicker.pick(.men, from: simulatorSet + [voice("Evan", gender: .male)])
        #expect(pick?.name == "Evan")
    }

    @Test func menOnTheSimulatorSetGetsFred() {
        #expect(BreathingVoicePicker.pick(.men, from: simulatorSet)?.name == "Fred")
    }
}

// The breathing streak is separate from the mood check-in streak (mm_ keys): one completed session per
// calendar day; the next day adds one; a missed day starts again at 1.
struct BreathingStreakTests {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC") ?? .current
        return c
    }

    private func day(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso + "T10:00:00Z") ?? .distantPast
    }

    @Test func firstSessionStartsAtOne() {
        let s = BreathingStreak.record(.empty, on: day("2026-11-16"), calendar: calendar)
        #expect(s == BreathingStreak.State(current: 1, longest: 1, totalDays: 1, lastDay: "2026-11-16"))
    }

    @Test func secondSessionSameDayCountsOnce() {
        let first  = BreathingStreak.record(.empty, on: day("2026-11-16"), calendar: calendar)
        let second = BreathingStreak.record(first, on: day("2026-11-16"), calendar: calendar)
        #expect(second == first)
    }

    @Test func nextDayAddsOne() {
        let first  = BreathingStreak.record(.empty, on: day("2026-11-16"), calendar: calendar)
        let next   = BreathingStreak.record(first, on: day("2026-11-17"), calendar: calendar)
        #expect(next.current == 2)
        #expect(next.longest == 2)
        #expect(next.totalDays == 2)
    }

    @Test func missedDayResetsToOneButKeepsLongestAndTotal() {
        let state = BreathingStreak.State(current: 5, longest: 5, totalDays: 9, lastDay: "2026-11-16")
        let after = BreathingStreak.record(state, on: day("2026-11-18"), calendar: calendar)
        #expect(after == BreathingStreak.State(current: 1, longest: 5, totalDays: 10, lastDay: "2026-11-18"))
    }

    @Test func monthBoundaryIsStillTheNextDay() {
        let state = BreathingStreak.State(current: 3, longest: 3, totalDays: 3, lastDay: "2026-11-30")
        #expect(BreathingStreak.record(state, on: day("2026-12-01"), calendar: calendar).current == 4)
    }

    @Test func streakShownBeforeASession() {
        let state = BreathingStreak.State(current: 5, longest: 8, totalDays: 12, lastDay: "2026-11-16")
        #expect(BreathingStreak.displayed(state, on: day("2026-11-16"), calendar: calendar) == 5)
        #expect(BreathingStreak.displayed(state, on: day("2026-11-17"), calendar: calendar) == 5)
        #expect(BreathingStreak.displayed(state, on: day("2026-11-18"), calendar: calendar) == 0)
        #expect(BreathingStreak.displayed(.empty, on: day("2026-11-18"), calendar: calendar) == 0)
    }

    @Test func milestonesAt7_14_21_30() {
        #expect(BreathingStreak.milestones == [7, 14, 21, 30])
        let six = BreathingStreak.State(current: 6, longest: 6, totalDays: 6, lastDay: "2026-11-16")
        let seven = BreathingStreak.record(six, on: day("2026-11-17"), calendar: calendar)
        #expect(BreathingStreak.newMilestone(before: six, after: seven) == 7)
        #expect(BreathingStreak.newMilestone(before: seven, after: seven) == nil)
        #expect(BreathingStreak.highestBadge(for: 16) == 14)
        #expect(BreathingStreak.highestBadge(for: 6) == nil)
    }

    @Test func dayThirtyUnlocksTheReward() {
        let twentyNine = BreathingStreak.State(current: 29, longest: 29, totalDays: 40, lastDay: "2026-11-16")
        #expect(BreathingReward.isUnlocked(by: twentyNine) == false)
        let thirty = BreathingStreak.record(twentyNine, on: day("2026-11-17"), calendar: calendar)
        #expect(thirty.current == 30)
        #expect(BreathingStreak.newMilestone(before: twentyNine, after: thirty) == 30)
        #expect(BreathingReward.isUnlocked(by: thirty))
        let reset = BreathingStreak.record(thirty, on: day("2026-11-20"), calendar: calendar)
        #expect(reset.current == 1)
        #expect(BreathingReward.isUnlocked(by: reset))
    }

    @Test func savesUnderItsOwnKeysNotTheMoodStreakKeys() throws {
        let suite = "breathing-streak-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let state = BreathingStreak.State(current: 3, longest: 8, totalDays: 12, lastDay: "2026-11-16")
        BreathingStreak.save(state, to: defaults)
        #expect(BreathingStreak.load(from: defaults) == state)
        let written = defaults.persistentDomain(forName: suite)?.keys.sorted() ?? []
        #expect(written == ["breathingStreakCurrent", "breathingStreakLastDay", "breathingStreakLongest", "breathingStreakTotalDays"])
        #expect(written.allSatisfy { !$0.hasPrefix("mm_") })
    }
}

// Synthetic chest motion for the breath-sensing tests. The simulator has no motion sensor, so these
// build fake readings at 20 Hz: the phone's tilt (gravity direction) follows `tilt(t)` in degrees.
// Real accuracy can only be judged on a real iPhone resting on a real chest.
enum SyntheticChest {
    static func samples(start: Double, seconds: Double, accel: Double = 0.003,
                        tilt: (Double) -> Double) -> [BreathMotionSample] {
        let n = Int(seconds * 20)
        return (0..<n).map { i in
            let t = start + Double(i) / 20
            let r = tilt(t) * .pi / 180
            return BreathMotionSample(time: t, gravity: SIMD3(0, sin(r), -cos(r)), userAcceleration: accel)
        }
    }

    /// Relaxed breathing: `depth` degrees peak to peak, one breath every `period` seconds.
    static func natural(start: Double = 0, seconds: Double = 8, depth: Double = 0.6, period: Double = 5) -> [BreathMotionSample] {
        samples(start: start, seconds: seconds) { t in depth * (1 - cos(2 * .pi * (t - start) / period)) / 2 }
    }

    /// A steady move from `from` to `to` degrees over `seconds` (a guided breath in or out, or a hold).
    static func ramp(start: Double, seconds: Double = 3, from: Double, to: Double, accel: Double = 0.003) -> [BreathMotionSample] {
        samples(start: start, seconds: seconds, accel: accel) { t in from + (to - from) * min(1, (t - start) / (seconds - 0.05)) }
    }

    /// Lying still apart from tiny fast wobbles (`size` degrees either way).
    static func still(start: Double, seconds: Double = 3, at level: Double = 0, size: Double = 0.02) -> [BreathMotionSample] {
        var flip = false
        return samples(start: start, seconds: seconds) { _ in flip.toggle(); return level + (flip ? size : -size) }
    }

    static var profile: BreathProfile? { BreathCalibration.profile(from: natural()) }

    /// Round 5: a phone held in the hands. Hand tremor adds a fast wobble (`tremor` degrees) and some
    /// movement (`accel` g) on top of the breathing tilt. Deterministic, so the tests never flake.
    static func handHeld(start: Double, seconds: Double, tremor: Double = 0.06, accel: Double = 0.05,
                         tilt: @escaping (Double) -> Double) -> [BreathMotionSample] {
        samples(start: start, seconds: seconds, accel: accel) { t in
            tilt(t) + tremor * sin(t * 47) * cos(t * 31)
        }
    }
}

// Round 4, item 7: one cycle of natural breathing sets the detector's axis and thresholds.
struct BreathCalibrationTests {

    @Test func naturalBreathingGivesAProfile() throws {
        let profile = try #require(BreathCalibration.profile(from: SyntheticChest.natural()))
        let expected = 0.6 * .pi / 180
        #expect(abs(profile.amplitude - expected) < expected * 0.2)
        #expect(abs(profile.axis.y) > 0.95)                     // the tilt was about the phone's x axis
        #expect(abs(profile.threshold - BreathCalibration.thresholdFraction * profile.amplitude) < 1e-9)
    }

    @Test func aDeeperBreatherGetsAHigherThreshold() throws {
        let shallow = try #require(BreathCalibration.profile(from: SyntheticChest.natural(depth: 0.5)))
        let deep    = try #require(BreathCalibration.profile(from: SyntheticChest.natural(depth: 2.0)))
        #expect(deep.threshold > shallow.threshold * 3)
    }

    @Test func lyingStillGivesNoProfile() {
        #expect(BreathCalibration.profile(from: SyntheticChest.still(start: 0, seconds: 8)) == nil)
    }

    @Test func aPhoneBeingHandledGivesNoProfile() {
        let handled = SyntheticChest.samples(start: 0, seconds: 8, accel: 0.2) { t in 0.6 * sin(t) }
        #expect(BreathCalibration.profile(from: handled) == nil)
    }

    // Round 5, item 3: held in the hands, tremor and a little movement must not stop calibration.
    @Test func aHandHeldPhoneStillCalibrates() throws {
        let natural = SyntheticChest.handHeld(start: 0, seconds: 8) { t in 0.8 * (1 - cos(2 * .pi * t / 5)) / 2 }
        let profile = try #require(BreathCalibration.profile(from: natural))
        #expect(profile.threshold >= BreathCalibration.thresholdFraction * profile.amplitude - 1e-12)
    }

    @Test func tooLittleDataGivesNoProfile() {
        #expect(BreathCalibration.profile(from: SyntheticChest.natural(seconds: 2)) == nil)
    }
}

// The live detector: smoothed, with a threshold from calibration, so small movements don't count.
struct BreathTrackerTests {

    private func feed(_ tracker: inout BreathTracker, _ samples: [BreathMotionSample], learnInhale: Bool = false) -> [Breath] {
        samples.map { tracker.add($0, learnInhale: learnInhale); return tracker.breath }
    }

    @Test func aGuidedBreathIsInThenStillThenOut() throws {
        var tracker = BreathTracker(profile: try #require(SyntheticChest.profile))
        let inhale = feed(&tracker, SyntheticChest.ramp(start: 0, from: 0, to: 1), learnInhale: true)
        #expect(tracker.inhaleSign != nil)
        #expect(inhale.contains(.inhaling))
        #expect(!inhale.contains(.exhaling))
        let hold = feed(&tracker, SyntheticChest.still(start: 3, at: 1))
        #expect(hold.last == .still)
        #expect(!hold.contains(.exhaling))
        let exhale = feed(&tracker, SyntheticChest.ramp(start: 6, from: 1, to: 0))
        #expect(exhale.contains(.exhaling))
        #expect(!exhale.contains(.inhaling))
    }

    @Test func smallMovementsDoNotCount() throws {
        var tracker = BreathTracker(profile: try #require(SyntheticChest.profile))
        // Fast wobble plus a slow sway a fifth the size of a natural breath: neither is a breath.
        let wobble = SyntheticChest.still(start: 0, seconds: 6, size: 0.05)
        let sway   = SyntheticChest.samples(start: 6, seconds: 6) { t in 0.06 * sin(t - 6) }
        let seen = feed(&tracker, wobble + sway, learnInhale: true)
        #expect(seen.allSatisfy { $0 == .still || $0 == .unknown })
        #expect(tracker.inhaleSign == nil)
    }

    @Test func theFirstGuidedInhaleSetsWhichWayIsIn() throws {
        var tracker = BreathTracker(profile: try #require(SyntheticChest.profile))
        // This chest tilts the "other" way when breathing in.
        let inhale = feed(&tracker, SyntheticChest.ramp(start: 0, from: 0, to: -1), learnInhale: true)
        #expect(inhale.contains(.inhaling))
        let exhale = feed(&tracker, SyntheticChest.ramp(start: 3, from: -1, to: 0))
        #expect(exhale.contains(.exhaling))
    }

    @Test func movementBeforeTheDirectionIsKnownIsNotYetABreath() throws {
        var tracker = BreathTracker(profile: try #require(SyntheticChest.profile))
        let seen = feed(&tracker, SyntheticChest.ramp(start: 0, from: 0, to: 1), learnInhale: false)
        #expect(seen.allSatisfy { $0 == .still || $0 == .unknown })
        #expect(tracker.movement == .rising)
    }

    // Round 5, item 3: held in the hands. A guided breath is still seen through hand tremor, and tremor
    // plus a slow small drift alone is never a breath.
    @Test func handHeldBreathingIsSeenThroughTremor() throws {
        let calibration = SyntheticChest.handHeld(start: 0, seconds: 8) { t in 0.8 * (1 - cos(2 * .pi * t / 5)) / 2 }
        var tracker = BreathTracker(profile: try #require(BreathCalibration.profile(from: calibration)))
        let inhale = feed(&tracker, SyntheticChest.handHeld(start: 8, seconds: 3) { t in 1.2 * min(1, (t - 8) / 2.95) },
                          learnInhale: true)
        #expect(inhale.contains(.inhaling))
        let exhale = feed(&tracker, SyntheticChest.handHeld(start: 11, seconds: 3) { t in 1.2 * (1 - min(1, (t - 11) / 2.95)) })
        #expect(exhale.contains(.exhaling))
    }

    @Test func handTremorAloneIsNotABreath() throws {
        let calibration = SyntheticChest.handHeld(start: 0, seconds: 8) { t in 0.8 * (1 - cos(2 * .pi * t / 5)) / 2 }
        var tracker = BreathTracker(profile: try #require(BreathCalibration.profile(from: calibration)))
        let seen = feed(&tracker, SyntheticChest.handHeld(start: 8, seconds: 10) { t in 0.05 * sin((t - 8) / 2) },
                        learnInhale: true)
        #expect(seen.allSatisfy { $0 == .still || $0 == .unknown })
    }

    // Moving the hands (more than 0.12 g) is "can't tell", not a breath.
    @Test func movingTheHandsIsHandled() throws {
        var tracker = BreathTracker(profile: try #require(SyntheticChest.profile))
        let seen = feed(&tracker, SyntheticChest.ramp(start: 0, from: 0, to: 1, accel: 0.2), learnInhale: true)
        #expect(tracker.movement == .handled)
        #expect(!seen.contains(.inhaling))
        #expect(BreathTracker.handledAcceleration == 0.12)
    }

    @Test func aPhoneBeingHandledIsUnknown() throws {
        var tracker = BreathTracker(profile: try #require(SyntheticChest.profile))
        let seen = feed(&tracker, SyntheticChest.ramp(start: 0, from: 0, to: 1, accel: 0.3), learnInhale: true)
        #expect(seen.last == .unknown)
        #expect(tracker.movement == .handled)
        #expect(!seen.contains(.inhaling))
    }
}

// Round 4, item 4: the lungs follow the real breath signal, never the timer. They widen while an
// inhale is seen, narrow on an exhale, and hold still otherwise and while paused.
struct LungsMotionTests {

    @Test func widenWhileBreathingInUpToFullSize() {
        var scale = LungsMotion.restScale
        scale = LungsMotion.next(scale, breath: .inhaling, elapsed: 0.5, paused: false)
        #expect(scale > LungsMotion.restScale)
        for _ in 0..<100 { scale = LungsMotion.next(scale, breath: .inhaling, elapsed: 0.05, paused: false) }
        #expect(scale == LungsMotion.fullScale)
    }

    @Test func narrowWhileBreathingOutDownToRest() {
        var scale = LungsMotion.fullScale
        scale = LungsMotion.next(scale, breath: .exhaling, elapsed: 0.5, paused: false)
        #expect(scale < LungsMotion.fullScale)
        for _ in 0..<100 { scale = LungsMotion.next(scale, breath: .exhaling, elapsed: 0.05, paused: false) }
        #expect(scale == LungsMotion.restScale)
    }

    @Test func holdStillWhenNoBreathIsSeen() {
        #expect(LungsMotion.next(1.2, breath: .still, elapsed: 1, paused: false) == 1.2)
        #expect(LungsMotion.next(1.2, breath: .unknown, elapsed: 1, paused: false) == 1.2)
    }

    @Test func holdStillWhilePaused() {
        #expect(LungsMotion.next(1.2, breath: .inhaling, elapsed: 1, paused: true) == 1.2)
        #expect(LungsMotion.next(1.2, breath: .exhaling, elapsed: 1, paused: true) == 1.2)
    }
}

// Round 4, item 6: never skip the breathing. A phase with no breath detected pauses; nothing but Done
// or a spoken "no" ends the session; the same cycle continues after a pause; the streak counts only
// when breathing was detected for every cycle.
struct BreathingCoachTests {

    private func breatheThroughOneCycle(_ coach: inout BreathingCoach) -> BreathingCoach.Action {
        _ = coach.phaseEnded(.inhale, breathDetected: true)
        _ = coach.phaseEnded(.holdAfterInhale, breathDetected: false)
        _ = coach.phaseEnded(.exhale, breathDetected: true)
        return coach.phaseEnded(.holdAfterExhale, breathDetected: false)
    }

    @Test func fourDetectedCyclesFinishAndCountForTheStreak() {
        var coach = BreathingCoach()
        #expect(coach.phaseEnded(.inhale, breathDetected: true) == .nextPhase)
        #expect(coach.phaseEnded(.holdAfterInhale, breathDetected: false) == .nextPhase)   // holds aren't judged
        #expect(coach.phaseEnded(.exhale, breathDetected: true) == .nextPhase)
        #expect(coach.phaseEnded(.holdAfterExhale, breathDetected: false) == .nextCycle)
        #expect(breatheThroughOneCycle(&coach) == .nextCycle)
        #expect(breatheThroughOneCycle(&coach) == .nextCycle)
        #expect(coach.countsForStreak == false)
        #expect(breatheThroughOneCycle(&coach) == .finished)
        #expect(coach.countsForStreak)
    }

    @Test func noBreathPausesAndNeverEnds() {
        var coach = BreathingCoach()
        for _ in 0..<20 { #expect(coach.phaseEnded(.inhale, breathDetected: false) == .pause) }
        #expect(coach.phaseEnded(.exhale, breathDetected: false) == .pause)
        #expect(coach.completedCycles == 0)
        #expect(coach.pauses == 21)
        #expect(coach.countsForStreak == false)
    }

    @Test func afterAPauseTheSameCycleContinues() {
        var coach = BreathingCoach()
        #expect(breatheThroughOneCycle(&coach) == .nextCycle)
        #expect(coach.phaseEnded(.inhale, breathDetected: true) == .nextPhase)
        #expect(coach.phaseEnded(.holdAfterInhale, breathDetected: false) == .nextPhase)
        #expect(coach.phaseEnded(.exhale, breathDetected: false) == .pause)
        #expect(coach.completedCycles == 1)                       // the paused cycle isn't counted
        #expect(breatheThroughOneCycle(&coach) == .nextCycle)
        #expect(coach.completedCycles == 2)
    }

    // The whole chain on synthetic motion: calibrate, then breathing → stopped → breathing → stopped →
    // breathing. Each stop pauses; each return to breathing resumes the same cycle; then it finishes.
    @Test func pauseAndResumeThroughTheRealDetector() throws {
        var tracker = BreathTracker(profile: try #require(SyntheticChest.profile))
        var coach = BreathingCoach()
        var t = 0.0
        var level = 0.0
        var actions: [BreathingCoach.Action] = []

        func phase(_ p: BreathingPhase, to target: Double) -> BreathingCoach.Action {
            var watch = BreathPhaseWatch(phase: p, current: tracker.breath)
            let samples = target == level ? SyntheticChest.still(start: t, at: level)
                                          : SyntheticChest.ramp(start: t, from: level, to: target)
            for s in samples {
                tracker.add(s, learnInhale: p == .inhale)
                watch.observe(tracker.breath)
            }
            t += 3; level = target
            return coach.phaseEnded(p, breathDetected: watch.detected)
        }
        func breathingCycle() -> BreathingCoach.Action {
            _ = phase(.inhale, to: 1); _ = phase(.holdAfterInhale, to: 1)
            _ = phase(.exhale, to: 0); return phase(.holdAfterExhale, to: 0)
        }
        func stoppedInhale() -> BreathingCoach.Action { phase(.inhale, to: 0) }

        actions.append(breathingCycle())
        actions.append(stoppedInhale())
        actions.append(breathingCycle())
        actions.append(stoppedInhale())
        actions.append(breathingCycle())
        actions.append(breathingCycle())
        #expect(actions == [.nextCycle, .pause, .nextCycle, .pause, .nextCycle, .finished])
        #expect(coach.pauses == 2)
        #expect(coach.countsForStreak)
    }
}

// A phase is "detected" once the matching breath is seen at any moment during it, including a breath
// already under way when the phase starts (a resume after a pause starts on the user's own inhale).
struct BreathPhaseWatchTests {

    @Test func inhaleSeenDuringThePhase() {
        var watch = BreathPhaseWatch(phase: .inhale, current: .still)
        #expect(watch.detected == false)
        watch.observe(.exhaling)
        #expect(watch.detected == false)
        watch.observe(.inhaling)
        watch.observe(.still)
        #expect(watch.detected)
    }

    @Test func aBreathAlreadyUnderWayCounts() {
        #expect(BreathPhaseWatch(phase: .inhale, current: .inhaling).detected)
        #expect(BreathPhaseWatch(phase: .exhale, current: .inhaling).detected == false)
    }

    @Test func holdsNeedNothing() {
        #expect(BreathPhaseWatch(phase: .holdAfterInhale, current: .still).detected == false)
    }
}

// Round 4, item 8: Sign in with Apple. Only the Apple user identifier and the first name are kept, on
// the device, under their own keys. Apple sends the name only the first time, so a later sign-in
// without one keeps the name already saved.
struct AppleAccountTests {

    private func withDefaults(_ body: (UserDefaults, String) throws -> Void) throws {
        let suite = "apple-account-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults, suite)
    }

    @Test func savesOnlyTheUserIDAndFirstNameUnderNewKeys() throws {
        try withDefaults { defaults, suite in
            AppleAccount.save(userID: "001234.abc", givenName: "Sam", to: defaults)
            #expect(AppleAccount.userID(in: defaults) == "001234.abc")
            #expect(AppleAccount.givenName(in: defaults) == "Sam")
            let written = defaults.persistentDomain(forName: suite)?.keys.sorted() ?? []
            #expect(written == ["appleSignInGivenName", "appleSignInUserID"])
        }
    }

    @Test func aLaterSignInWithoutANameKeepsTheSavedName() throws {
        try withDefaults { defaults, _ in
            AppleAccount.save(userID: "001234.abc", givenName: "Sam", to: defaults)
            AppleAccount.save(userID: "001234.abc", givenName: nil, to: defaults)
            #expect(AppleAccount.givenName(in: defaults) == "Sam")
        }
    }

    @Test func aDifferentAppleIDDoesNotInheritTheOldName() throws {
        try withDefaults { defaults, _ in
            AppleAccount.save(userID: "001234.abc", givenName: "Sam", to: defaults)
            AppleAccount.save(userID: "009999.xyz", givenName: nil, to: defaults)
            #expect(AppleAccount.userID(in: defaults) == "009999.xyz")
            #expect(AppleAccount.givenName(in: defaults) == nil)
        }
    }

    @Test func blankNamesAreNotNames() throws {
        try withDefaults { defaults, _ in
            AppleAccount.save(userID: "001234.abc", givenName: "   ", to: defaults)
            #expect(AppleAccount.givenName(in: defaults) == nil)
            #expect(BreathingCueScript.opening(name: AppleAccount.givenName(in: defaults)).hasPrefix("Hi there,"))
        }
    }

    @Test func signOutRemovesOnlyItsOwnKeys() throws {
        try withDefaults { defaults, suite in
            defaults.set(5, forKey: "breathingStreakCurrent")
            AppleAccount.save(userID: "001234.abc", givenName: "Sam", to: defaults)
            AppleAccount.signOut(from: defaults)
            #expect(AppleAccount.userID(in: defaults) == nil)
            #expect(AppleAccount.givenName(in: defaults) == nil)
            #expect(defaults.persistentDomain(forName: suite)?.keys.sorted() == ["breathingStreakCurrent"])
        }
    }
}

// Round 5, item 1 (Joel's report): "I am not good want to kill myself" was answered with "Thank you for
// sharing." Every spoken answer in Breathing now goes through the chat's SafetyChecker first, in memory
// only, and a match shows the chat's own crisis response with the region's help lines.
@MainActor
struct BreathingSafetyTests {

    @Test(arguments: [
        "I am not good want to kill myself",
        "I\u{2019}m not good, want to KILL MYSELF!!",
        "i am not good want to kill my self",
    ])
    func joelsAnswerGetsTheChatsCrisisResponse(_ said: String) throws {
        let response = try #require(BreathingSafety.crisisResponse(for: said, region: "US"))
        #expect(response == SafetyChecker().crisisResponse(forRegion: "US"))
        #expect(response.contains("988"))
    }

    // Help lines follow the Region setting, as in the chat: 988 only for the US, Canada and US territories.
    @Test func helpLinesFollowTheRegion() throws {
        let ph = try #require(BreathingSafety.crisisResponse(for: "I want to kill myself", region: "PH"))
        #expect(ph.contains("1553"))
        #expect(!ph.contains("988"))
        let ca = try #require(BreathingSafety.crisisResponse(for: "I want to kill myself", region: "CA"))
        #expect(ca.contains("988"))
    }

    @Test(arguments: ["yes", "no", "I'm good, ready to breathe", "a bit tired but okay", "", "this day is killing me"])
    func everydayAnswersAreNotACrisis(_ said: String) {
        #expect(BreathingSafety.crisisResponse(for: said, region: "US") == nil)
    }
}

// Round 5, item 6: Breathing opens on Alex's intro screen and flips to the lungs once you say yes;
// it never flips back. A "no" or a crisis stays on the intro screen.
struct BreathingFaceTests {

    @Test func flipsToTheLungsWhenTheExerciseBegins() {
        #expect(BreathingFace.first == .intro)
        #expect(BreathingFace.after(.intro, step: .askFeeling) == .intro)
        #expect(BreathingFace.after(.intro, step: .askReady(attempt: 1, thankFirst: true)) == .intro)
        #expect(BreathingFace.after(.intro, step: .begin) == .lungs)
    }

    @Test func noOrACrisisStaysOnTheIntro() {
        #expect(BreathingFace.after(.intro, step: .endGently) == .intro)
        #expect(BreathingFace.after(.intro, step: .crisis) == .intro)
    }

    @Test func neverFlipsBack() {
        #expect(BreathingFace.after(.lungs, step: .askAnotherRound(attempt: 1)) == .lungs)
        #expect(BreathingFace.after(.lungs, step: .goodbye) == .lungs)
        #expect(BreathingFace.after(.lungs, step: .crisis) == .lungs)
    }
}

// Round 5, item 2: the sign-in failure names Apple's error code, so the cause can be told apart
// (1000 = the app was built without the Sign in with Apple entitlement, or no Apple ID on the device).
struct AppleSignInMessageTests {

    @Test func failureMessageNamesTheErrorCode() {
        #expect(AppleSignIn.failureMessage(code: 1000)
                == "Sign in with Apple isn't available right now (error 1000). Please try again later.")
    }
}

#if DEBUG
// Simulator-only stand-ins (compiled out of Release): spoken answers in order, and a fake chest that
// breathes along (or stays still) for each guided inhale, because the simulator has no microphone
// input or motion sensor.
struct BreathingDebugTests {

    @Test func readsStandInAnswersInOrder() {
        #expect(BreathingDebug.answers(from: "fine, yes,no") == ["fine", "yes", "no"])
        #expect(BreathingDebug.answers(from: nil) == [])
    }

    @Test func readsTheFakeChestPlan() {
        #expect(BreathingDebug.inhalePlan(from: "follow,still,follow") == [true, false, true])
        #expect(BreathingDebug.inhalePlan(from: nil) == [])
    }
}
#endif

// The lungs widen to 1.5x their frame; the layout reserves that room so they never cover the "Box
// Breathing" heading. On short screens (iPhone SE) they shrink so everything fits.
struct BreathingLayoutTests {

    @Test func reservesRoomForTheFullSizeVisual() {
        #expect(BreathingLayout.maxScale == 1.5)
        #expect(BreathingLayout.maxScale == LungsMotion.fullScale)
        #expect(BreathingLayout.overflow(for: 220) == 55)
    }

    @Test func tallScreensKeepTheOriginal220ptSize() {
        #expect(BreathingLayout.circleSize(forHeight: 760) == 220)
        #expect(BreathingLayout.circleSize(forHeight: 2000) == 220)
    }

    @Test func shortScreensShrinkSoEverythingFits() {
        let seHeight: CGFloat = 529
        let size = BreathingLayout.circleSize(forHeight: seHeight)
        #expect(size < 220)
        #expect(size * BreathingLayout.maxScale + BreathingLayout.otherContentHeight <= seHeight)
    }

    @Test func neverCollapses() {
        #expect(BreathingLayout.circleSize(forHeight: 100) == BreathingLayout.minimumCircleSize)
    }
}
