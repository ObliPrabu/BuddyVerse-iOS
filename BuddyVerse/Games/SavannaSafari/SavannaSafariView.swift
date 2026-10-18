import SwiftUI

/// Mirrors SavannaSafariActivity. A go/no-go reaction game: a target animal is
/// picked at the start ("Tap only when you see: X") and the animal shown on the
/// button keeps auto-cycling. Tapping while the target is showing scores
/// points; tapping any other animal costs a strike. Either way the display
/// jumps to a new animal immediately after the tap (so you can't farm points by
/// hammering a lucky correct animal).
///
/// Depth: a fixed 1000-point safari split into four themed zones that each
/// cycle animals faster; three strikes fall back to the current zone's floor
/// score, and strikes clear on reaching a new zone; a consecutive-correct-tap
/// "Tracker Streak" multiplies points per spot; a persisted personal best per
/// difficulty; and reaching 1000 ends the safari with confetti.
struct SavannaSafariView: View {
    @StateObject private var vm: SavannaSafariViewModel
    @StateObject private var confetti = ConfettiController()
    @EnvironmentObject private var router: Router
    @State private var showFeedback = false
    @State private var showReport = false

    init(selection: GameSelection) {
        _vm = StateObject(wrappedValue: SavannaSafariViewModel(difficulty: selection.difficulty ?? "EASY"))
    }

    var body: some View {
        ZStack {
            vm.zone.bgColor.ignoresSafeArea()
                .animation(.easeInOut(duration: 0.3), value: vm.zone.name)

            VStack(spacing: 0) {
                Text(vm.zone.name)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.top, 16)
                    .padding(.bottom, 10)

                Text("Tap only when you see: \(vm.targetAnimal)")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(Color(hex: 0x3E2723))
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 10)

                Text("Spotted: \(vm.score) / \(SavannaSafariViewModel.safariGoal)")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)

                Text("Best: \(vm.bestScore) pts")
                    .font(.system(size: 13))
                    .foregroundColor(Color(hex: 0xFFE0B2))
                    .padding(.bottom, 8)

                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { i in
                        Text("❌")
                            .font(.system(size: 22))
                            .opacity(i < vm.strikes ? 1.0 : 0.25)
                    }
                }
                .padding(.bottom, 4)

                Text(vm.streakText ?? "Streak x2!")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(hex: 0xFFF176))
                    .opacity(vm.streakText == nil ? 0 : 1)
                    .padding(.bottom, 16)

                Button {
                    vm.onAnimalTapped()
                } label: {
                    Text(vm.currentAnimal)
                        .font(.system(size: 60))
                        .frame(width: 120, height: 120)
                        .background(Circle().fill(Color.white))
                }
                .padding(.bottom, 30)

                Text("Only tap for the target animal - wrong taps cost a strike!")
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 30)

                HStack(spacing: 10) {
                    Button("Back to Menu") { router.pop() }
                    Button("Home") { router.popToRoot() }
                }
                    // Android's backgroundTint is #AADDDDDD - alpha 0xAA (~0.667), not fully opaque.
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

            if let toast = vm.toast {
                VStack {
                    Spacer()
                    Text(toast)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.75)))
                        .foregroundColor(.white)
                        .padding(.bottom, 60)
                        .padding(.horizontal, 20)
                        .transition(.opacity)
                }
                .allowsHitTesting(false)
            }

            if vm.finished {
                ZStack {
                    Color.black.opacity(0.8).ignoresSafeArea()
                    VStack(spacing: 0) {
                        Text("🦁 Safari Complete!")
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
                            vm.restartSafari()
                        } label: {
                            Text("Safari Again")
                                .font(.system(size: 16, weight: .bold))
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                        }
                        .background(Color.white)
                        .foregroundColor(Color(hex: 0xF9A825))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .padding(24)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: vm.toast)
        .confettiOverlay(confetti)
        .onChange(of: vm.finished) { done in
            if done { confetti.start() }
        }
        .onAppear { vm.resume() }
        .onDisappear { vm.stop() }
        .sheet(isPresented: $showFeedback) { FeedbackSheetView(gameType: "SAVANNA") }
        .sheet(isPresented: $showReport) { ReportSheetView(gameType: "SAVANNA") }
    }
}

struct SavannaZone: Equatable {
    let name: String
    let floorScore: Int
    let ceilingScore: Int
    let bgHex: UInt32
    let cycleSpeedMultiplier: Double // shrinks the auto-cycle interval as zones get harder

    var bgColor: Color { Color(hex: bgHex) }
}

@MainActor
final class SavannaSafariViewModel: ObservableObject {
    static let zones: [SavannaZone] = [
        SavannaZone(name: "Grasslands", floorScore: 0, ceilingScore: 250, bgHex: 0xF9A825, cycleSpeedMultiplier: 1.0),
        SavannaZone(name: "Watering Hole", floorScore: 250, ceilingScore: 500, bgHex: 0xEF6C00, cycleSpeedMultiplier: 0.8),
        SavannaZone(name: "Acacia Grove", floorScore: 500, ceilingScore: 750, bgHex: 0xD84315, cycleSpeedMultiplier: 0.62),
        SavannaZone(name: "Pride Lands", floorScore: 750, ceilingScore: 1000, bgHex: 0xBF360C, cycleSpeedMultiplier: 0.46)
    ]
    static let safariGoal = zones[zones.count - 1].ceilingScore
    static let animals = ["🦁", "🐘", "🦒", "🦓", "🦏", "🐆", "🦛"]

    @Published var score = 0
    @Published var strikes = 0
    @Published var streak = 0
    @Published var bestScore = 0
    @Published var targetAnimal: String
    @Published var currentAnimal: String
    @Published var toast: String?
    @Published var finished = false
    @Published var recordText = ""

    private let bestKey: String
    // How often the shown animal auto-cycles - shorter gaps mean less time to
    // react, which is what makes HARD harder. Zone-1 baseline; later zones
    // shrink it via cycleSpeedMultiplier.
    private let baseCycleInterval: TimeInterval
    // Best at the start of the current run, so 'New Record!' still means beating it.
    private var recordAtRunStart = 0
    private var timer: Timer?
    private var toastWorkItem: DispatchWorkItem?

    var zone: SavannaZone { zoneFor(score) }

    var streakText: String? {
        let m = multiplier
        guard m > 1 else { return nil }
        return "Streak x\(streak)! (\(String(format: "%.1f", m))x points)"
    }

    private var multiplier: Double {
        if streak >= 10 { return 2.5 }
        if streak >= 6 { return 2.0 }
        if streak >= 3 { return 1.5 }
        return 1.0
    }

    init(difficulty: String) {
        switch difficulty {
        case "HARD": baseCycleInterval = 0.8
        case "MEDIUM": baseCycleInterval = 1.15
        default: baseCycleInterval = 1.5 // EASY (and default)
        }
        bestKey = "savanna_best_\(difficulty)"
        // Picked here (not via property initializers) so no instance
        // initializer depends on another property or a static.
        let animals = Self.animals
        targetAnimal = animals.randomElement() ?? "🦁"
        currentAnimal = animals.randomElement() ?? "🦁"
        bestScore = UserDefaults.standard.integer(forKey: bestKey)
        recordAtRunStart = bestScore
    }

    private func zoneFor(_ s: Int) -> SavannaZone {
        Self.zones.last(where: { s >= $0.floorScore }) ?? Self.zones[0]
    }

    private func cycleInterval() -> TimeInterval {
        baseCycleInterval * zone.cycleSpeedMultiplier
    }

    func onAnimalTapped() {
        guard !finished else { return }
        if currentAnimal == targetAnimal {
            streak += 1
            let gain = max(Int(Double(Int.random(in: 8..<20)) * multiplier), 1)
            let previousZone = zone
            score = min(score + gain, Self.safariGoal)
            let newZone = zone
            if newZone != previousZone {
                strikes = 0
                showToast("Entering \(newZone.name)! Strikes cleared.")
            }
            if score >= Self.safariGoal {
                completeSafari()
                return
            }
        } else {
            streak = 0
            strikes += 1
            if strikes >= 3 {
                let current = zone
                score = current.floorScore
                strikes = 0
                targetAnimal = randomAnimal()
                showToast("Too many wrong taps! Back to \(current.name)'s start.")
            }
        }
        updateBest()
        cycleAnimal()
    }

    private func randomAnimal() -> String {
        Self.animals.randomElement() ?? "🦁"
    }

    private func completeSafari() {
        stop()
        let isNewRecord = score > recordAtRunStart
        if isNewRecord {
            bestScore = score
            UserDefaults.standard.set(bestScore, forKey: bestKey)
        }
        recordText = isNewRecord ? "New Record! \(bestScore) pts" : "Best: \(bestScore) pts"
        finished = true
        updateBest()
    }

    func restartSafari() {
        recordAtRunStart = bestScore
        finished = false
        score = 0
        strikes = 0
        streak = 0
        targetAnimal = randomAnimal()
        resume()
    }

    // Keep the personal best as a high-water mark of progress, not just a
    // finished run, so 'Best' means something before the first win.
    private func updateBest() {
        if score > bestScore {
            bestScore = score
            UserDefaults.standard.set(bestScore, forKey: bestKey)
        }
    }

    /// Starts (or resumes) auto-cycling; safe to call repeatedly.
    func resume() {
        guard !finished, timer == nil else { return }
        scheduleNextCycle()
    }

    private func scheduleNextCycle() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: cycleInterval(), repeats: false) { [weak self] _ in
            runOnMain {
                guard let self = self else { return }
                self.timer = nil
                self.cycleAnimal()
                self.resume()
            }
        }
    }

    private func cycleAnimal() {
        currentAnimal = randomAnimal()
    }

    private func showToast(_ text: String) {
        toastWorkItem?.cancel()
        toast = text
        let work = DispatchWorkItem { [weak self] in
            runOnMain { self?.toast = nil }
        }
        toastWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        toastWorkItem?.cancel()
        toast = nil
    }
}
