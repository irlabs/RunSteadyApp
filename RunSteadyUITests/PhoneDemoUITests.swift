import XCTest

/// Walks through the phone experience with seeded history: check-in, suggestion,
/// manual schedule, plan and history.
final class PhoneDemoUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
        app.launchArguments = ["-demoSeed", "YES"]
        app.launch()
    }

    private func pause(_ seconds: TimeInterval) { Thread.sleep(forTimeInterval: seconds) }

    func testFullExperience() {
        // Today
        XCTAssertTrue(app.buttons["checkInButton"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Week 2"].exists)
        pause(2.5)
        app.swipeUp()
        pause(1.5)
        app.swipeDown()
        pause(1)

        // Check-in chat
        app.buttons["checkInButton"].tap()
        pause(2)
        // Effort slider (F11): slide down to an easy 3, which counts as "Great".
        let slider = app.sliders["effortSlider"]
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        slider.adjust(toNormalizedSliderPosition: 0.22)
        pause(1.2)
        app.buttons["effortDone"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '3 · '")).firstMatch.waitForExistence(timeout: 3))
        pause(1.5)
        app.buttons["comfort-yes"].tap()
        pause(1.5)
        // A typed answer instead of a button (F12): counts as no tap, goes to the coach.
        let typed = app.textFields["typedAnswerField"]
        XCTAssertTrue(typed.waitForExistence(timeout: 5))
        typed.tap()
        typed.typeText("All good, calves a little tight")
        app.buttons["typedAnswerSend"].tap()
        // Up to two "what happened?" questions about how the run differed from the plan.
        for _ in 0..<2 {
            pause(1.5)
            let skip = app.buttons["reason-skip"]
            guard skip.exists else { break }
            let feltGood = app.buttons["reason-feltGood"]
            (feltGood.exists ? feltGood : skip).tap()
        }
        // The same offer also appears on Today underneath the sheet; tap the one in the chat.
        // With a coach key, typed answers add a note-extraction call before the wrap-up, so wait for both.
        let offers = app.buttons.matching(identifier: "useSuggestionButton")
        let both = expectation(for: NSPredicate(format: "count >= 2"), evaluatedWith: offers)
        wait(for: [both], timeout: 45)
        pause(3)
        offers.element(boundBy: offers.count - 1).tap()
        pause(1)
        let field = app.textFields["chatField"]
        field.tap()
        field.typeText("Felt easy, so I did an extra round.")
        app.buttons["chatSend"].tap()
        pause(4)
        app.buttons["checkInDone"].tap()

        // Today now shows the accepted next step
        XCTAssertTrue(app.staticTexts["Week 3"].waitForExistence(timeout: 5))
        pause(2.5)

        // Manual schedule overrides the plan
        app.buttons["editScheduleButton"].tap()
        pause(1.5)
        app.buttons["runPlus"].tap(); pause(0.5)
        app.buttons["runPlus"].tap(); pause(0.5)
        app.buttons["walkMinus"].tap(); pause(0.5)
        app.buttons["roundsMinus"].tap(); pause(1.2)
        app.buttons["saveScheduleButton"].tap()
        XCTAssertTrue(app.staticTexts["Manual"].waitForExistence(timeout: 5))
        pause(2)
        // The plan's suggestion sits collapsed under the manual schedule (F14): reason on tap, then ignore.
        app.swipeUp()
        let why = app.staticTexts["Why?"]
        XCTAssertTrue(why.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["suggestionReason"].exists)
        why.tap()
        XCTAssertTrue(app.staticTexts["suggestionReason"].waitForExistence(timeout: 3))
        pause(2)
        XCTAssertEqual(app.buttons["keepMineButton"].label, "Ignore")
        app.buttons["keepMineButton"].tap()
        pause(1)
        XCTAssertFalse(app.buttons["keepMineButton"].exists)
        // Editing the manual schedule again doesn't bring it back.
        app.swipeDown()
        app.buttons["editScheduleButton"].tap()
        pause(1)
        app.buttons["runPlus"].tap()
        app.buttons["saveScheduleButton"].tap()
        pause(1.5)
        XCTAssertFalse(app.buttons["keepMineButton"].exists)
        pause(1)

        // Plan
        app.tabBars.buttons["Plan"].tap()
        pause(2)
        app.swipeUp()
        pause(2)

        // History and detail
        app.tabBars.buttons["History"].tap()
        pause(2)
        app.buttons.matching(identifier: "sessionRow").firstMatch.tap()
        pause(2)
        app.swipeUp()
        pause(2.5)
        app.swipeUp()
        pause(2)

        // Coach notes: the sore-knee note from the seeded history
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["coachNotesButton"].waitForExistence(timeout: 5))
        app.buttons["coachNotesButton"].tap()
        XCTAssertTrue(app.staticTexts["Left knee a bit stiff afterwards."].waitForExistence(timeout: 5))
        pause(2.5)
    }

    /// Hidden diagnostics: long-press the title on Today, then show the log.
    func testDiagnostics() {
        let title = app.staticTexts["appTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 15))
        title.press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["requestHealth"].waitForExistence(timeout: 5))
        let launch = NSPredicate(format: "label BEGINSWITH 'Now:' OR label BEGINSWITH 'Share '")
        XCTAssertTrue(app.staticTexts.matching(launch).firstMatch.waitForExistence(timeout: 5))
        pause(2)
        app.segmentedControls.buttons.element(boundBy: 1).tap()
        pause(1.5)
        app.buttons["Done"].tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5))
    }
}
