import SwiftUI

/// Mirrors MountainClimbActivity. A solo self-paced rhythm game: tap STEP at
/// a steady pace to climb. Tap too soon and you lose grip; wait too long and
/// a gust of wind costs grip. A fixed 1000m climb split into four zones that
/// each tighten the ideal-pace window and shorten the wind-gust fuse; a
/// 3-point grip meter (0 grip falls back to the current zone's floor, grip
/// refills on reaching a new zone); a consecutive-ideal-tap streak
/// multiplier; a persisted best per difficulty; and a confetti summit win.
/// The wind-gust timer is paused while the app is backgrounded or the view
/// is off screen, and restarts with a full fuse on return.
struct MountainClimbView: View {
    @StateObject private var vm: MountainClimbViewModel
    @StateObject private var confetti = ConfettiController()
    @EnvironmentObject private var router: Router
    @Environment(\.scenePhase) private var scenePhase
    @State private var showFeedback = false
    @State private var showReport = false

    init(selection: GameSelection) {
        _vm = StateObject(wrappedValue: MountainClimbViewModel(difficulty: selection.difficulty ?? "EASY"))
    }

    var body: some View {
        ZStack {
            vm.zone.bgColor.ignoresSafeArea()

            VStack(spacing: 0) {
                Text(vm.zone.name)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.top, 16)

                Text("Tap STEP at a steady pace - not too fast, not too slow!")
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: 0xFFEB3B))
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)
                    .padding(.bottom, 10)

                Text("Altitude: \(vm.height)m / \(vm.summitHeight)m")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)

                Text("Best: \(vm.bestHeight)m")
                    .font(.system(size: 13))
                    .foregroundColor(Color(hex: 0xCFD8DC))
                    .padding(.bottom, 8)

                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { i in
                        Text("🧗")
                            .font(.system(size: 22))
                            .opacity(i < vm.grip ? 1.0 : 0.25)
                    }
                }
                .padding(.bottom, 4)

                Text(vm.streakText)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(hex: 0xFFD54F))
                    .opacity(vm.streakText.isEmpty ? 0 : 1)
                    .frame(minHeight: 18)
                    .padding(.bottom, 4)

                Text(vm.paceMessage)
                    .font(.system(size: 16))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .frame(minHeight: 22)
                    .padding(.bottom, 16)

                Button {
                    vm.onStepTapped()
                    if vm.reachedSummit { confetti.start() }
                } label: {
                    Text("STEP")
                        .font(.system(size: 17, weight: .bold))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(height: 80)
                .background(Color.white)
                .foregroundColor(Color(hex: 0x546E7A))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.bottom, 24)

                HStack(spacing: 10) {
                    Button("Back to Menu") { router.pop() }
                    Button("Home") { router.popToRoot() }
                }
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

            if vm.reachedSummit {
                ZStack {
                    Color.black.opacity(0.8).ignoresSafeArea()
                    VStack(spacing: 0) {
                        Text("🏔️ Summit Reached!")
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
                            vm.restartClimb()
                        } label: {
                            Text("Climb Again")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(Color(hex: 0x546E7A))
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white))
                        }
                    }
                    .padding(24)
                }
            }

            if let toast = vm.toastMessage {
                VStack {
                    Spacer()
                    Text(toast)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.75)))
                        .foregroundColor(.white)
                        .padding(.bottom, 40)
                        .transition(.opacity)
                }
                .allowsHitTesting(false)
            }
        }
        .confettiOverlay(confetti)
        .animation(.easeInOut(duration: 0.2), value: vm.toastMessage)
        .animation(.easeInOut(duration: 0.3), value: vm.zone.name)
        .onAppear { vm.resume() }
        .onDisappear { vm.pause() }
        .onChange(of: scenePhase) { phase in
            if phase == .active { vm.resume() } else { vm.pause() }
        }
        .sheet(isPresented: $showFeedback) { FeedbackSheetView(gameType: "MOUNTAIN") }
        .sheet(isPresented: $showReport) { ReportSheetView(gameType: "MOUNTAIN") }
    }
}

struct MountainZone {
    let name: String
    let floorM: Int
    let ceilingM: Int
    let bgColor: Color
    let windowMultiplier: Float
    let gustSpeedMultiplier: Float
}

@MainActor
final class MountainClimbViewModel: ObservableObject {
    private static let zones = [
        MountainZone(name: "Trailhead", floorM: 0, ceilingM: 250, bgColor: Color(hex: 0x546E7A), windowMultiplier: 1.0, gustSpeedMultiplier: 1.0),
        MountainZone(name: "Treeline", floorM: 250, ceilingM: 500, bgColor: Color(hex: 0x455A64), windowMultiplier: 0.85, gustSpeedMultiplier: 0.85),
        MountainZone(name: "Rocky Ridge", floorM: 500, ceilingM: 750, bgColor: Color(hex: 0x37474F), windowMultiplier: 0.7, gustSpeedMultiplier: 0.7),
        MountainZone(name: "Summit Approach", floorM: 750, ceilingM: 1000, bgColor: Color(hex: 0x263238), windowMultiplier: 0.55, gustSpeedMultiplier: 0.55)
    ]
    let summitHeight = MountainClimbViewModel.zones.last!.ceilingM

    @Published private(set) var height = 0
    @Published private(set) var grip = 3
    @Published private(set) var bestHeight = 0
    @Published private(set) var zone: MountainZone
    @Published private(set) var paceMessage = " "
    @Published private(set) var streakText = ""
    @Published private(set) var reachedSummit = false
    @Published private(set) var recordText = ""
    @Published private(set) var toastMessage: String?

    private let difficulty: String
    private var streak = 0
    private var lastTapTime: Date?
    private var hasTapped = false
    private var recordAtRunStart = 0
    private var toastWorkItem: DispatchWorkItem?
    private var gustWorkItem: DispatchWorkItem?
    // True from a tap until the gust fires or is cancelled by the next tap /
    // summit / restart. While true with no work item, the fuse is paused
    // (backgrounded or off screen) and resume() re-arms it.
    private var gustArmed = false

    private let baseIdealMinGapMs: Double
    private let baseIdealMaxGapMs: Double
    private let baseWindGustTimeoutMs: Double
    private var bestKey: String { "mountain_best_\(difficulty)" }

    init(difficulty: String) {
        self.difficulty = difficulty
        switch difficulty {
        case "HARD":
            baseIdealMinGapMs = 450; baseIdealMaxGapMs = 700; baseWindGustTimeoutMs = 1600
        case "MEDIUM":
            baseIdealMinGapMs = 400; baseIdealMaxGapMs = 850; baseWindGustTimeoutMs = 1900
        default: // EASY
            baseIdealMinGapMs = 350; baseIdealMaxGapMs = 1000; baseWindGustTimeoutMs = 2400
        }
        zone = MountainClimbViewModel.zones[0]
        bestHeight = UserDefaults.standard.integer(forKey: "mountain_best_\(difficulty)")
        recordAtRunStart = bestHeight
    }

    private func zoneFor(_ h: Int) -> MountainZone {
        Self.zones.last(where: { h >= $0.floorM }) ?? Self.zones[0]
    }
    private func idealMinGapMs() -> Double { Double(Int(Float(baseIdealMinGapMs) * zoneFor(height).windowMultiplier)) }
    private func idealMaxGapMs() -> Double { Double(Int(Float(baseIdealMaxGapMs) * zoneFor(height).windowMultiplier)) }
    private func windGustTimeoutMs() -> Double { Double(Int(Float(baseWindGustTimeoutMs) * zoneFor(height).gustSpeedMultiplier)) }

    func onStepTapped() {
        guard !reachedSummit else { return }
        let now = Date()
        cancelWindGust()

        if !hasTapped {
            hasTapped = true
            paceMessage = "Keep that pace going!"
        } else {
            let gap = now.timeIntervalSince(lastTapTime ?? now) * 1000
            if gap < idealMinGapMs() {
                paceMessage = "Too fast - you're exhausted!"
                loseGrip("Too rushed - that cost you grip!")
            } else if gap <= idealMaxGapMs() {
                streak += 1
                let multiplier: Float
                if streak >= 10 { multiplier = 2.5 }
                else if streak >= 6 { multiplier = 2.0 }
                else if streak >= 3 { multiplier = 1.5 }
                else { multiplier = 1.0 }
                let gain = max(Int(Float(Int.random(in: 8...18)) * multiplier), 1)
                climbBy(gain)
                paceMessage = "Great pace! +\(gain)m"
                streakText = multiplier > 1 ? "Streak x\(streak)! (\(String(format: "%.1f", multiplier))x height)" : ""
            } else {
                streak = 0
                streakText = ""
                let gain = Int.random(in: 1...4)
                climbBy(gain)
                paceMessage = "A bit slow, but still climbing. +\(gain)m"
            }
        }
        lastTapTime = now
        if height < summitHeight { scheduleWindGust() }
        updateBest()
    }

    private func climbBy(_ gain: Int) {
        let previous = zoneFor(height)
        height = min(height + gain, summitHeight)
        let newZone = zoneFor(height)
        if newZone.name != previous.name {
            grip = 3
            zone = newZone
            showToast("Entering \(newZone.name)! Grip refilled.", duration: 2.0)
        }
        if height >= summitHeight { reachSummit() }
    }

    private func loseGrip(_ message: String) {
        streak = 0
        streakText = ""
        grip -= 1
        if grip <= 0 {
            let z = zoneFor(height)
            height = z.floorM
            grip = 3
            hasTapped = false
            zone = zoneFor(height)
            showToast("Lost your footing! Back to \(z.name)'s start.", duration: 3.5)
        } else {
            showToast("\(message) (\(grip) grip left)", duration: 2.0)
        }
        updateBest()
    }

    // MARK: Wind gust (pausable)

    private func scheduleWindGust() {
        gustWorkItem?.cancel()
        gustArmed = true
        armGustTimer()
    }

    private func armGustTimer() {
        gustWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.gustWorkItem = nil
            self.gustArmed = false
            self.paceMessage = "A gust of wind caught you off guard!"
            self.loseGrip("A gust of wind caught you off guard!")
        }
        gustWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + windGustTimeoutMs() / 1000, execute: item)
    }

    private func cancelWindGust() {
        gustWorkItem?.cancel()
        gustWorkItem = nil
        gustArmed = false
    }

    /// Backgrounded or leaving the screen: stop the fuse but remember it was armed.
    func pause() {
        gustWorkItem?.cancel()
        gustWorkItem = nil
        toastWorkItem?.cancel()
        toastWorkItem = nil
        toastMessage = nil
    }

    /// Returning: re-arm a full fuse if one was pending when we paused.
    func resume() {
        guard gustArmed, gustWorkItem == nil, !reachedSummit else { return }
        armGustTimer()
    }

    private func reachSummit() {
        cancelWindGust()
        let isNewRecord = height > recordAtRunStart
        if isNewRecord {
            bestHeight = height
            UserDefaults.standard.set(bestHeight, forKey: bestKey)
        }
        recordText = isNewRecord ? "New Record! \(bestHeight)m" : "Best: \(bestHeight)m"
        reachedSummit = true
        updateBest()
    }

    func restartClimb() {
        recordAtRunStart = bestHeight
        cancelWindGust()
        reachedSummit = false
        height = 0
        grip = 3
        streak = 0
        hasTapped = false
        paceMessage = " "
        streakText = ""
        zone = zoneFor(0)
    }

    private func updateBest() {
        if height > bestHeight {
            bestHeight = height
            UserDefaults.standard.set(bestHeight, forKey: bestKey)
        }
    }

    private func showToast(_ text: String, duration: Double) {
        toastWorkItem?.cancel()
        toastMessage = text
        let item = DispatchWorkItem { [weak self] in self?.toastMessage = nil }
        toastWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: item)
    }
}
