import SwiftUI
import UIKit

/// Which game this screen is playing and how it looks.
struct ExpeditionConfig {
    /// Short key such as "ZIPLINE": used for the saved best and for Feedback/Report.
    let id: String
    let title: String
    let background: Color
}

/// Runs one round of an ArcadeGame: a 30-frames-a-second loop, the personal
/// best, and the win/lose flag. It is an ObservableObject only so the screen
/// redraws every frame; the rules themselves live in the game.
final class ExpeditionRunner: ObservableObject {
    let config: ExpeditionConfig
    let difficulty: String
    private let makeGame: (String) -> ArcadeGame
    private(set) var game: ArcadeGame
    private(set) var startLives: Int
    @Published private(set) var tick = 0
    @Published private(set) var best: Int
    @Published private(set) var finished = false
    private var timer: Timer?
    private var last = Date()

    init(config: ExpeditionConfig, difficulty: String, makeGame: @escaping (String) -> ArcadeGame) {
        self.config = config
        self.difficulty = difficulty
        self.makeGame = makeGame
        let g = makeGame(difficulty)
        self.game = g
        self.startLives = g.lives
        self.best = UserDefaults.standard.integer(forKey: "\(config.id.lowercased())_best_\(difficulty)")
    }

    var isRunning: Bool { timer != nil }

    func start() {
        guard timer == nil, game.status == .playing else { return }
        last = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in self?.frame() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func restart() {
        stop()
        game = makeGame(difficulty)
        startLives = game.lives
        finished = false
        tick += 1
        start()
    }

    private func frame() {
        let now = Date()
        // A long gap (the phone was busy) must not teleport everything, so a step is capped.
        let dt = min(100, max(0, Int(now.timeIntervalSince(last) * 1000)))
        last = now
        game.step(dtMs: dt)
        afterChange()
    }

    /// Called after every frame and every button press.
    func afterChange() {
        // Best is a high-water mark of the round, so it means something before a first win.
        if game.points > best {
            best = game.points
            UserDefaults.standard.set(best, forKey: "\(config.id.lowercased())_best_\(difficulty)")
        }
        if game.status != .playing && !finished {
            stop()
            finished = true
        }
        tick += 1
    }
}

/// The screen behind every "expedition" mini-game built on ArcadeCore.swift. A
/// game only supplies its config and how to make a new round; this screen draws
/// the sprites, builds the control buttons, shows score / best / hearts and the
/// win/lose overlay with confetti, and pauses whenever the app goes to the
/// background or a Feedback/Report sheet is open.
struct ExpeditionView: View {
    @StateObject private var runner: ExpeditionRunner
    @StateObject private var confetti = ConfettiController()
    @EnvironmentObject private var router: Router
    @State private var showFeedback = false
    @State private var showReport = false

    init(config: ExpeditionConfig, difficulty: String, makeGame: @escaping (String) -> ArcadeGame) {
        _runner = StateObject(wrappedValue: ExpeditionRunner(config: config, difficulty: difficulty, makeGame: makeGame))
    }

    private var game: ArcadeGame { runner.game }

    var body: some View {
        // Reading `tick` makes SwiftUI redraw on every frame.
        let _ = runner.tick
        return ZStack {
            runner.config.background.ignoresSafeArea()

            VStack(spacing: 0) {
                Text(runner.config.title)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.top, 6)

                Text(game.hud)
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: 0xFFF8E1))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .padding(.top, 2)

                HStack {
                    Text("\(game.goalLabel): \(game.score) / \(game.goal)")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    if game.lives >= 0 {
                        Text(String(repeating: "\u{2764}\u{FE0F}", count: max(0, game.lives))
                             + String(repeating: "\u{1F5A4}", count: max(0, runner.startLives - game.lives)))
                            .font(.system(size: 16))
                            .padding(.trailing, 10)
                    }
                    Text("Best: \(runner.best)")
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: 0xFFE0B2))
                }
                .padding(.vertical, 4)

                arena

                HStack(spacing: 8) {
                    ForEach(Array(game.controls.enumerated()), id: \.offset) { _, control in
                        ExpeditionControlButton(control: control, runner: runner)
                    }
                }
                .padding(.top, 8)

                HStack(spacing: 6) {
                    smallButton("Back") { runner.stop(); router.pop() }
                    smallButton("Home") { runner.stop(); router.popToRoot() }
                    smallButton("Feedback") { showFeedback = true }
                    smallButton("Report") { showReport = true }
                }
                .padding(.top, 6)
            }
            .buttonStyle(.plain)
            .padding(14)

            if runner.finished { overlay }
        }
        .confettiOverlay(confetti)
        .onAppear { runner.start() }
        .onDisappear { runner.stop() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in runner.stop() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            if !showFeedback && !showReport { runner.start() }
        }
        .onChange(of: showFeedback) { open in if open { runner.stop() } else if !showReport { runner.start() } }
        .onChange(of: showReport) { open in if open { runner.stop() } else if !showFeedback { runner.start() } }
        .onChange(of: runner.finished) { done in
            if done && game.status == .won { confetti.start() }
        }
        .sheet(isPresented: $showFeedback) { FeedbackSheetView(gameType: runner.config.id) }
        .sheet(isPresented: $showReport) { ReportSheetView(gameType: runner.config.id) }
    }

    private var arena: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: side * 0.03).fill(Color.white.opacity(0.2))
                ForEach(Array(game.sprites().enumerated()), id: \.offset) { _, s in
                    Text(s.emoji)
                        .font(.system(size: s.size * side))
                        .opacity(s.alpha)
                        .position(x: s.x * side, y: s.y * side)
                }
            }
            .frame(width: side, height: side)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onEnded { value in
                    guard runner.isRunning, game.status == .playing else { return }
                    game.onTapArena(x: Double(value.location.x / side), y: Double(value.location.y / side))
                    runner.afterChange()
                }
            )
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private var overlay: some View {
        VStack(spacing: 8) {
            Text(game.status == .won ? "\u{1F389} You did it!" : "Oh no! Try again!")
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(.white)
            Text("Score: \(game.points)   Best: \(runner.best)")
                .font(.system(size: 18))
                .foregroundColor(Color(hex: 0xFFEB3B))
                .padding(.bottom, 16)
            Button("PLAY AGAIN") { runner.restart() }
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(Color(hex: 0x263238))
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            smallButton("Home") { router.popToRoot() }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.8).ignoresSafeArea())
    }

    private func smallButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.system(size: 13))
            .foregroundColor(Color(hex: 0x333333))
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color(hex: 0xDDDDDD, opacity: 0xAA / 255.0))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

/// One button under the play area: a hold button reports press and release, any other reports one tap.
private struct ExpeditionControlButton: View {
    let control: ArcadeControl
    @ObservedObject var runner: ExpeditionRunner
    @State private var down = false

    var body: some View {
        Text(control.label)
            .font(.system(size: 18))
            .foregroundColor(Color(hex: 0x333333))
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(Color(hex: 0xDDDDDD, opacity: down ? 1 : 0xAA / 255.0))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !down else { return }
                        down = true
                        guard runner.isRunning else { return }
                        runner.game.onControl(id: control.id, pressed: true)
                        if !control.hold { runner.game.onControl(id: control.id, pressed: false) }
                        runner.afterChange()
                    }
                    .onEnded { _ in
                        down = false
                        if control.hold {
                            runner.game.onControl(id: control.id, pressed: false)
                            runner.afterChange()
                        }
                    }
            )
    }
}
