//
//  JabeWellnessAIUITests.swift
//  JabeWellnessAIUITests
//
//  Created by Joel Reamosio Abelarde on 5/13/26.
//

import XCTest

final class JabeWellnessAIUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    // xcodebuild resets the app's container between separate -only-testing invocations,
    // so onboarding can reappear even though hasSeenOnboarding was already set in a prior run.
    private func dismissOnboardingIfPresent(_ app: XCUIApplication) {
        let skipButton = app.buttons["Skip"]
        if skipButton.waitForExistence(timeout: 3) {
            skipButton.tap()
        } else {
            let getStarted = app.buttons["Get Started"]
            if getStarted.waitForExistence(timeout: 2) { getStarted.tap() }
        }
    }

    @MainActor
    func testChatSendAndNavigateTabs() throws {
        let app = XCUIApplication()
        app.launch()
        dismissOnboardingIfPresent(app)

        let textView = app.textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 5), "Chat text editor should exist")
        textView.tap()
        textView.typeText("I'm feeling really anxious about my job interview tomorrow")

        // SF Symbol "arrow.up" / "plus.bubble" get default accessibility labels "Up" / "Comment"
        app.buttons["Up"].tap()

        // This used to wait on staticTexts["Jabe"], which is ALSO the navigation header —
        // already on screen before anything is sent, and identical whether the reply is a
        // real answer or an API error. The test passed while chat was returning HTTP 401.
        // Assert on the content of the reply instead, and name the failure texts explicitly,
        // because this test is the documented way to confirm the Groq key works without
        // anyone reading it.
        let failureTexts = [
            "issue with the API key",
            "Something went wrong",
            "need a moment to breathe"
        ]

        let notAFailure = failureTexts
            .map { "NOT (label CONTAINS[c] '\($0)')" }
            .joined(separator: " AND ")

        // XCUITest predicates do NOT support label.length — it throws
        // XCTElementQueryInvalidPredicate at evaluation time. MATCHES with an ICU regex is
        // the supported way to express "a substantial reply"; (?s) so newlines count too.
        let reply = app.staticTexts.matching(
            NSPredicate(format: "label MATCHES %@ AND NOT (label CONTAINS[c] %@) AND \(notAFailure)",
                        "(?s).{60,}", "job interview tomorrow")
        ).firstMatch

        XCTAssertTrue(
            reply.waitForExistence(timeout: 25),
            "A genuine AI reply should arrive. If this fails with the error bubble on screen, "
            + "the Groq API key is being rejected — check GROQ STATUS in the console.\n\(app.debugDescription)"
        )

        for failureText in failureTexts {
            XCTAssertFalse(
                app.staticTexts.matching(
                    NSPredicate(format: "label CONTAINS[c] %@", failureText)
                ).firstMatch.exists,
                "Chat returned an error instead of a reply: \(failureText)"
            )
        }

        app.buttons["Comment"].tap()

        app.tabBars.buttons["Insights"].tap()
        app.tabBars.buttons["Exercises"].tap()
        app.tabBars.buttons["Journal"].tap()
        app.tabBars.buttons["Settings"].tap()
        app.tabBars.buttons["Chat"].tap()
    }

    @MainActor
    func testHistoryShowsSavedSessions() throws {
        let app = XCUIApplication()
        app.launch()
        dismissOnboardingIfPresent(app)

        let textView = app.textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 5), "Chat text editor should exist")
        textView.tap()
        textView.typeText("Just checking in, feeling okay today")
        app.buttons["Up"].tap()
        XCTAssertTrue(app.staticTexts["Jabe"].firstMatch.waitForExistence(timeout: 20), "AI reply bubble should appear")
        app.buttons["Comment"].tap()

        app.tabBars.buttons["Insights"].tap()
        let historyRow = app.staticTexts["Chat History"].firstMatch
        XCTAssertTrue(historyRow.waitForExistence(timeout: 5), "Chat History row should exist on Insights")
        historyRow.tap()

        let firstCell = app.cells.firstMatch
        XCTAssertTrue(firstCell.waitForExistence(timeout: 5), "History should list the session just saved")
        firstCell.tap()
    }

    // The trial anchor moved from UserDefaults to the Keychain and the purchased flag is now
    // re-derived from StoreKit entitlements. Both feed the Settings row and the paywall, so
    // this guards that a fresh install still lands in a working trial rather than locked out.
    @MainActor
    // Until 2026-08-18 the $3.99 purchase unlocked nothing: no feature consulted
    // entitlement. These pin both directions of the gate.

    // A locked user must be able to REACH the paywall from a premium feature. Before
    // the gate, showPaywall was set only from Settings and its sheet was attached only
    // to Settings, so a tap anywhere else would have flipped a flag and shown nothing.
    func testLockedUserTappingAPremiumFeatureGetsThePaywall() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-jabeForceLocked"]
        app.launch()
        dismissOnboardingIfPresent(app)

        // The splash runs ~3.8s before MainTabView exists; tapping straight away finds no tab bar.
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30), "Tab bar should appear after the splash")
        app.tabBars.buttons["Insights"].tap()

        let lock = app.buttons["premiumLock"].firstMatch
        XCTAssertTrue(lock.waitForExistence(timeout: 10),
                      "Premium surfaces should be locked when the user is not entitled")

        lock.tap()

        XCTAssertTrue(app.staticTexts["Jabe Premium"].waitForExistence(timeout: 10),
                      "Tapping a locked premium feature should open the paywall from a non-Settings tab")
    }

    // The mirror image, and the more damaging failure: over-gating would put a blur in
    // front of paying and trialling users alike.
    func testTrialUsersSeeNoLocks() throws {
        let app = XCUIApplication()
        app.launch()
        dismissOnboardingIfPresent(app)

        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30), "Tab bar should appear after the splash")
        app.tabBars.buttons["Insights"].tap()
        XCTAssertFalse(app.buttons["premiumLock"].firstMatch.exists,
                       "A trial user is entitled and must not see a lock on Insights")

        app.tabBars.buttons["Exercises"].tap()
        XCTAssertFalse(app.buttons["premiumLock"].firstMatch.exists,
                       "A trial user is entitled and must not see a lock on Exercises")
    }

    func testTrialStateIsVisibleAndPaywallOpens() throws {
        let app = XCUIApplication()
        app.launch()
        dismissOnboardingIfPresent(app)

        app.tabBars.buttons["Settings"].tap()

        // Which of the three states shows depends on whether this device already holds a
        // StoreKit entitlement, so assert on whichever one the entitlement check produced
        // rather than pinning the test to one of them.
        let unlocked = app.staticTexts["Premium Unlocked"]
        let tappableRow = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Free Trial Active' OR label CONTAINS[c] 'Unlock Premium'")
        ).firstMatch

        let unlockedShown = unlocked.waitForExistence(timeout: 5)
        let rowShown      = tappableRow.exists

        XCTAssertTrue(
            unlockedShown || rowShown,
            "Settings should show a premium status row in one of its three states.\n\(app.debugDescription)"
        )
        XCTAssertFalse(
            unlockedShown && rowShown,
            "Settings should show exactly one premium state, not a paid row and an unpaid row at once"
        )

        // A paid-up user has nothing left to buy, so the row is deliberately not tappable.
        guard rowShown else { return }

        tappableRow.tap()

        XCTAssertTrue(
            app.staticTexts["Jabe Premium"].waitForExistence(timeout: 5),
            "Tapping the premium row should open the paywall.\n\(app.debugDescription)"
        )
        XCTAssertTrue(
            app.buttons["Restore Purchase"].waitForExistence(timeout: 5),
            "Paywall should still offer Restore Purchase"
        )

        app.buttons["Close"].firstMatch.tap()
    }

    // The About rows are the only build fingerprint a user can read off an install, so pin them.
    // The 2026-08-19 attempt failed on LabeledContent's accessibility shape: depending on the
    // OS, the value surfaces as its own staticText or folded into one element's label/value.
    // Match either shape rather than one of them.
    @MainActor
    func testAboutShowsCurrentAppNameAndModel() throws {
        let app = XCUIApplication()
        app.launch()
        dismissOnboardingIfPresent(app)

        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30), "Tab bar should appear after the splash")
        app.tabBars.buttons["Settings"].tap()

        func row(_ text: String) -> XCUIElement {
            app.descendants(matching: .any).matching(
                NSPredicate(format: "label == %@ OR value == %@ OR label ENDSWITH %@", text, text, ", \(text)")
            ).firstMatch
        }

        let model = row("GPT OSS 120B via Groq")
        for _ in 0..<6 where !model.exists { app.swipeUp() }

        XCTAssertTrue(model.waitForExistence(timeout: 5), "About should name the model.\n\(app.debugDescription)")
        XCTAssertTrue(row("Jabe Wellness").exists, "About's App row should read the current name.\n\(app.debugDescription)")
        XCTAssertFalse(row("Jabe Wellness AI").exists, "About still shows the pre-2026-08-23 name")
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
