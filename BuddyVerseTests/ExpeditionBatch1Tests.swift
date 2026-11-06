import XCTest

/// Rules of Canyon Zipline, Meteor Shower, Dino Valley and Pirate Island - the same cases as Android's ExpeditionBatch1Test.
final class ExpeditionBatch1Tests: XCTestCase {
    private func zip() -> ZiplineGame { ZiplineGame(difficulty: "EASY", seed: 1) }
    private func meteor() -> MeteorGame { MeteorGame(difficulty: "EASY", seed: 1) }
    private func dino() -> DinoValleyGame { DinoValleyGame(difficulty: "EASY", seed: 3) }

    // MARK: Canyon Zipline

    func testZiplineLaneChangesAndStaysOnTheThreeLines() {
        let g = zip()
        XCTAssertEqual(g.lane, 1)
        for _ in 0..<3 { g.onControl(id: "left", pressed: true) }
        XCTAssertEqual(g.lane, 0)
        for _ in 0..<5 { g.onControl(id: "right", pressed: true) }
        XCTAssertEqual(g.lane, 2)
        g.onControl(id: "left", pressed: false)   // a release does nothing
        XCTAssertEqual(g.lane, 2)
    }

    func testZiplineTapOnEitherHalfSwitchesLane() {
        let g = zip()
        g.onTapArena(x: 0.9, y: 0.5)
        XCTAssertEqual(g.lane, 2)
        g.onTapArena(x: 0.1, y: 0.5)
        XCTAssertEqual(g.lane, 1)
    }

    func testZiplineCoinScoresAndEagleCostsAHeart() {
        let g = zip()
        g.items.append(ZiplineGame.Item(lane: 1, y: ZiplineGame.playerY, kind: .coin))
        g.items.append(ZiplineGame.Item(lane: 1, y: ZiplineGame.playerY, kind: .eagle))
        g.step(dtMs: 16)
        XCTAssertEqual(g.score, 1)
        XCTAssertEqual(g.lives, 2)
    }

    func testZiplineItemsInAnotherLaneMissYou() {
        let g = zip()
        g.items.append(ZiplineGame.Item(lane: 0, y: ZiplineGame.playerY, kind: .eagle))
        g.step(dtMs: 16)
        XCTAssertEqual(g.lives, 3)
    }

    func testZiplineWinsAt15CoinsAndLosesAfterThreeEagles() {
        let w = zip()
        for _ in 0..<15 {
            w.items.append(ZiplineGame.Item(lane: 1, y: ZiplineGame.playerY, kind: .coin))
            w.step(dtMs: 16)
        }
        XCTAssertEqual(w.status, .won)

        let l = zip()
        for _ in 0..<3 {
            l.items.append(ZiplineGame.Item(lane: 1, y: ZiplineGame.playerY, kind: .eagle))
            l.step(dtMs: 16)
        }
        XCTAssertEqual(l.status, .lost)
        XCTAssertEqual(l.lives, 0)
    }

    func testZiplineStopsMovingOnceTheRoundIsOver() {
        let g = zip()
        for _ in 0..<3 {
            g.items.append(ZiplineGame.Item(lane: 1, y: ZiplineGame.playerY, kind: .eagle))
            g.step(dtMs: 16)
        }
        let before = g.items.count
        g.step(dtMs: 1000)
        XCTAssertEqual(g.items.count, before)
        g.onControl(id: "left", pressed: true)
        XCTAssertEqual(g.lane, 1)
    }

    func testZiplineSpawnsItemsAndDropsTheOnesThatFallPast() {
        let g = zip()
        for _ in 0..<200 { g.step(dtMs: 33) }
        XCTAssertTrue(g.items.allSatisfy { $0.y <= 1.08 })
        XCTAssertFalse(g.sprites().isEmpty)
    }

    // MARK: Meteor Shower

    func testMeteorShipMovesWhileHeldAndStopsAtTheEdges() {
        let g = meteor()
        g.onControl(id: "right", pressed: true)
        for _ in 0..<200 { g.step(dtMs: 16) }
        XCTAssertEqual(g.shipX, MeteorGame.maxX, accuracy: 0.0001)
        g.onControl(id: "right", pressed: false)
        g.onControl(id: "left", pressed: true)
        for _ in 0..<400 { g.step(dtMs: 16) }
        XCTAssertEqual(g.shipX, MeteorGame.minX, accuracy: 0.0001)
    }

    func testMeteorHoldingBothButtonsStandsStill() {
        let g = meteor()
        g.onControl(id: "left", pressed: true)
        g.onControl(id: "right", pressed: true)
        g.step(dtMs: 100)
        XCTAssertEqual(g.shipX, 0.5, accuracy: 0.0001)
    }

    func testMeteorStarScoresAndMeteorHurts() {
        let g = meteor()
        g.rocks.append(MeteorGame.Rock(x: g.shipX, y: MeteorGame.shipY, fall: 0, star: true))
        g.rocks.append(MeteorGame.Rock(x: g.shipX, y: MeteorGame.shipY, fall: 0, star: false))
        g.step(dtMs: 16)
        XCTAssertEqual(g.score, 1)
        XCTAssertEqual(g.lives, 2)
    }

    func testMeteorTapNudgesTheShipTowardsTheTap() {
        let g = meteor()
        g.onTapArena(x: 0.9, y: 0.3)
        XCTAssertEqual(g.shipX, 0.7, accuracy: 0.0001)
    }

    func testMeteorWinsAt12StarsAndLosesAfterThreeHits() {
        let w = meteor()
        for _ in 0..<12 {
            w.rocks.append(MeteorGame.Rock(x: w.shipX, y: MeteorGame.shipY, fall: 0, star: true))
            w.step(dtMs: 16)
        }
        XCTAssertEqual(w.status, .won)
        let l = meteor()
        for _ in 0..<3 {
            l.rocks.append(MeteorGame.Rock(x: l.shipX, y: MeteorGame.shipY, fall: 0, star: false))
            l.step(dtMs: 16)
        }
        XCTAssertEqual(l.status, .lost)
    }

    func testHardIsFasterThanEasy() {
        XCTAssertGreaterThan(ArcadeDifficulty.speed("HARD"), ArcadeDifficulty.speed("MEDIUM"))
        XCTAssertGreaterThan(ArcadeDifficulty.speed("MEDIUM"), ArcadeDifficulty.speed("EASY"))
        XCTAssertEqual(ArcadeDifficulty.speed("anything else"), ArcadeDifficulty.speed("EASY"))
    }

    // MARK: Dino Valley

    func testDinoValleyStartsWithFiveEggsAndSafeDinosaurs() {
        for seed in UInt64(1)...50 {
            let g = DinoValleyGame(difficulty: "EASY", seed: seed)
            XCTAssertEqual(g.eggs.count, 5)
            XCTAssertEqual(Set(g.eggs.map { $0.r * 10 + $0.c }).count, 5)
            XCTAssertTrue(g.eggs.allSatisfy { !($0.r == 4 && $0.c == 0) })
            XCTAssertTrue(g.dinos.allSatisfy { !($0.r == 4 && $0.c == 0) })
        }
        XCTAssertEqual(DinoValleyGame(difficulty: "HARD", seed: 1).dinos.count, 3)
    }

    func testDinoValleyWallsStopYou() {
        let g = dino()
        g.dinos = []
        g.onControl(id: "left", pressed: true)
        g.onControl(id: "down", pressed: true)
        XCTAssertEqual(g.playerR, 4)
        XCTAssertEqual(g.playerC, 0)
    }

    func testDinoValleyCollectingEveryEggWins() {
        let g = dino()
        g.dinos = []
        g.eggs = (1...4).map { DinoValleyGame.Pos(4, $0) } + [DinoValleyGame.Pos(3, 4)]
        for _ in 0..<4 { g.onControl(id: "right", pressed: true) }
        XCTAssertEqual(g.score, 4)
        g.onControl(id: "up", pressed: true)
        XCTAssertEqual(g.status, .won)
        XCTAssertEqual(g.score, 5)
    }

    func testDinoValleyBumpSendsYouHomeAndCostsAHeart() {
        let g = dino()
        g.eggs = [DinoValleyGame.Pos(0, 4)]
        g.dinos = [DinoValleyGame.Pos(4, 1)]
        g.onControl(id: "right", pressed: true)   // walk onto the dinosaur
        XCTAssertEqual(g.lives, 2)
        XCTAssertEqual(g.playerR, 4)
        XCTAssertEqual(g.playerC, 0)
    }

    func testDinoValleyTapOnANeighbouringSquareWalksThere() {
        let g = dino()
        g.dinos = []
        g.eggs = [DinoValleyGame.Pos(0, 4)]
        g.onTapArena(x: 0.7, y: 0.9)   // two squares away: ignored
        XCTAssertEqual(g.playerC, 0)
        g.onTapArena(x: 0.3, y: 0.9)   // the next square along the bottom row
        XCTAssertEqual(g.playerC, 1)
    }

    func testDinoValleyDinosaursStayOnTheValley() {
        let g = DinoValleyGame(difficulty: "HARD", seed: 9)
        g.eggs = [DinoValleyGame.Pos(0, 4)]
        let moves = ["up", "down", "left", "right"]
        for i in 0..<300 {
            g.onControl(id: moves[i % 4], pressed: true)
            XCTAssertTrue(g.dinos.allSatisfy { (0...4).contains($0.r) && (0...4).contains($0.c) })
            if g.status != .playing { return }
        }
    }

    // MARK: Pirate Island

    func testPirateIslandHidesOneChestAndFourOrFiveTraps() {
        for seed in UInt64(1)...50 {
            let e = PirateIslandGame(difficulty: "EASY", seed: seed)
            XCTAssertEqual(e.traps.count, 4)
            XCTAssertFalse(e.traps.contains(e.chest))
            XCTAssertEqual(PirateIslandGame(difficulty: "HARD", seed: seed).traps.count, 5)
        }
    }

    func testPirateIslandCluesCountNeighbouringTraps() {
        let g = PirateIslandGame(difficulty: "EASY", seed: 5)
        for i in 0..<25 {
            XCTAssertEqual(g.trapsNear(i), g.neighbours(i).filter { g.traps.contains($0) }.count)
            XCTAssertTrue((3...8).contains(g.neighbours(i).count))
        }
        XCTAssertEqual(g.neighbours(0).count, 3)
        XCTAssertEqual(g.neighbours(12).count, 8)
    }

    func testPirateIslandFindingTheChestWinsWithPoints() {
        let g = PirateIslandGame(difficulty: "EASY", seed: 5)
        g.dig(g.chest)
        XCTAssertEqual(g.status, .won)
        XCTAssertEqual(g.score, 1)
        XCTAssertEqual(g.points, 100 + 3 * 20 - 1 * 3)
    }

    func testPirateIslandThreeTrapsEndTheRound() {
        let g = PirateIslandGame(difficulty: "EASY", seed: 5)
        for t in g.traps.prefix(3) { g.dig(t) }
        XCTAssertEqual(g.status, .lost)
        XCTAssertEqual(g.points, 0)
    }

    func testPirateIslandDiggingTheSameSquareTwiceCountsOnce() {
        let g = PirateIslandGame(difficulty: "EASY", seed: 5)
        let trap = g.traps.first!
        g.dig(trap)
        g.dig(trap)
        XCTAssertEqual(g.lives, 2)
        XCTAssertEqual(g.digs, 1)
    }

    func testPirateIslandTapDigsTheRightSquare() {
        let g = PirateIslandGame(difficulty: "EASY", seed: 5)
        let target = (0..<25).first { $0 != g.chest && !g.traps.contains($0) }!
        g.onTapArena(x: ArcadeGrid.centre(target % 5, 5), y: ArcadeGrid.centre(target / 5, 5))
        XCTAssertTrue(g.revealed.contains(target))
    }

    func testEverySpriteStaysOnTheBoard() {
        let games: [ArcadeGame] = [zip(), meteor(), dino(), PirateIslandGame(difficulty: "EASY", seed: 2)]
        for g in games {
            for _ in 0..<60 { g.step(dtMs: 33) }
            for s in g.sprites() {
                XCTAssertTrue((-0.05...1.05).contains(s.x), "sprite \(s.emoji) x=\(s.x)")
                XCTAssertTrue((-0.1...1.1).contains(s.y), "sprite \(s.emoji) y=\(s.y)")
            }
        }
    }
}
