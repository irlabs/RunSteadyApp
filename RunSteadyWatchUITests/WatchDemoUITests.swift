import XCTest

/// Walks through a complete (fast-forwarded) session on the watch.
final class WatchDemoUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
        app.launchArguments = ["-inMemory", "YES", "-demoStage", "1", "-demoSession", "3", "-timeScale", "40"]
        app.launch()
    }

    private func waitForTarget(extra: TimeInterval = 0.4) {
        let over = NSPredicate(format: "label CONTAINS 'over'")
        let reached = expectation(for: over, evaluatedWith: app.staticTexts["statusLabel"])
        wait(for: [reached], timeout: 20)
        Thread.sleep(forTimeInterval: extra)
    }

    func testFullSession() {
        let next = app.buttons["nextButton"]
        XCTAssertTrue(app.buttons["startButton"].waitForExistence(timeout: 15))
        Thread.sleep(forTimeInterval: 2.5)
        app.buttons["startButton"].tap()

        // Warm-up: start the run early, before the target is reached.
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 4)
        next.tap()

        for round in 1...6 {
            waitForTarget(extra: round == 2 ? 1.6 : 0.4) // round 2: linger past the target
            next.tap() // -> walk
            if round == 3 {
                // Pause and resume from the controls page.
                app.swipeRight()
                app.buttons["pauseButton"].tap()
                Thread.sleep(forTimeInterval: 2)
                app.swipeRight()
                app.buttons["pauseButton"].tap()
            }
            waitForTarget()
            next.tap() // -> next run (after round 6 this is an extra round)
        }

        XCTAssertTrue(app.staticTexts["roundLabel"].label.contains("extra"))
        Thread.sleep(forTimeInterval: 2.5)
        app.buttons["coolDownButton"].tap()
        waitForTarget(extra: 1)
        next.tap() // Finish

        XCTAssertTrue(app.buttons["doneButton"].waitForExistence(timeout: 5) || app.staticTexts["Steady does it!"].exists)
        Thread.sleep(forTimeInterval: 2.5)
        app.swipeUp()
        Thread.sleep(forTimeInterval: 2.5)
        app.swipeUp()
        Thread.sleep(forTimeInterval: 1.5)
        app.buttons["doneButton"].tap()
        XCTAssertTrue(app.buttons["startButton"].waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 1.5)
    }
}
