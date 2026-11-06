import XCTest

/// Rules of Shipwreck Dive, Haunted Mansion, Rainforest Canopy and Desert Oasis Race - the same cases as Android's ExpeditionBatch3Test.
final class ExpeditionBatch3Tests: XCTestCase {
    // MARK: Shipwreck Dive

    func testShipwreckPingShowsDistanceAndSpendsAir() {
        let g = ShipwreckGame(difficulty: "EASY", seed: 4)
        let miss = (0..<36).first { !g.chests.contains($0) }!
        let air = g.air
        g.dive(miss)
        XCTAssertEqual(g.air, air - 1)
        XCTAssertEqual(g.pings[miss], g.distanceToNearest(miss))
        XCTAssertGreaterThanOrEqual(g.pings[miss]!, 1)
        g.dive(miss)
        XCTAssertEqual(g.air, air - 1)
    }

    func testShipwreckCollectingAllThreeWins() {
        let g = ShipwreckGame(difficulty: "EASY", seed: 4)
        for c in g.chests { g.dive(c) }
        XCTAssertEqual(g.score, 3)
        XCTAssertEqual(g.status, .won)
    }

    func testShipwreckRunsOutOfAir() {
        let g = ShipwreckGame(difficulty: "HARD", seed: 4)
        for i in (0..<36) where !g.chests.contains(i) { g.dive(i) }
        XCTAssertEqual(g.status, .lost)
        XCTAssertEqual(g.air, 0)
    }

    func testShipwreckTapMapsToTheRightSquare() {
        let g = ShipwreckGame(difficulty: "EASY", seed: 4)
        g.onTapArena(x: 0.99, y: 0.99)
        XCTAssertTrue(g.found.contains(35) || g.pings[35] != nil)
    }

    // MARK: Haunted Mansion

    func testMansionEveryRiddleHasThreeDistinctOptions() {
        for r in MansionGame.riddles { XCTAssertEqual(Set([r.answer, r.wrong1, r.wrong2]).count, 3) }
    }

    func testMansionRightAnswersWinAfterFive() {
        let g = MansionGame(difficulty: "EASY", seed: 2)
        for _ in 0..<5 { g.onControl(id: "opt\(g.correctIndex)", pressed: true) }
        XCTAssertEqual(g.status, .won)
    }

    func testMansionThreeWrongAnswersBlowOutAllCandles() {
        let g = MansionGame(difficulty: "EASY", seed: 2)
        for _ in 0..<3 { g.onControl(id: "opt\((g.correctIndex + 1) % 3)", pressed: true) }
        XCTAssertEqual(g.lives, 0)
        XCTAssertEqual(g.status, .lost)
    }

    func testMansionRiddlesDoNotRepeatWithinARound() {
        let g = MansionGame(difficulty: "EASY", seed: 9)
        var seen = Set<String>()
        for _ in 0..<5 {
            XCTAssertTrue(seen.insert(g.current.question).inserted)
            g.onControl(id: "opt\(g.correctIndex)", pressed: true)
        }
    }

    // MARK: Rainforest Canopy

    func testCanopyLettingGoOnTargetScores() {
        let g = CanopyGame(difficulty: "EASY", seed: 1)
        g.step(dtMs: 100)
        g.moveTargetForTest(g.landing())
        g.onControl(id: "jump", pressed: true)
        XCTAssertEqual(g.score, 1)
    }

    func testCanopyMissCostsAHeartAndThreeEndTheRun() {
        let g = CanopyGame(difficulty: "EASY", seed: 1)
        for _ in 0..<3 {
            g.moveTargetForTest(g.landing() > 0.5 ? 0.05 : 0.95)
            g.onControl(id: "jump", pressed: true)
            g.step(dtMs: 600)
        }
        XCTAssertEqual(g.status, .lost)
    }

    func testCanopyDoubleTapInTheSameMomentCountsOnce() {
        let g = CanopyGame(difficulty: "EASY", seed: 1)
        g.moveTargetForTest(g.landing())
        g.onControl(id: "jump", pressed: true)
        g.onControl(id: "jump", pressed: true)
        XCTAssertEqual(g.score, 1)
    }

    // MARK: Desert Oasis Race

    func testOasisAlternatingTapsRunAndSameSideStumbles() {
        let g = OasisGame(difficulty: "EASY", seed: 1)
        g.onControl(id: "left", pressed: true)
        g.onControl(id: "right", pressed: true)
        XCTAssertEqual(g.me, OasisGame.step * 2, accuracy: 0.0001)
        g.onControl(id: "right", pressed: true)
        XCTAssertGreaterThan(g.stumble, 0)
        let at = g.me
        g.onControl(id: "left", pressed: true)
        XCTAssertEqual(g.me, at, accuracy: 0.0001)
        g.step(dtMs: 800)
        g.onControl(id: "left", pressed: true)
        XCTAssertGreaterThan(g.me, at)
    }

    func testOasisFastTapperBeatsTheRivals() {
        let g = OasisGame(difficulty: "EASY", seed: 1)
        var left = true
        var guardCount = 0
        while g.status == .playing && guardCount < 10000 {
            g.onControl(id: left ? "left" : "right", pressed: true)
            left.toggle()
            g.step(dtMs: 150)
            guardCount += 1
        }
        XCTAssertEqual(g.status, .won)
    }

    func testOasisIdlePlayerLosesToTheRivalsOrSunset() {
        let g = OasisGame(difficulty: "EASY", seed: 1)
        g.step(dtMs: 40_000)
        XCTAssertEqual(g.status, .lost)
    }
}
