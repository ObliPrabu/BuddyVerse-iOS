import SwiftUI

/// Mirrors VolcanoClimbActivity. A solo timing/reflex game instead of the
/// turn-based resource-mash the other expeditions use: a needle sweeps back
/// and forth across a heat gauge, and tapping COOL DOWN only helps if the
/// needle is currently inside the green safe zone - tap while it's outside
/// that zone and the lava gets you. Each successful tap climbs higher, moves
/// the safe zone somewhere new, and speeds the needle up a little. Solo
/// only - this game never reads IS_BOT on Android either (see GameCatalog's
/// soloGamesWithNoBot), so there's no bot/pass-and-play branching here.
struct VolcanoClimbView: View {
    @StateObject private var vm: VolcanoClimbViewModel
    @EnvironmentObject private var router: Router
    @State private var showFeedback = false
    @State private var showReport = false

    init(selection: GameSelection) {
        _vm = StateObject(wrappedValue: VolcanoClimbViewModel(difficulty: selection.difficulty ?? "EASY"))
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("Volcano Climb 🌋")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.white)
                .padding(.top, 20)

            Text("Tap COOL DOWN when the marker is in the green zone!")
                .font(.system(size: 15))
                .foregroundColor(Color(hex: 0xFFEB3B))
                .multilineTextAlignment(.center)
                .padding(.bottom, 16)

            Text("Height: \(vm.height)m")
                .font(.system(size: 20))
                .foregroundColor(.white)
                .padding(.bottom, 20)

            Text("🌋")
                .font(.system(size: 55))
                .frame(width: 90, height: 90)
                .padding(.bottom, 20)

            // The track's real point width isn't known until layout, so the
            // needle/safe-zone math waits for GeometryReader's first report -
            // mirroring the Android code's own comment about waiting for
            // `track.post {}` instead of guessing a size from dp values.
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
            }
            .frame(height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .padding(.bottom, 30)

            Text(vm.message)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.9))
                .multilineTextAlignment(.center)
                .frame(minHeight: 20)

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
            .padding(.bottom, 30)

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
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: 0xD84315).ignoresSafeArea())
        .navigationTitle("Volcano Climb")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { vm.stop() }
        .sheet(isPresented: $showFeedback) { FeedbackSheetView(gameType: "VOLCANO") }
        .sheet(isPresented: $showReport) { ReportSheetView(gameType: "VOLCANO") }
    }
}

@MainActor
final class VolcanoClimbViewModel: ObservableObject {
    @Published var height = 0
    @Published var needleX: CGFloat = 0
    @Published var safeZoneStart: CGFloat = 0
    @Published var safeZoneWidth: CGFloat = 0
    @Published var message = ""

    let needleWidth: CGFloat = 10
    private let difficulty: String
    private var trackWidth: CGFloat = 0
    private var needleStep: CGFloat
    private var direction: CGFloat = 1
    private var ready = false
    private var timer: Timer?

    // HARD = faster needle and a narrower safe zone (less margin for
    // error); EASY = slower needle and a wider, more forgiving zone.
    init(difficulty: String) {
        self.difficulty = difficulty
        needleStep = Self.baseNeedleStep(for: difficulty)
    }

    private static func baseNeedleStep(for difficulty: String) -> CGFloat {
        switch difficulty {
        case "HARD": return 16
        case "MEDIUM": return 12
        default: return 8 // EASY
        }
    }

    private static func safeZoneFraction(for difficulty: String) -> CGFloat {
        switch difficulty {
        case "HARD": return 0.18
        case "MEDIUM": return 0.26
        default: return 0.36 // EASY
        }
    }

    func configureTrack(width: CGFloat) {
        guard width > 0, trackWidth == 0 else { return }
        trackWidth = width
        safeZoneWidth = width * Self.safeZoneFraction(for: difficulty)
        ready = true
        rollNewSafeZone()
        startNeedle()
    }

    private func rollNewSafeZone() {
        let maxStart = max(trackWidth - safeZoneWidth, 0)
        safeZoneStart = maxStart > 0 ? CGFloat.random(in: 0...maxStart) : 0
    }

    private func startNeedle() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
            self?.tickNeedle()
        }
    }

    private func tickNeedle() {
        needleX += needleStep * direction
        let maxX = max(trackWidth - needleWidth, 0)
        if needleX <= 0 {
            needleX = 0
            direction = 1
        } else if needleX >= maxX {
            needleX = maxX
            direction = -1
        }
    }

    func attemptCoolDown() {
        guard ready else { return }
        let needleCenter = needleX + needleWidth / 2
        let inSafeZone = needleCenter >= safeZoneStart && needleCenter <= safeZoneStart + safeZoneWidth

        if inSafeZone {
            let gain = Int.random(in: 8..<20)
            height += gain
            message = "Nice timing! Climbed \(gain)m higher."
            // Gets a bit harder each success so a long streak stays challenging.
            needleStep += 0.6
            rollNewSafeZone()
        } else {
            message = "The lava got you at \(height)m! Starting over."
            height = 0
            needleStep = Self.baseNeedleStep(for: difficulty)
            rollNewSafeZone()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
