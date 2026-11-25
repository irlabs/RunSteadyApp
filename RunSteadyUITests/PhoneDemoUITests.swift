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
        // Effort slider (G5): starts empty, a tap does nothing, a drag to an easy 3 ("Great") sets it.
        let slider = app.descendants(matching: .any).matching(identifier: "effortSlider").firstMatch
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["effortDone"].exists)
        slider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        pause(0.8)
        XCTAssertFalse(app.buttons["effortDone"].exists)
        slider.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: slider.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)),
                   withVelocity: .slow, thenHoldForDuration: 0.4)
        XCTAssertTrue(app.buttons["effortDone"].waitForExistence(timeout: 3))
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
        // G10: the choice of the next session is pinned under the conversation.
        // With a coach key, typed answers add a note-extraction call before the wrap-up, so wait long.
        let use = app.buttons["useSuggestionButton"]
        XCTAssertTrue(use.waitForExistence(timeout: 45))
        pause(3)
        let field = app.textFields["chatField"]
        field.tap()
        field.typeText("Felt easy, so I did an extra round.")
        app.buttons["chatSend"].tap()
        pause(4)
        // G11: closing settles nothing. Today keeps the card and reopens the conversation at its end.
        app.buttons["checkInClose"].tap()
        let choose = app.buttons["chooseNextButton"]
        XCTAssertTrue(choose.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Week 2 · Session 3"].exists) // next session not changed yet
        pause(2)
        choose.tap()
        XCTAssertTrue(use.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == 'Felt easy, so I did an extra round.'"))
            .firstMatch.exists)
        pause(2)
        use.tap() // applies it and closes the check-in

        // Today now shows the accepted next step; the watch confirms it (G9, simulated in the demo).
        XCTAssertTrue(app.staticTexts["Week 3"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["chooseNextButton"].exists)
        let line = app.staticTexts["watchPlanLine"]
        let confirmed = expectation(for: NSPredicate(format: "label == 'On your watch'"), evaluatedWith: line)
        wait(for: [confirmed], timeout: 8)
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

    /// G4: tapping the check-in notification opens the run's summary full screen (here via -demoOpenRun).
    func testRunSummaryFromNotification() {
        app.terminate()
        app.launchArguments = ["-demoSeed", "YES", "-demoOpenRun", "YES"]
        app.launch()
        let start = app.buttons["startCheckInButton"]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Steady does it!"].exists)
        pause(2.5)
        start.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "effortSlider").firstMatch
            .waitForExistence(timeout: 5))
        pause(1.5)
        // Closing before the answers are in keeps the run waiting for its check-in on Today.
        app.buttons["checkInClose"].tap()
        XCTAssertTrue(app.buttons["checkInButton"].waitForExistence(timeout: 5))
        pause(1.5)
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
