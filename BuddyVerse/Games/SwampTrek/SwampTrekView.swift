import SwiftUI

/// Mirrors SwampTrekActivity: a solo press-and-hold timing game. Press and
/// hold WADE to fill a meter, then let go while the fill is inside the green
/// sweet spot for a clean step forward. Release too early or too late and you
/// waste a point of grit. A fixed 1000m trek split into four zones that each
/// narrow the sweet spot and speed up the fill, a 3-point grit meter, a
/// clean-release streak multiplier, a persisted best distance per difficulty,
/// and a confetti finish at 1000m. No bot, no nearby mode.
struct SwampTrekView: View {
    let selection: GameSelection
    @EnvironmentObject private var router: Router
    @StateObject private var confetti = ConfettiController()

    private struct Zone {
        let name: String
        let floorM: Int
        let ceilingM: Int
        let bgColor: UInt32
        let fillSpeedMultiplier: CGFloat
        let sweetSpotMultiplier: CGFloat
    }

    private static let zones: [Zone] = [
        Zone(name: "Shallow Marsh", floorM: 0, ceilingM: 250, bgColor: 0x33691E, fillSpeedMultiplier: 1.0, sweetSpotMultiplier: 1.0),
        Zone(name: "Mangrove Maze", floorM: 250, ceilingM: 500, bgColor: 0x2E5E1A, fillSpeedMultiplier: 1.2, sweetSpotMultiplier: 0.85),
        Zone(name: "Murky Bog", floorM: 500, ceilingM: 750, bgColor: 0x264D16, fillSpeedMultiplier: 1.45, sweetSpotMultiplier: 0.7),
        Zone(name: "Gator Territory", floorM: 750, ceilingM: 1000, bgColor: 0x1E3D12, fillSpeedMultiplier: 1.75, sweetSpotMultiplier: 0.55)
    ]
    private static let finishDistance = 1000

    @State private var distance = 0
    @State private var grit = 3
    @State private var streak = 0
    @State private var streakText = ""
    @State private var bestDistance = 0
    // Best at the start of the current run, so 'New Record!' still means beating it.
    @State private var recordAtRunStart = 0
    @State private var finished = false
    @State private var meterValue: CGFloat = 0 // 0...100
    @GestureState private var isTouching = false
    @State private var isHolding = false
    // Measured meter width in points; 0 until the first layout pass.
    @State private var containerWidth: CGFloat = 0
    @State private var sweetSpotStartFraction: CGFloat = 0 // fraction of container width, 0...1
    @State private var fillTimer: Timer?
    @State private var toastMessage: String?
    @State private var toastWorkItem: DispatchWorkItem?
    @State private var showFeedback = false
    @State private var showReport = false

    private var difficulty: String { selection.difficulty ?? "EASY" }
    private var bestKey: String { "swamp_best_\(difficulty)" }

    private func zoneFor(_ d: Int) -> Zone {
        Self.zones.last(where: { d >= $0.floorM }) ?? Self.zones[0]
    }

    // HARD = faster fill and a narrower sweet spot; EASY = slower and wider.
    // These are the zone-1 baseline; later zones scale them via the Zone multipliers.
    private var baseFillPerTick: CGFloat {
        switch difficulty {
        case "HARD": return 10
        case "MEDIUM": return 7
        default: return 4 // EASY
        }
    }

    private var baseSweetSpotFraction: CGFloat {
        switch difficulty {
        case "HARD": return 0.16
        case "MEDIUM": return 0.24
        default: return 0.34 // EASY
        }
    }

    private var currentFillPerTick: CGFloat {
        baseFillPerTick * zoneFor(distance).fillSpeedMultiplier
    }

    /// Sweet-spot width as a fraction of the measured meter width.
    private var sweetSpotWidthFraction: CGFloat {
        baseSweetSpotFraction * zoneFor(distance).sweetSpotMultiplier
    }

    var body: some View {
        let zone = zoneFor(distance)
        ZStack {
            Color(hex: zone.bgColor).ignoresSafeArea()

            VStack(spacing: 0) {
                Text(zone.name)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.top, 16)

                Text("Hold WADE, release when the fill is in the green zone!")
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: 0xFFEB3B))
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)
                    .padding(.bottom, 10)

                Text("Distance: \(distance)m / \(Self.finishDistance)m")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)

                Text("Best: \(bestDistance)m")
                    .font(.system(size: 13))
                    .foregroundColor(Color(hex: 0xDCEDC8))
                    .padding(.bottom, 8)

                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { index in
                        Text("💪")
                            .font(.system(size: 22))
                            .opacity(index < grit ? 1.0 : 0.25)
                    }
                }
                .padding(.bottom, 4)

                Text(streakText.isEmpty ? " " : streakText)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(hex: 0xFFD54F))
                    .opacity(streak > 0 && !streakText.isEmpty ? 1 : 0)
                    .padding(.bottom, 8)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Color(hex: 0x1B5E20))

                        Rectangle()
                            .fill(Color(hex: 0xFFEB3B))
                            .frame(width: geo.size.width * (meterValue / 100))

                        Rectangle()
                            .fill(Color(hex: 0x4CAF50, opacity: 0.4))
                            .frame(width: geo.size.width * sweetSpotWidthFraction)
                            .offset(x: geo.size.width * sweetSpotStartFraction)
                    }
                    // Re-measure whenever the real width changes (rotation,
                    // split view); the sweet spot is stored as a fraction of
                    // it so it stays correctly sized and placed.
                    .onAppear { containerWidth = geo.size.width }
                    .onChange(of: geo.size.width) { containerWidth = $0 }
                }
                .frame(height: 44)
                .padding(.top, 6)
                .padding(.bottom, 24)

                // Plain view + gesture rather than a Button, since this is a
                // press-and-hold control - mirrors the Android raw touch listener.
                Text("HOLD TO WADE")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(Color(hex: 0x33691E))
                    .frame(maxWidth: .infinity)
                    .frame(height: 80)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white))
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            // Also goes back to false when the system cancels
                            // the gesture, which lets us notice an interrupted hold.
                            .updating($isTouching) { _, state, _ in state = true }
                            .onChanged { _ in
                                if !isHolding && containerWidth > 0 && !finished {
                                    isHolding = true
                                    meterValue = 0
                                }
                            }
                            .onEnded { _ in
                                if isHolding {
                                    isHolding = false
                                    evaluateRelease()
                                }
                            }
                    )
                    .onChange(of: isTouching) { touching in
                        // Cancelled gesture: drop the hold without scoring it.
                        if !touching && isHolding {
                            isHolding = false
                            meterValue = 0
                        }
                    }
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

            if let toastMessage {
                VStack {
                    Spacer()
                    Text(toastMessage)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.75)))
                        .foregroundColor(.white)
                        .padding(.bottom, 60)
                        .transition(.opacity)
                }
            }

            if finished {
                VStack(spacing: 0) {
                    Text("🐊 Made it Through!")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 12)

                    Text(distance > recordAtRunStart ? "New Record! \(bestDistance)m" : "Best: \(bestDistance)m")
                        .font(.system(size: 16))
                        .foregroundColor(Color(hex: 0xFFD54F))
                        .padding(.bottom, 24)

                    Button("Trek Again") { restartTrek() }
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(Color(hex: 0x33691E))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white))
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.8).ignoresSafeArea())
            }
        }
        .animation(.easeInOut(duration: 0.2), value: toastMessage)
        .confettiOverlay(confetti)
        .onAppear {
            bestDistance = UserDefaults.standard.integer(forKey: bestKey)
            recordAtRunStart = bestDistance
            if !finished {
                rollNewSweetSpot()
                startFillLoop()
            }
        }
        .onDisappear {
            fillTimer?.invalidate()
            fillTimer = nil
            toastWorkItem?.cancel()
            toastWorkItem = nil
        }
        .sheet(isPresented: $showFeedback) { FeedbackSheetView(gameType: "SWAMP") }
        .sheet(isPresented: $showReport) { ReportSheetView(gameType: "SWAMP") }
    }

    private func saveBest() {
        UserDefaults.standard.set(bestDistance, forKey: bestKey)
    }

    private func rollNewSweetSpot() {
        // The meter only takes whole multiples of the current per-tick step
        // (plus the 100 cap), so on fast settings a narrow spot can fall
        // between two reachable values. Re-roll until the spot contains one;
        // flush against the right edge always contains the 100 cap.
        let widthPct = sweetSpotWidthFraction * 100
        let maxStartPct = max(0, 100 - widthPct)
        let step = currentFillPerTick
        var startPct = maxStartPct
        for _ in 0..<50 {
            let candidate = CGFloat.random(in: 0...maxStartPct)
            let endPct = candidate + widthPct
            let firstReachable = (candidate / step).rounded(.up) * step
            if firstReachable <= endPct || endPct >= 100 {
                startPct = candidate
                break
            }
        }
        sweetSpotStartFraction = startPct / 100
    }

    private func startFillLoop() {
        fillTimer?.invalidate()
        fillTimer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { _ in
            runOnMain {
                if isHolding {
                    meterValue = min(meterValue + currentFillPerTick, 100)
                }
            }
        }
    }

    private func evaluateRelease() {
        guard containerWidth > 0, !finished else { return }
        let sweetSpotStart = sweetSpotStartFraction * 100
        let sweetSpotEnd = sweetSpotStart + sweetSpotWidthFraction * 100
        let inSweetSpot = meterValue >= sweetSpotStart && meterValue <= sweetSpotEnd

        if inSweetSpot {
            streak += 1
            let multiplier: Float
            if streak >= 10 { multiplier = 2.5 }
            else if streak >= 6 { multiplier = 2.0 }
            else if streak >= 3 { multiplier = 1.5 }
            else { multiplier = 1.0 }
            let gain = max(Int(Float(Int.random(in: 6...15)) * multiplier), 1)
            let previousZone = zoneFor(distance).name
            distance = min(distance + gain, Self.finishDistance)
            let newZone = zoneFor(distance)

            if multiplier > 1 {
                streakText = "Streak x\(streak)! (\(String(format: "%.1f", multiplier))x distance)"
            } else {
                streakText = ""
            }

            if newZone.name != previousZone {
                grit = 3 // reaching a new zone is itself a checkpoint - full grit refill
                showToast("Entering \(newZone.name)! Grit refilled.")
            } else {
                showToast("Clean step! +\(gain)m")
            }

            if distance >= Self.finishDistance {
                updateDisplay()
                finishTrek()
                return
            }
        } else {
            streak = 0
            streakText = ""
            grit -= 1
            if grit <= 0 {
                let zone = zoneFor(distance)
                distance = zone.floorM
                grit = 3
                showToast("Stuck in the mud! Back to \(zone.name)'s start.", duration: 3.5)
            } else {
                showToast("Misstep in the mud! \(grit) grit left.")
            }
        }

        meterValue = 0
        rollNewSweetSpot()
        updateDisplay()
    }

    private func finishTrek() {
        fillTimer?.invalidate()
        fillTimer = nil
        isHolding = false
        meterValue = 0
        if distance > recordAtRunStart {
            bestDistance = distance
            saveBest()
        }
        finished = true
        confetti.start()
    }

    private func restartTrek() {
        recordAtRunStart = bestDistance
        finished = false
        distance = 0
        grit = 3
        streak = 0
        streakText = ""
        meterValue = 0
        rollNewSweetSpot()
        startFillLoop()
        updateDisplay()
    }

    private func updateDisplay() {
        // Keep the personal best as a high-water mark of progress, not just
        // a finished run, so 'Best' means something before the first win.
        if distance > bestDistance {
            bestDistance = distance
            saveBest()
        }
    }

    private func showToast(_ text: String, duration: TimeInterval = 2.0) {
        toastWorkItem?.cancel()
        toastMessage = text
        let workItem = DispatchWorkItem { toastMessage = nil }
        toastWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
    }
}
