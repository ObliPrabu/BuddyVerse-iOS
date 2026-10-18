import SwiftUI
import Combine

/// Mirrors JungleRunActivity: a fruit jumps to a new spot on a timer and must
/// be tapped before it moves. A 1000-point run split into four zones that
/// tighten the reaction window, a 3-heart stamina meter, a combo streak
/// multiplier, a persisted best score per difficulty (UserDefaults key
/// `jungle_best_<difficulty>`, same as Android), and a confetti "Reached the
/// Treehouse" overlay with a Run Again button.
struct JungleRunView: View {
    @StateObject private var vm: JungleRunViewModel
    @StateObject private var confetti = ConfettiController()
    @EnvironmentObject private var router: Router
    @Environment(\.scenePhase) private var scenePhase
    @State private var showFeedback = false
    @State private var showReport = false

    init(selection: GameSelection) {
        _vm = StateObject(wrappedValue: JungleRunViewModel(difficulty: selection.difficulty ?? "EASY"))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                vm.zone.bgColor.ignoresSafeArea()

                VStack(spacing: 0) {
                    Text(vm.zone.name)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.top, 16)

                    Text("Catch the fruit before it moves!")
                        .font(.system(size: 14))
                        .foregroundColor(Color(hex: 0xC8E6C9))
                        .multilineTextAlignment(.center)
                        .padding(.top, 6)
                        .padding(.bottom, 10)

                    Text("Score: \(vm.score) / \(JungleRunViewModel.targetScore)")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)

                    Text("Best: \(vm.bestScore)pts")
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: 0xC8E6C9))
                        .padding(.bottom, 8)

                    HStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { i in
                            Text("💚")
                                .font(.system(size: 22))
                                .opacity(i < vm.stamina ? 1.0 : 0.25)
                        }
                    }
                    .padding(.bottom, 4)

                    Text("Combo x\(vm.streak)! (\(vm.multiplier)x points)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color(hex: 0xFFD54F))
                        .opacity(vm.multiplier > 1 ? 1 : 0)
                        .padding(.bottom, 30)

                    // Placeholder for the fruit's slot in the Android column;
                    // the real fruit floats at its random position above.
                    Color.clear
                        .frame(width: 120, height: 120)
                        .padding(.bottom, 30)

                    HStack(spacing: 10) {
                        Button("Back to Menu") { vm.stop(); router.pop() }
                        Button("Home") { vm.stop(); router.popToRoot() }
                    }
                    // Android's backgroundTint is #AADDDDDD - alpha 0xAA (~0.667).
                    .buttonStyle(LegacyBorderedButtonStyle(tint: Color(hex: 0xDDDDDD).opacity(0xAA / 255.0)))
                    .foregroundColor(Color(hex: 0x333333))

                    HStack(spacing: 10) {
                        Button("Feedback") { showFeedback = true }
                        Button("Report") { showReport = true }
                    }
                    .buttonStyle(LegacyBorderedButtonStyle(tint: Color(hex: 0xDDDDDD).opacity(0xAA / 255.0)))
                    .foregroundColor(Color(hex: 0x333333))
                    .padding(.top, 10)

                    Spacer(minLength: 0)
                }
                .padding(20)

                Button {
                    vm.fruitCaught()
                } label: {
                    Text(vm.currentFruit)
                        .font(.system(size: 60))
                        .frame(width: 120, height: 120)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
                }
                .position(x: vm.fruitTopLeft.x + 60, y: vm.fruitTopLeft.y + 60)

                if let toast = vm.toast {
                    Text(toast)
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.8))
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .padding(.horizontal, 24)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 80)
                        .allowsHitTesting(false)
                }

                if vm.reachedTreehouse {
                    ZStack {
                        Color.black.opacity(0.8).ignoresSafeArea()
                        VStack(spacing: 0) {
                            Text("🐒 Reached the Treehouse!")
                                .font(.system(size: 30, weight: .bold))
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                                .padding(.bottom, 12)
                            Text(vm.recordText)
                                .font(.system(size: 16))
                                .foregroundColor(Color(hex: 0xFFD54F))
                                .multilineTextAlignment(.center)
                                .padding(.bottom, 24)
                            Button {
                                vm.restartRun()
                            } label: {
                                Text("Run Again")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(Color(hex: 0x2E7D32))
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 12)
                                    .background(Color.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        .padding(24)
                    }
                }
            }
            .onAppear { vm.configure(size: geo.size) }
            .onChange(of: geo.size) { vm.configure(size: $0) }
        }
        .confettiOverlay(confetti)
        .onReceive(vm.winPublisher) { confetti.start() }
        .onDisappear { vm.stop() }
        .onChange(of: scenePhase) { phase in
            if phase == .active { vm.resume() } else { vm.stop() }
        }
        .sheet(isPresented: $showFeedback) { FeedbackSheetView(gameType: "JUNGLE") }
        .sheet(isPresented: $showReport) { ReportSheetView(gameType: "JUNGLE") }
    }
}

private struct JungleZone: Equatable {
    let name: String
    let floorScore: Int
    let ceilingScore: Int
    let bg: UInt32
    let intervalMultiplier: Double
    var bgColor: Color { Color(hex: bg) }
}

@MainActor
final class JungleRunViewModel: ObservableObject {
    // Android works in raw pixels; converted to points at ~2.75 px/pt.
    private static let px: CGFloat = 2.75

    fileprivate static let zones: [JungleZone] = [
        JungleZone(name: "Vine Path", floorScore: 0, ceilingScore: 250, bg: 0x2E7D32, intervalMultiplier: 1.0),
        JungleZone(name: "River Crossing", floorScore: 250, ceilingScore: 500, bg: 0x00695C, intervalMultiplier: 0.82),
        JungleZone(name: "Ancient Ruins", floorScore: 500, ceilingScore: 750, bg: 0x4E342E, intervalMultiplier: 0.68),
        JungleZone(name: "Treetop Canopy", floorScore: 750, ceilingScore: 1000, bg: 0x1B5E20, intervalMultiplier: 0.55)
    ]
    static let targetScore = 1000
    private static let fruits = ["🍎", "🍌", "🍍", "🥭", "🍒"]

    @Published var score = 0
    @Published var stamina = 3
    @Published var streak = 0
    @Published var multiplier: Float = 1.0
    @Published var bestScore = 0
    @Published var reachedTreehouse = false
    @Published var recordText = ""
    @Published var currentFruit = "🍎"
    @Published var fruitTopLeft = CGPoint(x: 36, y: 73)
    @Published var toast: String?
    let winPublisher = PassthroughSubject<Void, Never>()

    private let difficulty: String
    private let baseMoveIntervalMs: Double
    private var recordAtRunStart = 0
    private var size: CGSize = .zero
    private var timer: Timer?
    private var toastWork: DispatchWorkItem?

    fileprivate var zone: JungleZone { Self.zones.last { score >= $0.floorScore }! }
    private var key: String { "jungle_best_\(difficulty)" }
    private var currentInterval: TimeInterval { baseMoveIntervalMs * zone.intervalMultiplier / 1000.0 }

    init(difficulty: String) {
        self.difficulty = difficulty
        switch difficulty {
        case "HARD": baseMoveIntervalMs = 800
        case "MEDIUM": baseMoveIntervalMs = 1150
        default: baseMoveIntervalMs = 1500
        }
        bestScore = UserDefaults.standard.integer(forKey: "jungle_best_\(difficulty)")
        recordAtRunStart = bestScore
        currentFruit = Self.fruits.randomElement()!
    }

    func configure(size newSize: CGSize) {
        let first = size == .zero
        size = newSize
        if first {
            moveFruit()
            scheduleTimeout()
        }
    }

    func resume() {
        guard size != .zero, !reachedTreehouse else { return }
        scheduleTimeout()
    }

    private func scheduleTimeout() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: currentInterval, repeats: false) { [weak self] _ in
            runOnMain { self?.fruitMissed() }
        }
    }

    func fruitCaught() {
        guard !reachedTreehouse else { return }
        streak += 1
        let previousZone = zone
        multiplier = streak >= 10 ? 2.5 : streak >= 6 ? 2.0 : streak >= 3 ? 1.5 : 1.0
        let gain = max(1, Int(Float(Int.random(in: 8..<20)) * multiplier))
        score = min(score + gain, Self.targetScore)
        let newZone = zone
        if newZone != previousZone {
            stamina = 3
            showToast("Entering \(newZone.name)! Stamina refilled.", long: false)
        }
        updateDisplay()
        if score >= Self.targetScore {
            reachTreehouse()
            return
        }
        moveFruit()
        scheduleTimeout()
    }

    private func fruitMissed() {
        guard !reachedTreehouse else { return }
        streak = 0
        multiplier = 1.0
        stamina -= 1
        if stamina <= 0 {
            let z = zone
            score = z.floorScore
            stamina = 3
            showToast("Too slow! Back to \(z.name)'s start.", long: true)
        } else {
            showToast("Missed it! \(stamina) stamina left.", long: false)
        }
        updateDisplay()
        moveFruit()
        scheduleTimeout()
    }

    private func reachTreehouse() {
        timer?.invalidate()
        timer = nil
        let isNewRecord = score > recordAtRunStart
        if isNewRecord {
            bestScore = score
            UserDefaults.standard.set(bestScore, forKey: key)
        }
        recordText = isNewRecord ? "New Record! \(bestScore)pts" : "Best: \(bestScore)pts"
        reachedTreehouse = true
        winPublisher.send()
        updateDisplay()
    }

    func restartRun() {
        recordAtRunStart = bestScore
        reachedTreehouse = false
        score = 0
        stamina = 3
        streak = 0
        multiplier = 1.0
        updateDisplay()
        moveFruit()
        scheduleTimeout()
    }

    private func moveFruit() {
        // Android spawn range in px (top-left origin), upper bounds clamped
        // for narrow windows.
        let w = size.width * Self.px
        let h = size.height * Self.px
        let x = CGFloat.random(in: 100...max(101, w - 300))
        let y = CGFloat.random(in: 200...max(201, h - 600))
        fruitTopLeft = CGPoint(x: x / Self.px, y: y / Self.px)
        currentFruit = Self.fruits.randomElement()!
    }

    private func updateDisplay() {
        if score > bestScore {
            bestScore = score
            UserDefaults.standard.set(bestScore, forKey: key)
        }
    }

    private func showToast(_ text: String, long: Bool) {
        toastWork?.cancel()
        toast = text
        let work = DispatchWorkItem { [weak self] in self?.toast = nil }
        toastWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (long ? 3.5 : 2.0), execute: work)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        toastWork?.cancel()
        toastWork = nil
        toast = nil
    }
}
