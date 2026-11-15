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
        app.buttons["feeling-great"].tap()
        pause(1.5)
        app.buttons["comfort-yes"].tap()
        pause(1.5)
        app.buttons["knee-none"].tap()
        // The same offer also appears on Today underneath the sheet; tap the one in the chat.
        let offers = app.buttons.matching(identifier: "useSuggestionButton")
        XCTAssertTrue(offers.firstMatch.waitForExistence(timeout: 30))
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
        pause(2.5)
        // The plan's suggestion is offered again; ignore it.
        app.buttons["keepMineButton"].tap()
        pause(2)

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
    }
}
