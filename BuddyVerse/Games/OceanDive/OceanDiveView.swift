import SwiftUI

/// Mirrors OceanDiveActivity. A solo resource-management tap game: each tap
/// costs one bubble and gains random depth. A fixed 1000m dive split into
/// four themed zones that each reduce how much depth a dive earns; a
/// bubble meter where running dry only falls back to the current zone's
/// floor (and refills on reaching a new zone); a consecutive-good-dive
/// streak that multiplies depth gained per tap; a persisted personal-best
/// depth per difficulty; and reaching the target depth ends the dive with
/// a confetti celebration.
struct OceanDiveView: View {
    @StateObject private var vm: OceanDiveViewModel
    @StateObject private var confetti = ConfettiController()
    @EnvironmentObject private var router: Router
    @State private var showFeedback = false
    @State private var showReport = false

    init(selection: GameSelection) {
        _vm = StateObject(wrappedValue: OceanDiveViewModel(difficulty: selection.difficulty ?? "EASY"))
    }

    var body: some View {
        ZStack {
            vm.zone.bgColor.ignoresSafeArea()

            VStack(spacing: 0) {
                Text(vm.zone.name)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.top, 16)

                Text("Tap to dive deeper! Don't let the bubbles run out!")
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: 0xB2EBF2))
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)
                    .padding(.bottom, 10)

                Text("Bubbles: \(vm.bubbles) / \(vm.startingBubbles)")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)

                Text("Best: \(vm.bestDepth)m")
                    .font(.system(size: 13))
                    .foregroundColor(Color(hex: 0xB2EBF2))
                    .padding(.bottom, 8)

                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { i in
                        Text("🫧")
                            .font(.system(size: 22))
                            .opacity(vm.bubbleLit(i) ? 1.0 : 0.25)
                    }
                }
                .padding(.bottom, 4)

                Text(vm.streakText)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(hex: 0xFFD54F))
                    .opacity(vm.streakText.isEmpty ? 0 : 1)
                    .frame(minHeight: 18)
                    .padding(.bottom, 10)

                Button {
                    vm.dive()
                    if vm.reachedTarget { confetti.start() }
                } label: {
                    Text(vm.currentCreature)
                        .font(.system(size: 80))
                        .frame(width: 150, height: 150)
                        .background(Circle().fill(Color.white))
                }
                .padding(.bottom, 30)

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

            if vm.reachedTarget {
                ZStack {
                    Color.black.opacity(0.8).ignoresSafeArea()
                    VStack(spacing: 0) {
                        Text("🌊 Reached the Abyss!")
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
                            vm.restartDive()
                        } label: {
                            Text("Dive Again")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(Color(hex: 0x0288D1))
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
        .onDisappear { vm.stop() }
        .sheet(isPresented: $showFeedback) { FeedbackSheetView(gameType: "OCEAN") }
        .sheet(isPresented: $showReport) { ReportSheetView(gameType: "OCEAN") }
    }
}

struct OceanZone {
    let name: String
    let floorM: Int
    let ceilingM: Int
    let bgColor: Color
    let yieldMultiplier: Float
}

@MainActor
final class OceanDiveViewModel: ObservableObject {
    private static let zones = [
        OceanZone(name: "Sunlight Zone", floorM: 0, ceilingM: 250, bgColor: Color(hex: 0x0288D1), yieldMultiplier: 1.0),
        OceanZone(name: "Twilight Zone", floorM: 250, ceilingM: 500, bgColor: Color(hex: 0x01579B), yieldMultiplier: 0.8),
        OceanZone(name: "Midnight Zone", floorM: 500, ceilingM: 750, bgColor: Color(hex: 0x002F6C), yieldMultiplier: 0.62),
        OceanZone(name: "The Abyss", floorM: 750, ceilingM: 1000, bgColor: Color(hex: 0x001233), yieldMultiplier: 0.48)
    ]
    private static let creatures = ["🐙", "🐡", "🐬", "🐳", "🦈"]
    private let targetDepth = OceanDiveViewModel.zones.last!.ceilingM

    @Published private(set) var bubbles = 10
    @Published private(set) var startingBubbles = 10
    @Published private(set) var depth = 0
    @Published private(set) var streak = 0
    @Published private(set) var bestDepth = 0
    @Published private(set) var zone: OceanZone
    @Published private(set) var currentCreature = "🐙"
    @Published private(set) var streakText = ""
    @Published private(set) var reachedTarget = false
    @Published private(set) var recordText = ""
    @Published private(set) var toastMessage: String?

    private let difficulty: String
    private var recordAtRunStart = 0
    private var toastWorkItem: DispatchWorkItem?
    private var bestKey: String { "ocean_best_\(difficulty)" }

    init(difficulty: String) {
        self.difficulty = difficulty
        zone = OceanDiveViewModel.zones[0]
        bestDepth = UserDefaults.standard.integer(forKey: "ocean_best_\(difficulty)")
        recordAtRunStart = bestDepth
        startingBubbles = bubblesForZone(zone)
        bubbles = startingBubbles
    }

    private func zoneFor(_ d: Int) -> OceanZone {
        Self.zones.last(where: { d >= $0.floorM }) ?? Self.zones[0]
    }

    // Deeper zones pay out less depth per tap, so the bubble budget per zone
    // is the number of average un-streaked taps to cross it, scaled by a
    // difficulty factor (EASY comfortable surplus, HARD tight).
    private func bubblesForZone(_ z: OceanZone) -> Int {
        let averageTap: Float = 13 * z.yieldMultiplier
        let tapsNeeded = Int(Double((Float(z.ceilingM - z.floorM) / averageTap)).rounded(.up))
        let factor: Float
        switch difficulty {
        case "HARD": factor = 0.85
        case "MEDIUM": factor = 0.95
        default: factor = 1.1
        }
        return max(Int(Double(Float(tapsNeeded) * factor).rounded(.up)), 3)
    }

    func bubbleLit(_ index: Int) -> Bool {
        let litCount = min(max(Int((Float(bubbles) / Float(startingBubbles)) * 3), 0), 3)
        return index < litCount || (litCount == 0 && bubbles > 0 && index == 0)
    }

    func dive() {
        guard !reachedTarget else { return }
        let z = zoneFor(depth)
        // A streak only survives on a roll at or above the 13 average.
        let roll = Int.random(in: 6...20)
        if roll >= 13 { streak += 1 } else { streak = 1 }
        let multiplier: Float
        if streak >= 10 { multiplier = 2.5 }
        else if streak >= 6 { multiplier = 2.0 }
        else if streak >= 3 { multiplier = 1.5 }
        else { multiplier = 1.0 }
        let depthIncrease = max(Int(Float(roll) * z.yieldMultiplier * multiplier), 1)
        bubbles -= 1
        depth = min(depth + depthIncrease, targetDepth)
        let newZone = zoneFor(depth)

        currentCreature = Self.creatures.randomElement()!
        streakText = multiplier > 1 ? "Streak x\(streak)! (\(String(format: "%.1f", multiplier))x depth)" : ""

        if newZone.name != z.name {
            startingBubbles = bubblesForZone(newZone)
            bubbles = startingBubbles
            zone = newZone
            showToast("Entering \(newZone.name)! Bubbles refilled.", duration: 2.0)
        }

        if depth >= targetDepth {
            reachAbyss()
            return
        }

        if bubbles <= 0 {
            streak = 0
            streakText = ""
            depth = z.floorM
            startingBubbles = bubblesForZone(z)
            bubbles = startingBubbles
            zone = zoneFor(depth)
            showToast("Out of bubbles! Back to \(z.name)'s start.", duration: 3.5)
        }
        updateBest()
    }

    private func reachAbyss() {
        let isNewRecord = depth > recordAtRunStart
        if isNewRecord {
            bestDepth = depth
            UserDefaults.standard.set(bestDepth, forKey: bestKey)
        }
        recordText = isNewRecord ? "New Record! \(bestDepth)m" : "Best: \(bestDepth)m"
        reachedTarget = true
        updateBest()
    }

    func restartDive() {
        recordAtRunStart = bestDepth
        reachedTarget = false
        depth = 0
        zone = zoneFor(0)
        startingBubbles = bubblesForZone(zone)
        bubbles = startingBubbles
        streak = 0
        streakText = ""
    }

    // Keep the personal best as a high-water mark of progress.
    private func updateBest() {
        if depth > bestDepth {
            bestDepth = depth
            UserDefaults.standard.set(bestDepth, forKey: bestKey)
        }
    }

    private func showToast(_ text: String, duration: Double) {
        toastWorkItem?.cancel()
        toastMessage = text
        let item = DispatchWorkItem { [weak self] in self?.toastMessage = nil }
        toastWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: item)
    }

    func stop() {
        toastWorkItem?.cancel()
        toastWorkItem = nil
        toastMessage = nil
    }
}
