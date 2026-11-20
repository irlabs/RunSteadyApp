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

    /// Scrolls the list until `element` sits fully below the navigation bar (the watch screen shows
    /// only a few rows). Short drags that hold before release, so the list does not fling past it.
    private func reveal(_ element: XCUIElement) -> XCUIElement {
        let list = app.collectionViews.firstMatch
        let screen = app.windows.firstMatch.frame
        func visible() -> Bool {
            element.exists && element.frame.minY >= 62 && element.frame.maxY <= screen.maxY
        }
        for _ in 0..<10 where !visible() {
            let down = element.exists && element.frame.minY < 62
            let a = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.45 : 0.7))
            let b = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.7 : 0.45))
            a.press(forDuration: 0.05, thenDragTo: b, withVelocity: .slow, thenHoldForDuration: 0.3)
            Thread.sleep(forTimeInterval: 0.6)
        }
        return element
    }

    /// Hidden diagnostics: long-press the tortoise, check permissions, try a voice, send a fake run.
    func testDiagnostics() {
        let tortoise = app.otherElements["tortoise"].exists ? app.otherElements["tortoise"] : app.buttons["tortoise"]
        XCTAssertTrue(tortoise.waitForExistence(timeout: 15))
        Thread.sleep(forTimeInterval: 2)
        tortoise.press(forDuration: 1.2)

        let check = app.buttons["checkPermissions"]
        XCTAssertTrue(check.waitForExistence(timeout: 10))
        check.tap()
        Thread.sleep(forTimeInterval: 1.5)

        reveal(app.buttons["voiceLab"]).tap()
        XCTAssertTrue(app.buttons["rateToggle"].waitForExistence(timeout: 5))
        let before = app.buttons["rateToggle"].label
        app.buttons["rateToggle"].tap()
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertNotEqual(app.buttons["rateToggle"].label, before)
        Thread.sleep(forTimeInterval: 1.5)
        app.navigationBars.buttons.firstMatch.tap()

        XCTAssertTrue(app.buttons["voiceLab"].waitForExistence(timeout: 5))
        reveal(app.buttons["fakeRun"]).tap()
        Thread.sleep(forTimeInterval: 1)
        reveal(app.buttons["logLink"]).tap()
        let logged = NSPredicate(format: "label CONTAINS 'Fake run' OR label CONTAINS 'Test workout'")
        XCTAssertTrue(app.staticTexts.matching(logged).firstMatch.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 2)
    }
}
