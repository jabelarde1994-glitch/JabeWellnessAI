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
    @AppStorage(BreathingCueScript.nameKey) private var userName           = ""
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
                                Text(premium.product?.displayPrice ?? "$3.99").font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                }

                // Optional; on-device only (UserDefaults). Never sent to the AI or anywhere else.
                Section {
                    TextField("Your first name (optional)", text: $userName)
                        .textContentType(.givenName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .accessibilityIdentifier("settingsName")
                } header: {
                    Text("Name")
                } footer: {
                    Text("Used only to greet you in Box Breathing. Stays on this iPhone.")
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

/// The four box-breathing phases, in order. Drives both the circle and the spoken cues, so the
/// voice and the screen can never disagree about what the user should be doing.
nonisolated enum BreathingPhase: CaseIterable {
    case inhale, holdAfterInhale, exhale, holdAfterExhale

    var label: String {
        switch self {
        case .inhale:                            return "Inhale"
        case .holdAfterInhale, .holdAfterExhale: return "Hold"
        case .exhale:                            return "Exhale"
        }
    }

    var targetScale: CGFloat {
        switch self {
        case .inhale, .holdAfterInhale: return 1.5
        case .exhale, .holdAfterExhale: return 1.0
        }
    }

    /// Joel (2026-11-16, Revision 2): breathe in and out for 3 s; the holds stay at 4 s.
    var seconds: Int {
        switch self {
        case .inhale, .exhale:                   return 3
        case .holdAfterInhale, .holdAfterExhale: return 4
        }
    }

    var spokenCue: String {
        switch self {
        case .inhale:                            return "Breathe in."
        case .holdAfterInhale, .holdAfterExhale: return "Hold."
        case .exhale:                            return "Breathe out."
        }
    }
}

/// What the voice says and how. One short utterance per second (the cue, then "Two.", "Three.", …),
/// so each one finishes before the next tick and speech cannot drift behind the circle. Every cue
/// ends in a full stop so the system voice drops its pitch and pauses, like a person counting.
nonisolated enum BreathingCueScript {
    static let cycles = 4
    static var cycleSeconds: Int { BreathingPhase.allCases.reduce(0) { $0 + $1.seconds } }
    static var header: String {
        BreathingPhase.allCases.map { "\($0.label) \($0.seconds)s" }.joined(separator: " · ")
    }

    static let readyQuestion = "Are you ready to begin?"
    static let declined      = "That's okay. Come back whenever you're ready."
    static let notFollowing  = "Try to breathe with the circle."
    static let placementTip  = "Tip: lie down and rest your phone on your chest or belly."

    /// UserDefaults key for the optional name typed in Settings (on-device only).
    static let nameKey = "userName"

    // The plain system en-US voices (Joel: no Enhanced/Premium picking), a little slower than the 0.5
    // default, pitch left at 1.0: a shifted pitch is what makes a voice sound synthetic.
    static let voiceLanguage = "en-US"
    static let voiceRate:  Float = 0.44
    static let voicePitch: Float = 1.0

    /// Quiet seconds after "How are you feeling today?" so the user can answer in their own time.
    /// The answer is not recorded or transcribed; only the ready check listens.
    static let answerPause: Double     = 4
    /// How long the ready check listens for "yes" or "no" before leaving it to the Start button.
    static let listenTimeout: Double   = 8
    /// Seconds the circle rests after "Try to breathe with the circle." before repeating the cycle.
    static let pauseBeforeRetry: Double = 5

    static func cues(for phase: BreathingPhase) -> [String] {
        [phase.spokenCue] + ["Two.", "Three.", "Four."].prefix(max(phase.seconds - 1, 0))
    }

    private static func trimmed(_ name: String?) -> String {
        name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    static func greeting(name: String?) -> String {
        let n = trimmed(name)
        return "Hi \(n.isEmpty ? "there" : n), good day. How are you feeling today?"
    }

    static func congratulations(name: String?) -> String {
        let n = trimmed(name)
        let opening = n.isEmpty ? "Congratulations" : "Congratulations, \(n)"
        return "\(opening), you've completed your breathing for today. See you again tomorrow."
    }
}

/// The spoken answer to "Are you ready to begin?". Whole words only, any case; a "no" word wins, so
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

/// The Women / Men voice choice on the breathing screen, remembered on the device.
nonisolated enum BreathingVoiceChoice: String, CaseIterable {
    case women, men

    static let storageKey    = "breathingVoiceGender"
    static let defaultChoice = BreathingVoiceChoice.women

    var label: String { self == .women ? "Women" : "Men" }
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

/// Women: Samantha. Men: Aaron if installed, otherwise the best other male en-US voice: Apple's
/// current voices before the old MacinTalk ones, the basic quality first (Joel: plain system voices),
/// never a novelty voice, the user's Personal Voice, or the child voice "Junior". nil = use the
/// system default en-US voice.
nonisolated enum BreathingVoicePicker {
    static func pick(_ choice: BreathingVoiceChoice, from all: [BreathingVoiceCandidate],
                     language: String = BreathingCueScript.voiceLanguage) -> BreathingVoiceCandidate? {
        let usable = all.filter { $0.language == language && !$0.isNovelty && !$0.isPersonal }
        func preferred(_ a: BreathingVoiceCandidate, _ b: BreathingVoiceCandidate) -> Bool {
            if a.isLegacy != b.isLegacy { return !a.isLegacy }
            if a.quality != b.quality   { return a.quality.rawValue < b.quality.rawValue }
            return a.name < b.name
        }
        switch choice {
        case .women:
            return usable.filter { $0.baseName == "Samantha" }.min(by: preferred)
        case .men:
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

    /// The state after a session completed on `date`. A second session on the same day changes nothing.
    static func record(_ state: State, on date: Date, calendar: Calendar = .current) -> State {
        let today = dayKey(date, calendar: calendar)
        guard state.lastDay != today else { return state }
        var gap = Int.max
        if let last = state.lastDay.flatMap({ Self.date(fromKey: $0, calendar: calendar) }),
           let now = Self.date(fromKey: today, calendar: calendar) {
            gap = calendar.dateComponents([.day], from: last, to: now).day ?? Int.max
        }
        guard gap > 0 else { return state }      // the clock went backwards: count nothing
        var next = state
        next.current   = gap == 1 ? state.current + 1 : 1
        next.longest   = max(state.longest, next.current)
        next.totalDays = state.totalDays + 1
        next.lastDay   = today
        return next
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
/// Today: once someone has reached a 30-day breathing streak, the circle uses a calm mint-to-indigo
/// theme, and each completed session shows a card with their name and total days.
nonisolated enum BreathingReward {
    static let unlockDays = 30
    static let circleColors: [Color] = [.mint, .indigo]
    static let ringColor: Color      = .indigo

    static func isUnlocked(by state: BreathingStreak.State) -> Bool { state.longest >= unlockDays }

    static func cardTitle(name: String?) -> String {
        let n = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return n.isEmpty ? "Your 30-day calm" : "\(n)'s 30-day calm"
    }

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

nonisolated enum BreathVerdict: Equatable { case following, notFollowing, unknown }

/// PROTOTYPE breath sensing. With the phone resting on the chest or belly, breathing in tilts it one
/// way and breathing out tilts it back. The first cycle sets which tilt direction means "in"; each
/// cycle must then tilt that way during the inhale and back during the exhale. Unknown (never a
/// failure) when there is too little data or the phone is being moved. The thresholds are educated
/// guesses: they have only been checked against synthetic samples, never on a real chest.
nonisolated struct BreathDetector {
    static let minimumSwingDegrees = 0.2
    static let maximumMovement     = 0.03     // average g of user acceleration; above this the phone is handled
    static let minimumSamples      = 15       // per phase window (20 Hz × 3 s = 60 expected)

    private(set) var axis: SIMD3<Double>?

    mutating func evaluate(inhale: [BreathMotionSample], exhale: [BreathMotionSample]) -> BreathVerdict {
        guard inhale.count >= Self.minimumSamples, exhale.count >= Self.minimumSamples else { return .unknown }
        let all = inhale + exhale
        let movement = all.reduce(0) { $0 + $1.userAcceleration } / Double(all.count)
        guard movement <= Self.maximumMovement else { return .unknown }

        let minimumSwing = Self.minimumSwingDegrees * .pi / 180     // gravity moves ~1 rad per radian of tilt
        let rise = Self.mean(inhale.suffix(5)) - Self.mean(inhale.prefix(5))
        let fall = Self.mean(exhale.suffix(5)) - Self.mean(exhale.prefix(5))

        if axis == nil {
            let size = (rise * rise).sum().squareRoot()
            guard size >= minimumSwing else { return .notFollowing }
            axis = rise / size
        }
        guard let axis else { return .unknown }
        let inSwing  = (rise * axis).sum()
        let outSwing = (fall * axis).sum()
        return inSwing >= minimumSwing && outSwing <= -0.6 * minimumSwing ? .following : .notFollowing
    }

    private static func mean<S: Collection>(_ samples: S) -> SIMD3<Double> where S.Element == BreathMotionSample {
        samples.reduce(SIMD3<Double>.zero) { $0 + $1.gravity } / Double(max(samples.count, 1))
    }
}

/// When to pause for "Try to breathe with the circle.": only on a clear miss, and at most twice per
/// session, so an inaccurate sensor can never trap someone in a loop of retries.
nonisolated enum BreathingSensingPolicy {
    static let maximumPauses = 2

    static func shouldPause(after verdict: BreathVerdict, pausesSoFar: Int) -> Bool {
        verdict == .notFollowing && pausesSoFar < maximumPauses
    }
}

/// At full size the circle is drawn 1.5x its frame, so it spills a quarter of its size past the
/// frame on each side (55 pt for 220 pt). scaleEffect takes up no layout space, so that room is
/// reserved above and below; without it the full-size circle covered the "Box Breathing" heading
/// (pre-existing on main). On short screens (iPhone SE) the circle shrinks so the rest still fits.
nonisolated enum BreathingLayout {
    static let preferredCircleSize: CGFloat = 220
    static let minimumCircleSize: CGFloat   = 120
    static let maxScale: CGFloat            = BreathingPhase.allCases.map(\.targetScale).max() ?? 1
    /// Everything in the column except the circle: heading, two description lines, the two-line
    /// status area, the controls row, and the four 40 pt gaps, with a little to spare.
    static let otherContentHeight: CGFloat  = 320

    static func overflow(for size: CGFloat) -> CGFloat { size * (maxScale - 1) / 2 }

    /// The largest circle (up to 220 pt) whose full-size drawing fits beside the other content.
    static func circleSize(forHeight height: CGFloat) -> CGFloat {
        let fitting = ((height - otherContentHeight) / maxScale).rounded(.down)
        return min(preferredCircleSize, max(minimumCircleSize, fitting))
    }
}

/// Reads the phone's tilt 20 times a second while the exercise runs. CoreMotion device motion needs
/// no permission prompt; samples stay in memory for the session and are never stored or sent.
/// On the simulator `isAvailable` is false and the exercise keeps its own pace.
final class BreathMotionMonitor: ObservableObject {
    private var manager = CMMotionManager()
    private var samples: [BreathMotionSample] = []

    var isAvailable: Bool { manager.isDeviceMotionAvailable }

    func start() {
        guard isAvailable, !manager.isDeviceMotionActive else { return }
        samples.removeAll()
        manager.deviceMotionUpdateInterval = 1.0 / 20
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            let g = motion.gravity, a = motion.userAcceleration
            let sample = BreathMotionSample(time: motion.timestamp, gravity: SIMD3(g.x, g.y, g.z),
                                            userAcceleration: (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot())
            self?.append(sample)
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        samples.removeAll()
    }

    func samples(from start: TimeInterval, to end: TimeInterval) -> [BreathMotionSample] {
        samples.filter { $0.time >= start && $0.time <= end }
    }

    private func append(_ sample: BreathMotionSample) {
        samples.append(sample)
        if samples.count > 1_200 { samples.removeFirst(samples.count - 1_200) }   // last ~60 s
    }
}

/// Speaks the breathing cues on the device (AVSpeechSynthesizer; no network, no text leaves the
/// phone). Owns the audio session only while guiding, and never touches it while a microphone
/// recording is live.
final class BreathingVoiceGuide: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {

    // var, not let: keeps it main-actor isolated (AVSpeechSynthesizer is not Sendable).
    private var synthesizer = AVSpeechSynthesizer()
    private var voice = AVSpeechSynthesisVoice(language: BreathingCueScript.voiceLanguage)
    private var ownsAudioSession = false
    private var releaseWhenIdle  = false
    private var pending          = 0
    private var completions: [ObjectIdentifier: () -> Void] = [:]

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Switches to the Women or Men voice (falls back to the system default en-US voice).
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
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice           = voice
        utterance.rate            = BreathingCueScript.voiceRate
        utterance.pitchMultiplier = BreathingCueScript.voicePitch
        if let completion { completions[ObjectIdentifier(utterance)] = completion }
        pending += 1
        synthesizer.speak(utterance)
    }

    /// Cut off anything being said (Start tapped mid-greeting), keeping the audio session.
    func silence() {
        synthesizer.stopSpeaking(at: .immediate)
        pending = 0
        let waiting = completions.values
        completions.removeAll()
        waiting.forEach { $0() }
    }

    /// Hand the audio session to the microphone for the ready check.
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

    private enum Stage { case idle, greeting, askingReady, listening, running, paused, finished }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview

    @AppStorage("breathingVoiceEnabled") private var voiceEnabled = true
    @AppStorage(BreathingVoiceChoice.storageKey) private var voiceChoice = BreathingVoiceChoice.defaultChoice
    @AppStorage(BreathingCueScript.nameKey) private var userName = ""
    @StateObject private var guide    = BreathingVoiceGuide()
    @StateObject private var listener = VoiceInputManager()     // this screen's own mic, for the ready check
    @StateObject private var motion   = BreathMotionMonitor()

    @State private var stage: Stage   = .idle
    @State private var run            = 0      // bumps on every start and stop; stale timers do nothing
    @State private var phase          = "Tap to Begin"
    @State private var caption        = BreathingCueScript.placementTip
    @State private var sensingNote    = ""
    @State private var scale: CGFloat = 1.0
    @State private var isActive       = true
    @State private var cycleCount     = 0
    @State private var phaseStep      = 0      // bumps on every phase change; drives the haptic pulse
    @State private var detector       = BreathDetector()
    @State private var pauses         = 0
    @State private var streak: BreathingStreak.State?
    @State private var newBadge: Int?
    @State private var rewardUnlocked = false

    var body: some View {
        NavigationView {
            GeometryReader { geo in
                // 220 pt on most iPhones; smaller on short screens so the full-size circle fits.
                let circleSize = BreathingLayout.circleSize(forHeight: geo.size.height)
                VStack(spacing: 40) {
                    Spacer()

                    if stage == .finished && rewardUnlocked {
                        // Same height as the full-size circle, so nothing below moves.
                        rewardCard(height: circleSize * BreathingLayout.maxScale)
                    } else {
                        breathingCircle(size: circleSize)
                            .padding(.vertical, BreathingLayout.overflow(for: circleSize))   // room for the full-size circle
                    }

                    VStack(spacing: 8) {
                        Text("Box Breathing").font(.headline)
                        Text("\(BreathingCueScript.header)\nRepeat \(BreathingCueScript.cycles) cycles for best results")
                            .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)   // never cut to one line
                        statusLine
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
            .onAppear { rewardUnlocked = BreathingReward.isUnlocked(by: BreathingStreak.load()) }
            .onDisappear { endSession() }
            .onChange(of: voiceEnabled) { _, on in voiceSwitched(on) }
            .onChange(of: voiceChoice) { _, choice in guide.use(choice) }
            .onChange(of: listener.transcript) { _, said in heard(said) }
            .onChange(of: listener.isRecording) { _, recording in
                // Permission callbacks are asynchronous: a recording that opens after the ready check
                // has moved on (Start tapped, Done, timeout) is closed at once.
                if recording && stage != .listening { listener.stopRecording() }
            }
            .onChange(of: listener.permissionDenied) { _, denied in
                if denied && stage == .listening { stopListening(); offerStartButton() }
            }
        }
    }

    // MARK: Pieces

    private func breathingCircle(size: CGFloat) -> some View {
        let colors = rewardUnlocked ? BreathingReward.circleColors : [Color.teal, Color.blue]
        let ring   = rewardUnlocked ? BreathingReward.ringColor : Color.teal
        return ZStack {
            Circle()
                .fill(LinearGradient(colors: colors.map { $0.opacity(0.25) }, startPoint: .top, endPoint: .bottom))
                .frame(width: size, height: size)
                .scaleEffect(scale)
            Circle()
                .stroke(ring.opacity(0.5), lineWidth: 2)
                .frame(width: size, height: size)
                .scaleEffect(scale)
            Text(phase)
                .font(.title2).fontWeight(.semibold)
                .multilineTextAlignment(.center)
        }
        .onTapGesture { circleTapped() }
    }

    private func rewardCard(height: CGFloat) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles").font(.title).foregroundStyle(BreathingReward.ringColor)
            Text(BreathingReward.cardTitle(name: userName))
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

    @ViewBuilder private var statusLine: some View {
        switch stage {
        case .running, .paused:
            Text("Cycle \(min(cycleCount + 1, BreathingCueScript.cycles)) of \(BreathingCueScript.cycles)")
                .font(.subheadline).foregroundColor(.teal)
            Text(stage == .paused ? caption : sensingNote)
                .font(.caption2).foregroundColor(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        case .finished:
            if let streak {
                Text("🔥 \(streak.current)-day breathing streak")
                    .font(.subheadline).fontWeight(.semibold).foregroundColor(.teal)
                    .accessibilityIdentifier("breathingStreak")
                if let newBadge {
                    Text("🏅 New badge: \(newBadge) days in a row").font(.caption)
                } else if let badge = BreathingStreak.highestBadge(for: streak.current) {
                    Text("🏅 \(badge)-day badge").font(.caption).foregroundColor(.secondary)
                }
            }
        default:
            Text(caption)
                .font(.footnote).foregroundColor(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("breathingCaption")
        }
    }

    @ViewBuilder private var controls: some View {
        switch stage {
        case .greeting, .askingReady, .listening:
            Button { startTapped() } label: { Text("Start").frame(maxWidth: 200) }
                .buttonStyle(.borderedProminent).tint(.teal).controlSize(.large)
                .accessibilityIdentifier("breathingStart")
        case .paused:
            Button { resume() } label: { Text("Continue").frame(maxWidth: 200) }
                .buttonStyle(.bordered).tint(.teal).controlSize(.large)
                .accessibilityIdentifier("breathingContinue")
        default:
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
    }

    // MARK: Flow: greeting → ready check → cycles → finish

    private func after(_ seconds: Double, _ thisRun: Int, _ action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            guard isActive, run == thisRun else { return }
            action()
        }
    }

    private func circleTapped() {
        switch stage {
        case .idle, .finished: begin()
        case .paused:          resume()
        default:               break
        }
    }

    private func begin() {
        run += 1
        let thisRun = run
        cycleCount = 0
        pauses     = 0
        detector   = BreathDetector()
        streak     = nil
        newBadge   = nil
        withAnimation(.easeInOut(duration: 0.4)) { scale = 1.0 }
        guard voiceEnabled else { startExercise(thisRun); return }   // voice off: the tap itself is the start
        guide.use(voiceChoice)
        guide.prepare()
        stage = .greeting
        phase = "Hello"
        let greeting = BreathingCueScript.greeting(name: userName)
        caption = "“\(greeting)”"
        guide.speak(greeting) {
            after(BreathingCueScript.answerPause, thisRun) { askIfReady(thisRun) }
        }
        after(15, thisRun) { askIfReady(thisRun) }     // safety net if the speech engine never reports back
    }

    private func askIfReady(_ thisRun: Int) {
        guard stage == .greeting else { return }
        stage   = .askingReady
        phase   = "Ready?"
        caption = "“\(BreathingCueScript.readyQuestion)”"
        guide.speak(BreathingCueScript.readyQuestion) {
            after(0.3, thisRun) { listenForAnswer(thisRun) }
        }
    }

    private func listenForAnswer(_ thisRun: Int) {
        guard stage == .askingReady else { return }
        // Never take the mic from a live chat recording, and don't ask again once permission was refused.
        guard !VoiceInputManager.isAnyRecording, !listener.permissionDenied else { offerStartButton(); return }
        stage   = .listening
        caption = "Listening… say “yes” to begin, or tap Start."
        guide.releaseForListening()
        listener.startRecording()
        after(BreathingCueScript.listenTimeout, thisRun) {
            guard stage == .listening else { return }
            stopListening()
            offerStartButton()
        }
    }

    private func offerStartButton() {
        stage   = .askingReady
        caption = "Tap Start when you're ready."
    }

    private func heard(_ said: String) {
        guard stage == .listening, let answer = ReadyAnswer.parse(said) else { return }
        stopListening()
        switch answer {
        case .yes: startExercise(run)
        case .no:  decline()
        }
    }

    /// Closes this screen's microphone. Called before the exercise starts and on every way out.
    private func stopListening() {
        if listener.isRecording || stage == .listening { listener.stopRecording() }
    }

    private func decline() {
        stage   = .idle
        phase   = "Tap to Begin"
        caption = BreathingCueScript.declined
        if voiceEnabled {
            guide.prepare()
            guide.speak(BreathingCueScript.declined)
        }
        guide.finish()
    }

    private func startTapped() {
        stopListening()
        guide.silence()
        startExercise(run)
    }

    private func startExercise(_ thisRun: Int) {
        guard run == thisRun, isActive else { return }
        stopListening()                                  // the mic is never open during the exercise
        stage   = .running
        caption = ""
        if voiceEnabled { guide.prepare() }
        motion.start()
        sensingNote = motion.isAvailable
            ? "Breath sensing on. Rest your phone on your chest or belly."
            : "Breath sensing isn't available here, so the circle keeps its own pace."
        runCycles(thisRun)
    }

    private func runCycles(_ thisRun: Int) {
        guard run == thisRun, isActive, stage == .running else { return }
        guard cycleCount < BreathingCueScript.cycles else { finish(); return }
        runPhase(0, thisRun, marks: [:]) { marks in judgeCycle(marks, thisRun) }
    }

    private func runPhase(_ index: Int, _ thisRun: Int, marks: [BreathingPhase: ClosedRange<TimeInterval>],
                          done: @escaping ([BreathingPhase: ClosedRange<TimeInterval>]) -> Void) {
        let phases = BreathingPhase.allCases
        guard index < phases.count else { done(marks); return }
        guard stage == .running else { return }
        let step  = phases[index]
        let start = ProcessInfo.processInfo.systemUptime   // same clock as CoreMotion timestamps
        animate(step, thisRun)
        after(Double(step.seconds), thisRun) {
            var updated = marks
            updated[step] = start...ProcessInfo.processInfo.systemUptime
            runPhase(index + 1, thisRun, marks: updated, done: done)
        }
    }

    private func animate(_ step: BreathingPhase, _ thisRun: Int) {
        phase      = step.label
        phaseStep += 1
        withAnimation(.easeInOut(duration: Double(step.seconds))) { scale = step.targetScale }
        // One cue per second, so each is spoken in step with the circle.
        for (second, cue) in BreathingCueScript.cues(for: step).enumerated() {
            after(Double(second), thisRun) {
                guard voiceEnabled, stage == .running else { return }
                guide.speak(cue)
            }
        }
    }

    private func judgeCycle(_ marks: [BreathingPhase: ClosedRange<TimeInterval>], _ thisRun: Int) {
        var verdict = BreathVerdict.unknown
        if let inhale = marks[.inhale], let exhale = marks[.exhale] {
            verdict = detector.evaluate(inhale: motion.samples(from: inhale.lowerBound, to: inhale.upperBound),
                                        exhale: motion.samples(from: exhale.lowerBound, to: exhale.upperBound))
        }
        if motion.isAvailable {
            switch verdict {
            case .following:    sensingNote = "Breath sensing: you're breathing with the circle."
            case .unknown:      sensingNote = "Breath sensing: can't tell. Keep the phone still on your chest or belly."
            case .notFollowing: sensingNote = pauses >= BreathingSensingPolicy.maximumPauses
                                    ? "Breath sensing: I'll keep the rhythm for you." : sensingNote
            }
        }
        if BreathingSensingPolicy.shouldPause(after: verdict, pausesSoFar: pauses) {
            pause(thisRun)
        } else {
            cycleCount += 1
            runCycles(thisRun)
        }
    }

    /// Not following: say so gently, rest, then repeat the same cycle (it is not counted).
    private func pause(_ thisRun: Int) {
        pauses += 1
        stage   = .paused
        phase   = "Paused"
        caption = BreathingCueScript.notFollowing
        withAnimation(.easeInOut(duration: 1)) { scale = 1.0 }
        if voiceEnabled { guide.speak(BreathingCueScript.notFollowing) }
        after(BreathingCueScript.pauseBeforeRetry, thisRun) { resume() }
    }

    private func resume() {
        guard stage == .paused else { return }
        stage = .running
        runCycles(run)
    }

    private func finish() {
        stage = .finished
        motion.stop()
        stopListening()
        phase = "Well done! 🎉"
        withAnimation(.easeInOut(duration: 1)) { scale = 1.0 }
        let before  = BreathingStreak.load()
        let updated = BreathingStreak.record(before, on: Date())
        BreathingStreak.save(updated)
        streak         = updated
        newBadge       = BreathingStreak.newMilestone(before: before, after: updated)
        rewardUnlocked = BreathingReward.isUnlocked(by: updated)
        if voiceEnabled { guide.speak(BreathingCueScript.congratulations(name: userName)) }
        guide.finish()
        // A calm, finished moment: let the celebration land, then maybe ask. Skipped if closed.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard isActive else { return }
            ReviewPrompt.askIfEligible { requestReview() }
        }
    }

    private func voiceSwitched(_ on: Bool) {
        if on {
            if stage == .running { guide.prepare() }
        } else {
            guide.stop()
            // No voice: no spoken question and no listening; the Start button takes over.
            if stage == .greeting || stage == .askingReady || stage == .listening {
                stopListening()
                offerStartButton()
            }
        }
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
