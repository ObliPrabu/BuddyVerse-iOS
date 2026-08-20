import XCTest

/// Drives a real, several-levels-deep navigation flow (Welcome ->
/// OnePhoneSelection -> BotDifficulty -> InstructionsChoice -> the actual
/// Tic-Tac-Toe board) and confirms a tap on the board actually registers.
/// This exact depth is what exposed the RootView hit-testing bug (every
/// previously-pushed screen stayed mounted and touch-eligible, so several
/// full-screen interactive layers fought over each tap) - a shallow test
/// wouldn't have caught it.
@MainActor
final class BuddyVerseUITests: XCTestCase {
    func testTicTacToeCellTapRegisters() throws {
        // Pin portrait so the coordinate math below (based on portrait
        // spacing) is reliable - orientation itself isn't what this test
        // is checking.
        XCUIDevice.shared.orientation = .portrait

        let app = XCUIApplication()
        app.launch()

        let exploreButton = app.buttons["Explore the app"]
        XCTAssertTrue(exploreButton.waitForExistence(timeout: 15), "Welcome screen didn't load")

        let cardPredicate = NSPredicate(format: "label CONTAINS[c] %@", "Tic-Tac-Toe")
        var foundCard = false
        for _ in 0..<15 {
            if app.buttons.matching(cardPredicate).firstMatch.exists {
                foundCard = true
                break
            }
            app.swipeUp()
        }
        XCTAssertTrue(foundCard, "Could not find the Tic-Tac-Toe game card after scrolling")
        app.buttons.matching(cardPredicate).firstMatch.tap()

        let vsBotButton = app.buttons["No (Play vs Bot)"]
        XCTAssertTrue(vsBotButton.waitForExistence(timeout: 10), "OnePhoneSelection screen didn't load / wasn't tappable")
        vsBotButton.tap()

        let easyButton = app.buttons["Easy"]
        XCTAssertTrue(easyButton.waitForExistence(timeout: 10), "BotDifficulty screen didn't load / wasn't tappable")
        easyButton.tap()

        let noRulesButton = app.buttons["NO, I KNOW THE RULES"]
        XCTAssertTrue(noRulesButton.waitForExistence(timeout: 10), "InstructionsChoice screen didn't load / wasn't tappable")
        noRulesButton.tap()

        // Now 4 layers deep (Welcome, OnePhoneSelection, BotDifficulty,
        // Game) - exactly the depth that was broken.
        let resetButton = app.buttons["Reset Game"]
        XCTAssertTrue(resetButton.waitForExistence(timeout: 10), "Tic-Tac-Toe game screen didn't load")
        // waitForExistence only confirms the element entered the
        // accessibility tree, not that RootView's 0.3s push transition has
        // finished animating - give it a moment so the frame read below
        // isn't a stale mid-slide value.
        Thread.sleep(forTimeInterval: 1.0)

        // Querying cell buttons by their (empty) label matched a phantom
        // zero-size element instead of a real 80x80 cell, so anchor off a
        // real, known-size, known-position element instead: the grid sits
        // directly above "Reset Game" with a 30pt gap, so a point ~150pt
        // above its top edge, horizontally centered, lands inside the
        // middle row of the 3x3 board regardless of exact screen size.
        // Anchored off resetButton's own coordinate space (not the app's
        // {0,0} corner + absolute offset) to avoid any coordinate-space
        // mismatch on a real device.
        let tapPoint = resetButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
            .withOffset(CGVector(dx: 0, dy: -150))
        tapPoint.tap()

        let markAppeared = app.buttons["X"].waitForExistence(timeout: 3)
        XCTAssertTrue(markAppeared, "Tapping the Tic-Tac-Toe board did not place a mark - hit-testing is still broken this deep in the nav stack")
    }
}
