import XCTest

/// Walks through a complete (fast-forwarded) session on the watch.
final class WatchDemoUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
    }

    /// Week 2, session 3, fast-forwarded, welcome already done, zones for a 50-year-old.
    private func launch(_ overrides: [String: String] = [:]) {
        let defaults = ["inMemory": "YES", "demoStage": "1", "demoSession": "3", "timeScale": "40",
                        "welcomeDone": "YES", "demoAge": "50"]
        app.launchArguments = defaults.merging(overrides) { $1 }.sorted { $0.key < $1.key }
            .flatMap { ["-\($0.key)", $0.value] }
        app.launch()
    }

    private func waitForTarget(extra: TimeInterval = 0.4) {
        let over = NSPredicate(format: "label BEGINSWITH 'Over'")
        let reached = expectation(for: over, evaluatedWith: app.staticTexts["statusLabel"])
        wait(for: [reached], timeout: 20)
        Thread.sleep(forTimeInterval: extra)
    }

    func testFullSession() {
        launch()
        let next = app.buttons["nextButton"]
        XCTAssertTrue(app.buttons["startButton"].waitForExistence(timeout: 15))
        // G7: no walk after the last run, so week 2 is 2 min shorter.
        XCTAssertEqual(app.staticTexts["startDuration"].label, "≈ 32 min")
        XCTAssertFalse(app.staticTexts["welcomeBack"].exists)
        Thread.sleep(forTimeInterval: 2.5)
        app.buttons["startButton"].tap()

        // Warm-up: start the run early, before the target is reached. The big time counts down.
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        let clock = app.staticTexts["segmentClock"]
        XCTAssertFalse(clock.label.hasPrefix("+"))
        Thread.sleep(forTimeInterval: 4)
        next.tap()

        for round in 1...6 {
            waitForTarget(extra: round == 2 ? 1.6 : 0.4) // round 2: linger past the target
            if round == 2 {
                // Past the target the big time counts up with a plus. G3: the zone is a dot, no "Z3" label.
                XCTAssertTrue(clock.label.hasPrefix("+"), clock.label)
                XCTAssertTrue(app.staticTexts["bpm"].exists)
                XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'bpm · Z'")).firstMatch.exists)
            }
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
        launch()
        let tortoise = app.otherElements["tortoise"].exists ? app.otherElements["tortoise"] : app.buttons["tortoise"]
        XCTAssertTrue(tortoise.waitForExistence(timeout: 15))
        Thread.sleep(forTimeInterval: 2)
        tortoise.press(forDuration: 1.2)

        let check = app.buttons["checkPermissions"]
        XCTAssertTrue(check.waitForExistence(timeout: 10))
        check.tap()
        Thread.sleep(forTimeInterval: 1.5)

        // G2: haptic and chime checks.
        reveal(app.buttons["haptic-hapticThenChime"]).tap()
        Thread.sleep(forTimeInterval: 1)

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
        let logged = NSPredicate(format: "label CONTAINS 'Fake run' OR label CONTAINS 'Test workout' OR label CONTAINS 'Haptic'")
        XCTAssertTrue(app.staticTexts.matching(logged).firstMatch.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 2)
    }

    /// F15: after two weeks without a run the watch steps back a week by itself.
    func testWelcomeBackAfterAGap() {
        launch(["demoStage": "3", "demoSession": "2", "demoGapDays": "14"])
        let line = app.staticTexts["welcomeBack"]
        XCTAssertTrue(line.waitForExistence(timeout: 15))
        XCTAssertEqual(line.label, "Welcome back, it's been 2 weeks → Week 3")
        XCTAssertTrue(app.staticTexts["Week 3 · Session 1"].exists)
        Thread.sleep(forTimeInterval: 2.5)
    }

    /// F1: the first launch shows the welcome screen (Continue asks for Health and location).
    func testWelcomeScreenOnFirstLaunch() {
        launch(["welcomeDone": "NO"])
        XCTAssertTrue(app.buttons["welcomeContinue"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["startButton"].exists)
        Thread.sleep(forTimeInterval: 2)
    }
}
