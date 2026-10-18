import SwiftUI

/// Mirrors VolcanoClimbActivity. A solo timing/reflex game: a needle sweeps
/// back and forth across a heat gauge, and tapping COOL DOWN only helps if the
/// needle is currently inside the green safe zone - tap while it's outside
/// that zone and the lava gets you.
///
/// Depth: a fixed 1000m climb split into four themed zones that each ramp up
/// needle speed / shrink the safe zone and add a chance of a mid-sweep "gust"
/// that relocates the safe zone; a 3-flame heat meter (one bad tap only drops
/// you to the current zone's floor, and reaching a new zone refills it); a
/// consecutive-success streak multiplying height gains; a persisted personal
/// best per difficulty; and reaching the summit ends the climb with confetti.
/// Solo only - this game never reads IS_BOT on Android either.
struct VolcanoClimbView: View {
    @StateObject private var vm: VolcanoClimbViewModel
    @StateObject private var confetti = ConfettiController()
    @EnvironmentObject private var router: Router
    @State private var showFeedback = false
    @State private var showReport = false

    init(selection: GameSelection) {
        _vm = StateObject(wrappedValue: VolcanoClimbViewModel(difficulty: selection.difficulty ?? "EASY"))
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

                Text("Tap COOL DOWN when the marker is in the green zone!")
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: 0xFFEB3B))
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)
                    .padding(.bottom, 10)

                Text("Height: \(vm.height)m / \(VolcanoClimbViewModel.summitHeight)m")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)

                Text("Best: \(vm.bestHeight)m")
                    .font(.system(size: 13))
                    .foregroundColor(Color(hex: 0xFFD8CC))
                    .padding(.bottom, 8)

                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { i in
                        Text("🔥")
                            .font(.system(size: 22))
                            .opacity(i < vm.heat ? 1.0 : 0.25)
                    }
                }
                .padding(.bottom, 4)

                Text(vm.streakText ?? "Streak x2!")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(hex: 0xFFD54F))
                    .opacity(vm.streakText == nil ? 0 : 1)
                    .padding(.bottom, 8)

                // The track's real point width isn't known until layout, so the
                // needle/safe-zone math is driven by GeometryReader and
                // re-measured whenever the width changes (rotation, split view).
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Color(hex: 0x5D4037)
                        Rectangle()
                            .fill(Color(hex: 0x4CAF50))
                            .frame(width: vm.safeZoneWidth)
                            .offset(x: vm.safeZoneStart)
                        Rectangle()
                            .fill(Color.white)
                            .frame(width: vm.needleWidth)
                            .offset(x: vm.needleX)
                    }
                    .onAppear { vm.configureTrack(width: geo.size.width) }
                    .onChange(of: geo.size.width) { w in vm.configureTrack(width: w) }
                }
                .frame(height: 44)
                .clipped()
                .padding(.top, 6)
                .padding(.bottom, 24)

                Button {
                    vm.attemptCoolDown()
                } label: {
                    Text("COOL DOWN")
                        .font(.system(size: 17, weight: .bold))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(height: 80)
                .background(Color.white)
                .foregroundColor(Color(hex: 0xD84315))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.bottom, 24)

                HStack(spacing: 10) {
                    Button("Back to Menu") { router.pop() }
                    Button("Home") { router.popToRoot() }
                }
                .font(.subheadline.bold())
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(hex: 0xDDDDDD, opacity: 0.67))
                .foregroundColor(Color(hex: 0x333333))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                HStack(spacing: 10) {
                    Button("Feedback") { showFeedback = true }
                    Button("Report") { showReport = true }
                }
                .font(.subheadline.bold())
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(hex: 0xDDDDDD, opacity: 0.67))
                .foregroundColor(Color(hex: 0x333333))
                .clipShape(RoundedRectangle(cornerRadius: 8))
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

            if vm.summitReached {
                ZStack {
                    Color.black.opacity(0.8).ignoresSafeArea()
                    VStack(spacing: 0) {
                        Text("🏔️ Summit Reached!")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .padding(.bottom, 12)
                        Text(vm.summitRecordText)
                            .font(.system(size: 16))
                            .foregroundColor(Color(hex: 0xFFD54F))
                            .multilineTextAlignment(.center)
                            .padding(.bottom, 24)
                        Button {
                            vm.restartClimb()
                        } label: {
                            Text("Climb Again")
                                .font(.system(size: 16, weight: .bold))
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                        }
                        .background(Color.white)
                        .foregroundColor(Color(hex: 0xD84315))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .padding(24)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: vm.toast)
        .confettiOverlay(confetti)
        .onChange(of: vm.summitReached) { reached in
            if reached { confetti.start() }
        }
        .onAppear { vm.resume() }
        .onDisappear { vm.stop() }
        .sheet(isPresented: $showFeedback) { FeedbackSheetView(gameType: "VOLCANO") }
        .sheet(isPresented: $showReport) { ReportSheetView(gameType: "VOLCANO") }
    }
}

struct VolcanoZone: Equatable {
    let name: String
    let floorM: Int
    let ceilingM: Int
    let bgHex: UInt32
    let speedMultiplier: CGFloat
    let safeZoneMultiplier: CGFloat
    let gustChance: Double

    var bgColor: Color { Color(hex: bgHex) }
}

@MainActor
final class VolcanoClimbViewModel: ObservableObject {
    static let zones: [VolcanoZone] = [
        VolcanoZone(name: "Base Camp", floorM: 0, ceilingM: 250, bgHex: 0xD84315, speedMultiplier: 1.0, safeZoneMultiplier: 1.0, gustChance: 0),
        VolcanoZone(name: "Ash Field", floorM: 250, ceilingM: 500, bgHex: 0xBF360C, speedMultiplier: 1.25, safeZoneMultiplier: 0.85, gustChance: 0.05),
        VolcanoZone(name: "Lava Falls", floorM: 500, ceilingM: 750, bgHex: 0x8D2B0B, speedMultiplier: 1.55, safeZoneMultiplier: 0.7, gustChance: 0.12),
        VolcanoZone(name: "Crater Rim", floorM: 750, ceilingM: 1000, bgHex: 0x6D1B00, speedMultiplier: 1.9, safeZoneMultiplier: 0.55, gustChance: 0.2)
    ]
    static let summitHeight = zones[zones.count - 1].ceilingM

    @Published var height = 0
    @Published var heat = 3
    @Published var streak = 0
    @Published var bestHeight = 0
    @Published var needleX: CGFloat = 0
    @Published var safeZoneStart: CGFloat = 0
    @Published var safeZoneWidth: CGFloat = 0
    @Published var toast: String?
    @Published var summitReached = false
    @Published var summitRecordText = ""

    let needleWidth: CGFloat = 10
    private let difficulty: String
    private let bestKey: String
    private let baseNeedleStep: CGFloat
    private let baseSafeZoneFraction: CGFloat
    // Best at the start of the current run, so 'New Record!' still means beating it.
    private var recordAtRunStart = 0
    private var trackWidth: CGFloat = 0
    private var direction: CGFloat = 1
    private var ready = false
    private var timer: Timer?
    private var toastWorkItem: DispatchWorkItem?

    var zone: VolcanoZone { zoneFor(height) }

    var streakText: String? {
        let m = multiplier
        guard m > 1 else { return nil }
        return "Streak x\(streak)! (\(String(format: "%.1f", m))x height)"
    }

    private var multiplier: Double {
        if streak >= 10 { return 2.5 }
        if streak >= 6 { return 2.0 }
        if streak >= 3 { return 1.5 }
        return 1.0
    }

    // HARD = faster needle and a narrower safe zone (less margin for error);
    // EASY = slower needle and a wider, more forgiving zone. These are the
    // zone-1 baseline; later zones scale them via the zone multipliers.
    init(difficulty: String) {
        self.difficulty = difficulty
        switch difficulty {
        case "HARD": baseNeedleStep = 16
        case "MEDIUM": baseNeedleStep = 12
        default: baseNeedleStep = 8
        }
        switch difficulty {
        case "HARD": baseSafeZoneFraction = 0.18
        case "MEDIUM": baseSafeZoneFraction = 0.26
        default: baseSafeZoneFraction = 0.36
        }
        bestKey = "volcano_best_\(difficulty)"
        bestHeight = UserDefaults.standard.integer(forKey: bestKey)
        recordAtRunStart = bestHeight
    }

    private func zoneFor(_ h: Int) -> VolcanoZone {
        Self.zones.last(where: { h >= $0.floorM }) ?? Self.zones[0]
    }

    /// Called with the track's real width on first layout and again whenever
    /// it changes; rescales the safe zone and clamps the needle to fit.
    func configureTrack(width: CGFloat) {
        guard width > 0, width != trackWidth else { return }
        trackWidth = width
        applyZoneVisuals()
        needleX = min(needleX, max(trackWidth - needleWidth, 0))
        rollNewSafeZone()
        ready = true
        resume()
    }

    private func applyZoneVisuals() {
        safeZoneWidth = trackWidth * baseSafeZoneFraction * zone.safeZoneMultiplier
    }

    private func currentNeedleStep() -> CGFloat {
        let streakBonusSpeed = 1 + CGFloat(min(streak, 10)) * 0.01
        return baseNeedleStep * zone.speedMultiplier * streakBonusSpeed
    }

    private func rollNewSafeZone() {
        let maxStart = max(trackWidth - safeZoneWidth, 0)
        safeZoneStart = maxStart > 0 ? CGFloat.random(in: 0...maxStart) : 0
    }

    /// Starts (or resumes) the needle; safe to call repeatedly. Does nothing
    /// before the track is measured or after the summit is reached.
    func resume() {
        guard ready, !summitReached, timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
            runOnMain { self?.tickNeedle() }
        }
    }

    private func tickNeedle() {
        needleX += currentNeedleStep() * direction
        let maxX = max(trackWidth - needleWidth, 0)
        if needleX <= 0 {
            needleX = 0
            direction = 1
        } else if needleX >= maxX {
            needleX = maxX
            direction = -1
        }
        // A "gust" relocates the safe zone without warning.
        let gust = zone.gustChance
        if gust > 0 && Double.random(in: 0..<1) < gust / 30 {
            rollNewSafeZone()
        }
    }

    func attemptCoolDown() {
        guard ready, !summitReached else { return }
        let needleCenter = needleX + needleWidth / 2
        let inSafeZone = needleCenter >= safeZoneStart && needleCenter <= safeZoneStart + safeZoneWidth

        if inSafeZone {
            streak += 1
            let previousZone = zone
            let gain = max(Int(Double(Int.random(in: 8..<20)) * multiplier), 1)
            height = min(height + gain, Self.summitHeight)
            let newZone = zone

            if newZone != previousZone {
                heat = 3 // reaching a new zone is itself a checkpoint - full heat refill
                applyZoneVisuals()
                showToast("Entering \(newZone.name)! Heat refilled.")
            } else {
                showToast("Nice timing! Climbed \(gain)m higher.")
            }

            if height >= Self.summitHeight {
                reachSummit()
            } else {
                rollNewSafeZone()
            }
        } else {
            streak = 0
            heat -= 1
            if heat <= 0 {
                let current = zone
                height = current.floorM
                heat = 3
                applyZoneVisuals()
                showToast("The lava overwhelmed you! Back to \(current.name)'s start.")
            } else {
                showToast("Ouch, that was hot! \(heat) heat left.")
            }
            rollNewSafeZone()
        }
        updateBest()
    }

    private func reachSummit() {
        stop()
        let isNewRecord = height > recordAtRunStart
        if isNewRecord {
            bestHeight = height
            UserDefaults.standard.set(bestHeight, forKey: bestKey)
        }
        summitRecordText = isNewRecord ? "New Record! \(bestHeight)m" : "Best: \(bestHeight)m"
        summitReached = true
    }

    func restartClimb() {
        recordAtRunStart = bestHeight
        summitReached = false
        height = 0
        heat = 3
        streak = 0
        applyZoneVisuals()
        rollNewSafeZone()
        resume()
    }

    // Keep the personal best as a high-water mark of progress, not just a
    // finished run, so 'Best' means something before the first win.
    private func updateBest() {
        if height > bestHeight {
            bestHeight = height
            UserDefaults.standard.set(bestHeight, forKey: bestKey)
        }
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

    /// Pauses the needle (view disappeared); `resume()` restarts it.
    func stop() {
        timer?.invalidate()
        timer = nil
        toastWorkItem?.cancel()
        toast = nil
    }
}
