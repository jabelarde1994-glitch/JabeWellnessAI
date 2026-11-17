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
import CoreMotion
import StoreKit
import Security
import AuthenticationServices

//*======================================================================*//
// MARK: - Secrets
//*======================================================================*//

enum Secrets {

    // The app holds no Groq key: the Worker does. Do not add one back here.

    // Simulator-only: the simulator cannot attest, so DEBUG simulator builds present this to the
    // Worker instead. Compiled out of every device build so it cannot ship in the binary.
    #if DEBUG && targetEnvironment(simulator)
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

    private static let emotionMap: [(MoodType, [String])] = [

        (.happy, [
            "happy", "excited", "great", "amazing", "joy", "joyful", "love",
            "wonderful", "fantastic", "glad", "thrilled", "elated", "cheerful",
            "delighted", "blessed", "grateful", "hopeful", "proud"
        ]),

        (.sad, [
            "sad", "cry", "crying", "cried", "cries", "lonely", "depressed", "hopeless", "empty",
            "broken", "miss", "grief", "sorrow", "tears", "miserable",
            "heartbroken", "lost", "tired", "exhausted", "drained", "numb"
        ]),

        (.anxious, [
            "anxious", "worried", "nervous", "scared", "afraid",
            "stressed", "panic", "overwhelmed", "dread", "uneasy", "tense",
            "restless", "fear", "overthinking", "overthink", "panicking", "panicked",
            "racing thoughts", "thoughts are racing", "mind is racing"
        ]),

        (.angry, [
            "angry", "mad", "furious", "frustrated", "rage", "annoyed",
            "irritated", "hate", "livid", "outraged", "bitter", "upset",
            "resentful", "fed up"
        ])
    ]

    // A keyword matches a whole word or the word plus a regular ending, so "hated" and "sadness" count
    // but "made" (mad), "mission" (miss) and "crystal" (cry) don't. Irregular forms are listed above.
    // Built once: every counted word form per mood, and multi-word phrases as word sequences.
    private static let endings = ["", "s", "es", "d", "ed", "ing", "ly", "ness", "ful"]
    private static let matchers: [(mood: MoodType, forms: Set<String>, phrases: [[String]])] =
        emotionMap.map { mood, keywords in
            let forms = keywords.filter { !$0.contains(" ") }.flatMap { k in endings.map { k + $0 } }
            let phrases = keywords.filter { $0.contains(" ") }.map { $0.split(separator: " ").map(String.init) }
            return (mood, Set(forms), phrases)
        }

    func detectEmotion(from text: String) -> MoodType {

        let negations: Set<String> = ["not", "no", "never", "don't", "dont", "without", "isn't", "isnt", "am not"]
        // Curly apostrophes (the iPhone default) are straightened so "don’t" still negates, and emoji or
        // other symbols split words so "happy😊" still reads as "happy".
        let words = text.lowercased()
            .replacingOccurrences(of: "[\u{2018}\u{2019}\u{02BC}]", with: "'", options: .regularExpression)
            .replacingOccurrences(of: "[^\\p{L}\\p{N}'-]+", with: " ", options: .regularExpression)
            .split(separator: " ")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "'-")) }
            .filter { !$0.isEmpty }

        func negated(at i: Int) -> Bool {
            words[max(0, i - 2) ..< i].contains(where: negations.contains)
        }

        // Ties go to the mood listed first (happy, sad, anxious, angry), never to a random one.
        var best: (mood: MoodType, score: Int) = (.neutral, 0)

        for matcher in Self.matchers {
            var score = 0
            for (i, word) in words.enumerated() where matcher.forms.contains(word) && !negated(at: i) {
                score += 1
            }
            for phrase in matcher.phrases where words.count >= phrase.count {
                for i in 0 ... (words.count - phrase.count)
                    where Array(words[i ..< i + phrase.count]) == phrase && !negated(at: i) {
                    score += 1
                }
            }
            if score > best.score { best = (matcher.mood, score) }
        }

        return best.mood
    }
}

//*======================================================================*//
// MARK: - Safety Checker
//*======================================================================*//

final class SafetyChecker {

    // Kept specific on purpose: a match replaces the AI reply with the crisis response, so a phrase
    // that also covers everyday venting ("this is killing me") would cut those conversations off.
    private static let riskyKeywords = [
        "suicide", "suicidal", "kill myself", "self harm", "self-harm",
        "end my life", "want to die", "don't want to live",
        "hurt myself", "take my life", "no reason to live",
        "can't go on", "ending it", "end it all",
        "unalive", "cutting myself", "took an overdose", "take an overdose",
        "don't see the point anymore", "better off without me", "better off dead",
        "wish i was dead", "wish i were dead", "wish i wasn't here", "rather be dead",
        "don't want to be here anymore", "nothing to live for", "not worth living",
        "isn't worth living", "sleep and never wake up", "never wake up again",
        "self-harming", "self harming", "self-harmed", "self harmed", "killing myself",
        "hurting myself", "harming myself", "ending my life", "taking my life",
        "wanted to die", "wanting to die"
    ].map(normalized)

    func containsRisk(_ text: String) -> Bool {
        let text = Self.normalized(text)
        return Self.riskyKeywords.contains { text.contains($0) }
    }

    // Lowercases, drops apostrophes of any style (the iPhone keyboard types a curly ’ by default,
    // and many people type none), turns other punctuation and whitespace runs into single spaces,
    // and pads both ends, so phrases match whole words only ("ending it" no longer hits "spending it").
    private static func normalized(_ text: String) -> String {
        let words = text.lowercased()
            .replacingOccurrences(of: "['\u{2018}\u{2019}\u{02BC}]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "[^\\p{L}\\p{N}-]+", with: " ", options: .regularExpression)
            .split(separator: " ")
        return " " + words.joined(separator: " ") + " "
    }

    // 988 reaches only the US and Canada; every other listed country has its own line. Numbers checked
    // 2026-10-11 against Find A Helpline and, for the Philippines, DOH's December 2025 / January 2026
    // announcements. Any other region gets the local-emergency + directory fallback. The region is read
    // on the device from Settings → Language & Region; nothing is sent anywhere.
    private struct CrisisLines {
        let message: String   // the block shown in the chat crisis response
        let short: String     // the clause shown on the onboarding disclaimer page
    }

    private static let unitedStates = CrisisLines(
        message: "📞 988 Suicide & Crisis Lifeline\nCall or text 988 — available 24/7, free & confidential\n\n💬 Crisis Text Line\nText HOME to 741741",
        short: "call or text 988 (Suicide & Crisis Lifeline) anytime")

    // US territories (PR, GU, VI, AS, MP) are served by 988 too.
    private static let linesByRegion: [String: CrisisLines] = [
        "US": unitedStates, "PR": unitedStates, "GU": unitedStates, "VI": unitedStates,
        "AS": unitedStates, "MP": unitedStates,
        "CA": CrisisLines(
            message: "📞 9-8-8 Suicide Crisis Helpline\nCall or text 988 — available 24/7",
            short: "call or text 988 (Suicide Crisis Helpline) anytime"),
        "PH": CrisisLines(
            message: "📞 NCMH Crisis Hotline\nCall 1553, or 0917-899-8727 / 0919-057-1553 — available 24/7",
            short: "call the NCMH Crisis Hotline at 1553 or 0917-899-8727, 24/7"),
        "GB": CrisisLines(
            message: "📞 Samaritans\nCall 116 123 — available 24/7, free",
            short: "call Samaritans on 116 123, free, 24/7"),
        "IE": CrisisLines(
            message: "📞 Samaritans\nCall 116 123 — available 24/7, free\n\n💬 Text About It\nText 50808 — available 24/7, free",
            short: "call Samaritans on 116 123 or text 50808, 24/7"),
        "AU": CrisisLines(
            message: "📞 Lifeline\nCall 13 11 14 — available 24/7, or text 0477 13 11 14",
            short: "call Lifeline on 13 11 14, 24/7"),
        "NZ": CrisisLines(
            message: "📞 Need to talk?\nCall or text 1737 — free, any time",
            short: "call or text 1737, free, any time"),
        "IN": CrisisLines(
            message: "📞 Tele-MANAS\nCall 14416 — available 24/7, free",
            short: "call Tele-MANAS on 14416, free, 24/7"),
        "SG": CrisisLines(
            message: "📞 Samaritans of Singapore\nCall 1767 — available 24/7",
            short: "call Samaritans of Singapore on 1767, 24/7"),
        "MY": CrisisLines(
            message: "📞 Talian HEAL\nCall 15555\n\n📞 Befrienders Kuala Lumpur\nCall 03-7627 2929",
            short: "call Talian HEAL on 15555 or Befrienders on 03-7627 2929"),
        "ZA": CrisisLines(
            message: "📞 SADAG Suicide Crisis Line\nCall 0800 567 567 — free\n\n📞 Lifeline South Africa\nCall 0861 322 322 — available 24/7",
            short: "call the SADAG Suicide Crisis Line on 0800 567 567"),
    ]

    private static let fallback = CrisisLines(
        message: "📞 Call your local emergency number, or find a free crisis line for your country at findahelpline.com",
        short: "call your local emergency number, or find a free crisis line at findahelpline.com")

    // The Region setting can be wrong (travel, expats), so a listed country's message also says what to do elsewhere.
    private static let elsewhere = "If you're somewhere else, call your local emergency number."

    static var currentRegion: String? { Locale.current.region?.identifier }

    static func crisisLine(forRegion region: String?) -> String {
        "If you're in crisis, \((listedLines(forRegion: region) ?? fallback).short)."
    }

    private static func listedLines(forRegion region: String?) -> CrisisLines? {
        region.flatMap { linesByRegion[$0.uppercased()] }
    }

    var crisisResponse: String { crisisResponse(forRegion: Self.currentRegion) }

    func crisisResponse(forRegion region: String?) -> String {
        let listed = Self.listedLines(forRegion: region)
        let resources = (listed ?? Self.fallback).message
        let elsewhere = listed == nil ? "" : "\n\n" + Self.elsewhere
        return """
        You are not alone, and what you're feeling matters deeply. 💙

        Please reach out for support right now:

        \(resources)\(elsewhere)

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
// MARK: - Review Prompt
//*======================================================================*//

/// When it is reasonable to ask for an App Store rating. Pure, so every rule is unit-tested.
/// Apple decides whether anything is shown (and caps it at 3 a year); this only picks the moment.
enum ReviewPromptGate {

    static let minStreak        = 3
    static let minInstallDays   = 7
    static let minDaysBetween   = 120

    static func shouldAsk(longestStreak: Int, installDate: Date?, lastAsked: Date?,
                          lastAskedVersion: String?, currentVersion: String, now: Date) -> Bool {
        guard longestStreak >= minStreak, let installDate else { return false }
        guard lastAskedVersion != currentVersion else { return false }
        let cal = Calendar.current
        guard let installAge = cal.dateComponents([.day], from: installDate, to: now).day,
              installAge >= minInstallDays else { return false }
        if let lastAsked {
            guard let sinceAsk = cal.dateComponents([.day], from: lastAsked, to: now).day,
                  sinceAsk >= minDaysBetween else { return false }
        }
        return true
    }
}

enum ReviewPrompt {

    private static let lastAskedKey   = "mm_reviewLastAsked"
    private static let lastVersionKey = "mm_reviewLastVersion"

    /// Records the ask and then calls `ask`, only when the gate allows it. Recording comes first so a
    /// crash or an early dismissal can never cause a second ask for the same version.
    static func askIfEligible(
        defaults: UserDefaults = .standard,
        installDate: Date? = TrialAnchorStore.load(),
        version: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
        now: Date = Date(),
        ask: () -> Void
    ) {
        let lastAsked = defaults.object(forKey: lastAskedKey) as? Date
        guard ReviewPromptGate.shouldAsk(
            longestStreak: defaults.integer(forKey: "mm_longestStreak"),
            installDate: installDate,
            lastAsked: lastAsked,
            lastAskedVersion: defaults.string(forKey: lastVersionKey),
            currentVersion: version,
            now: now
        ) else { return }

        defaults.set(now,     forKey: lastAskedKey)
        defaults.set(version, forKey: lastVersionKey)
        ask()
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

    // True while any VoiceInputManager has the microphone open. The breathing voice guide reads it so
    // it never takes the audio session from a live recording. (The session's category stays .record
    // after a recording ends, so the category alone can't tell.) Locked: stopRecording can run on the
    // recognizer's callback queue.
    nonisolated private static let liveLock = NSLock()
    nonisolated(unsafe) private static var liveCount = 0
    nonisolated(unsafe) private var countedLive = false
    nonisolated static var isAnyRecording: Bool { liveLock.withLock { liveCount > 0 } }

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

        Self.liveLock.withLock {
            if !countedLive { countedLive = true; Self.liveCount += 1 }
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
        Self.liveLock.withLock {
            if countedLive { countedLive = false; Self.liveCount -= 1 }
        }
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

    /// Injectable so tests can stub the Worker's responses; the app always uses `.shared`.
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

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

    /// How much conversation, in characters, goes to the model with each message (~2K tokens).
    /// The Worker rejects bodies over 20,000 characters, and before this cap a long chat crossed
    /// that line and failed on every later message. It also keeps one long chat from spending
    /// most of the per-minute Groq token allowance every install shares. Saved history is
    /// unaffected; Jabe just stops seeing the oldest part of a very long conversation.
    static let historyCharBudget = 8_000

    /// The newest messages whose combined text fits in `maxChars`, oldest first. The newest
    /// message is always kept, even alone over budget, so the user's latest words are never
    /// dropped.
    static func recentHistory(_ history: [ChatMessage], maxChars: Int) -> [ChatMessage] {
        var kept: [ChatMessage] = []
        var used = 0
        for message in history.reversed() {
            used += message.content.count
            if used > maxChars && !kept.isEmpty { break }
            kept.append(message)
        }
        return kept.reversed()
    }

    func send(
        history: [ChatMessage],
        mood: MoodType
    ) async throws -> String {

        let url = Self.workerBaseURL.appendingPathComponent("chat")

        var messages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt]
        ]

        for message in Self.recentHistory(history, maxChars: Self.historyCharBudget) {
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
    /// short-lived App Attest token; the simulator cannot attest, so a Debug simulator build
    /// presents the dev bypass secret instead (that branch, and the secret, exist in no other build).
    private func authorizedData(for request: URLRequest) async throws -> (Data, URLResponse) {
        var request = request
        #if DEBUG && targetEnvironment(simulator)
        request.setValue(Secrets.devBypassSecret, forHTTPHeaderField: "X-Dev-Bypass")
        #else
        let token = try await Self.attestation.validToken()
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        #endif
        return try await session.data(for: request)
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

        currentInput = ""

        // A crisis message skips mood detection: it is tagged Neutral, leaves the header mood alone,
        // and the reply carries no mood, so the exchange never counts as a mood in history or Insights.
        if safetyChecker.containsRisk(text) {
            append(ChatMessage(content: text, isUser: true, mood: .neutral, timestamp: Date()))
            append(ChatMessage(content: safetyChecker.crisisResponse, isUser: false, mood: nil, timestamp: Date()))
            haptic(.warning)
            return
        }

        let mood = emotionDetector.detectEmotion(from: text)
        if mood != .neutral { currentMood = mood }

        append(ChatMessage(content: text, isUser: true, mood: currentMood, timestamp: Date()))

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
                 subtitle: "Jabe is an AI wellness companion, not a licensed therapist or medical provider. " + SafetyChecker.crisisLine(forRegion: SafetyChecker.currentRegion),
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
    @AppStorage(AppleAccount.userIDKey)    private var appleUserID    = ""
    @AppStorage(AppleAccount.givenNameKey) private var appleGivenName = ""
    @State private var signInMessage: String?
    @Environment(\.colorScheme) private var colorScheme

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
                                Text(premium.product?.displayPrice ?? "$3.99").font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                }

                // Optional Sign in with Apple: only the Apple user ID and first name, kept on this device,
                // so the breathing coach can greet you by name. No server call.
                Section {
                    if appleUserID.isEmpty {
                        SignInWithAppleButton(.signIn) { request in
                            request.requestedScopes = [.fullName]
                        } onCompletion: { result in
                            signInMessage = AppleSignIn.handle(result)
                        }
                        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                        .frame(height: 44)
                        .accessibilityIdentifier("signInWithApple")
                    } else {
                        LabeledContent("Signed in with Apple", value: appleGivenName)
                        Button("Sign Out", role: .destructive) {
                            AppleAccount.signOut()
                            signInMessage = nil
                        }
                    }
                    if let signInMessage {
                        Text(signInMessage).font(.caption).foregroundColor(.secondary)
                    }
                } header: {
                    Text("Account")
                } footer: {
                    Text("Optional. Lets your breathing coach greet you by your first name. Only your Apple sign-in ID and first name are kept, on this iPhone. Nothing is sent to Jabe.")
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
                    LabeledContent("App",       value: "Jabe Wellness")
                    LabeledContent("Version",   value: appVersion)
                    LabeledContent("Developer", value: "Jabe")
                    LabeledContent("AI Model",  value: AIService.modelDisplayName)
                    LabeledContent("Storage",   value: "Local device")
                }
            }
            .navigationTitle("Settings")
            .task { await AppleSignIn.refreshCredentialState() }
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

// MARK: Breathing Voice Guide

/// The four box-breathing phases, in order. They set the rhythm of Alex's voice; the lungs follow the
/// user's real breathing (BreathTracker), never this timer.
nonisolated enum BreathingPhase: CaseIterable {
    case inhale, holdAfterInhale, exhale, holdAfterExhale

    var label: String {
        switch self {
        case .inhale:                            return "Inhale"
        case .holdAfterInhale, .holdAfterExhale: return "Hold"
        case .exhale:                            return "Exhale"
        }
    }

    /// The breath the user should be making. Holds are not checked against the sensor.
    var expectedBreath: Breath? {
        switch self {
        case .inhale:                            return .inhaling
        case .exhale:                            return .exhaling
        case .holdAfterInhale, .holdAfterExhale: return nil
        }
    }

    /// Joel (2026-11-16, Revision 3): every phase is 3 seconds.
    var seconds: Int { 3 }
}

/// Everything Alex says, and how (round 4: warm, chat-like wording; Apple's normal speed with a little
/// more energy; commas instead of ellipses so there are no long gaps inside a phrase).
nonisolated enum BreathingCueScript {
    static let cycles = 4
    static var cycleSeconds: Int { BreathingPhase.allCases.reduce(0) { $0 + $1.seconds } }
    static var header: String {
        BreathingPhase.allCases.map { "\($0.label) \($0.seconds)s" }.joined(separator: " · ")
    }

    static let coachName = "Alex"

    /// "Hi Sam, …" with the first name from Sign in with Apple, otherwise "Hi there, …".
    static func opening(name: String?) -> String {
        let first = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hello = first.isEmpty ? "Hi there" : "Hi \(first)"
        return "\(hello), I'm Alex, your breathing coach. It's so nice to see you. How are you feeling right now?"
    }

    static let thanks            = "Thank you for sharing that with me."
    static let readyQuestion     = "Are you ready to breathe together?"
    static let readyAgain        = "Take your time. Just say yes when you'd like to begin."
    static let declined          = "That's completely okay. I'll be right here whenever you'd like to breathe together."
    static let settle            = "Let's get comfortable first. Rest your phone gently on your chest."
    static let calibrate         = "Now breathe in and out naturally, and I'll follow along with you."
    static let calibrateAgain    = "I couldn't quite feel your breathing yet, and that's okay. Let's try once more. Breathe in and out naturally, with your phone resting on your chest."
    static let letsBegin         = "Lovely, I can feel your breathing. Let's take a slow breath in together."
    static let pause             = "Let's rest for a moment. Breathe in with me whenever you're ready, and we'll continue from here."
    static let congratulations   = "Wonderful, you've completed your breathing for today. Thank you for taking this time for yourself."
    static let anotherRound      = "Would you like to do another round?"
    static let anotherRoundAgain = "Just say yes if you'd like another round, or no if you're all done."
    static let goAgain           = "Lovely, let's go again together."
    static let goodbye           = "That's okay. Thank you for breathing with me today. See you again tomorrow."
    static let noMotionSensor    = "I can't feel your breathing on this device, so we can't breathe together here yet."

    /// On screen only, while paused.
    static let pauseTip = "Tip: rest your phone flat on your chest or belly."

    /// Round 4, item 2: no "I'm ready" button. If Alex can't listen, she says why.
    static func cannotHear(permissionRefused: Bool) -> String {
        permissionRefused
            ? "I'd love to hear you, but I can't use the microphone yet. Please allow Microphone and Speech Recognition for Jabe Wellness in Settings, then open Breathing again."
            : "I can't hear you right now. Please check your connection, then open Breathing again in a little while."
    }

    static func cue(for phase: BreathingPhase) -> String {
        switch phase {
        case .inhale:          return "Breathe in, two, three."
        case .holdAfterInhale: return "Gently hold, two, three."
        case .exhale:          return "Now breathe out, two, three."
        case .holdAfterExhale: return "And hold, two, three."
        }
    }

    /// Every line Alex can say, for the tests and the task log.
    static func allSpokenLines(name: String?) -> [String] {
        [opening(name: name), opening(name: nil), thanks, readyQuestion, readyAgain, declined, settle, calibrate,
         calibrateAgain, letsBegin, pause, congratulations, anotherRound, anotherRoundAgain, goAgain, goodbye,
         noMotionSensor, cannotHear(permissionRefused: true), cannotHear(permissionRefused: false)]
            + BreathingPhase.allCases.map(cue(for:))
    }

    // Round 4, item 1: Apple's normal speed (AVSpeechUtteranceDefaultSpeechRate = 0.5), pitch up 5%.
    static let voiceLanguage = "en-US"
    static let voiceRate:  Float = 0.5
    static let voicePitch: Float = 1.05

    /// Every line is spoken with these settings and no extra silence before or after it.
    static func utterance(_ text: String, voice: AVSpeechSynthesisVoice?) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice              = voice
        utterance.rate               = voiceRate
        utterance.pitchMultiplier    = voicePitch
        utterance.preUtteranceDelay  = 0
        utterance.postUtteranceDelay = 0
        return utterance
    }

    /// How long Alex listens for an answer.
    static let listenSeconds: Double = 8
    /// Once someone has started answering "How are you feeling?", this much quiet means they're done.
    static let answerSettleSeconds: Double = 1.5
    /// With the voice off, how long each spoken line stays on screen before the next step.
    static let readingSeconds: Double = 2.5
}

/// The talk around the exercise. Before: Alex asks how you feel (the answer is never stored or read;
/// it is only used to know you've finished speaking), thanks you if you said something, then asks if
/// you're ready. Yes starts; no ends gently; no answer asks once more, then ends gently.
/// After a finished session: "Would you like to do another round?" Yes goes again; no says goodbye;
/// no answer asks once more, then goodbye.
nonisolated enum BreathingConversation {

    nonisolated enum Step: Equatable {
        case askFeeling
        case askReady(attempt: Int, thankFirst: Bool)
        case begin
        case endGently
        case askAnotherRound(attempt: Int)
        case goAgain
        case goodbye
    }

    nonisolated enum Event {
        case feelingHeard, feelingSilent
        case ready(ReadyAnswer?)            // a yes/no answer; nil = no answer
    }

    static let firstStep    = Step.askFeeling
    static let afterSession = Step.askAnotherRound(attempt: 1)
    static let maximumAttempts = 2

    static func next(after step: Step, _ event: Event) -> Step {
        switch (step, event) {
        case (.askFeeling, .feelingHeard):   return .askReady(attempt: 1, thankFirst: true)
        case (.askFeeling, .feelingSilent):  return .askReady(attempt: 1, thankFirst: false)
        case (.askReady, .ready(.some(.yes))): return .begin
        case (.askReady, .ready(.some(.no))):  return .endGently
        case (.askReady(let attempt, _), .ready(.none)):
            return attempt < maximumAttempts ? .askReady(attempt: attempt + 1, thankFirst: false) : .endGently
        case (.askAnotherRound, .ready(.some(.yes))): return .goAgain
        case (.askAnotherRound, .ready(.some(.no))):  return .goodbye
        case (.askAnotherRound(let attempt), .ready(.none)):
            return attempt < maximumAttempts ? .askAnotherRound(attempt: attempt + 1) : .goodbye
        default:
            return step
        }
    }
}

/// The spoken answer to "Are you ready…?" and "another round?". Whole words only, any case; a "no" word wins, so
/// "I'm not ready" is never read as yes, and "yesterday" is not "yes".
nonisolated enum ReadyAnswer: Equatable {
    case yes, no

    private static let noWords: Set<String>  = ["no", "nope", "nah", "not", "later", "don't", "dont", "stop", "cancel"]
    private static let yesWords: Set<String> = ["yes", "yeah", "yep", "yup", "sure", "ready", "ok", "okay", "go", "start", "begin"]

    static func parse(_ transcript: String) -> ReadyAnswer? {
        let words = transcript.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .components(separatedBy: CharacterSet.letters.union(CharacterSet(charactersIn: "'")).inverted)
            .filter { !$0.isEmpty }
        if words.contains(where: { noWords.contains($0) })  { return .no }
        if words.contains(where: { yesWords.contains($0) }) { return .yes }
        return nil
    }
}

/// The exercise, phase by phase (round 4, item 6: never skip the breathing). A breathing phase with no
/// breath detected pauses the session; it never ends it. Only Done or a spoken "no" ends a session.
/// After a pause the same cycle runs again. A cycle counts only when both its breaths were detected,
/// so finishing all cycles is the only way the streak counts.
nonisolated struct BreathingCoach {

    nonisolated enum Action: Equatable { case nextPhase, pause, nextCycle, finished }

    private(set) var completedCycles = 0
    private(set) var pauses          = 0

    mutating func phaseEnded(_ phase: BreathingPhase, breathDetected: Bool) -> Action {
        if phase.expectedBreath != nil && !breathDetected {
            pauses += 1
            return .pause
        }
        guard phase == .holdAfterExhale else { return .nextPhase }
        completedCycles += 1
        return completedCycles >= BreathingCueScript.cycles ? .finished : .nextCycle
    }

    var countsForStreak: Bool { completedCycles >= BreathingCueScript.cycles }
}

/// The voice choice on the breathing screen, remembered on the device. Alex (the coach, a female
/// voice) is the default; "Men" keeps its label from Revision 2.
nonisolated enum BreathingVoiceChoice: String, CaseIterable {
    case alex, men

    static let storageKey    = "breathingVoiceGender"
    static let defaultChoice = BreathingVoiceChoice.alex

    var label: String { self == .alex ? "Alex" : "Men" }
}

/// A plain copy of the voice fields the picker needs, so the choice can be unit-tested without
/// depending on which voices a given device or simulator has installed.
nonisolated struct BreathingVoiceCandidate: Equatable {
    let identifier: String
    let name:       String
    let language:   String
    let gender:     AVSpeechSynthesisVoiceGender
    let quality:    AVSpeechSynthesisVoiceQuality
    let isNovelty:  Bool
    let isPersonal: Bool

    /// Apple's old MacinTalk voices (Fred, Ralph, …) sound more robotic than the current ones.
    var isLegacy: Bool { identifier.hasPrefix("com.apple.speech.synthesis.voice.") }
    /// "Samantha (Enhanced)" → "Samantha".
    var baseName: String { name.components(separatedBy: " (").first ?? name }
}

nonisolated extension BreathingVoiceCandidate {
    init(voice: AVSpeechSynthesisVoice) {
        self.init(identifier: voice.identifier, name: voice.name, language: voice.language,
                  gender: voice.gender, quality: voice.quality,
                  isNovelty:  voice.voiceTraits.contains(.isNoveltyVoice),
                  isPersonal: voice.voiceTraits.contains(.isPersonalVoice))
    }
}

/// Alex: the best installed US-English female voice, Premium then Enhanced then standard; at the same
/// quality, the calmer-sounding names first. Men: Aaron if installed, otherwise the best other male
/// en-US voice, Apple's current voices before the old MacinTalk ones. Never a novelty voice, the
/// user's Personal Voice, or the child voice "Junior". nil = use the system default en-US voice.
nonisolated enum BreathingVoicePicker {
    static let calmFemaleNames = ["Ava", "Zoe", "Samantha", "Allison", "Susan", "Nicky"]

    static func pick(_ choice: BreathingVoiceChoice, from all: [BreathingVoiceCandidate],
                     language: String = BreathingCueScript.voiceLanguage) -> BreathingVoiceCandidate? {
        let usable = all.filter { $0.language == language && !$0.isNovelty && !$0.isPersonal }
        switch choice {
        case .alex:
            func calmRank(_ c: BreathingVoiceCandidate) -> Int {
                calmFemaleNames.firstIndex(of: c.baseName) ?? calmFemaleNames.count
            }
            return usable.filter { $0.gender == .female }.min { a, b in
                if a.quality != b.quality   { return a.quality.rawValue > b.quality.rawValue }
                if calmRank(a) != calmRank(b) { return calmRank(a) < calmRank(b) }
                if a.isLegacy != b.isLegacy { return !a.isLegacy }
                return a.name < b.name
            }
        case .men:
            func preferred(_ a: BreathingVoiceCandidate, _ b: BreathingVoiceCandidate) -> Bool {
                if a.isLegacy != b.isLegacy { return !a.isLegacy }
                if a.quality != b.quality   { return a.quality.rawValue < b.quality.rawValue }
                return a.name < b.name
            }
            if let aaron = usable.filter({ $0.baseName == "Aaron" }).min(by: preferred) { return aaron }
            return usable.filter { $0.gender == .male && $0.baseName != "Junior" }.min(by: preferred)
        }
    }
}

/// The breathing streak: one completed session per calendar day; the next day adds one; a missed day
/// starts again at 1. Separate from the mood check-in streak (StreakManager, mm_ keys), which it never
/// reads or writes. Stored on the device under its own four keys.
nonisolated enum BreathingStreak {

    nonisolated struct State: Equatable {
        var current:   Int
        var longest:   Int
        var totalDays: Int
        var lastDay:   String?          // "yyyy-MM-dd" in the user's calendar

        static let empty = State(current: 0, longest: 0, totalDays: 0, lastDay: nil)
    }

    static let milestones = [7, 14, 21, 30]

    private static let currentKey   = "breathingStreakCurrent"
    private static let longestKey   = "breathingStreakLongest"
    private static let totalDaysKey = "breathingStreakTotalDays"
    private static let lastDayKey   = "breathingStreakLastDay"

    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private static func date(fromKey key: String, calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// Whole days from the last completed day to `date`; nil if there is no last day.
    private static func daysSinceLast(_ state: State, on date: Date, calendar: Calendar) -> Int? {
        guard let last = state.lastDay.flatMap({ Self.date(fromKey: $0, calendar: calendar) }),
              let now = Self.date(fromKey: dayKey(date, calendar: calendar), calendar: calendar) else { return nil }
        return calendar.dateComponents([.day], from: last, to: now).day
    }

    /// The state after a session completed on `date`. A second session on the same day changes nothing.
    static func record(_ state: State, on date: Date, calendar: Calendar = .current) -> State {
        let today = dayKey(date, calendar: calendar)
        guard state.lastDay != today else { return state }
        let gap = daysSinceLast(state, on: date, calendar: calendar) ?? Int.max
        guard gap > 0 else { return state }      // the clock went backwards: count nothing
        var next = state
        next.current   = gap == 1 ? state.current + 1 : 1
        next.longest   = max(state.longest, next.current)
        next.totalDays = state.totalDays + 1
        next.lastDay   = today
        return next
    }

    /// The streak to show before a session: still alive if the last session was today or yesterday.
    static func displayed(_ state: State, on date: Date, calendar: Calendar = .current) -> Int {
        guard let gap = daysSinceLast(state, on: date, calendar: calendar), (0...1).contains(gap) else { return 0 }
        return state.current
    }

    /// The milestone reached by this session, if it reached one just now.
    static func newMilestone(before: State, after: State) -> Int? {
        after != before && milestones.contains(after.current) ? after.current : nil
    }

    static func highestBadge(for streak: Int) -> Int? {
        milestones.last { $0 <= streak }
    }

    static func load(from defaults: UserDefaults = .standard) -> State {
        State(current:   defaults.integer(forKey: currentKey),
              longest:   defaults.integer(forKey: longestKey),
              totalDays: defaults.integer(forKey: totalDaysKey),
              lastDay:   defaults.string(forKey: lastDayKey))
    }

    static func save(_ state: State, to defaults: UserDefaults = .standard) {
        defaults.set(state.current,   forKey: currentKey)
        defaults.set(state.longest,   forKey: longestKey)
        defaults.set(state.totalDays, forKey: totalDaysKey)
        if let lastDay = state.lastDay { defaults.set(lastDay, forKey: lastDayKey) }
        else { defaults.removeObject(forKey: lastDayKey) }
    }
}

/// THE 30-DAY REWARD, in one place so it is easy to change (open decision for Joel in the task log).
/// Today: once someone has reached a 30-day breathing streak, the lungs use a calm mint-to-indigo
/// theme, and each completed session shows a card with their total days.
nonisolated enum BreathingReward {
    static let unlockDays = 30
    static let circleColors: [Color] = [.mint, .indigo]
    static let ringColor: Color      = .indigo
    static let cardTitle             = "Your 30-day calm"

    static func isUnlocked(by state: BreathingStreak.State) -> Bool { state.longest >= unlockDays }

    static func cardDetail(totalDays: Int) -> String {
        "\(totalDays) \(totalDays == 1 ? "day" : "days") of breathing"
    }
}

/// One reading of the phone's motion: gravity direction (tilt) and how much it is being moved.
nonisolated struct BreathMotionSample {
    let time: TimeInterval               // seconds since boot (CoreMotion's clock)
    let gravity: SIMD3<Double>           // unit vector, in g
    let userAcceleration: Double         // g; near 0 when the phone is resting
}

/// Which way the smoothed tilt is moving along the breathing axis; `handled` = the phone is being moved.
nonisolated enum BreathMovement: Equatable { case rising, falling, still, handled }

/// What the detector believes the user is doing right now. `unknown` = phone handled, or the direction
/// of "in" is not known yet.
nonisolated enum Breath: Equatable { case inhaling, exhaling, still, unknown }

/// Set by calibration: the tilt direction breathing moves along, the size of one natural breath, and how
/// far the smoothed signal must move before it counts as a breath (so small movements don't count).
nonisolated struct BreathProfile: Equatable {
    let axis: SIMD3<Double>
    let amplitude: Double
    let threshold: Double
}

nonisolated enum BreathMath {
    /// Exponential smoothing weight for a step of `dt` seconds with time constant `tau`.
    static func alpha(dt: Double, tau: Double) -> Double { dt <= 0 ? 0 : 1 - exp(-dt / tau) }
    static func length(_ v: SIMD3<Double>) -> Double { (v * v).sum().squareRoot() }
}

/// Round 4, item 7: Alex says "breathe in and out naturally" and the detector learns from that one
/// natural cycle. The breathing axis is the main direction the (smoothed) tilt moves in; the threshold
/// is 30% of one natural breath, and never less than three times the sensor's jitter.
/// APPROXIMATE: checked only against synthetic signals; real accuracy is known only on a real iPhone.
nonisolated enum BreathCalibration {
    static let seconds: Double     = 8          // one natural breath takes about 3 to 6 s
    static let minimumSamples      = 80         // 4 s at 20 Hz
    static let thresholdFraction   = 0.3
    static let minimumAmplitude    = 0.1 * Double.pi / 180      // 0.1° of tilt
    static let minimumThreshold    = 0.03 * Double.pi / 180
    static let maximumMovement     = 0.04       // average g of user acceleration; above this the phone is handled
    static let smoothingSeconds    = 0.4

    static func profile(from samples: [BreathMotionSample]) -> BreathProfile? {
        guard samples.count >= minimumSamples, let first = samples.first else { return nil }
        let movement = samples.reduce(0) { $0 + $1.userAcceleration } / Double(samples.count)
        guard movement <= maximumMovement else { return nil }

        var smoothed: [SIMD3<Double>] = []
        var current = first.gravity
        var lastTime = first.time
        for sample in samples {
            current += (sample.gravity - current) * BreathMath.alpha(dt: sample.time - lastTime, tau: smoothingSeconds)
            lastTime = sample.time
            smoothed.append(current)
        }
        guard let axis = principalAxis(smoothed) else { return nil }

        let level = smoothed.map { ($0 * axis).sum() }
        let amplitude = (level.max() ?? 0) - (level.min() ?? 0)

        // Sensor jitter from the raw readings' second differences (a slow breath barely changes them).
        let raw = samples.map { ($0.gravity * axis).sum() }
        var sumOfSquares = 0.0
        for i in 2..<raw.count {
            let d = raw[i] - 2 * raw[i - 1] + raw[i - 2]
            sumOfSquares += d * d
        }
        let jitter = (sumOfSquares / Double(raw.count - 2)).squareRoot() / 6.0.squareRoot()

        guard amplitude >= minimumAmplitude, amplitude >= 4 * jitter else { return nil }
        let threshold = max(thresholdFraction * amplitude, 3 * jitter, minimumThreshold)
        return BreathProfile(axis: axis, amplitude: amplitude, threshold: threshold)
    }

    /// The direction the points spread along most (power iteration), signed so its largest part is positive.
    private static func principalAxis(_ points: [SIMD3<Double>]) -> SIMD3<Double>? {
        guard !points.isEmpty else { return nil }
        let mean = points.reduce(SIMD3<Double>.zero, +) / Double(points.count)
        let deviations = points.map { $0 - mean }
        guard var axis = deviations.max(by: { BreathMath.length($0) < BreathMath.length($1) }),
              BreathMath.length(axis) > 1e-12 else { return nil }
        axis /= BreathMath.length(axis)
        for _ in 0..<25 {
            var next = SIMD3<Double>.zero
            for d in deviations { next += d * (d * axis).sum() }
            let size = BreathMath.length(next)
            guard size > 1e-20 else { return nil }
            axis = next / size
        }
        let largest = [axis.x, axis.y, axis.z].max { abs($0) < abs($1) } ?? 1
        return largest < 0 ? -axis : axis
    }
}

/// The live breath detector, fed 20 readings a second. The tilt along the calibrated axis is smoothed
/// (0.4 s), and a breath is only seen once it has moved by the calibrated threshold from its last
/// turning point; small wobbles and slow drifts below that never count. No new progress for 0.8 s
/// means still (a hold). The first guided inhale sets which direction means "in".
/// APPROXIMATE: a phone resting on a chest; real accuracy is known only on a real iPhone.
nonisolated struct BreathTracker {
    static let smoothingSeconds    = 0.4
    static let stillAfterSeconds   = 0.8
    static let handledAcceleration = 0.06      // smoothed g; above this the phone is being moved
    static let accelerationSmoothingSeconds = 0.3

    let profile: BreathProfile
    private(set) var inhaleSign: Int?
    private(set) var movement = BreathMovement.still

    private var level: Double?
    private var acceleration: Double?
    private var lastTime: TimeInterval?
    private var direction = 0
    private var extreme = 0.0
    private var progressMark = 0.0
    private var lastProgress: TimeInterval = 0
    private var low = 0.0
    private var high = 0.0

    init(profile: BreathProfile, inhaleSign: Int? = nil) {
        self.profile = profile
        self.inhaleSign = inhaleSign
    }

    var breath: Breath {
        switch movement {
        case .still:   return .still
        case .handled: return .unknown
        case .rising, .falling:
            guard let inhaleSign else { return .unknown }
            return (movement == .rising ? 1 : -1) == inhaleSign ? .inhaling : .exhaling
        }
    }

    /// `learnInhale`: true during a guided inhale; the first clear movement then defines "in".
    mutating func add(_ sample: BreathMotionSample, learnInhale: Bool) {
        let dt = lastTime.map { max(0, sample.time - $0) } ?? 0
        lastTime = sample.time
        let x = (sample.gravity * profile.axis).sum()
        let current = level.map { $0 + (x - $0) * BreathMath.alpha(dt: dt, tau: Self.smoothingSeconds) } ?? x
        let isFirst = level == nil
        level = current
        let shake = acceleration.map {
            $0 + (sample.userAcceleration - $0) * BreathMath.alpha(dt: dt, tau: Self.accelerationSmoothingSeconds)
        } ?? sample.userAcceleration
        acceleration = shake

        if isFirst { becomeStill(at: current) }
        guard shake <= Self.handledAcceleration else {
            becomeStill(at: current)
            movement = .handled
            return
        }

        let threshold = profile.threshold
        switch direction {
        case 1:
            extreme = max(extreme, current)
            if current >= progressMark + 0.1 * threshold { progressMark = current; lastProgress = sample.time }
            if extreme - current >= threshold { turn(-1, at: current, time: sample.time) }
            else if sample.time - lastProgress > Self.stillAfterSeconds { becomeStill(at: current) }
        case -1:
            extreme = min(extreme, current)
            if current <= progressMark - 0.1 * threshold { progressMark = current; lastProgress = sample.time }
            if current - extreme >= threshold { turn(1, at: current, time: sample.time) }
            else if sample.time - lastProgress > Self.stillAfterSeconds { becomeStill(at: current) }
        default:
            low  = min(low, current)
            high = max(high, current)
            if current - low >= threshold { turn(1, at: current, time: sample.time) }
            else if high - current >= threshold { turn(-1, at: current, time: sample.time) }
        }
        movement = direction == 1 ? .rising : direction == -1 ? .falling : .still
        if learnInhale, inhaleSign == nil, direction != 0 { inhaleSign = direction }
    }

    private mutating func turn(_ newDirection: Int, at x: Double, time: TimeInterval) {
        direction    = newDirection
        extreme      = x
        progressMark = x
        lastProgress = time
    }

    private mutating func becomeStill(at x: Double) {
        direction = 0
        low  = x
        high = x
    }
}

/// Whether the breath a phase asks for was seen at any moment during it, including a breath already
/// under way when the phase started (a resume after a pause starts on the user's own inhale).
nonisolated struct BreathPhaseWatch {
    let phase: BreathingPhase
    private(set) var detected: Bool

    init(phase: BreathingPhase, current: Breath) {
        self.phase = phase
        detected = phase.expectedBreath.map { $0 == current } ?? false
    }

    mutating func observe(_ breath: Breath) {
        if let expected = phase.expectedBreath, breath == expected { detected = true }
    }
}

/// Round 4, item 4: the lungs follow the detector, not the timer. They widen while an inhale is seen,
/// narrow on an exhale, and hold still otherwise and while the exercise is paused.
nonisolated enum LungsMotion {
    static let restScale: CGFloat = 1.0
    static let fullScale: CGFloat = 1.5
    static let secondsRestToFull  = 2.5

    static func next(_ scale: CGFloat, breath: Breath, elapsed: Double, paused: Bool) -> CGFloat {
        guard !paused else { return scale }
        let step = CGFloat(max(0, elapsed) / secondsRestToFull) * (fullScale - restScale)
        switch breath {
        case .inhaling:          return min(fullScale, scale + step)
        case .exhaling:          return max(restScale, scale - step)
        case .still, .unknown:   return scale
        }
    }
}

/// Round 4, item 8: Sign in with Apple. Only the Apple user identifier and the first name are kept, on
/// this device, under their own two keys; nothing is sent to Jabe. Apple sends the name only on the
/// first sign-in, so a later sign-in without one keeps the saved name (for the same Apple ID only).
nonisolated enum AppleAccount {
    static let userIDKey    = "appleSignInUserID"
    static let givenNameKey = "appleSignInGivenName"

    static func userID(in defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: userIDKey).flatMap { $0.isEmpty ? nil : $0 }
    }

    static func givenName(in defaults: UserDefaults = .standard) -> String? {
        let name = defaults.string(forKey: givenNameKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? nil : name
    }

    static func save(userID: String, givenName: String?, to defaults: UserDefaults = .standard) {
        let name = givenName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let sameUser = defaults.string(forKey: userIDKey) == userID
        defaults.set(userID, forKey: userIDKey)
        if !name.isEmpty { defaults.set(name, forKey: givenNameKey) }
        else if !sameUser { defaults.removeObject(forKey: givenNameKey) }
    }

    static func signOut(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: userIDKey)
        defaults.removeObject(forKey: givenNameKey)
    }
}

/// The calls to Apple's Sign in with Apple service (AuthenticationServices). No Jabe server is involved.
enum AppleSignIn {

    /// Forgets the saved account if the user has stopped using Sign in with Apple for this app
    /// (Settings → Apple ID → Sign in with Apple). Only an explicit "revoked" clears it.
    static func refreshCredentialState() async {
        guard let id = AppleAccount.userID() else { return }
        let state = try? await ASAuthorizationAppleIDProvider().credentialState(forUserID: id)
        if state == .revoked { AppleAccount.signOut() }
    }

    /// Saves the result; returns a message to show, or nil.
    static func handle(_ result: Result<ASAuthorization, Error>) -> String? {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                return "Sign in didn't finish. Please try again."
            }
            AppleAccount.save(userID: credential.user, givenName: credential.fullName?.givenName)
            return nil
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code == .canceled { return nil }
            return "Sign in with Apple isn't available right now. Please try again later."
        }
    }
}

#if DEBUG
/// SIMULATOR TESTING ONLY, compiled out of Release. The simulator has no real microphone input and no
/// motion sensor, so these launch arguments stand in for them:
///   -breathingDebugAnswers "fine,yes,no"   → the answer to each question in turn ("silent" = no answer,
///                                             "denied" = microphone refused); none left = no answer
///   -breathingDebugMotion "follow,still,…"  → a fake chest: calibrates on natural breathing, then for
///                                             each guided inhale breathes along ("follow") or stays still;
///                                             after a pause it breathes in again after 8 s
nonisolated enum BreathingDebug {
    static var rawAnswers: String? { UserDefaults.standard.string(forKey: "breathingDebugAnswers") }
    static var rawMotion: String?  { UserDefaults.standard.string(forKey: "breathingDebugMotion") }
    static let resumeAfterSeconds  = 8.0

    static func answers(from raw: String?) -> [String] {
        (raw ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    static func inhalePlan(from raw: String?) -> [Bool] {
        answers(from: raw).map { $0 == "follow" }
    }
}
#endif

/// The lungs keep the old circle's size rules. At full size they are drawn 1.5x their frame, so they
/// spill a quarter of their size past the frame on each side (55 pt for 220 pt). scaleEffect takes up
/// no layout space, so that room is reserved above and below; without it the full-size visual covered
/// the "Box Breathing" heading (pre-existing on main). On short screens (iPhone SE) it shrinks.
nonisolated enum BreathingLayout {
    static let preferredCircleSize: CGFloat = 220
    static let minimumCircleSize: CGFloat   = 120
    static let maxScale: CGFloat            = LungsMotion.fullScale
    static let columnSpacing: CGFloat       = 28
    /// Everything in the column except the lungs: heading, two description lines, up to three status
    /// lines, the controls row, and the four 28 pt gaps, with a little to spare.
    static let otherContentHeight: CGFloat  = 330

    static func overflow(for size: CGFloat) -> CGFloat { size * (maxScale - 1) / 2 }

    /// The largest visual (up to 220 pt) whose full-size drawing fits beside the other content.
    static func circleSize(forHeight height: CGFloat) -> CGFloat {
        let fitting = ((height - otherContentHeight) / maxScale).rounded(.down)
        return min(preferredCircleSize, max(minimumCircleSize, fitting))
    }
}

/// One lung, drawn from code (no image assets), in a unit square. The viewer's left is the person's
/// right lung; the other side is mirrored with a cardiac notch on its inner edge.
struct LungLobeShape: Shape {
    let mirrored: Bool

    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + (mirrored ? 1 - x : x) * rect.width, y: rect.minY + y * rect.height)
        }
        let inner: CGFloat = mirrored ? 0.40 : 0.45      // the cardiac notch on the person's left lung
        var path = Path()
        path.move(to: p(0.40, 0.17))
        path.addCurve(to: p(0.13, 0.48), control1: p(0.30, 0.11), control2: p(0.16, 0.27))
        path.addCurve(to: p(0.10, 0.86), control1: p(0.09, 0.64), control2: p(0.06, 0.79))
        path.addCurve(to: p(0.30, 0.89), control1: p(0.14, 0.94), control2: p(0.22, 0.90))
        path.addCurve(to: p(inner, 0.84), control1: p(0.36, 0.89), control2: p(inner - 0.02, 0.88))
        path.addCurve(to: p(0.44, 0.58), control1: p(inner + 0.02, 0.74), control2: p(0.47, 0.65))
        path.addCurve(to: p(0.42, 0.45), control1: p(0.41, 0.54), control2: p(0.40, 0.49))
        path.addCurve(to: p(0.40, 0.17), control1: p(0.45, 0.36), control2: p(0.44, 0.22))
        path.closeSubpath()
        return path
    }
}

/// The faint lines between the lobes (two on the person's right lung, one on the left).
struct LungFissuresShape: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height) }
        var path = Path()
        path.move(to: p(0.40, 0.38)); path.addQuadCurve(to: p(0.17, 0.80), control: p(0.27, 0.60))
        path.move(to: p(0.14, 0.55)); path.addQuadCurve(to: p(0.33, 0.54), control: p(0.24, 0.57))
        path.move(to: p(0.60, 0.38)); path.addQuadCurve(to: p(0.83, 0.80), control: p(0.73, 0.60))
        return path
    }
}

/// The airway's branches inside each lung.
struct BronchialTreeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for mirrored in [false, true] {
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: rect.minX + (mirrored ? 1 - x : x) * rect.width, y: rect.minY + y * rect.height)
            }
            path.move(to: p(0.39, 0.46)); path.addQuadCurve(to: p(0.27, 0.32), control: p(0.33, 0.42))
            path.move(to: p(0.39, 0.46)); path.addQuadCurve(to: p(0.22, 0.62), control: p(0.31, 0.52))
            path.move(to: p(0.39, 0.46)); path.addQuadCurve(to: p(0.33, 0.76), control: p(0.38, 0.62))
            path.move(to: p(0.31, 0.38)); path.addLine(to: p(0.33, 0.30))
            path.move(to: p(0.28, 0.55)); path.addLine(to: p(0.20, 0.52))
            path.move(to: p(0.36, 0.64)); path.addLine(to: p(0.27, 0.71))
        }
        return path
    }
}

/// Trachea and main bronchi: one centre line, drawn as a soft tube.
struct TracheaShape: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height) }
        var path = Path()
        path.move(to: p(0.50, 0.03))
        path.addLine(to: p(0.50, 0.33))
        path.addQuadCurve(to: p(0.39, 0.46), control: p(0.45, 0.36))
        path.move(to: p(0.50, 0.33))
        path.addQuadCurve(to: p(0.61, 0.46), control: p(0.55, 0.36))
        return path
    }
}

/// The rings of cartilage across the trachea.
struct TracheaRingsShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for y in stride(from: 0.07, through: 0.30, by: 0.035) {
            path.move(to: CGPoint(x: rect.minX + 0.474 * rect.width, y: rect.minY + y * rect.height))
            path.addQuadCurve(to: CGPoint(x: rect.minX + 0.526 * rect.width, y: rect.minY + y * rect.height),
                              control: CGPoint(x: rect.midX, y: rect.minY + (y + 0.012) * rect.height))
        }
        return path
    }
}

/// The breathing visual (round 4, item 9): softly shaded lungs with a natural trachea, all in code.
/// No text is drawn on it (item 4). The lungs widen with `scale`, which comes from the breath detector.
struct LungsView: View {
    let size: CGFloat
    let scale: CGFloat
    let colors: [Color]
    let ring: Color

    private var light: Color { colors.first ?? .teal }
    private var deep: Color  { colors.last ?? .blue }

    var body: some View {
        ZStack {
            // The airway sits behind the lungs, so the bronchi disappear into them as in a real chest.
            ZStack {
                TracheaShape()
                    .stroke(deep.opacity(0.32), style: StrokeStyle(lineWidth: size * 0.065, lineCap: .round, lineJoin: .round))
                TracheaShape()
                    .stroke(light.opacity(0.30), style: StrokeStyle(lineWidth: size * 0.03, lineCap: .round, lineJoin: .round))
                TracheaRingsShape()
                    .stroke(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 1, lineCap: .round))
            }

            ZStack {
                lobe(mirrored: false, highlight: UnitPoint(x: 0.27, y: 0.40))
                lobe(mirrored: true,  highlight: UnitPoint(x: 0.73, y: 0.40))
                LungFissuresShape()
                    .stroke(deep.opacity(0.25), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
                BronchialTreeShape()
                    .stroke(deep.opacity(0.22), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            }
            .scaleEffect(x: scale, y: 1 + (scale - 1) * 0.5, anchor: UnitPoint(x: 0.5, y: 0.2))
        }
        .frame(width: size, height: size)
        .shadow(color: deep.opacity(0.18), radius: 10, y: 6)
        .animation(.linear(duration: 0.12), value: scale)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Lungs")
        .accessibilityValue(scale > LungsMotion.restScale + 0.05 ? "breathing in" : "at rest")
        .accessibilityIdentifier("breathingLungs")
    }

    private func lobe(mirrored: Bool, highlight: UnitPoint) -> some View {
        let shape = LungLobeShape(mirrored: mirrored)
        return ZStack {
            shape.fill(RadialGradient(colors: [light.opacity(0.55), deep.opacity(0.38), deep.opacity(0.22)],
                                      center: highlight, startRadius: 0, endRadius: size * 0.42))
            shape.stroke(deep.opacity(0.35), lineWidth: size * 0.05)          // soft shade along the edges
                .blur(radius: size * 0.02)
                .clipShape(shape)
            Ellipse()
                .fill(Color.white.opacity(0.28))
                .frame(width: size * 0.10, height: size * 0.22)
                .position(x: size * highlight.x, y: size * highlight.y)
                .blur(radius: size * 0.03)
                .clipShape(shape)
            shape.stroke(ring.opacity(0.45), lineWidth: 1.2)
        }
    }
}

/// Reads the phone's tilt 20 times a second during the exercise. CoreMotion device motion needs no
/// permission prompt; readings stay in memory for the session and are never stored or sent.
/// Calibration samples one natural cycle; after that every reading feeds the BreathTracker, whose
/// verdict moves the lungs (held still while paused).
final class BreathMotionMonitor: ObservableObject {
    @Published private(set) var breath: Breath = .still
    @Published private(set) var lungScale: CGFloat = LungsMotion.restScale

    /// While paused the lungs hold still.
    var isPaused = false
    /// True during a guided inhale (or while waiting to resume): the first clear movement defines "in".
    var learnsInhale = false

    private var manager = CMMotionManager()
    private var tracker: BreathTracker?
    private var calibrationSamples: [BreathMotionSample] = []
    private var isCalibrating = false
    private var lastTime: TimeInterval?

    var isCalibrated: Bool { tracker != nil }

    var isAvailable: Bool {
        #if DEBUG
        if usesFakeChest { return true }
        #endif
        return manager.isDeviceMotionAvailable
    }

    func start() {
        guard isAvailable else { return }
        lastTime = nil
        #if DEBUG
        if usesFakeChest { startFakeChest(); return }
        #endif
        guard !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 20
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            let g = motion.gravity, a = motion.userAcceleration
            let sample = BreathMotionSample(time: motion.timestamp, gravity: SIMD3(g.x, g.y, g.z),
                                            userAcceleration: (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot())
            self?.handle(sample)
        }
    }

    func beginCalibration() {
        calibrationSamples.removeAll()
        isCalibrating = true
    }

    /// True if one natural cycle was clear enough to set the thresholds.
    func finishCalibration() -> Bool {
        isCalibrating = false
        defer { calibrationSamples.removeAll() }
        guard let profile = BreathCalibration.profile(from: calibrationSamples) else { return false }
        tracker = BreathTracker(profile: profile, inhaleSign: tracker?.inhaleSign)
        return true
    }

    /// Stops the sensor. The calibration is kept for "another round" on this screen.
    func stop() {
        manager.stopDeviceMotionUpdates()
        #if DEBUG
        fakeTimer?.invalidate()
        fakeTimer = nil
        #endif
        isCalibrating = false
        calibrationSamples.removeAll()
        if let profile = tracker?.profile {
            tracker = BreathTracker(profile: profile, inhaleSign: tracker?.inhaleSign)
        }
        if breath != .still { breath = .still }
    }

    /// The lungs settle back to rest at the end of a session.
    func settleLungs() {
        lungScale = LungsMotion.restScale
    }

    private func handle(_ sample: BreathMotionSample) {
        let elapsed = lastTime.map { max(0, sample.time - $0) } ?? 0
        lastTime = sample.time
        if isCalibrating {
            calibrationSamples.append(sample)
            if calibrationSamples.count > 400 { calibrationSamples.removeFirst(calibrationSamples.count - 400) }
        }
        guard var current = tracker else { return }
        current.add(sample, learnInhale: learnsInhale)
        tracker = current
        if current.breath != breath { breath = current.breath }
        let next = LungsMotion.next(lungScale, breath: current.breath, elapsed: elapsed, paused: isPaused)
        if next != lungScale { lungScale = next }
    }

    #if DEBUG
    /// Simulator only: a fake chest the screen tells what to do.
    enum FakeChest { case natural, breatheIn, breatheOut, hold }
    var fakeChest = FakeChest.hold
    private var fakeTimer: Timer?
    private var fakeAngle = 0.0
    private var fakeClock = 0.0
    private var usesFakeChest: Bool { BreathingDebug.rawMotion != nil }

    private func startFakeChest() {
        fakeTimer?.invalidate()
        fakeTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.fakeTick() }
        }
    }

    private func fakeTick() {
        fakeClock += 1.0 / 20
        let step = 0.45 / 20                               // degrees per tick: about 1.35° in 3 s
        switch fakeChest {
        case .natural:    fakeAngle = 0.3 * (1 - cos(2 * .pi * fakeClock / 5))
        case .breatheIn:  fakeAngle = min(1.2 + 0.6, fakeAngle + step)
        case .breatheOut: fakeAngle = max(0, fakeAngle - step)
        case .hold:       break
        }
        let r = fakeAngle * .pi / 180
        handle(BreathMotionSample(time: fakeClock, gravity: SIMD3(0, sin(r), -cos(r)), userAcceleration: 0.003))
    }
    #endif
}

/// Speaks for Alex on the device (AVSpeechSynthesizer; no network, no text leaves the phone). Owns the
/// audio session only while guiding, and never touches it while a microphone recording is live.
final class BreathingVoiceGuide: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {

    // var, not let: keeps it main-actor isolated (AVSpeechSynthesizer is not Sendable).
    private var synthesizer = AVSpeechSynthesizer()
    private var voice = AVSpeechSynthesisVoice(language: BreathingCueScript.voiceLanguage)
    private var ownsAudioSession = false
    private var releaseWhenIdle  = false
    private var pending          = 0
    private var completions: [ObjectIdentifier: () -> Void] = [:]

    /// The voice actually in use, for the task log and the simulator check.
    var voiceIdentifier: String { voice?.identifier ?? "system default" }

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Switches to Alex or the male voice (falls back to the system default en-US voice).
    func use(_ choice: BreathingVoiceChoice) {
        let installed = AVSpeechSynthesisVoice.speechVoices().map(BreathingVoiceCandidate.init(voice:))
        if let pick = BreathingVoicePicker.pick(choice, from: installed),
           let chosen = AVSpeechSynthesisVoice(identifier: pick.identifier) {
            voice = chosen
        } else {
            voice = AVSpeechSynthesisVoice(language: BreathingCueScript.voiceLanguage)
        }
    }

    /// Play through the silent switch and lower other audio while guiding. Leaves the session alone
    /// while a microphone recording is live, so the recording is never cut off.
    func prepare() {
        releaseWhenIdle = false
        #if os(iOS)
        guard !ownsAudioSession, !VoiceInputManager.isAnyRecording else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .spokenAudio, options: .duckOthers)
            try session.setActive(true)
            ownsAudioSession = true
        } catch {
            print("Breathing audio session setup failed:", error)
        }
        #endif
    }

    /// `completion` runs once the line has finished, or straight away if speech is stopped.
    func speak(_ text: String, completion: (() -> Void)? = nil) {
        let utterance = BreathingCueScript.utterance(text, voice: voice)
        if let completion { completions[ObjectIdentifier(utterance)] = completion }
        pending += 1
        synthesizer.speak(utterance)
    }

    /// A phase line: cut off whatever is left of the last one first, so the voice stays on the beat.
    func speakOnBeat(_ text: String) {
        if synthesizer.isSpeaking { silence() }
        speak(text)
    }

    /// Cut off anything being said, keeping the audio session.
    func silence() {
        synthesizer.stopSpeaking(at: .immediate)
        pending = 0
        let waiting = completions.values
        completions.removeAll()
        waiting.forEach { $0() }
    }

    /// Hand the audio session to the microphone while Alex listens.
    func releaseForListening() {
        releaseAudioSession()
    }

    /// Let anything still queued (the closing line) finish, then hand the audio back.
    func finish() {
        releaseWhenIdle = true
        if pending == 0 { releaseAudioSession() }
    }

    /// Stop now: Done tapped, sheet closed, or voice switched off.
    func stop() {
        silence()
        releaseAudioSession()
    }

    private func releaseAudioSession() {
        releaseWhenIdle = false
        #if os(iOS)
        guard ownsAudioSession else { return }
        ownsAudioSession = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    private func utteranceEnded(_ id: ObjectIdentifier) {
        pending = max(0, pending - 1)
        completions.removeValue(forKey: id)?()
        if releaseWhenIdle && pending == 0 { releaseAudioSession() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.utteranceEnded(id) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.utteranceEnded(id) }
    }
}

// MARK: Box Breathing

struct BreathingExerciseView: View {

    private enum Stage { case starting, talking, listening, cannotHear, settling, running, paused, ended }
    private enum Listening { case feeling, answer }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview

    @AppStorage("breathingVoiceEnabled") private var voiceEnabled = true
    @AppStorage(BreathingVoiceChoice.storageKey) private var voiceChoice = BreathingVoiceChoice.defaultChoice
    @StateObject private var guide    = BreathingVoiceGuide()
    @StateObject private var listener = VoiceInputManager()     // this screen's own mic, for Alex's questions
    @StateObject private var motion   = BreathMotionMonitor()

    @State private var stage: Stage   = .starting
    @State private var step           = BreathingConversation.firstStep
    @State private var listeningFor   = Listening.feeling
    @State private var lastHeard      = Date.distantPast
    @State private var run            = 0      // bumps on every start and stop; stale timers do nothing
    @State private var caption        = ""
    @State private var listeningNote  = ""
    @State private var isActive       = true
    @State private var phaseStep      = 0      // bumps on every phase change; drives the haptic pulse
    @State private var currentPhase: BreathingPhase?
    @State private var phaseWatch: BreathPhaseWatch?
    @State private var awaitingResume = false
    @State private var coach          = BreathingCoach()
    @State private var sessionDone    = false
    @State private var greetingName: String?
    @State private var shownStreak    = 0
    @State private var streak: BreathingStreak.State?
    @State private var newBadge: Int?
    @State private var rewardUnlocked = false
    #if DEBUG
    @State private var debugAnswers: [String] = []
    @State private var debugInhalePlan: [Bool] = []
    #endif

    var body: some View {
        NavigationView {
            GeometryReader { geo in
                // 220 pt on most iPhones; smaller on short screens so the full-size lungs fit.
                let size = BreathingLayout.circleSize(forHeight: geo.size.height)
                VStack(spacing: BreathingLayout.columnSpacing) {
                    Spacer()

                    if sessionDone && rewardUnlocked && stage != .running {
                        // Same height as the full-size visual, so nothing below moves.
                        rewardCard(height: size * BreathingLayout.maxScale)
                    } else {
                        LungsView(size: size, scale: motion.lungScale,
                                  colors: rewardUnlocked ? BreathingReward.circleColors : [Color.teal, Color.blue],
                                  ring: rewardUnlocked ? BreathingReward.ringColor : Color.teal)
                            .padding(.vertical, BreathingLayout.overflow(for: size))   // room for the full-size lungs
                    }

                    VStack(spacing: 8) {
                        Text("Box Breathing").font(.headline)
                        Text("\(BreathingCueScript.header)\nRepeat \(BreathingCueScript.cycles) cycles for best results")
                            .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)   // never cut to one line
                        statusLines
                    }

                    controls

                    Spacer()
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .padding(24)
            .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.7), trigger: phaseStep)
            .navigationTitle("Breathing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { endSession(); dismiss() }
                }
            }
            .onAppear(perform: appeared)
            .onDisappear { endSession() }
            .onChange(of: voiceEnabled) { _, on in voiceSwitched(on) }
            .onChange(of: voiceChoice) { _, choice in guide.use(choice) }
            .onChange(of: listener.transcript) { _, said in heard(said) }
            .onChange(of: listener.isRecording) { _, recording in
                // Permission callbacks are asynchronous: a recording that opens after Alex has moved on
                // (Done, timeout, an answer already handled) is closed at once.
                if recording && stage != .listening { listener.stopRecording() }
            }
            .onChange(of: listener.permissionDenied) { _, denied in
                if denied && stage == .listening { stopListening(); cannotHear(permissionRefused: true) }
            }
            .onChange(of: motion.breath) { _, breath in breathChanged(breath) }
        }
    }

    // MARK: Pieces

    private func rewardCard(height: CGFloat) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles").font(.title).foregroundStyle(BreathingReward.ringColor)
            Text(BreathingReward.cardTitle)
                .font(.headline).multilineTextAlignment(.center)
                .lineLimit(2).minimumScaleFactor(0.8)
            Text(BreathingReward.cardDetail(totalDays: streak?.totalDays ?? 0))
                .font(.subheadline).foregroundColor(.secondary)
                .lineLimit(2).minimumScaleFactor(0.8)
        }
        .padding(20)
        .frame(maxWidth: 320)
        .frame(height: height)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(LinearGradient(colors: BreathingReward.circleColors.map { $0.opacity(0.25) },
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("breathingRewardCard")
    }

    private var streakLine: some View {
        Text(shownStreak > 0 ? "🔥 \(shownStreak)-day breathing streak" : "🔥 Start your breathing streak today")
            .font(.subheadline).fontWeight(.semibold).foregroundColor(.teal)
            .accessibilityIdentifier("breathingStreak")
    }

    private var captionText: some View {
        Text(caption)
            .font(.footnote).foregroundColor(.secondary).multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("breathingCaption")
    }

    private var cycleText: String {
        "Cycle \(min(coach.completedCycles + 1, BreathingCueScript.cycles)) of \(BreathingCueScript.cycles)"
    }

    @ViewBuilder private var statusLines: some View {
        switch stage {
        case .running:
            Text(cycleText + (currentPhase.map { " · \($0.label)" } ?? ""))
                .font(.subheadline).foregroundColor(.teal)
                .accessibilityIdentifier("breathingCycle")
            Text("Alex is following your breathing through the phone's motion sensor.")
                .font(.caption2).foregroundColor(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        case .paused:
            Text("Paused · \(cycleText)").font(.subheadline).foregroundColor(.teal)
                .accessibilityIdentifier("breathingCycle")
            captionText
            Text(BreathingCueScript.pauseTip).font(.caption2).foregroundColor(.secondary)
        default:
            if sessionDone {
                streakLine
                if let newBadge {
                    Text("🏅 New badge: \(newBadge) days in a row").font(.caption)
                } else if let badge = BreathingStreak.highestBadge(for: shownStreak) {
                    Text("🏅 \(badge)-day badge").font(.caption).foregroundColor(.secondary)
                }
            }
            if !caption.isEmpty { captionText }
            if !listeningNote.isEmpty {
                Text(listeningNote).font(.caption).foregroundColor(.teal)
                    .accessibilityIdentifier("breathingListening")
            }
            if !sessionDone { streakLine }
        }
    }

    /// The Voice switch and the Alex/Men choice. There is no start button (round 4, item 2).
    private var controls: some View {
        HStack(spacing: 12) {
            Toggle(isOn: $voiceEnabled) {
                Label("Voice", systemImage: voiceEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.subheadline)
            }
            .fixedSize()
            .tint(.teal)
            .accessibilityIdentifier("breathingVoiceToggle")
            Picker("Voice", selection: $voiceChoice) {
                ForEach(BreathingVoiceChoice.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 150)
            .disabled(!voiceEnabled)
            .accessibilityIdentifier("breathingVoiceChoice")
        }
    }

    // MARK: Flow: Alex's questions → calibration → cycles → another round? (or a gentle end)

    private func after(_ seconds: Double, _ thisRun: Int, _ action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            guard isActive, run == thisRun else { return }
            action()
        }
    }

    private func quoted(_ lines: [String]) -> String { "“\(lines.joined(separator: " "))”" }

    /// Alex says `lines` one after another (or, with the voice off, shows them long enough to read),
    /// then `then` runs.
    private func say(_ lines: [String], _ thisRun: Int, then: @escaping () -> Void) {
        guard voiceEnabled else {
            after(BreathingCueScript.readingSeconds * Double(lines.count), thisRun, then)
            return
        }
        guide.prepare()
        for (index, line) in lines.enumerated() {
            guide.speak(line, completion: index == lines.count - 1 ? { after(0.2, thisRun, then) } : nil)
        }
    }

    private func appeared() {
        let saved = BreathingStreak.load()
        shownStreak    = BreathingStreak.displayed(saved, on: Date())
        rewardUnlocked = BreathingReward.isUnlocked(by: saved)
        greetingName   = AppleAccount.givenName()
        guide.use(voiceChoice)
        #if DEBUG
        debugAnswers    = BreathingDebug.answers(from: BreathingDebug.rawAnswers)
        debugInhalePlan = BreathingDebug.inhalePlan(from: BreathingDebug.rawMotion)
        #endif
        Task { @MainActor in
            await AppleSignIn.refreshCredentialState()
            greetingName = AppleAccount.givenName()
        }
        let thisRun = run
        after(1.0, thisRun) { beginConversation() }     // a breath of quiet before Alex speaks
    }

    private func beginConversation() {
        run += 1
        coach       = BreathingCoach()
        sessionDone = false
        streak      = nil
        newBadge    = nil
        perform(BreathingConversation.firstStep, run)
    }

    private func perform(_ next: BreathingConversation.Step, _ thisRun: Int) {
        step = next
        listeningNote = ""
        switch next {
        case .askFeeling:
            stage = .talking
            let line = BreathingCueScript.opening(name: greetingName)
            caption = quoted([line])
            say([line], thisRun) { listen(for: .feeling, thisRun) }
        case .askReady(let attempt, let thankFirst):
            stage = .talking
            let lines = (thankFirst ? [BreathingCueScript.thanks] : [])
                + [attempt == 1 ? BreathingCueScript.readyQuestion : BreathingCueScript.readyAgain]
            caption = quoted(lines)
            say(lines, thisRun) { listen(for: .answer, thisRun) }
        case .begin:
            startExercise(thisRun)
        case .endGently:
            endGently(BreathingCueScript.declined)
        case .askAnotherRound(let attempt):
            stage = .talking
            let line = attempt == 1 ? BreathingCueScript.anotherRound : BreathingCueScript.anotherRoundAgain
            caption = quoted([line])
            say([line], thisRun) { listen(for: .answer, thisRun) }
        case .goAgain:
            goAgain(thisRun)
        case .goodbye:
            endGently(BreathingCueScript.goodbye)
        }
    }

    // MARK: Listening

    /// True when Alex can hear an answer: microphone allowed and free, speech recognition available.
    private var canListen: Bool {
        !VoiceInputManager.isAnyRecording && !listener.permissionDenied
            && (SFSpeechRecognizer(locale: Locale(identifier: "en-US"))?.isAvailable ?? false)
    }

    private func listen(for purpose: Listening, _ thisRun: Int) {
        listeningFor  = purpose
        let note      = purpose == .feeling ? "Listening…" : "Listening… say “yes” or “no”."
        #if DEBUG
        if BreathingDebug.rawAnswers != nil {                 // simulator: no listening at all
            let raw = debugAnswers.isEmpty ? "silent" : debugAnswers.removeFirst()
            if raw == "denied" { cannotHear(permissionRefused: true); return }
            stage         = .listening
            listeningNote = note
            let silent    = raw == "silent"
            after(silent ? BreathingCueScript.listenSeconds : 1.5, thisRun) {
                guard stage == .listening else { return }
                answered(purpose == .feeling ? (silent ? .feelingSilent : .feelingHeard)
                                             : .ready(silent ? nil : ReadyAnswer.parse(raw)), thisRun)
            }
            return
        }
        #endif
        guard canListen else { cannotHear(permissionRefused: listener.permissionDenied); return }
        stage         = .listening
        listeningNote = note
        lastHeard     = .distantPast
        guide.releaseForListening()
        listener.startRecording()
        after(BreathingCueScript.listenSeconds, thisRun) {
            guard stage == .listening else { return }
            let heardSomething = !listener.transcript.trimmingCharacters(in: .whitespaces).isEmpty
            stopListening()
            answered(purpose == .feeling ? (heardSomething ? .feelingHeard : .feelingSilent) : .ready(nil), thisRun)
        }
    }

    /// Each new piece of transcript. The feelings answer is never read: it only tells Alex someone is
    /// still talking. A yes/no answer is matched and then discarded.
    private func heard(_ said: String) {
        guard stage == .listening, !said.isEmpty else { return }
        let thisRun = run
        switch listeningFor {
        case .feeling:
            lastHeard = Date()
            after(BreathingCueScript.answerSettleSeconds, thisRun) {
                guard stage == .listening, listeningFor == .feeling,
                      Date().timeIntervalSince(lastHeard) >= BreathingCueScript.answerSettleSeconds - 0.1 else { return }
                stopListening()
                answered(.feelingHeard, thisRun)
            }
        case .answer:
            guard let answer = ReadyAnswer.parse(said) else { return }
            stopListening()
            answered(.ready(answer), thisRun)
        }
    }

    private func answered(_ event: BreathingConversation.Event, _ thisRun: Int) {
        guard run == thisRun, isActive else { return }
        perform(BreathingConversation.next(after: step, event), thisRun)
    }

    /// Closes this screen's microphone. Called before the exercise starts and on every way out.
    private func stopListening() {
        if listener.isRecording || stage == .listening { listener.stopRecording() }
    }

    /// Round 4, item 2: no button. A plain message (spoken too, if the voice is on) and nothing else.
    private func cannotHear(permissionRefused: Bool) {
        stage         = .cannotHear
        listeningNote = ""
        let line = BreathingCueScript.cannotHear(permissionRefused: permissionRefused)
        caption = line
        if voiceEnabled {
            guide.prepare()
            guide.speak(line)
        }
        guide.finish()
    }

    // MARK: The exercise

    private func startExercise(_ thisRun: Int) {
        guard run == thisRun, isActive else { return }
        stopListening()                                  // the mic is never open during the exercise
        guard motion.isAvailable else { endGently(BreathingCueScript.noMotionSensor); return }
        stage = .settling
        motion.start()
        caption = quoted([BreathingCueScript.settle, BreathingCueScript.calibrate])
        say([BreathingCueScript.settle, BreathingCueScript.calibrate], thisRun) { calibrate(thisRun) }
    }

    /// One natural cycle sets the detector's thresholds. If it was unclear, Alex asks once more, and
    /// again after that: the exercise never starts without it (Done always works).
    private func calibrate(_ thisRun: Int) {
        guard stage == .settling else { return }
        listeningNote = "Feeling your breathing…"
        motion.beginCalibration()
        #if DEBUG
        motion.fakeChest = .natural
        #endif
        after(BreathCalibration.seconds, thisRun) {
            guard stage == .settling else { return }
            listeningNote = ""
            #if DEBUG
            motion.fakeChest = .hold
            #endif
            if motion.finishCalibration() {
                caption = quoted([BreathingCueScript.letsBegin])
                say([BreathingCueScript.letsBegin], thisRun) {
                    guard stage == .settling else { return }
                    stage = .running
                    caption = ""
                    runPhase(0, thisRun)
                }
            } else {
                caption = quoted([BreathingCueScript.calibrateAgain])
                say([BreathingCueScript.calibrateAgain], thisRun) { calibrate(thisRun) }
            }
        }
    }

    private func runPhase(_ index: Int, _ thisRun: Int) {
        let phases = BreathingPhase.allCases
        guard run == thisRun, isActive, stage == .running, index < phases.count else { return }
        let current = phases[index]
        currentPhase        = current
        phaseStep          += 1
        motion.isPaused     = false
        motion.learnsInhale = current == .inhale
        phaseWatch          = BreathPhaseWatch(phase: current, current: motion.breath)
        #if DEBUG
        switch current {
        case .inhale:
            let follows = debugInhalePlan.isEmpty ? true : debugInhalePlan.removeFirst()
            motion.fakeChest = follows ? .breatheIn : .hold
        case .exhale:
            motion.fakeChest = .breatheOut
        case .holdAfterInhale, .holdAfterExhale:
            motion.fakeChest = .hold
        }
        #endif
        if voiceEnabled { guide.speakOnBeat(BreathingCueScript.cue(for: current)) }
        after(Double(current.seconds), thisRun) {
            guard stage == .running else { return }
            switch coach.phaseEnded(current, breathDetected: phaseWatch?.detected ?? false) {
            case .nextPhase: runPhase(index + 1, thisRun)
            case .nextCycle: runPhase(0, thisRun)
            case .finished:  finish()
            case .pause:     pause(thisRun)
            }
        }
    }

    private func breathChanged(_ breath: Breath) {
        if stage == .running { phaseWatch?.observe(breath) }
        if stage == .paused, awaitingResume, breath == .inhaling { resume(run) }
    }

    /// Round 4, item 6: no breath detected. The lungs hold still, Alex invites a breath, and the same
    /// cycle continues from its inhale as soon as she feels one. There is no limit and no ending here.
    private func pause(_ thisRun: Int) {
        stage               = .paused
        awaitingResume      = false
        motion.isPaused     = true
        motion.learnsInhale = true
        caption             = BreathingCueScript.pause
        #if DEBUG
        motion.fakeChest = .hold
        after(BreathingDebug.resumeAfterSeconds, thisRun) { motion.fakeChest = .breatheIn }
        #endif
        say([BreathingCueScript.pause], thisRun) {
            guard stage == .paused else { return }
            awaitingResume = true
            if motion.breath == .inhaling { resume(thisRun) }
        }
    }

    private func resume(_ thisRun: Int) {
        guard run == thisRun, stage == .paused, awaitingResume else { return }
        awaitingResume = false
        stage          = .running
        caption        = ""
        runPhase(0, thisRun)                          // the same cycle, starting on the user's own inhale
    }

    private func finish() {
        motion.stop()
        motion.settleLungs()
        currentPhase = nil
        sessionDone  = true
        if coach.countsForStreak {                    // breathing was detected for every cycle
            let before  = BreathingStreak.load()
            let updated = BreathingStreak.record(before, on: Date())
            BreathingStreak.save(updated)
            streak         = updated
            shownStreak    = updated.current
            newBadge       = BreathingStreak.newMilestone(before: before, after: updated)
            rewardUnlocked = BreathingReward.isUnlocked(by: updated)
        }
        stage   = .talking
        caption = quoted([BreathingCueScript.congratulations])
        let thisRun = run
        say([BreathingCueScript.congratulations], thisRun) {
            perform(BreathingConversation.afterSession, thisRun)
        }
    }

    /// "Yes" to another round: the calibration from this visit is kept, so it starts straight away.
    private func goAgain(_ thisRun: Int) {
        stopListening()
        coach       = BreathingCoach()
        sessionDone = false
        newBadge    = nil
        stage       = .settling
        motion.start()
        caption = quoted([BreathingCueScript.goAgain])
        say([BreathingCueScript.goAgain], thisRun) {
            guard stage == .settling else { return }
            stage   = .running
            caption = ""
            runPhase(0, thisRun)
        }
    }

    private func endGently(_ line: String) {
        stage         = .ended
        motion.stop()
        motion.settleLungs()
        stopListening()
        currentPhase  = nil
        listeningNote = ""
        caption       = line
        if voiceEnabled {
            guide.prepare()
            guide.speak(line)
        }
        guide.finish()
        guard sessionDone else { return }
        // A calm, finished moment: let the goodbye land, then maybe ask for a review. Skipped if closed.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard isActive else { return }
            ReviewPrompt.askIfEligible { requestReview() }
        }
    }

    private func voiceSwitched(_ on: Bool) {
        if on { guide.prepare() } else { guide.stop() }
    }

    private func endSession() {
        isActive = false
        run += 1
        stopListening()
        guide.stop()
        motion.stop()
    }
}

// MARK: 5-4-3-2-1 Grounding

struct GroundingExerciseView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview
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
                                .task {
                                    // Cancelled when the view goes away, so a closed screen never asks.
                                    guard (try? await Task.sleep(nanoseconds: 1_500_000_000)) != nil else { return }
                                    ReviewPrompt.askIfEligible { requestReview() }
                                }
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
