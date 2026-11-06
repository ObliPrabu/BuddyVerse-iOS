import XCTest

/// Rules of Ancient Temple, Mars Rover, River Rapids and Hot-Air Balloon - the same cases as Android's ExpeditionBatch2Test.
final class ExpeditionBatch2Tests: XCTestCase {
    // MARK: Ancient Temple

    func testTemplePuzzlesAlwaysHaveOneCorrectDistinctAnswer() {
        for s in 0..<200 {
            let p = TempleGame(difficulty: "EASY", seed: UInt64(s)).puzzle
            XCTAssertEqual(p.options.count, 3)
            XCTAssertEqual(Set(p.options).count, 3)
            XCTAssertTrue((0...2).contains(p.correct))
        }
    }

    func testTempleRightAnswerScoresAndFiveWin() {
        let g = TempleGame(difficulty: "EASY", seed: 3)
        for _ in 0..<5 { g.onControl(id: "opt\(g.puzzle.correct)", pressed: true) }
        XCTAssertEqual(g.score, 5)
        XCTAssertEqual(g.status, .won)
    }

    func testTempleWrongAnswerCostsFiveSecondsAndTimeRunsOut() {
        let g = TempleGame(difficulty: "EASY", seed: 3)
        let wrong = (0...2).first { $0 != g.puzzle.correct }!
        let before = g.timeLeft
        g.onControl(id: "opt\(wrong)", pressed: true)
        XCTAssertEqual(g.timeLeft, before - 5, accuracy: 0.01)
        XCTAssertEqual(g.score, 0)
        g.step(dtMs: 61_000)
        XCTAssertEqual(g.status, .lost)
    }

    func testTempleControlsFollowThePuzzle() {
        let g = TempleGame(difficulty: "EASY", seed: 5)
        XCTAssertEqual(g.puzzle.options, g.controls.map { $0.label })
    }

    // MARK: Mars Rover

    func testRoverDrivesAndScoopsOnlyNearASample() {
        let g = RoverGame(difficulty: "EASY", seed: 1)
        g.onControl(id: "scoop", pressed: true)
        XCTAssertEqual(g.score, 0)
        while g.pos < 0.12 - RoverGame.scoopReach + 0.001 { g.onControl(id: "drive", pressed: true) }
        g.onControl(id: "scoop", pressed: true)
        XCTAssertEqual(g.score, 1)
    }

    func testRoverStormShortensEachDrive() {
        let a = RoverGame(difficulty: "EASY", seed: 1)
        let b = RoverGame(difficulty: "EASY", seed: 1)
        var guardCount = 0
        while !b.storm && guardCount < 1000 { b.step(dtMs: 100); guardCount += 1 }
        let bStart = b.pos
        b.onControl(id: "drive", pressed: true)
        a.onControl(id: "drive", pressed: true)
        XCTAssertLessThan(b.pos - bStart, a.pos)
    }

    func testRoverLosesWhenBatteryDies() {
        let g = RoverGame(difficulty: "EASY", seed: 1)
        g.step(dtMs: 46_000)
        XCTAssertEqual(g.status, .lost)
    }

    func testRoverWinsAtFiveSamples() {
        let g = RoverGame(difficulty: "EASY", seed: 1)
        var guardCount = 0
        while g.status == .playing && guardCount < 5000 {
            g.onControl(id: "scoop", pressed: true)
            g.onControl(id: "drive", pressed: true)
            guardCount += 1
        }
        XCTAssertEqual(g.status, .won)
    }

    // MARK: River Rapids

    func testRapidsPaddleMovesRaftAgainstTheDrift() {
        let g = RapidsGame(difficulty: "EASY", seed: 1)
        g.spawnRocks = false
        let x0 = g.raftX
        g.onControl(id: "right", pressed: true)
        g.step(dtMs: 200)
        XCTAssertGreaterThan(g.raftX, x0)
        g.onControl(id: "right", pressed: false)
        g.onControl(id: "left", pressed: true)
        let x1 = g.raftX
        g.step(dtMs: 200)
        XCTAssertLessThan(g.raftX, x1)
    }

    func testRapidsRockCostsAHeartAndThreeEndTheRun() {
        let g = RapidsGame(difficulty: "EASY", seed: 1)
        g.spawnRocks = false
        for _ in 0..<3 {
            g.rocks.append(RapidsGame.Rock(x: g.raftX, y: RapidsGame.raftY))
            g.step(dtMs: 16)
        }
        XCTAssertEqual(g.lives, 0)
        XCTAssertEqual(g.status, .lost)
    }

    func testRapidsSurvivingThirtySecondsWins() {
        let g = RapidsGame(difficulty: "EASY", seed: 1)
        g.spawnRocks = false
        for _ in 0..<(31 * 20) { g.step(dtMs: 50) }
        XCTAssertEqual(g.status, .won)
    }

    // MARK: Hot-Air Balloon

    func testBalloonBurnerRisesAndReleaseSinks() {
        let g = BalloonGame(difficulty: "EASY", seed: 1)
        g.onControl(id: "burner", pressed: true)
        let a0 = g.alt
        g.step(dtMs: 200)
        XCTAssertLessThan(g.alt, a0)
        g.onControl(id: "burner", pressed: false)
        let a1 = g.alt
        g.step(dtMs: 200)
        XCTAssertGreaterThan(g.alt, a1)
    }

    func testBalloonDropOnlyScoresOverAVillage() {
        let g = BalloonGame(difficulty: "EASY", seed: 1)
        g.onControl(id: "drop", pressed: true)
        XCTAssertEqual(g.score, 0)
        g.villages.append(BalloonGame.Village(x: BalloonGame.balloonX))
        g.onControl(id: "drop", pressed: true)
        XCTAssertEqual(g.score, 2)
        g.onControl(id: "drop", pressed: true)
        XCTAssertEqual(g.score, 2)
    }

    func testBalloonRingScoresAndCloudCostsAHeart() {
        let g = BalloonGame(difficulty: "EASY", seed: 1)
        g.rings.append(BalloonGame.Ring(x: BalloonGame.balloonX, y: g.alt))
        g.clouds.append(BalloonGame.Cloud(x: BalloonGame.balloonX, y: g.alt))
        g.step(dtMs: 1)
        XCTAssertEqual(g.score, 1)
        XCTAssertEqual(g.lives, 2)
    }

    func testBalloonScrapingTheGroundCostsHeartsUntilLost() {
        let g = BalloonGame(difficulty: "EASY", seed: 1)
        var guardCount = 0
        while g.status == .playing && guardCount < 2000 { g.step(dtMs: 100); guardCount += 1 }
        XCTAssertEqual(g.status, .lost)
    }
}
