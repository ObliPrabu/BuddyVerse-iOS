import SwiftUI
import Combine

/// Mirrors SpaceExplorerActivity: a solo tap-to-catch trip of 1000 light-years
/// split into four zones that each shrink the catch radius, a 3-tank oxygen
/// meter, a consecutive-catch "warp streak" multiplier, a persisted best
/// distance per difficulty (UserDefaults key `space_best_<difficulty>`, same as
/// the Android SharedPreferences key), and a confetti "Made it Home" overlay
/// with a Fly Again button.
struct SpaceExplorerView: View {
    @StateObject private var vm: SpaceExplorerViewModel
    @StateObject private var confetti = ConfettiController()
    @EnvironmentObject private var router: Router
    @Environment(\.scenePhase) private var scenePhase
    @State private var showFeedback = false
    @State private var showReport = false
    @State private var touchActive = false

    init(selection: GameSelection) {
        _vm = StateObject(wrappedValue: SpaceExplorerViewModel(difficulty: selection.difficulty ?? "EASY"))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                vm.zone.bgColor.ignoresSafeArea()

                // Touch layer: Android reacts to ACTION_DOWN only, so each
                // touch counts once (a miss costs oxygen) - no drag-following.
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .local)
                            .onChanged { value in
                                guard !touchActive else { return }
                                touchActive = true
                                vm.touch(at: value.location)
                            }
                            .onEnded { _ in touchActive = false }
                    )

                Text("🚀")
                    .font(.system(size: 40))
                    .frame(width: 60, height: 60)
                    .position(vm.hasPlacedShip ? vm.shipPosition : CGPoint(x: geo.size.width / 2, y: geo.size.height / 2))
                    .allowsHitTesting(false)

                Text("⭐")
                    .font(.system(size: 30))
                    .frame(width: 50, height: 50)
                    .position(x: vm.starTopLeft.x + 25, y: vm.starTopLeft.y + 25)
                    .allowsHitTesting(false)

                VStack(spacing: 0) {
                    Text(vm.zone.name)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.top, 20)

                    Text("Distance: \(vm.distance) / \(SpaceExplorerViewModel.targetDistance) ly")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Color(hex: 0xFFEB3B))
                        .padding(.top, 6)

                    Text("Best: \(vm.bestDistance) ly")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: 0xC5CAE9))
                        .padding(.top, 2)

                    HStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { i in
                            Text("🫁")
                                .font(.system(size: 20))
                                .opacity(i < vm.oxygen ? 1.0 : 0.25)
                        }
                    }
                    .padding(.top, 8)

                    Text("Warp Streak x\(vm.streak)! (\(vm.multiplier)x distance)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Color(hex: 0xFFD54F))
                        .opacity(vm.multiplier > 1 ? 1 : 0)
                        .padding(.top, 6)

                    Spacer()

                    Text("Tap near the star to catch it!")
                        .foregroundColor(.white)
                        .padding(.bottom, 20)

                    HStack(spacing: 10) {
                        Button("Feedback") { showFeedback = true }
                        Button("Report") { showReport = true }
                    }
                    .buttonStyle(LegacyBorderedButtonStyle(tint: Color(hex: 0xDDDDDD).opacity(0xAA / 255.0)))
                    .foregroundColor(Color(hex: 0x333333))
                    .padding(.bottom, 10)

                    HStack(spacing: 10) {
                        Button("Back") { vm.stop(); router.pop() }
                        Button("Home") { vm.stop(); router.popToRoot() }
                    }
                    .buttonStyle(LegacyProminentButtonStyle(tint: Color(hex: 0x757575)))
                    .foregroundColor(.white)
                    .padding(.bottom, 30)
                }

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

                if vm.reachedHome {
                    ZStack {
                        Color.black.opacity(0.8).ignoresSafeArea()
                        VStack(spacing: 0) {
                            Text("🚀 Made it Home!")
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
                                vm.restartTrip()
                            } label: {
                                Text("Fly Again")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(Color(hex: 0x1A237E))
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
            if phase != .active { vm.stop() }
        }
        .sheet(isPresented: $showFeedback) { FeedbackSheetView(gameType: "SPACE") }
        .sheet(isPresented: $showReport) { ReportSheetView(gameType: "SPACE") }
    }
}

private struct SpaceZone: Equatable {
    let name: String
    let floorLy: Int
    let ceilingLy: Int
    let bg: UInt32
    let radiusMultiplier: Float
    var bgColor: Color { Color(hex: bg) }
}

@MainActor
final class SpaceExplorerViewModel: ObservableObject {
    // Android works in raw pixels; these are converted to points with the
    // typical 2.75 px/pt density so on-screen sizes match.
    private static let px: CGFloat = 2.75

    fileprivate static let zones: [SpaceZone] = [
        SpaceZone(name: "Low Orbit", floorLy: 0, ceilingLy: 250, bg: 0x1A237E, radiusMultiplier: 1.0),
        SpaceZone(name: "Asteroid Belt", floorLy: 250, ceilingLy: 500, bg: 0x311B92, radiusMultiplier: 0.8),
        SpaceZone(name: "Nebula", floorLy: 500, ceilingLy: 750, bg: 0x4A148C, radiusMultiplier: 0.65),
        SpaceZone(name: "Deep Space", floorLy: 750, ceilingLy: 1000, bg: 0x880E4F, radiusMultiplier: 0.52)
    ]
    static let targetDistance = 1000

    @Published var distance = 0
    @Published var oxygen = 3
    @Published var streak = 0
    @Published var multiplier: Float = 1.0
    @Published var bestDistance = 0
    @Published var reachedHome = false
    @Published var recordText = ""
    @Published var shipPosition = CGPoint.zero
    @Published var hasPlacedShip = false
    @Published var starTopLeft = CGPoint(x: 18, y: 36)
    @Published var toast: String?
    let winPublisher = PassthroughSubject<Void, Never>()

    private let difficulty: String
    private let baseCatchRadius: CGFloat   // px
    private var recordAtRunStart = 0
    private var size: CGSize = .zero
    private var toastWork: DispatchWorkItem?

    fileprivate var zone: SpaceZone { Self.zones.last { distance >= $0.floorLy }! }
    private func zoneFor(_ d: Int) -> SpaceZone { Self.zones.last { d >= $0.floorLy }! }
    private var key: String { "space_best_\(difficulty)" }
    private var catchRadius: CGFloat { baseCatchRadius * CGFloat(zone.radiusMultiplier) / Self.px }

    init(difficulty: String) {
        self.difficulty = difficulty
        switch difficulty {
        case "HARD": baseCatchRadius = 90
        case "MEDIUM": baseCatchRadius = 120
        default: baseCatchRadius = 150
        }
        bestDistance = UserDefaults.standard.integer(forKey: "space_best_\(difficulty)")
        recordAtRunStart = bestDistance
    }

    func configure(size newSize: CGSize) {
        let first = size == .zero
        size = newSize
        if first { moveStar() }
    }

    func touch(at point: CGPoint) {
        guard !reachedHome else { return }
        shipPosition = point
        hasPlacedShip = true
        let star = CGPoint(x: starTopLeft.x + 25, y: starTopLeft.y + 25)
        let r = catchRadius
        if abs(point.x - star.x) < r && abs(point.y - star.y) < r {
            onStarCaught()
        } else {
            onStarMissed()
        }
    }

    private func onStarCaught() {
        streak += 1
        let previousZone = zone
        multiplier = streak >= 10 ? 2.5 : streak >= 6 ? 2.0 : streak >= 3 ? 1.5 : 1.0
        let gain = max(1, Int(Float(Int.random(in: 8..<20)) * multiplier))
        distance = min(distance + gain, Self.targetDistance)
        let newZone = zone
        if newZone != previousZone {
            oxygen = 3
            showToast("Entering \(newZone.name)! Oxygen refilled.", long: false)
        }
        updateDisplay()
        if distance >= Self.targetDistance {
            reachHome()
            return
        }
        moveStar()
    }

    private func onStarMissed() {
        streak = 0
        multiplier = 1.0
        oxygen -= 1
        if oxygen <= 0 {
            let z = zone
            distance = z.floorLy
            oxygen = 3
            showToast("Out of oxygen! Back to \(z.name)'s start.", long: true)
        }
        updateDisplay()
    }

    private func reachHome() {
        let isNewRecord = distance > recordAtRunStart
        if isNewRecord {
            bestDistance = distance
            UserDefaults.standard.set(bestDistance, forKey: key)
        }
        recordText = isNewRecord ? "New Record! \(bestDistance)ly" : "Best: \(bestDistance)ly"
        reachedHome = true
        winPublisher.send()
        updateDisplay()
    }

    func restartTrip() {
        recordAtRunStart = bestDistance
        reachedHome = false
        distance = 0
        oxygen = 3
        streak = 0
        multiplier = 1.0
        updateDisplay()
        moveStar()
    }

    private func moveStar() {
        // Android spawn range in px, top-left origin; upper bounds clamped so
        // the range stays valid on narrow/split-screen windows.
        let w = size.width * Self.px
        let h = size.height * Self.px
        let x = CGFloat.random(in: 100...max(101, w - 200))
        let y = CGFloat.random(in: 320...max(321, h - 400))
        starTopLeft = CGPoint(x: x / Self.px, y: y / Self.px)
    }

    private func updateDisplay() {
        // High-water mark of progress, like Android.
        if distance > bestDistance {
            bestDistance = distance
            UserDefaults.standard.set(bestDistance, forKey: key)
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
        toastWork?.cancel()
        toastWork = nil
        toast = nil
    }
}
