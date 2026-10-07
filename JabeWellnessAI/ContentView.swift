//+-------------------------------------+//
// Jabe Wellness AI
// Creator: Jabe
// AI Emotional Wellness Chatbot
// ENHANCED VERSION v3 — Premium Features
//+-------------------------------------+//

import SwiftUI
import Foundation
import Combine
import UserNotifications
import Charts
import Speech
import AVFoundation
import StoreKit
import Security

//*======================================================================*//
// MARK: - Secrets
//*======================================================================*//

enum Secrets {

    // The app holds no Groq key: the Worker does. Do not add one back here.

    // Simulator-only: the simulator cannot attest, so DEBUG simulator builds present this to the
    // Worker instead. Compiled out of every device build so it cannot ship in the binary.
    #if targetEnvironment(simulator)
    static let devBypassSecret = SecretsStore.devBypassSecret
    #endif
}

//*======================================================================*//
// MARK: - MoodType
//*======================================================================*//

enum MoodType: String, Codable {

    case happy   = "Happy"
    case sad     = "Sad"
    case anxious = "Anxious"
    case angry   = "Angry"
    case neutral = "Neutral"

    var emoji: String {
        switch self {
        case .happy:   return "😊"
        case .sad:     return "😢"
        case .anxious: return "😰"
        case .angry:   return "😤"
        case .neutral: return "😐"
        }
    }

    var color: Color {
        switch self {
        case .happy:   return Color(red: 1.00, green: 0.75, blue: 0.00)
        case .sad:     return Color(red: 0.35, green: 0.55, blue: 0.95)
        case .anxious: return Color(red: 0.95, green: 0.55, blue: 0.15)
        case .angry:   return Color(red: 0.90, green: 0.25, blue: 0.25)
        case .neutral: return Color(red: 0.40, green: 0.65, blue: 0.85)
        }
    }

    // 1–5 scale used by the mood chart
    var score: Int {
        switch self {
        case .happy:   return 5
        case .neutral: return 3
        case .anxious: return 2
        case .sad:     return 2
        case .angry:   return 1
        }
    }

    var bubbleGradient: LinearGradient {
        switch self {
        case .happy:
            return LinearGradient(
                colors: [Color(red: 1.00, green: 0.82, blue: 0.25), Color(red: 0.95, green: 0.55, blue: 0.10)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        case .sad:
            return LinearGradient(
                colors: [Color(red: 0.45, green: 0.62, blue: 1.00), Color(red: 0.25, green: 0.38, blue: 0.88)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        case .anxious:
            return LinearGradient(
                colors: [Color(red: 1.00, green: 0.68, blue: 0.28), Color(red: 0.90, green: 0.42, blue: 0.10)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        case .angry:
            return LinearGradient(
                colors: [Color(red: 1.00, green: 0.38, blue: 0.32), Color(red: 0.80, green: 0.12, blue: 0.12)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        case .neutral:
            return LinearGradient(
                colors: [Color(red: 0.52, green: 0.42, blue: 0.95), Color(red: 0.32, green: 0.22, blue: 0.85)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
    }
}

//*======================================================================*//
// MARK: - ChatMessage
//*======================================================================*//

struct ChatMessage: Identifiable, Codable {

    let id:        UUID
    let content:   String
    let isUser:    Bool
    let mood:      MoodType?
    let timestamp: Date

    init(content: String, isUser: Bool, mood: MoodType?, timestamp: Date) {
        self.id        = UUID()
        self.content   = content
        self.isUser    = isUser
        self.mood      = mood
        self.timestamp = timestamp
    }
}

//*======================================================================*//
// MARK: - Sentiment Analyzer
//*======================================================================*//

final class SentimentAnalyzer {

    private let positiveWords: Set<String> = [
        "happy", "great", "good", "amazing", "wonderful", "fantastic",
        "excited", "joyful", "love", "grateful", "thankful", "blessed",
        "hopeful", "optimistic", "peaceful", "content", "proud", "cheerful",
        "delighted", "glad", "relieved", "calm", "motivated", "energized",
        "inspired", "confident", "strong", "better", "fine", "okay"
    ]

    private let negativeWords: Set<String> = [
        "sad", "depressed", "angry", "tired", "hopeless", "worthless",
        "lonely", "afraid", "stressed", "overwhelmed", "hurt", "pain",
        "lost", "empty", "broken", "anxious", "worried", "scared",
        "frustrated", "upset", "miserable", "exhausted", "numb", "stuck",
        "trapped", "useless", "failure", "helpless", "drained", "awful"
    ]

    func analyze(text: String) -> Double {

        let words = text.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }

        var score = 0.0

        for word in words {
            if positiveWords.contains(word) { score += 1.0 }
            if negativeWords.contains(word) { score -= 1.0 }
        }

        let normalized = score / max(1.0, Double(words.count) * 0.3)

        return max(-1.0, min(1.0, normalized))
    }
}

//*======================================================================*//
// MARK: - Emotion Detector
//*======================================================================*//

final class EmotionDetector {

    private let emotionMap: [(MoodType, [String])] = [

        (.happy, [
            "happy", "excited", "great", "amazing", "joy", "joyful", "love",
            "wonderful", "fantastic", "glad", "thrilled", "elated", "cheerful",
            "delighted", "blessed", "grateful", "hopeful", "proud", "content"
        ]),

        (.sad, [
            "sad", "cry", "crying", "lonely", "depressed", "hopeless", "empty",
            "broken", "miss", "grief", "sorrow", "tears", "miserable",
            "heartbroken", "lost", "tired", "exhausted", "drained", "numb"
        ]),

        (.anxious, [
            "anxious", "worried", "nervous", "scared", "afraid",
            "stressed", "panic", "overwhelmed", "dread", "uneasy", "tense",
            "restless", "fear", "overthinking", "overthink", "racing"
        ]),

        (.angry, [
            "angry", "mad", "furious", "frustrated", "rage", "annoyed",
            "irritated", "hate", "livid", "outraged", "bitter", "upset",
            "resentful", "fed up", "done"
        ])
    ]

    func detectEmotion(from text: String) -> MoodType {

        let negations: Set<String> = ["not", "no", "never", "don't", "dont", "without", "isn't", "isnt", "am not"]
        let lowercase = text.lowercased()
        let words = lowercase
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }

        var scores: [MoodType: Int] = [:]

        for (mood, keywords) in emotionMap {
            var score = 0
            for keyword in keywords {
                if keyword.contains(" ") {
                    if lowercase.contains(keyword) { score += 1 }
                } else {
                    for (i, word) in words.enumerated() {
                        if word == keyword || word.hasPrefix(keyword) {
                            let window = words[max(0, i - 2) ..< i]
                            if !window.contains(where: { negations.contains($0) }) {
                                score += 1
                            }
                        }
                    }
                }
            }
            scores[mood] = score
        }

        guard let best = scores.max(by: { $0.value < $1.value }),
              best.value > 0
        else {
            return .neutral
        }

        return best.key
    }
}

//*======================================================================*//
// MARK: - Safety Checker
//*======================================================================*//

final class SafetyChecker {

    private let riskyKeywords = [
        "suicide", "kill myself", "self harm", "self-harm",
        "end my life", "want to die", "don't want to live",
        "hurt myself", "take my life", "no reason to live",
        "can't go on", "ending it", "end it all"
    ]

    func containsRisk(_ text: String) -> Bool {
        riskyKeywords.contains { text.localizedCaseInsensitiveContains($0) }
    }

    var crisisResponse: String {
        """
        You are not alone, and what you're feeling matters deeply. 💙

        Please reach out for support right now:

        📞 988 Suicide & Crisis Lifeline
        Call or text 988 — available 24/7, free & confidential

        💬 Crisis Text Line
        Text HOME to 741741

        You deserve care and support. I'm here with you.
        """
    }
}

//*======================================================================*//
// MARK: - Persistent Data Models
//*======================================================================*//

struct ChatSession: Identifiable, Codable {

    let id:           UUID
    let date:         Date
    let messages:     [ChatMessage]
    let dominantMood: MoodType

    init(messages: [ChatMessage], date: Date = Date()) {
        self.id           = UUID()
        self.date         = date
        self.messages     = messages
        self.dominantMood = Self.computeDominantMood(messages)
    }

    // The mood that occurs most often among the session's tagged messages — not just
    // whichever mood the first tagged message happened to have. Ties go to whichever
    // mood occurred first, so behavior stays stable for short conversations.
    private static func computeDominantMood(_ messages: [ChatMessage]) -> MoodType {
        let moods = messages.compactMap { $0.mood }
        guard !moods.isEmpty else { return .neutral }

        var counts: [MoodType: Int] = [:]
        for mood in moods { counts[mood, default: 0] += 1 }

        let maxCount = counts.values.max() ?? 0
        return moods.first { counts[$0] == maxCount } ?? .neutral
    }
}

struct JournalEntry: Identifiable, Codable {

    let id:         UUID
    let date:       Date
    let mood:       MoodType
    let reflection: String

    init(mood: MoodType, reflection: String, date: Date = Date()) {
        self.id         = UUID()
        self.date       = date
        self.mood       = mood
        self.reflection = reflection
    }
}

//*======================================================================*//
// MARK: - Storage Manager
//*======================================================================*//

final class StorageManager: ObservableObject {

    static let shared = StorageManager()

    @Published var sessions:       [ChatSession]  = []
    @Published var journalEntries: [JournalEntry] = []

    private let sessionsKey = "mm_sessions"
    private let journalKey  = "mm_journal"

    init() { loadAll() }

    func saveSession(_ session: ChatSession) {
        sessions.insert(session, at: 0)
        persist(sessions, key: sessionsKey)
    }

    func deleteSession(_ session: ChatSession) {
        sessions.removeAll { $0.id == session.id }
        persist(sessions, key: sessionsKey)
    }

    func clearAllSessions() {
        sessions = []
        persist(sessions, key: sessionsKey)
    }

    func saveJournalEntry(_ entry: JournalEntry) {
        journalEntries.insert(entry, at: 0)
        persist(journalEntries, key: journalKey)
    }

    func deleteJournalEntry(_ entry: JournalEntry) {
        journalEntries.removeAll { $0.id == entry.id }
        persist(journalEntries, key: journalKey)
    }

    private func persist<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func loadAll() {
        sessions       = load([ChatSession].self,  key: sessionsKey) ?? []
        journalEntries = load([JournalEntry].self, key: journalKey)  ?? []
    }

    private func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

//*======================================================================*//
// MARK: - Streak Manager
//*======================================================================*//

final class StreakManager: ObservableObject {

    static let shared = StreakManager()

    @Published private(set) var currentStreak: Int = 0
    @Published private(set) var longestStreak: Int = 0

    private let fmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    init() {
        currentStreak = UserDefaults.standard.integer(forKey: "mm_currentStreak")
        longestStreak = UserDefaults.standard.integer(forKey: "mm_longestStreak")
    }

    func recordCheckIn() {
        let today     = fmt.string(from: Date())
        let stored    = UserDefaults.standard.string(forKey: "mm_lastCheckIn") ?? ""
        guard today != stored else { return }
        let yesterday = fmt.string(
            from: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        )
        currentStreak = (stored == yesterday) ? currentStreak + 1 : 1
        longestStreak = max(longestStreak, currentStreak)
        UserDefaults.standard.set(currentStreak, forKey: "mm_currentStreak")
        UserDefaults.standard.set(longestStreak, forKey: "mm_longestStreak")
        UserDefaults.standard.set(today,         forKey: "mm_lastCheckIn")
    }

    var isCheckedInToday: Bool {
        fmt.string(from: Date()) == (UserDefaults.standard.string(forKey: "mm_lastCheckIn") ?? "")
    }
}

//*======================================================================*//
// MARK: - Trial Anchor Store
//*======================================================================*//

// The date the free trial started, kept in the Keychain rather than UserDefaults.
// Keychain items survive deleting the app; UserDefaults does not, so a UserDefaults
// anchor handed out a fresh 7-day trial on every reinstall.
enum TrialAnchorStore {

    private static let service = "com.jabe.wellnessai"
    private static let account = "trialAnchor"

    private static var baseQuery: [String: Any] {
        [
            kSecClass       as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    static func load() -> Date? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data   = item as? Data,
              let string = String(data: data, encoding: .utf8)
        else { return nil }

        return ISO8601DateFormatter().date(from: string)
    }

    static func save(_ date: Date) {
        guard let data = ISO8601DateFormatter().string(from: date).data(using: .utf8) else { return }

        SecItemDelete(baseQuery as CFDictionary)

        var attributes = baseQuery
        attributes[kSecValueData     as String] = data
        // Needs to be readable on a background launch, but never syncs to iCloud
        // or migrates to a new device — the trial is per-install, not per-account.
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
    }
}

//*======================================================================*//
// MARK: - Premium Manager (StoreKit 2)
//*======================================================================*//

// Where an entitlement came from, not merely whether one exists. isPremium is lossy —
// true for a trial and true for a purchase alike — so a purchase made DURING a trial
// moves nothing observable and the paywall has nothing to react to.
enum EntitlementState: Equatable {
    case locked
    case trial(daysRemaining: Int)
    case purchased
}

@MainActor
final class PremiumManager: ObservableObject {

    static let shared = PremiumManager()

    // Whether the user is entitled AT ALL. Correct as a gate, but useless as a change
    // trigger: it is already true during the trial and stays true after a purchase, so
    // .onChange never fires on it. Views that need to react to a purchase must watch
    // entitlementState instead.
    @Published private(set) var isPremium: Bool    = false
    @Published private(set) var entitlementState: EntitlementState = .locked
    @Published private(set) var product:   Product?
    @Published var showPaywall: Bool = false
    @Published var purchaseError: String?

    // Replace with your App Store Connect product ID before submitting
    private let productID = "com.jabe.premium"
    private let trialDays = 7

    // Offline cache of the last entitlement check, never the grant itself.
    // Transaction.currentEntitlements is the source of truth: refreshEntitlements()
    // overwrites this on launch, on foreground, and after any purchase or restore,
    // so hand-editing the key in the app container buys at most one session.
    private var isPurchased: Bool {
        get { UserDefaults.standard.bool(forKey: "mm_isPurchased") }
        set { UserDefaults.standard.set(newValue, forKey: "mm_isPurchased"); refreshStatus() }
    }

    private var trialStartDate: Date? {
        if let anchored = TrialAnchorStore.load() { return anchored }

        // Adopt the old UserDefaults anchor if one is there, so an install that
        // started its trial before this moved to the Keychain keeps the days it used.
        if let legacy = UserDefaults.standard.string(forKey: "mm_firstLaunch"),
           let date   = ISO8601DateFormatter().date(from: legacy) {
            TrialAnchorStore.save(date)
            return date
        }

        return nil
    }

    init() {
        if trialStartDate == nil {
            let now = Date()
            TrialAnchorStore.save(now)
            UserDefaults.standard.set(ISO8601DateFormatter().string(from: now), forKey: "mm_firstLaunch")
        }

        refreshStatus()
        Task { await loadProduct() }
        Task { await refreshEntitlements() }

        // A purchase made on another device, or a refund, arrives here rather than
        // through the paywall — pick it up and re-derive status either way.
        Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result { await transaction.finish() }
                await self?.refreshEntitlements()
            }
        }

        Task { [weak self] in
            // notifications(named:) hands back an AsyncSequence synchronously — it is not
            // itself async, so awaiting it did nothing but raise a warning. The suspension
            // that matters is the `for await` below.
            let foreground = NotificationCenter.default.notifications(
                named: UIApplication.willEnterForegroundNotification
            )
            for await _ in foreground { await self?.refreshEntitlements() }
        }
    }

    private func refreshStatus() {
        #if DEBUG
        // UI-test hook. The locked branch is otherwise unreachable from a clean install:
        // a fresh install starts a 7-day trial, so the app is entitled and nothing is
        // gated. Compiled out of Release, so it cannot reach an archive or the store.
        if ProcessInfo.processInfo.arguments.contains("-jabeForceLocked") {
            isPremium = false
            entitlementState = .locked
            return
        }
        #endif
        isPremium = isPurchased || isInTrial
        entitlementState = Self.entitlementState(isPurchased: isPurchased,
                                                 isInTrial: isInTrial,
                                                 trialDaysRemaining: trialDaysRemaining)
    }

    // Authoritative entitlement check. Sets isPurchased false as readily as true, so a
    // refunded or revoked purchase actually downgrades instead of staying unlocked forever.
    func refreshEntitlements() async {
        var entitled = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == productID,
               transaction.revocationDate == nil {
                entitled = true
            }
        }
        isPurchased = entitled
    }

    var isInTrial: Bool {
        guard !isPurchased else { return false }
        guard let start = trialStartDate else { return true }
        return Self.isInTrial(start: start, now: Date(), trialDays: trialDays)
    }

    var trialDaysRemaining: Int {
        guard !isPurchased else { return 0 }
        guard let start = trialStartDate else { return trialDays }
        return Self.trialDaysRemaining(start: start, now: Date(), trialDays: trialDays)
    }

    // Pure, so the trial window can be tested without StoreKit, the Keychain, or the device
    // clock. nonisolated because the rest of the class is @MainActor and this needs neither.
    nonisolated static func trialDaysRemaining(start: Date, now: Date, trialDays: Int) -> Int {
        let elapsed = Calendar.current.dateComponents([.day], from: start, to: now).day ?? 0
        return max(0, trialDays - max(0, elapsed))
    }

    nonisolated static func isInTrial(start: Date, now: Date, trialDays: Int) -> Bool {
        trialDaysRemaining(start: start, now: now, trialDays: trialDays) > 0
    }

    // The single question every gated feature asks. Reads entitlementState rather than
    // isPremium so there is one tested source of truth: a trial unlocks, a purchase
    // unlocks, an expired trial does not.
    nonisolated static func isFeatureUnlocked(_ state: EntitlementState) -> Bool {
        switch state {
        case .locked:               return false
        case .trial, .purchased:    return true
        }
    }

    nonisolated static func entitlementState(isPurchased: Bool,
                                             isInTrial: Bool,
                                             trialDaysRemaining: Int) -> EntitlementState {
        if isPurchased { return .purchased }
        if isInTrial   { return .trial(daysRemaining: trialDaysRemaining) }
        return .locked
    }

    func purchase() async {
        if product == nil {
            purchaseError = nil
            await loadProduct()
        }
        guard let product else {
            if purchaseError == nil {
                purchaseError = "Store isn't ready yet — please try again in a moment."
            }
            return
        }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    isPurchased = true
                    await transaction.finish()
                case .unverified:
                    purchaseError = "Your purchase couldn't be verified. Please try again."
                }
            case .userCancelled:
                break
            case .pending:
                purchaseError = "Your purchase is pending approval."
            @unknown default:
                break
            }
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    func restorePurchases() async {
        do {
            try await AppStore.sync()
        } catch {
            purchaseError = error.localizedDescription
        }
        await refreshEntitlements()
    }

    private func loadProduct() async {
        do {
            let products = try await Product.products(for: [productID])
            product = products.first
            if product == nil {
                purchaseError = "Product '\(productID)' wasn't found. Check that a StoreKit Configuration file is selected in Xcode's scheme (Edit Scheme → Run → Options), or that this product exists in App Store Connect."
            }
        } catch {
            purchaseError = "Couldn't load the product from the store: \(error.localizedDescription)"
        }
    }
}

//*======================================================================*//
// MARK: - Voice Input Manager
//*======================================================================*//

final class VoiceInputManager: ObservableObject {

    @Published var isRecording:      Bool   = false
    @Published var transcript:       String = ""
    @Published var permissionDenied: Bool   = false

    private let recognizer  = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var request:    SFSpeechAudioBufferRecognitionRequest?
    private var task:       SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    // Prevents late-arriving recognition callbacks from overwriting text after stop
    private var stopped = false

    func startRecording() {
        stopped = false
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                guard status == .authorized else { self?.permissionDenied = true; return }
                AVAudioApplication.requestRecordPermission { granted in
                    DispatchQueue.main.async {
                        if granted { self?.beginSession() } else { self?.permissionDenied = true }
                    }
                }
            }
        }
    }

    private func beginSession() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("Audio session setup failed:", error)
            DispatchQueue.main.async { self.permissionDenied = true }
            return
        }
        #endif

        request = SFSpeechAudioBufferRecognitionRequest()
        guard let request, let recognizer, recognizer.isAvailable else { return }
        request.shouldReportPartialResults = true

        // Keep voice audio on the device. Left unset this defaults to false, which lets
        // iOS transcribe via Apple's servers — the privacy policy says transcription is
        // on-device, so ask for it explicitly wherever the device can do it.
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition

        let node = audioEngine.inputNode
        node.installTap(onBus: 0, bufferSize: 1024, format: node.outputFormat(forBus: 0)) { [weak self] buf, _ in
            self?.request?.append(buf)
        }
        audioEngine.prepare()

        do {
            try audioEngine.start()
        } catch {
            print("Audio engine failed to start:", error)
            audioEngine.inputNode.removeTap(onBus: 0)
            return
        }

        isRecording = true
        transcript  = ""

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self, !self.stopped else { return }
            if let result {
                DispatchQueue.main.async {
                    guard !self.stopped else { return }
                    self.transcript = result.bestTranscription.formattedString
                }
            }
            if error != nil || result?.isFinal == true { self.stopRecording() }
        }
    }

    func stopRecording() {
        stopped = true
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task    = nil
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
        DispatchQueue.main.async { self.isRecording = false }
    }
}

//*======================================================================*//
// MARK: - Groq Response Model
//*======================================================================*//

struct GroqResponse: Decodable {

    let choices: [Choice]

    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let content: String
    }
}

//*======================================================================*//
// MARK: - AI Service (Groq)
//*======================================================================*//

final class AIService {

    /// The single source of truth for which model is requested. Both request bodies and the
    /// Settings → About row read these, so the label cannot advertise a model the app is not
    /// actually calling — it did exactly that when llama-3.3-70b-versatile was decommissioned.
    static let model            = "openai/gpt-oss-120b"
    static let modelDisplayName = "GPT OSS 120B via Groq"

    /// The relay that holds the Groq key. Chat and Weekly Insight go here; the app no longer sends
    /// anything to Groq.
    static let workerBaseURL = URL(string: "https://jabe-proxy.jabelarde1994.workers.dev") ?? URL(fileURLWithPath: "/")

    /// One manager for the whole app: chat and Weekly Insight each own an AIService, and a shared
    /// manager is what coalesces their concurrent token refreshes into one App Attest round trip.
    @MainActor private static let attestation = AttestationManager(
        attester: SystemDeviceAttester(),
        transport: WorkerTransport(baseURL: AIService.workerBaseURL)
    )

    private let systemPrompt = """
    You are Jabe, a warm and emotionally supportive AI wellness companion.

    Personality:
    - Warm, calm, and deeply caring
    - Non-judgmental and patient
    - Conversational and human — never robotic or clinical
    - Emotionally intelligent and perceptive

    Rules:
    - Never claim to be a licensed therapist or provide clinical diagnoses
    - Keep responses concise (2-4 sentences) unless the user clearly needs more
    - Always acknowledge and validate the user's feelings before offering perspective
    - End with one thoughtful follow-up question to deepen the conversation
    - Use gentle, supportive, and empathetic language throughout
    - Remember conversation context and reference it when helpful
    - Write in plain natural text — no bullet points, headers, or markdown
    """

    // Failure copy. Every string below is appended to the chat transcript as if Jabe said it, so
    // none of it may name an API key, a provider, or a screen the user has no access to. Held as
    // constants and mapped by the pure functions underneath purely so it is testable — 1.0.1
    // shipped "check your Groq API key in the Secrets section" to end users, and nothing could
    // catch that while it sat inline in an async network call.
    static let serviceUnavailableMessage =
        "I can't reach the AI service right now. Let's try again in a moment. 🌿"

    static let verificationFailedMessage =
        "I couldn't verify this device just now. Please try again in a moment. 🌿"

    static let offlineMessage =
        "It looks like you're offline. Please check your connection and we'll pick this up. 🌿"

    /// Maps a thrown transport or decoding failure onto the sentence the user actually sees.
    ///
    /// `URLSession` throws when the device is offline or the request times out, and `JSONDecoder`
    /// throws whenever the upstream returns 200 with a body shape that no longer matches. Both
    /// land in `JournalViewModel`'s catch and are appended as Jabe speaking, so a raw
    /// `DecodingError` or `URLError` description would otherwise reach a user in a chat bubble.
    /// Only the offline case is actionable, so only that one gets its own advice.
    static func userFacingError(for error: Error) -> String {
        if error is AttestationError { return verificationFailedMessage }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                return offlineMessage
            default:
                return serviceUnavailableMessage
            }
        }
        return serviceUnavailableMessage
    }

    /// Maps an HTTP failure onto the sentence the user actually sees.
    ///
    /// Rate limiting is the only status a user can act on, so it is the only one with bespoke
    /// copy. Everything else — auth, a retired model id (Groq answers 404 for that, which is the
    /// 2026-08-16 failure), and 5xx outages — is indistinguishable from the user's side and must
    /// not surface a status code or send them chasing their own network. The status is still
    /// printed in DEBUG above, so nothing is lost for support.
    static func userFacingError(for statusCode: Int) -> String {
        switch statusCode {
        case 401, 403: return verificationFailedMessage
        case 429: return "I need a moment to breathe. 🌿 You've sent a lot of messages quickly — please wait about a minute and try again."
        default:  return serviceUnavailableMessage
        }
    }

    func send(
        history: [ChatMessage],
        mood: MoodType
    ) async throws -> String {

        let url = Self.workerBaseURL.appendingPathComponent("chat")

        var messages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt]
        ]

        for message in history {
            messages.append([
                "role":    message.isUser ? "user" : "assistant",
                "content": message.content
            ])
        }

        let body: [String: Any] = [
            "model":       Self.model,
            "messages":    messages,
            "temperature": 0.8,
            "max_tokens":  220
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody   = jsonData
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var (data, response) = try await authorizedData(for: request)

        // A 401 means the cached token was refused (expired early, or the Worker lost the key).
        // Drop it and retry once with a fresh one before surfacing anything to the user.
        if (response as? HTTPURLResponse)?.statusCode == 401 {
            await Self.attestation.invalidateToken()
            (data, response) = try await authorizedData(for: request)
        }

        guard let http = response as? HTTPURLResponse else { return Self.serviceUnavailableMessage }

        #if DEBUG
        print("PROXY STATUS:", http.statusCode)
        #endif

        guard http.statusCode == 200 else {
            return Self.userFacingError(for: http.statusCode)
        }

        let decoded = try JSONDecoder().decode(GroqResponse.self, from: data)
        return decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? "I'm here for you."
    }

    /// Sends the request with whatever credential this build can present. On a device that is a
    /// short-lived App Attest token; the simulator cannot attest, so it presents the dev bypass
    /// secret instead (that branch, and the secret, do not exist in device builds).
    private func authorizedData(for request: URLRequest) async throws -> (Data, URLResponse) {
        var request = request
        #if targetEnvironment(simulator)
        request.setValue(Secrets.devBypassSecret, forHTTPHeaderField: "X-Dev-Bypass")
        #else
        let token = try await Self.attestation.validToken()
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        #endif
        return try await URLSession.shared.data(for: request)
    }

    // Generates a short weekly emotional summary from recent sessions and journal entries
    func generateWeeklyInsight(sessions: [ChatSession], journal: [JournalEntry]) async -> String {
        let url = Self.workerBaseURL.appendingPathComponent("insight")

        // Moods and dates only — never reflection text. The privacy policy promises
        // journal entries stay on the device, and sending excerpts to Groq to build
        // this insight would break that promise for the most sensitive data the app holds.
        let chatSummary    = sessions.map { "\($0.dominantMood.rawValue) on \($0.date.formatted(date: .abbreviated, time: .omitted))" }.joined(separator: "; ")
        let journalSummary = journal.map  { "Felt \($0.mood.rawValue) on \($0.date.formatted(date: .abbreviated, time: .omitted))" }.joined(separator: "; ")

        let prompt = """
        Based on this user's recent emotional data, provide a warm, concise 2–3 sentence weekly insight. Be supportive, highlight any patterns, and end with one encouraging sentence. Write directly to the user. No headers, no bullets.

        Chat moods: \(chatSummary.isEmpty ? "none recorded" : chatSummary)
        Journal moods: \(journalSummary.isEmpty ? "none recorded" : journalSummary)
        """

        let body: [String: Any] = [
            "model":       Self.model,
            "messages":    [["role": "user", "content": prompt]],
            "temperature": 0.7,
            "max_tokens":  130
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else { return "" }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody   = jsonData
        req.timeoutInterval = 30
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        guard var (data, resp) = try? await authorizedData(for: req) else { return "" }
        if (resp as? HTTPURLResponse)?.statusCode == 401 {
            await Self.attestation.invalidateToken()
            guard let retry = try? await authorizedData(for: req) else { return "" }
            (data, resp) = retry
        }

        guard (resp as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(GroqResponse.self, from: data)
        else { return "" }

        return decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

//*======================================================================*//
// MARK: - Journal ViewModel
//*======================================================================*//

@MainActor
final class JournalViewModel: ObservableObject {

    @Published var messages:     [ChatMessage] = []
    @Published var currentInput: String        = ""
    @Published var isLoading:    Bool          = false
    @Published var currentMood:  MoodType      = .neutral

    private let sentimentAnalyzer = SentimentAnalyzer()
    private let emotionDetector   = EmotionDetector()
    private let safetyChecker     = SafetyChecker()
    private let aiService         = AIService()

    func send() async {

        let text = currentInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isLoading else { return }

        let mood = emotionDetector.detectEmotion(from: text)
        if mood != .neutral { currentMood = mood }
        currentInput = ""

        append(ChatMessage(content: text, isUser: true, mood: currentMood, timestamp: Date()))

        if safetyChecker.containsRisk(text) {
            append(ChatMessage(content: safetyChecker.crisisResponse, isUser: false, mood: .sad, timestamp: Date()))
            haptic(.warning)
            return
        }

        isLoading = true
        defer { isLoading = false }

        let history = messages

        do {
            let reply = try await aiService.send(history: history, mood: mood)
            append(ChatMessage(content: reply, isUser: false, mood: nil, timestamp: Date()))
            haptic(.success)
            StreakManager.shared.recordCheckIn()
        } catch {
            append(ChatMessage(content: AIService.userFacingError(for: error), isUser: false, mood: nil, timestamp: Date()))
            haptic(.error)
        }
    }

    func newChat() {
        guard !messages.isEmpty else { return }
        StorageManager.shared.saveSession(ChatSession(messages: messages))
        withAnimation(.easeInOut(duration: 0.25)) { messages = [] }
        currentMood  = .neutral
        currentInput = ""
    }

    private func append(_ message: ChatMessage) {
        withAnimation(.easeInOut(duration: 0.25)) { messages.append(message) }
    }

    private func haptic(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(type)
        #endif
    }
}

//*======================================================================*//
// MARK: - Day Formatting
//*======================================================================*//

/// Renders a day count with the matching noun, so a value of 1 reads "1 day"
/// rather than "1 days". Every user-facing day count goes through here.
func dayCount(_ days: Int) -> String {
    "\(days) day\(days == 1 ? "" : "s")"
}

//*======================================================================*//
// MARK: - Rounded Corner Shape
//*======================================================================*//

struct RoundedCorner: Shape {

    var radius:  CGFloat
    var corners: UIRectCorner

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect:       rect,
            byRoundingCorners: corners,
            cornerRadii:       CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

extension View {
    func roundedCorners(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

//*======================================================================*//
// MARK: - Typing Indicator
//*======================================================================*//

struct TypingIndicator: View {

    @State private var activeIndex = 0

    private let timer = Timer
        .publish(every: 0.38, on: .main, in: .common)
        .autoconnect()

    var body: some View {

        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.secondary.opacity(0.55))
                    .frame(width: 8, height: 8)
                    .scaleEffect(activeIndex == i ? 1.45 : 1.0)
                    .animation(.easeInOut(duration: 0.3), value: activeIndex)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .onReceive(timer) { _ in activeIndex = (activeIndex + 1) % 3 }
    }
}

//*======================================================================*//
// MARK: - Mood Badge
//*======================================================================*//

struct MoodBadge: View {

    let mood: MoodType

    var body: some View {

        HStack(spacing: 4) {
            Text(mood.emoji).font(.caption2)
            Text(mood.rawValue).font(.caption2).fontWeight(.semibold)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(mood.color.opacity(0.18))
        .foregroundColor(mood.color)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(mood.color.opacity(0.35), lineWidth: 1))
    }
}

//*======================================================================*//
// MARK: - Chat Bubble
//*======================================================================*//

struct ChatBubble: View {

    let message: ChatMessage

    private var timeString: String {
        message.timestamp.formatted(date: .omitted, time: .shortened)
    }

    var body: some View {

        HStack(alignment: .bottom, spacing: 0) {

            if message.isUser {

                Spacer(minLength: 56)

                VStack(alignment: .trailing, spacing: 5) {
                    if let mood = message.mood { MoodBadge(mood: mood) }
                    Text(message.content)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .foregroundColor(.white)
                        .background((message.mood ?? .neutral).bubbleGradient)
                        .roundedCorners(20, corners: [.topLeft, .topRight, .bottomLeft])
                    Text(timeString).font(.caption2).foregroundColor(.secondary)
                }

            } else {

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles").font(.caption2).foregroundColor(.purple)
                        Text("Jabe").font(.caption2).fontWeight(.semibold).foregroundColor(.purple)
                    }
                    Text(message.content)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .foregroundColor(.primary)
                        .background(Color(.systemGray6))
                        .roundedCorners(20, corners: [.topLeft, .topRight, .bottomRight])
                    Text(timeString).font(.caption2).foregroundColor(.secondary)
                }

                Spacer(minLength: 56)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}

//*======================================================================*//
// MARK: - App Header
//*======================================================================*//

struct AppHeader: View {

    let mood:           MoodType
    var onNewChat:      (() -> Void)? = nil
    var onJournalEntry: (() -> Void)? = nil

    var body: some View {

        VStack(spacing: 0) {

            HStack(alignment: .center) {

                VStack(alignment: .leading, spacing: 2) {
                    Text("Jabe").font(.title2).fontWeight(.bold)
                    Text("Your emotional wellness companion").font(.caption).foregroundColor(.secondary)
                }

                Spacer()

                HStack(spacing: 14) {

                    if let onJournalEntry {
                        Button(action: onJournalEntry) {
                            Image(systemName: "square.and.pencil")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(Color(red: 0.52, green: 0.22, blue: 0.88))
                        }
                    }

                    if let onNewChat {
                        Button(action: onNewChat) {
                            Image(systemName: "plus.bubble")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(Color(red: 0.52, green: 0.22, blue: 0.88))
                        }
                    }

                    ZStack {
                        Circle().fill(mood.color.opacity(0.18)).frame(width: 46, height: 46)
                        Text(mood.emoji).font(.title3)
                    }
                    .animation(.spring(response: 0.4, dampingFraction: 0.6), value: mood.rawValue)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)

            Divider()
        }
        .background(Color(.systemBackground))
    }
}

//*======================================================================*//
// MARK: - Empty State
//*======================================================================*//

struct EmptyStateView: View {

    var body: some View {

        VStack(spacing: 18) {

            BrainLogoView(size: 80).opacity(0.9)

            VStack(spacing: 8) {
                Text("How are you feeling today?").font(.title3).fontWeight(.semibold)
                Text("Share anything on your mind.\nJabe is here to listen.")
                    .font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
            }
        }
        .padding(32)
    }
}

//*======================================================================*//
// MARK: - Input Bar
//*======================================================================*//

struct InputBar: View {

    @Binding var text:    String
    let isLoading:        Bool
    let onSend:           () -> Void

    @StateObject   private var voice   = VoiceInputManager()
    @ObservedObject private var premium = PremiumManager.shared
    @FocusState    private var focused: Bool

    private var canSend: Bool {
        !isLoading && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {

        VStack(spacing: 0) {

            Divider()

            HStack(alignment: .bottom, spacing: 10) {

                // Auto-sizing TextEditor with placeholder
                ZStack(alignment: .topLeading) {

                    Text(text.isEmpty ? "placeholder" : text)
                        .font(.body)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .opacity(0)
                        .frame(maxHeight: 120)

                    if text.isEmpty {
                        Text(voice.isRecording ? "Listening…" : "How are you feeling?")
                            .foregroundColor(Color(.placeholderText))
                            .font(.body)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .allowsHitTesting(false)
                    }

                    TextEditor(text: $text)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .focused($focused)
                }
                .frame(minHeight: 44, maxHeight: 120)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 22))

                // Voice mic button — premium. Guarded rather than blurred: a 38pt
                // control reads as a rendering fault when blurred, and the guard also
                // stops the microphone permission prompt firing for a locked user.
                Button {
                    guard PremiumManager.isFeatureUnlocked(premium.entitlementState) else {
                        premium.showPaywall = true
                        return
                    }
                    if voice.isRecording {
                        let captured = voice.transcript
                        voice.stopRecording()
                        if !captured.isEmpty { text = captured }
                    } else {
                        voice.startRecording()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(voice.isRecording ? Color.red.opacity(0.15) : Color(.systemGray5))
                            .frame(width: 38, height: 38)
                        Image(systemName: voice.isRecording ? "mic.fill" : "mic")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(voice.isRecording ? .red : .secondary)
                        if !PremiumManager.isFeatureUnlocked(premium.entitlementState) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .padding(2)
                                .background(Circle().fill(Color(red: 0.52, green: 0.22, blue: 0.88)))
                                .offset(x: 13, y: 13)
                        }
                    }
                }
                .accessibilityIdentifier("voiceInput")
                .animation(.easeInOut(duration: 0.2), value: voice.isRecording)

                // Send button
                Button {
                    focused = false
                    if voice.isRecording { voice.stopRecording() }
                    onSend()
                } label: {
                    ZStack {
                        Circle()
                            .fill(
                                canSend
                                    ? LinearGradient(colors: [.purple, .indigo], startPoint: .top, endPoint: .bottom)
                                    : LinearGradient(colors: [Color(.systemGray4), Color(.systemGray4)], startPoint: .top, endPoint: .bottom)
                            )
                            .frame(width: 38, height: 38)
                        Image(systemName: "arrow.up").font(.system(size: 16, weight: .bold)).foregroundColor(.white)
                    }
                }
                .disabled(!canSend)
                .animation(.easeInOut(duration: 0.2), value: canSend)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(Color(.systemBackground))
        // Live transcript update while recording
        .onChange(of: voice.transcript) { _, newValue in
            if voice.isRecording { text = newValue }
        }
        .alert("Microphone Access Needed", isPresented: $voice.permissionDenied) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enable Microphone and Speech Recognition in iOS Settings to use voice input.")
        }
    }
}

//*======================================================================*//
// MARK: - Content View
//*======================================================================*//

struct ContentView: View {

    @StateObject private var viewModel  = JournalViewModel()
    @State private var showJournalEntry = false

    var body: some View {

        VStack(spacing: 0) {

            AppHeader(
                mood:           viewModel.currentMood,
                onNewChat:      { viewModel.newChat() },
                onJournalEntry: { showJournalEntry = true }
            )

            ScrollViewReader { proxy in

                ScrollView {

                    LazyVStack(spacing: 6) {

                        if viewModel.messages.isEmpty {
                            EmptyStateView()
                                .frame(maxWidth: .infinity)
                                .padding(.top, 48)
                        }

                        ForEach(viewModel.messages) { message in
                            ChatBubble(message: message)
                        }

                        if viewModel.isLoading {
                            HStack {
                                TypingIndicator()
                                Spacer()
                            }
                            .padding(.leading, 16)
                            .padding(.vertical, 4)
                            .transition(.opacity)
                        }

                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.vertical, 10)
                    .animation(.easeInOut(duration: 0.25), value: viewModel.isLoading)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: viewModel.messages.count) { _, _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.easeOut(duration: 0.25)) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }
                .onChange(of: viewModel.isLoading) { _, _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.easeOut(duration: 0.25)) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }
            }

            InputBar(
                text:      $viewModel.currentInput,
                isLoading: viewModel.isLoading,
                onSend:    { Task { await viewModel.send() } }
            )
        }
        .sheet(isPresented: $showJournalEntry) {
            NewJournalEntryView(preselectedMood: viewModel.currentMood)
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("ClearActiveChat"))) { _ in
            viewModel.messages = []
            viewModel.currentMood = .neutral
            viewModel.currentInput = ""
        }
    }
}

//*======================================================================*//
// MARK: - History View
//*======================================================================*//

struct HistoryView: View {

    @ObservedObject private var storage = StorageManager.shared
    @State private var selectedSession: ChatSession?

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; return f
    }()

    private var grouped: [(Date, [ChatSession])] {
        Dictionary(grouping: storage.sessions) { Calendar.current.startOfDay(for: $0.date) }
            .sorted { $0.key > $1.key }
    }

    var body: some View {
        NavigationView {
            Group {
                if storage.sessions.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "clock")
                            .font(.system(size: 52)).foregroundColor(.secondary.opacity(0.35))
                        Text("No saved chats yet")
                            .font(.headline).foregroundColor(.secondary)
                        Text("Tap the + bubble icon in Chat to start a new conversation.\nYour current chat will be saved automatically.")
                            .font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    List {
                        ForEach(grouped, id: \.0) { date, sessions in
                            Section(header: Text(Self.dateFmt.string(from: date))) {
                                ForEach(sessions) { session in
                                    Button { selectedSession = session } label: {
                                        HStack(spacing: 12) {
                                            ZStack {
                                                Circle().fill(session.dominantMood.color.opacity(0.15)).frame(width: 42, height: 42)
                                                Text(session.dominantMood.emoji).font(.title3)
                                            }
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text("\(session.dominantMood.rawValue) Conversation")
                                                    .font(.subheadline).fontWeight(.medium).foregroundColor(.primary)
                                                Text("\(session.messages.count) messages")
                                                    .font(.caption).foregroundColor(.secondary)
                                            }
                                            Spacer()
                                            Text(session.date, style: .time).font(.caption2).foregroundColor(.secondary)
                                        }
                                    }
                                }
                                .onDelete { offsets in offsets.forEach { storage.deleteSession(sessions[$0]) } }
                            }
                        }
                    }
                }
            }
            .navigationTitle("History")
            .sheet(item: $selectedSession) { SessionDetailView(session: $0) }
        }
    }
}

struct SessionDetailView: View {

    let session: ChatSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(session.messages) { ChatBubble(message: $0) }
                }
                .padding(.vertical, 12)
            }
            .navigationTitle(session.dominantMood.rawValue + " Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { dismiss() } }
            }
        }
    }
}

//*======================================================================*//
// MARK: - Share Sheet
//*======================================================================*//

struct ShareSheet: UIViewControllerRepresentable {

    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

//*======================================================================*//
// MARK: - Journal View
//*======================================================================*//

struct JournalView: View {

    @ObservedObject private var storage = StorageManager.shared
    @ObservedObject private var premium = PremiumManager.shared
    @State private var showingNewEntry  = false
    @State private var showExport       = false
    @State private var exportText       = ""

    var body: some View {
        NavigationView {
            Group {
                if storage.journalEntries.isEmpty {
                    VStack(spacing: 18) {
                        Image(systemName: "book.closed")
                            .font(.system(size: 52)).foregroundColor(.secondary.opacity(0.35))
                        Text("No journal entries yet").font(.headline).foregroundColor(.secondary)
                        Text("Reflect on your feelings and track\nyour emotional journey over time.")
                            .font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
                        Button("Write First Entry") { showingNewEntry = true }
                            .buttonStyle(.borderedProminent)
                            .tint(Color(red: 0.52, green: 0.22, blue: 0.88))
                    }
                    .padding()
                } else {
                    List {
                        ForEach(storage.journalEntries) { entry in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(entry.mood.emoji + " " + entry.mood.rawValue)
                                        .font(.subheadline).fontWeight(.semibold).foregroundColor(entry.mood.color)
                                    Spacer()
                                    Text(entry.date, style: .date).font(.caption).foregroundColor(.secondary)
                                }
                                Text(entry.reflection).font(.body).lineLimit(4).foregroundColor(.primary)
                            }
                            .padding(.vertical, 4)
                        }
                        .onDelete { offsets in
                            offsets.forEach { storage.deleteJournalEntry(storage.journalEntries[$0]) }
                        }
                    }
                }
            }
            .navigationTitle("Journal")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !storage.journalEntries.isEmpty {
                        // Writing and reading the journal stay free; only export is premium.
                        // A 22pt toolbar icon reads as broken when blurred, so this one gets a
                        // badge and an action guard instead of the PremiumLock overlay.
                        Button {
                            guard PremiumManager.isFeatureUnlocked(premium.entitlementState) else {
                                premium.showPaywall = true
                                return
                            }
                            exportText = storage.journalEntries.map { entry in
                                "[\(entry.date.formatted(date: .long, time: .omitted))] \(entry.mood.emoji) \(entry.mood.rawValue)\n\(entry.reflection)"
                            }.joined(separator: "\n\n---\n\n")
                            showExport = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundColor(Color(red: 0.52, green: 0.22, blue: 0.88))
                                .overlay(alignment: .bottomTrailing) {
                                    if !PremiumManager.isFeatureUnlocked(premium.entitlementState) {
                                        Image(systemName: "lock.fill")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(.white)
                                            .padding(2)
                                            .background(Circle().fill(Color(red: 0.52, green: 0.22, blue: 0.88)))
                                            .offset(x: 3, y: 3)
                                    }
                                }
                        }
                        .accessibilityIdentifier("journalExport")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showingNewEntry = true } label: {
                        Image(systemName: "square.and.pencil")
                            .foregroundColor(Color(red: 0.52, green: 0.22, blue: 0.88))
                    }
                }
            }
            .sheet(isPresented: $showingNewEntry) { NewJournalEntryView(preselectedMood: .neutral) }
            .sheet(isPresented: $showExport) { ShareSheet(items: [exportText]) }
        }
    }
}

struct NewJournalEntryView: View {

    @Environment(\.dismiss) private var dismiss
    let preselectedMood: MoodType

    @State private var selectedMood: MoodType
    @State private var reflection = ""

    init(preselectedMood: MoodType) {
        self.preselectedMood = preselectedMood
        _selectedMood = State(initialValue: preselectedMood)
    }

    var body: some View {
        NavigationView {
            Form {
                Section("How are you feeling?") {
                    Picker("Mood", selection: $selectedMood) {
                        ForEach([MoodType.happy, .neutral, .sad, .anxious, .angry], id: \.self) { mood in
                            Text(mood.emoji + " " + mood.rawValue).tag(mood)
                        }
                    }
                    .pickerStyle(.menu)
                }
                Section("Your reflection") {
                    TextEditor(text: $reflection).frame(minHeight: 160)
                }
            }
            .navigationTitle("New Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading)  { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        StorageManager.shared.saveJournalEntry(JournalEntry(mood: selectedMood, reflection: reflection))
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(reflection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

//*======================================================================*//
// MARK: - Onboarding
//*======================================================================*//

struct OnboardingView: View {

    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var page = 0

    private struct PageData {
        let title: String; let subtitle: String; let icon: String; let color: Color
    }

    private let pages: [PageData] = [
        PageData(title: "Welcome to\nJabe",
                 subtitle: "Your personal AI wellness companion, here to listen without judgment.",
                 icon: "", color: Color(red: 0.52, green: 0.22, blue: 0.88)),
        PageData(title: "Chat Anytime",
                 subtitle: "Share how you're feeling and get warm, thoughtful responses whenever you need.",
                 icon: "bubble.left.and.bubble.right.fill", color: Color(red: 0.35, green: 0.55, blue: 0.95)),
        PageData(title: "Track Your Mood",
                 subtitle: "Jabe detects your emotional state and tailors every response to how you feel.",
                 icon: "face.smiling.fill", color: Color(red: 0.95, green: 0.55, blue: 0.15)),
        PageData(title: "Keep a Journal",
                 subtitle: "Reflect on your day and save mood-linked entries to see your emotional journey.",
                 icon: "book.fill", color: Color(red: 0.12, green: 0.60, blue: 0.35)),
        PageData(title: "A Companion,\nNot a Clinician",
                 subtitle: "Jabe is an AI wellness companion, not a licensed therapist or medical provider. If you're in crisis, call or text 988 (Suicide & Crisis Lifeline) anytime.",
                 icon: "heart.text.square.fill", color: Color(red: 0.75, green: 0.30, blue: 0.35))
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(0..<pages.count, id: \.self) { i in
                    OnboardingPageView(
                        title: pages[i].title, subtitle: pages[i].subtitle,
                        icon: pages[i].icon, color: pages[i].color, isFirst: i == 0
                    )
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            VStack(spacing: 14) {

                // Custom page dots — replaces built-in dots that blocked the button
                HStack(spacing: 8) {
                    ForEach(0..<pages.count, id: \.self) { i in
                        Circle()
                            .fill(i == page ? Color(red: 0.62, green: 0.22, blue: 0.98) : Color.secondary.opacity(0.35))
                            .frame(width: i == page ? 10 : 7, height: i == page ? 10 : 7)
                            .animation(.easeInOut(duration: 0.2), value: page)
                    }
                }

                Button(page < pages.count - 1 ? "Next" : "Get Started") {
                    if page < pages.count - 1 {
                        withAnimation { page += 1 }
                    } else {
                        hasSeenOnboarding = true
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [Color(red: 0.62, green: 0.22, blue: 0.98), Color(red: 0.38, green: 0.12, blue: 0.78)],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .foregroundColor(.white)
                .fontWeight(.semibold)
                .clipShape(RoundedRectangle(cornerRadius: 14))

                if page < pages.count - 1 {
                    Button("Skip") { hasSeenOnboarding = true }
                        .foregroundColor(.secondary).font(.subheadline)
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 44)
            .padding(.top, 8)
        }
    }
}

struct OnboardingPageView: View {

    let title:   String
    let subtitle: String
    let icon:    String
    let color:   Color
    let isFirst: Bool

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            if isFirst {
                BrainLogoView(size: 90).padding(.bottom, 4)
            } else {
                ZStack {
                    Circle().fill(color.opacity(0.14)).frame(width: 110, height: 110)
                    Image(systemName: icon).font(.system(size: 48)).foregroundStyle(color)
                }
            }
            VStack(spacing: 14) {
                Text(title).font(.largeTitle).fontWeight(.bold).multilineTextAlignment(.center)
                Text(subtitle).font(.body).foregroundColor(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal, 28)
            }
            Spacer()
            Spacer()
        }
    }
}

//*======================================================================*//
// MARK: - Settings View
//*======================================================================*//

struct SettingsView: View {

    @ObservedObject private var storage   = StorageManager.shared
    @ObservedObject private var premium   = PremiumManager.shared
    @AppStorage("colorSchemePreference") private var colorSchemePreference = "system"
    @AppStorage("reminderEnabled")       private var reminderEnabled       = false
    @State private var reminderTime      = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var showClearConfirm  = false

    /// Read from the bundle rather than hardcoded — the old literal "1.0.0" was already wrong
    /// against MARKETING_VERSION 1.0, and would have kept claiming 1.0.0 after every version bump.
    /// Including the build number makes About a reliable way to identify which binary is installed.
    private var appVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(short) (\(build))"
    }

    var body: some View {
        NavigationView {
            List {

                // Premium
                Section("Premium") {
                    switch premium.entitlementState {
                    case .purchased:
                        HStack {
                            Label("Premium Unlocked", systemImage: "checkmark.seal.fill")
                                .foregroundColor(.green)
                            Spacer()
                        }
                    case .trial(let daysRemaining):
                        Button { premium.showPaywall = true } label: {
                            HStack {
                                Label("Free Trial Active", systemImage: "star.fill").foregroundColor(.orange)
                                Spacer()
                                Text("\(dayCount(daysRemaining)) left")
                                    .font(.caption).foregroundColor(.orange)
                            }
                        }
                    case .locked:
                        Button { premium.showPaywall = true } label: {
                            HStack {
                                Label("Unlock Premium", systemImage: "star.fill").foregroundColor(Color(red: 0.52, green: 0.22, blue: 0.88))
                                Spacer()
                                Text("$3.99").font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                }

                Section("Appearance") {
                    Picker("Theme", selection: $colorSchemePreference) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                    .pickerStyle(.segmented)
                }

                Section("Reminders") {
                    Toggle("Daily Check-in Reminder", isOn: $reminderEnabled)
                        .tint(Color(red: 0.52, green: 0.22, blue: 0.88))
                        .onChange(of: reminderEnabled) { _, enabled in
                            if enabled { requestNotificationPermission(); scheduleReminder() }
                            else { cancelReminder() }
                        }
                    if reminderEnabled {
                        DatePicker("Time", selection: $reminderTime, displayedComponents: .hourAndMinute)
                            .onChange(of: reminderTime) { _, _ in scheduleReminder() }
                    }
                }

                Section("Data") {
                    Button(role: .destructive) { showClearConfirm = true } label: {
                        Label("Clear Chat History", systemImage: "trash")
                    }
                }

                Section("About") {
                    LabeledContent("App",       value: "Jabe Wellness AI")
                    LabeledContent("Version",   value: appVersion)
                    LabeledContent("Developer", value: "Jabe")
                    LabeledContent("AI Model",  value: AIService.modelDisplayName)
                    LabeledContent("Storage",   value: "Local device")
                }
            }
            .navigationTitle("Settings")
            .alert("Clear Chat History?", isPresented: $showClearConfirm) {
                Button("Clear", role: .destructive) {
                    storage.clearAllSessions()
                    NotificationCenter.default.post(name: .init("ClearActiveChat"), object: nil)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete all saved conversations.")
            }
        }
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func scheduleReminder() {
        cancelReminder()
        let content   = UNMutableNotificationContent()
        content.title = "Jabe"
        content.body  = "How are you feeling today? 💙 Take a moment to check in."
        content.sound = .default
        let comps     = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
        let trigger   = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "jabe.daily", content: content, trigger: trigger)
        )
    }

    private func cancelReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["jabe.daily"])
    }
}

//*======================================================================*//
// MARK: - Insights View
//*======================================================================*//

struct InsightsView: View {

    @ObservedObject private var storage = StorageManager.shared
    @ObservedObject private var streak  = StreakManager.shared
    @ObservedObject private var premium = PremiumManager.shared
    @State private var weeklyInsight    = ""
    @State private var isLoadingInsight = false
    @State private var showHistory      = false

    private let aiService = AIService()

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 18) {

                    StreakBannerView(
                        currentStreak: streak.currentStreak,
                        longestStreak: streak.longestStreak,
                        isToday:       streak.isCheckedInToday
                    )
                    .premiumLocked()

                    MoodChartView(dataPoints: combinedMoodData)
                        .premiumLocked()

                    WeeklyInsightCard(
                        insight:   weeklyInsight,
                        isLoading: isLoadingInsight,
                        onGenerate: { Task { await loadInsight() } }
                    )
                    .premiumLocked()

                    // Chat history accessible from Insights
                    Button { showHistory = true } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle().fill(Color.blue.opacity(0.12)).frame(width: 44, height: 44)
                                Image(systemName: "clock.fill").foregroundColor(.blue).font(.system(size: 18))
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Chat History").font(.subheadline).fontWeight(.semibold).foregroundColor(.primary)
                                Text("\(storage.sessions.count) saved conversation\(storage.sessions.count == 1 ? "" : "s")")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                        }
                        .padding(16)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
            }
            .navigationTitle("Insights")
            .sheet(isPresented: $showHistory) { HistoryView() }
        }
    }

    private var combinedMoodData: [(Date, MoodType)] {
        let chatPts    = storage.sessions.prefix(20).map { ($0.date, $0.dominantMood) }
        let journalPts = storage.journalEntries.prefix(20).map { ($0.date, $0.mood) }
        return (Array(chatPts) + Array(journalPts)).sorted { $0.0 > $1.0 }.prefix(14).map { $0 }
    }

    private func loadInsight() async {
        // The card is blurred when locked, but guard the call too: blur is presentation,
        // and this one costs a live API request.
        guard PremiumManager.isFeatureUnlocked(premium.entitlementState) else {
            premium.showPaywall = true
            return
        }
        guard !storage.sessions.isEmpty || !storage.journalEntries.isEmpty else {
            weeklyInsight = "Start chatting and journaling — your personalized insight will appear here after a few days."
            return
        }
        isLoadingInsight = true
        weeklyInsight = await aiService.generateWeeklyInsight(
            sessions: Array(storage.sessions.prefix(7)),
            journal:  Array(storage.journalEntries.prefix(7))
        )
        isLoadingInsight = false
    }
}

struct StreakBannerView: View {

    let currentStreak: Int
    let longestStreak: Int
    let isToday:       Bool

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.orange, .red], startPoint: .top, endPoint: .bottom))
                    .frame(width: 58, height: 58)
                Text("🔥").font(.system(size: 28))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("\(currentStreak) day streak")
                    .font(.title3).fontWeight(.bold)
                Text(isToday ? "You checked in today!" : "Chat today to keep your streak")
                    .font(.caption).foregroundColor(.secondary)
                if longestStreak > 0 {
                    Text("Best: \(dayCount(longestStreak))")
                        .font(.caption2).foregroundColor(.orange)
                }
            }

            Spacer()
        }
        .padding(16)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct MoodChartView: View {

    let dataPoints: [(Date, MoodType)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Mood").font(.headline)

            if dataPoints.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "chart.bar")
                        .font(.system(size: 40)).foregroundColor(.secondary.opacity(0.35))
                    Text("No mood data yet.\nStart chatting to see your trends.")
                        .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 150)
            } else {
                Chart {
                    ForEach(Array(dataPoints.enumerated()), id: \.0) { index, point in
                        BarMark(
                            x: .value("Entry", index),
                            y: .value("Score", point.1.score)
                        )
                        .foregroundStyle(point.1.color.gradient)
                        .cornerRadius(5)
                        .annotation(position: .top) {
                            Text(point.1.emoji).font(.system(size: 10))
                        }
                    }
                }
                .chartXAxis(.hidden)
                .chartYScale(domain: 0...5)
                .chartYAxis {
                    AxisMarks(values: [1, 3, 5]) { val in
                        AxisValueLabel {
                            if let v = val.as(Int.self) {
                                Text(v == 5 ? "😊" : v == 3 ? "😐" : "😤").font(.caption2)
                            }
                        }
                        AxisGridLine()
                    }
                }
                .frame(height: 150)
            }
        }
        .padding(16)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct WeeklyInsightCard: View {

    let insight:    String
    let isLoading:  Bool
    let onGenerate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Weekly Insight", systemImage: "sparkles").font(.headline)
                Spacer()
                Button(action: onGenerate) {
                    Image(systemName: "arrow.clockwise")
                        .font(.subheadline).foregroundColor(.secondary)
                }
                .disabled(isLoading)
            }

            if isLoading {
                HStack { Spacer(); ProgressView(); Spacer() }.frame(height: 50)
            } else if insight.isEmpty {
                VStack(spacing: 10) {
                    Text("Tap the refresh button above to generate your personalized weekly emotional summary.")
                        .font(.subheadline).foregroundColor(.secondary)
                    Button("Generate Insight", action: onGenerate)
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundColor(Color(red: 0.52, green: 0.22, blue: 0.88))
                }
            } else {
                Text(insight).font(.subheadline).foregroundColor(.primary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

//*======================================================================*//
// MARK: - Guided Exercises View
//*======================================================================*//

struct GuidedExercisesView: View {

    enum ExerciseType: String, CaseIterable, Identifiable {
        case breathing = "Box Breathing"
        case grounding = "5-4-3-2-1 Grounding"
        case cbt       = "Reframe Your Thoughts"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .breathing: return "lungs.fill"
            case .grounding: return "hand.raised.fill"
            case .cbt:       return "brain.head.profile"
            }
        }

        var color: Color {
            switch self {
            case .breathing: return .teal
            case .grounding: return .green
            case .cbt:       return .purple
            }
        }

        var subtitle: String {
            switch self {
            case .breathing: return "Calm your nervous system in 2 minutes"
            case .grounding: return "Anchor yourself to the present moment"
            case .cbt:       return "Challenge and reframe negative thoughts"
            }
        }
    }

    @State private var selectedExercise: ExerciseType?

    var body: some View {
        NavigationView {
            List(ExerciseType.allCases) { exercise in
                Button { selectedExercise = exercise } label: {
                    HStack(spacing: 16) {
                        ZStack {
                            Circle().fill(exercise.color.opacity(0.15)).frame(width: 52, height: 52)
                            Image(systemName: exercise.icon).font(.system(size: 22)).foregroundColor(exercise.color)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(exercise.rawValue).font(.subheadline).fontWeight(.semibold).foregroundColor(.primary)
                            Text(exercise.subtitle).font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                    }
                    .padding(.vertical, 6)
                }
                .premiumLocked()
            }
            .navigationTitle("Exercises")
            .sheet(item: $selectedExercise) { exercise in
                switch exercise {
                case .breathing: BreathingExerciseView()
                case .grounding: GroundingExerciseView()
                case .cbt:       CBTExerciseView()
                }
            }
        }
    }
}

// MARK: Box Breathing

struct BreathingExerciseView: View {

    @Environment(\.dismiss) private var dismiss

    @State private var phase      = "Tap to Begin"
    @State private var scale: CGFloat = 1.0
    @State private var isRunning  = false
    @State private var isActive   = true
    @State private var cycleCount = 0

    var body: some View {
        NavigationView {
            VStack(spacing: 40) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [.teal.opacity(0.25), .blue.opacity(0.25)],
                            startPoint: .top, endPoint: .bottom
                        ))
                        .frame(width: 220, height: 220)
                        .scaleEffect(scale)
                    Circle()
                        .stroke(Color.teal.opacity(0.5), lineWidth: 2)
                        .frame(width: 220, height: 220)
                        .scaleEffect(scale)
                    Text(phase)
                        .font(.title2).fontWeight(.semibold)
                        .multilineTextAlignment(.center)
                }
                .onTapGesture { if !isRunning { startCycles() } }

                VStack(spacing: 8) {
                    Text("Box Breathing").font(.headline)
                    Text("Inhale 4s · Hold 4s · Exhale 4s · Hold 4s\nRepeat 4 cycles for best results")
                        .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
                    if cycleCount > 0 {
                        Text("Cycle \(min(cycleCount, 4)) of 4").font(.subheadline).foregroundColor(.teal)
                    }
                }

                Spacer()
            }
            .padding(24)
            .navigationTitle("Breathing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { isActive = false; dismiss() }
                }
            }
            .onDisappear { isActive = false }
        }
    }

    private func startCycles() {
        isRunning  = true
        cycleCount = 0
        runPhases(remaining: 4)
    }

    private func runPhases(remaining: Int) {
        guard remaining > 0 else {
            phase     = "Well done! 🎉"
            isRunning = false
            return
        }
        animate("Inhale", toScale: 1.5, duration: 4) {
            animate("Hold", toScale: 1.5, duration: 4) {
                animate("Exhale", toScale: 1.0, duration: 4) {
                    animate("Hold", toScale: 1.0, duration: 4) {
                        cycleCount += 1
                        runPhases(remaining: remaining - 1)
                    }
                }
            }
        }
    }

    private func animate(_ label: String, toScale s: CGFloat, duration: Double, then: @escaping () -> Void) {
        guard isActive else { return }
        phase = label
        withAnimation(.easeInOut(duration: duration)) { scale = s }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { then() }
    }
}

// MARK: 5-4-3-2-1 Grounding

struct GroundingExerciseView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var step = 0

    private let steps: [(Int, String, String, Color)] = [
        (5, "See",   "Name 5 things you can see right now",         .blue),
        (4, "Touch", "Name 4 things you can physically feel",       .teal),
        (3, "Hear",  "Name 3 things you can hear around you",       .green),
        (2, "Smell", "Name 2 things you can smell right now",       .orange),
        (1, "Taste", "Name 1 thing you can taste",                  .purple)
    ]

    var body: some View {
        NavigationView {
            GeometryReader { geo in
                VStack(spacing: 0) {
                    if step < steps.count {
                        let s = steps[step]
                        VStack(spacing: 20) {
                            Spacer(minLength: 16)
                            ZStack {
                                Circle().fill(s.3.opacity(0.15)).frame(width: 110, height: 110)
                                Text("\(s.0)").font(.system(size: 52, weight: .bold)).foregroundColor(s.3)
                            }
                            VStack(spacing: 10) {
                                Text(s.1).font(.title).fontWeight(.bold)
                                Text(s.2)
                                    .font(.body).foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.horizontal, 24)
                            }
                            Spacer(minLength: 16)
                            Button(step < steps.count - 1 ? "Next →" : "Finish") {
                                withAnimation { step += 1 }
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 16)
                            .background(s.3).foregroundColor(.white).fontWeight(.semibold)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .padding(.horizontal, 28).padding(.bottom, 24)
                        }
                        .frame(width: geo.size.width, height: geo.size.height)
                    } else {
                        VStack(spacing: 20) {
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 72)).foregroundColor(.green)
                            Text("Grounded!").font(.largeTitle).fontWeight(.bold)
                            Text("You're present, safe, and connected to this moment.")
                                .font(.body).foregroundColor(.secondary)
                                .multilineTextAlignment(.center).padding(.horizontal, 28)
                            Spacer()
                            Button("Close") { dismiss() }
                                .frame(maxWidth: .infinity).padding(.vertical, 16)
                                .background(Color.green).foregroundColor(.white).fontWeight(.semibold)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .padding(.horizontal, 28).padding(.bottom, 24)
                        }
                        .frame(width: geo.size.width, height: geo.size.height)
                    }
                }
            }
            .navigationTitle("5-4-3-2-1 Grounding")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Close") { dismiss() } }
            }
        }
    }
}

// MARK: CBT Thought Reframing

struct CBTExerciseView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var thought   = ""
    @State private var evidence  = ""
    @State private var reframe   = ""
    @State private var step      = 0
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        NavigationView {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Cognitive Reframing").font(.headline)
                        Text("Work through a negative thought in 3 steps.")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section("Step 1 — The Thought") {
                    TextField("What's the negative thought bothering you?", text: $thought, axis: .vertical)
                        .lineLimit(3...5)
                        .focused($isFieldFocused)
                }

                if step >= 1 {
                    Section("Step 2 — Challenge It") {
                        TextField("What evidence contradicts this thought? What would you tell a friend?", text: $evidence, axis: .vertical)
                            .lineLimit(3...5)
                            .focused($isFieldFocused)
                    }
                }

                if step >= 2 {
                    Section("Step 3 — Reframe") {
                        TextField("Write a more balanced, compassionate version of the thought…", text: $reframe, axis: .vertical)
                            .lineLimit(3...5)
                            .focused($isFieldFocused)
                    }
                }

                Section {
                    if step < 2 {
                        Button("Next Step →") { withAnimation { step += 1 } }
                            .foregroundColor(Color(red: 0.52, green: 0.22, blue: 0.88))
                            .disabled((step == 0 && thought.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ||
                                      (step == 1 && evidence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                    } else {
                        Button("Save to Journal") {
                            StorageManager.shared.saveJournalEntry(
                                JournalEntry(
                                    mood: .neutral,
                                    reflection: "Thought: \(thought)\n\nChallenge: \(evidence)\n\nReframe: \(reframe)"
                                )
                            )
                            dismiss()
                        }
                        .foregroundColor(.green)
                        .disabled(reframe.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .navigationTitle("Reframe Thoughts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Close") { dismiss() } }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { isFieldFocused = false }
                }
            }
        }
    }
}

//*======================================================================*//
// MARK: - Premium Paywall View
//*======================================================================*//

struct PremiumPaywallView: View {

    @ObservedObject private var premium = PremiumManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var isPurchasing = false
    @State private var isRestoring  = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 28) {

                    // Header
                    VStack(spacing: 14) {
                        BrainLogoView(size: 80)
                        Text("Jabe Premium")
                            .font(.largeTitle).fontWeight(.bold)

                        if premium.isInTrial {
                            HStack {
                                Image(systemName: "clock.fill").foregroundColor(.orange)
                                Text("\(dayCount(premium.trialDaysRemaining)) left in your free trial")
                                    .fontWeight(.medium)
                            }
                            .font(.subheadline)
                            .foregroundColor(.orange)
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(Color.orange.opacity(0.12))
                            .clipShape(Capsule())
                        }
                    }
                    .padding(.top, 24)

                    // Features list
                    VStack(alignment: .leading, spacing: 18) {
                        paywallRow(icon: "clock.fill",         color: .blue,   title: "Chat History",       sub: "Save and revisit every conversation")
                        paywallRow(icon: "book.fill",          color: .green,  title: "Journal + Export",   sub: "Write entries and export as text")
                        paywallRow(icon: "chart.bar.fill",     color: .purple, title: "Mood Insights",      sub: "Track emotional patterns over time")
                        paywallRow(icon: "lungs.fill",         color: .teal,   title: "Guided Exercises",   sub: "Breathing, grounding, and CBT tools")
                        paywallRow(icon: "mic.fill",           color: .red,    title: "Voice Input",        sub: "Speak your thoughts instead of typing")
                        paywallRow(icon: "sparkles",           color: .orange, title: "AI Weekly Insights", sub: "Personalized weekly emotional summary")
                    }
                    .padding(.horizontal, 24)

                    // Purchase
                    VStack(spacing: 12) {
                        if premium.entitlementState == .purchased {
                            // There is nothing left to sell, so say so. Without this the
                            // "$3.99" button stayed on screen after a completed purchase and
                            // people tapped it again — StoreKit no-ops silently on an
                            // already-owned non-consumable, so nothing happened.
                            HStack(spacing: 10) {
                                Image(systemName: "checkmark.seal.fill")
                                Text("Premium Unlocked").fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.green.opacity(0.15))
                            .foregroundColor(.green)
                            .clipShape(RoundedRectangle(cornerRadius: 14))

                            Text("Thank you — every feature above is yours for good.")
                                .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
                        } else {
                            Button {
                                Task { isPurchasing = true; await premium.purchase(); isPurchasing = false }
                            } label: {
                                Group {
                                    if isPurchasing {
                                        ProgressView().tint(.white)
                                    } else {
                                        Text("Unlock for \(premium.product?.displayPrice ?? "$3.99")")
                                        .fontWeight(.semibold)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    LinearGradient(
                                        colors: [Color(red: 0.62, green: 0.22, blue: 0.98),
                                                 Color(red: 0.38, green: 0.12, blue: 0.78)],
                                        startPoint: .leading, endPoint: .trailing
                                    )
                                )
                                .foregroundColor(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                            .disabled(isPurchasing)

                            Text("One-time purchase · No subscription · No recurring charges")
                                .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
                        }

                        Button {
                            Task { isRestoring = true; await premium.restorePurchases(); isRestoring = false }
                        } label: {
                            Group {
                                if isRestoring { ProgressView() }
                                else           { Text("Restore Purchase") }
                            }
                            .font(.caption).foregroundColor(.secondary)
                        }
                        .disabled(isRestoring)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 36)
                }
                .alert(
                    "Purchase Failed",
                    isPresented: Binding(
                        get: { premium.purchaseError != nil },
                        set: { if !$0 { premium.purchaseError = nil } }
                    )
                ) {
                    Button("OK", role: .cancel) { premium.purchaseError = nil }
                } message: {
                    Text(premium.purchaseError ?? "")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) { Button("Close") { dismiss() } }
            }
        }
        // Deliberately no auto-dismiss. The old rule watched isPremium, which is already
        // true throughout the trial and stays true after buying, so it never fired for
        // anyone who purchased during their first seven days — they paid and the paywall
        // sat there unchanged. Confirming in place also keeps Restore Purchase reachable,
        // which vanishes the instant the sheet closes.
    }

    @ViewBuilder
    private func paywallRow(icon: String, color: Color, title: String, sub: String) -> some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().fill(color.opacity(0.15)).frame(width: 46, height: 46)
                Image(systemName: icon).font(.system(size: 18)).foregroundColor(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline).fontWeight(.semibold)
                Text(sub).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Image(systemName: "checkmark").font(.caption).foregroundColor(.green)
        }
    }
}

//*======================================================================*//
// MARK: - Main Tab View
//*======================================================================*//

//*======================================================================*//
// MARK: - Premium Gate
//*======================================================================*//

// Blurs a premium surface and routes taps to the paywall when the user is not
// entitled. Trial users ARE entitled, so nothing changes for them — the blur only
// appears once a trial expires without a purchase.
//
// The content gets allowsHitTesting(false) rather than disabled(true): disabled
// propagates through the environment and would swallow the overlay's own taps.
private struct PremiumLock: ViewModifier {

    @ObservedObject private var premium = PremiumManager.shared

    func body(content: Content) -> some View {
        if PremiumManager.isFeatureUnlocked(premium.entitlementState) {
            content
        } else {
            content
                .blur(radius: 6)
                .allowsHitTesting(false)
                .overlay {
                    Button { premium.showPaywall = true } label: {
                        Color.clear
                            .contentShape(Rectangle())
                            .overlay(PremiumLockBadge())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("premiumLock")
                    .accessibilityLabel("Premium feature. Tap to unlock.")
                }
        }
    }
}

struct PremiumLockBadge: View {
    var body: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: 15, weight: .bold))
            .foregroundColor(.white)
            .padding(9)
            .background(Circle().fill(Color(red: 0.52, green: 0.22, blue: 0.88)))
            .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
    }
}

extension View {
    // Marks a view as premium. No-op for entitled users.
    func premiumLocked() -> some View { modifier(PremiumLock()) }
}

struct MainTabView: View {

    @ObservedObject private var premium = PremiumManager.shared
    @AppStorage("colorSchemePreference") private var colorSchemePreference = "system"

    private var preferredScheme: ColorScheme? {
        switch colorSchemePreference {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil
        }
    }

    var body: some View {
        TabView {
            ContentView()
                .tabItem { Label("Chat",      systemImage: "bubble.left.and.bubble.right.fill") }
            InsightsView()
                .tabItem { Label("Insights",  systemImage: "chart.bar.fill") }
            GuidedExercisesView()
                .tabItem { Label("Exercises", systemImage: "lungs.fill") }
            JournalView()
                .tabItem { Label("Journal",   systemImage: "book.fill") }
            SettingsView()
                .tabItem { Label("Settings",  systemImage: "gearshape.fill") }
        }
        .tint(Color(red: 0.52, green: 0.22, blue: 0.88))
        .preferredColorScheme(preferredScheme)
        // Presented here, not in SettingsView: showPaywall is a flag on the shared
        // PremiumManager, but a sheet only presents from the hierarchy it is attached
        // to. While it lived in Settings, every gated feature in the other four tabs
        // could set the flag and show nothing at all.
        .sheet(isPresented: $premium.showPaywall) { PremiumPaywallView() }
    }
}

//*======================================================================*//
// MARK: - Brain Logo
//*======================================================================*//

struct BrainLogoView: View {

    var size: CGFloat = 80

    var body: some View {

        ZStack {
            brainCircle(color: Color(red: 0.85, green: 0.18, blue: 0.12), w: 0.70, ox:  0.02, oy: -0.18)
            brainCircle(color: Color(red: 0.90, green: 0.58, blue: 0.05), w: 0.58, ox: -0.26, oy: -0.02)
            brainCircle(color: Color(red: 0.12, green: 0.50, blue: 0.18), w: 0.62, ox: -0.16, oy:  0.22)
            brainCircle(color: Color(red: 0.08, green: 0.62, blue: 0.58), w: 0.70, ox:  0.12, oy:  0.18)
            brainCircle(color: Color(red: 0.22, green: 0.48, blue: 0.88), w: 0.52, ox:  0.28, oy:  0.04)
            brainCircle(color: Color(red: 0.48, green: 0.14, blue: 0.72), w: 0.50, ox:  0.24, oy: -0.22)
            brainCircle(color: Color(red: 0.88, green: 0.28, blue: 0.52), w: 0.32, ox:  0.04, oy: -0.04)
        }
        .mask(
            Image(systemName: "brain")
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        )
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private func brainCircle(color: Color, w: CGFloat, ox: CGFloat, oy: CGFloat) -> some View {
        Circle()
            .fill(color.opacity(0.88))
            .frame(width: size * w, height: size * w)
            .offset(x: size * ox, y: size * oy)
    }
}

//*======================================================================*//
// MARK: - Holographic Brain (Splash Only)
//*======================================================================*//

struct HolographicBrainView: View {

    var size: CGFloat = 120

    @State private var huePhase:   Double  = 0
    @State private var glowScale:  CGFloat = 0.85
    @State private var shimmerX:   CGFloat = -0.5
    @State private var lightAlpha: [Double] = [0, 0, 0]
    @State private var tick:       Int     = 0

    private let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {

            // Pulsing glow halos
            ForEach(0..<3, id: \.self) { i in
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(hue: hmod(huePhase + Double(i) * 0.15),
                                      saturation: 0.9, brightness: 1.0).opacity(0.25),
                                .clear
                            ],
                            center: .center,
                            startRadius: 2,
                            endRadius: size * (0.55 + CGFloat(i) * 0.20)
                        )
                    )
                    .frame(
                        width:  size * (1.5 + CGFloat(i) * 0.40),
                        height: size * (1.3 + CGFloat(i) * 0.35)
                    )
                    .scaleEffect(glowScale + CGFloat(i) * 0.04)
                    .blur(radius: 8 + CGFloat(i) * 4)
            }

            // Neon lightning arcs
            Canvas { ctx, sz in
                let cx = sz.width / 2
                let cy = sz.height / 2
                let arcs: [(CGPoint, CGPoint, CGPoint)] = [
                    (CGPoint(x: cx - size*0.58, y: cy - size*0.28),
                     CGPoint(x: cx - size*0.32, y: cy - size*0.52),
                     CGPoint(x: cx - size*0.10, y: cy - size*0.20)),
                    (CGPoint(x: cx + size*0.42, y: cy - size*0.38),
                     CGPoint(x: cx + size*0.60, y: cy + size*0.02),
                     CGPoint(x: cx + size*0.36, y: cy + size*0.26)),
                    (CGPoint(x: cx - size*0.20, y: cy + size*0.46),
                     CGPoint(x: cx + size*0.06, y: cy + size*0.64),
                     CGPoint(x: cx + size*0.30, y: cy + size*0.40)),
                ]
                for (i, arc) in arcs.enumerated() {
                    guard lightAlpha[i] > 0.05 else { continue }
                    var p = Path()
                    p.move(to: arc.0)
                    p.addQuadCurve(to: arc.2, control: arc.1)
                    ctx.stroke(
                        p,
                        with: .color(
                            Color(hue: hmod(huePhase + Double(i) * 0.22),
                                  saturation: 0.95, brightness: 1.0)
                                .opacity(lightAlpha[i])
                        ),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                    )
                }
            }
            .frame(width: size * 2.4, height: size * 2.4)

            // Holographic brain circles
            ZStack {
                hBrainCircle(hue: hmod(huePhase + 0.00), w: 0.70, ox:  0.02, oy: -0.18)
                hBrainCircle(hue: hmod(huePhase + 0.14), w: 0.58, ox: -0.26, oy: -0.02)
                hBrainCircle(hue: hmod(huePhase + 0.28), w: 0.62, ox: -0.16, oy:  0.22)
                hBrainCircle(hue: hmod(huePhase + 0.42), w: 0.70, ox:  0.12, oy:  0.18)
                hBrainCircle(hue: hmod(huePhase + 0.57), w: 0.52, ox:  0.28, oy:  0.04)
                hBrainCircle(hue: hmod(huePhase + 0.71), w: 0.50, ox:  0.24, oy: -0.22)
                hBrainCircle(hue: hmod(huePhase + 0.85), w: 0.32, ox:  0.04, oy: -0.04)
            }
            .mask(
                Image(systemName: "brain")
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
            )
            .frame(width: size, height: size)

            // Shimmer sweep (Rectangle masked to brain shape)
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.50), .clear],
                        startPoint: UnitPoint(x: shimmerX - 0.20, y: 0.2),
                        endPoint:   UnitPoint(x: shimmerX + 0.20, y: 0.8)
                    )
                )
                .frame(width: size, height: size)
                .mask(
                    Image(systemName: "brain")
                        .resizable()
                        .scaledToFit()
                        .frame(width: size, height: size)
                )
                .blendMode(.overlay)
        }
        .onReceive(timer) { _ in
            tick     += 1
            huePhase  = hmod(huePhase + 0.006)
            glowScale = CGFloat(0.88 + sin(Double(tick) * 0.18) * 0.07)
            shimmerX += 0.03
            if shimmerX > 1.5 { shimmerX = -0.5 }
            if tick % 4 == 0 {
                for i in 0..<3 { lightAlpha[i] = Double.random(in: 0...0.72) }
            }
        }
    }

    private func hmod(_ v: Double) -> Double {
        let r = v.truncatingRemainder(dividingBy: 1.0)
        return r < 0 ? r + 1.0 : r
    }

    @ViewBuilder
    private func hBrainCircle(hue: Double, w: CGFloat, ox: CGFloat, oy: CGFloat) -> some View {
        Circle()
            .fill(Color(hue: hue, saturation: 0.85, brightness: 0.95).opacity(0.9))
            .frame(width: size * w, height: size * w)
            .offset(x: size * ox, y: size * oy)
    }
}

//*======================================================================*//
// MARK: - Typewriter Text
//*======================================================================*//

struct TypewriterText: View {

    let fullText:  String
    let speed:     Double

    @State private var displayed  = ""
    @State private var showCursor = true
    @State private var typingDone = false

    private let cursorTimer = Timer
        .publish(every: 0.5, on: .main, in: .common)
        .autoconnect()

    var body: some View {

        HStack(spacing: 2) {
            Text(displayed)
                .font(.system(size: 42, weight: .bold))
                .foregroundColor(.white)
            Rectangle()
                .fill(Color.white)
                .frame(width: 3, height: 42)
                .opacity(typingDone ? 0 : (showCursor ? 1 : 0))
                .animation(.easeInOut(duration: 0.1), value: showCursor)
        }
        .onAppear {
            displayed = ""
            for (i, char) in fullText.enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + speed * Double(i)) {
                    displayed += String(char)
                    if displayed.count == fullText.count {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                            withAnimation { typingDone = true }
                        }
                    }
                }
            }
        }
        .onReceive(cursorTimer) { _ in showCursor.toggle() }
    }
}

//*======================================================================*//
// MARK: - Splash Screen
//*======================================================================*//

struct SplashScreen: View {

    @State private var showIcon     = false
    @State private var showTitle    = false
    @State private var showSubtitle = false
    @State private var isActive     = false
    @State private var bgHue: Double = 0.70
    @State private var particles: [(CGFloat, CGFloat, CGFloat, Double)] = []

    private let titleText   = "Jabe"
    private let typingSpeed: Double = 0.09
    private let bgTimer = Timer.publish(every: 0.10, on: .main, in: .common).autoconnect()

    var body: some View {

        if isActive {
            MainTabView().transition(.opacity)
        } else {
            ZStack {

                // Slowly shifting gradient background
                LinearGradient(
                    colors: [
                        Color(hue: bgHue, saturation: 0.72, brightness: 0.52),
                        Color(hue: (bgHue + 0.09).truncatingRemainder(dividingBy: 1.0),
                              saturation: 0.88, brightness: 0.28),
                    ],
                    startPoint: .topLeading,
                    endPoint:   .bottomTrailing
                )
                .ignoresSafeArea()

                // Ambient glow orb (fixed size — no GeometryReader needed)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(hue: (bgHue + 0.05).truncatingRemainder(dividingBy: 1.0),
                                      saturation: 0.75, brightness: 0.95).opacity(0.16),
                                .clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 250
                        )
                    )
                    .frame(width: 500, height: 500)
                    .offset(y: -80)
                    .blendMode(.screen)

                // Floating particles via Canvas (fills screen, no GeometryReader)
                Canvas { ctx, sz in
                    for p in particles {
                        let r = p.2 / 2
                        let rect = CGRect(
                            x: sz.width * p.0 - r,
                            y: sz.height * p.1 - r,
                            width: p.2, height: p.2
                        )
                        ctx.fill(Path(ellipseIn: rect),
                                 with: .color(Color.white.opacity(p.3)))
                    }
                }
                .ignoresSafeArea()

                // Main content — direct ZStack child so it is always centered
                VStack(spacing: 20) {
                    HolographicBrainView(size: 120)
                        .frame(width: 288, height: 200)
                        .opacity(showIcon ? 1 : 0)
                        .scaleEffect(showIcon ? 1 : 0.4)
                        .animation(.spring(response: 0.6, dampingFraction: 0.65), value: showIcon)

                    if showTitle {
                        TypewriterText(fullText: titleText, speed: typingSpeed)
                    }

                    Text("Your emotional wellness companion")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.75))
                        .opacity(showSubtitle ? 1 : 0)
                        .offset(y: showSubtitle ? 0 : 8)
                        .animation(.easeOut(duration: 0.6), value: showSubtitle)
                }
            }
            .onReceive(bgTimer) { _ in
                bgHue = (bgHue + 0.002).truncatingRemainder(dividingBy: 1.0)
            }
            .onAppear {
                particles = (0..<20).map { _ in
                    (CGFloat.random(in: 0.05...0.95),
                     CGFloat.random(in: 0.05...0.95),
                     CGFloat.random(in: 2...5),
                     Double.random(in: 0.08...0.32))
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showIcon = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { showTitle = true }
                let typingDuration = typingSpeed * Double(titleText.count) + 0.8
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8 + typingDuration) { showSubtitle = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8 + typingDuration + 1.0) {
                    withAnimation(.easeInOut(duration: 0.8)) { isActive = true }
                }
            }
        }
    }
}

//*======================================================================*//
// MARK: - App Entry
//*======================================================================*//

@main
struct JabeWellnessAIApp: App {

    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    var body: some Scene {
        WindowGroup {
            if hasSeenOnboarding {
                SplashScreen()
            } else {
                OnboardingView()
            }
        }
    }
}
