import SwiftUI

/// Mirrors SwampTrekActivity: a solo press-and-hold timing game. Press and
/// hold WADE to fill a meter, then let go while the fill is inside the
/// randomly-placed green "sweet spot" for a clean step forward. Release too
/// early, too late, or hold until it caps out and you waste energy in the
/// mud. Energy hitting 0 resets the round. No bot, no nearby mode.
struct SwampTrekView: View {
    let selection: GameSelection
    @EnvironmentObject private var router: Router

    @State private var energy = 100
    @State private var distance = 0
    @State private var meterValue: CGFloat = 0 // 0...100
    @State private var isHolding = false
    @State private var sweetSpotWidthFraction: CGFloat = 0.34 // fraction of container width
    @State private var sweetSpotStartFraction: CGFloat = 0    // fraction of container width, 0...1
    @State private var fillTimer: Timer?
    @State private var toastMessage: String?
    @State private var toastWorkItem: DispatchWorkItem?

    // HARD = faster fill and a narrower sweet spot (less time to react,
    // less margin for error); EASY = slower fill and a wider zone.
    private var fillPerTick: CGFloat {
        switch selection.difficulty {
        case "HARD": return 10
        case "MEDIUM": return 7
        default: return 4 // EASY
        }
    }

    private var sweetSpotFraction: CGFloat {
        switch selection.difficulty {
        case "HARD": return 0.16
        case "MEDIUM": return 0.24
        default: return 0.34 // EASY
        }
    }

    var body: some View {
        ZStack {
            Color(hex: 0x33691E).ignoresSafeArea()

            VStack(spacing: 0) {
                Text("Swamp Trek 🐊")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.top, 20)
                    .padding(.bottom, 10)

                Text("Hold WADE, release when the fill is in the green zone!")
                    .font(.system(size: 15))
                    .foregroundColor(Color(hex: 0xFFEB3B))
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 16)

                Text("Energy Level: \(max(energy, 0))%")
                    .font(.system(size: 20))
                    .foregroundColor(.white)
                    .padding(.bottom, 10)

                Text("Distance: \(distance)m")
                    .font(.system(size: 20))
                    .foregroundColor(.white)
                    .padding(.bottom, 20)

                Text("🐊")
                    .font(.system(size: 55))
                    .frame(width: 90, height: 90)
                    .padding(.bottom, 20)

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
                    .onAppear {
                        sweetSpotWidthFraction = sweetSpotFraction
                        rollNewSweetSpot()
                        startFillLoop()
                    }
                }
                .frame(height: 44)
                .padding(.bottom, 30)

                // Plain view + gesture rather than a Button, since this is a
                // press-and-hold control (not a discrete tap) - mirrors the
                // Android version's raw onTouchListener with ACTION_DOWN /
                // ACTION_UP / ACTION_CANCEL instead of a click listener.
                Text("HOLD TO WADE")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(Color(hex: 0x33691E))
                    .frame(maxWidth: .infinity)
                    .frame(height: 80)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white))
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in
                                if !isHolding {
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
                    .padding(.bottom, 30)

                Button("Back to Menu") { router.pop() }
                    .font(.subheadline.bold())
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(hex: 0xDDDDDD, opacity: 0.67))
                    .foregroundColor(Color(hex: 0x333333))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding(20)

            if let toastMessage {
                VStack {
                    Spacer()
                    Text(toastMessage)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.75)))
                        .foregroundColor(.white)
                        .padding(.bottom, 120)
                        .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: toastMessage)
        .onDisappear {
            fillTimer?.invalidate()
            fillTimer = nil
        }
    }

    private func rollNewSweetSpot() {
        // Guards against the narrow-screen "empty range" crash the Android
        // version had to work around: if the sweet spot is as wide as (or
        // wider than) the container, the only valid start is 0 rather than
        // letting an inverted range through.
        let maxStartFraction = max(0, 1 - sweetSpotWidthFraction)
        sweetSpotStartFraction = .random(in: 0...maxStartFraction)
    }

    private func startFillLoop() {
        fillTimer?.invalidate()
        fillTimer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { _ in
            if isHolding {
                meterValue = min(meterValue + fillPerTick, 100)
            }
        }
    }

    private func evaluateRelease() {
        let sweetSpotStart = sweetSpotStartFraction * 100
        let sweetSpotEnd = sweetSpotStart + sweetSpotWidthFraction * 100
        let inSweetSpot = meterValue >= sweetSpotStart && meterValue <= sweetSpotEnd

        var ranOutOfEnergy = false
        if inSweetSpot {
            let gain = Int.random(in: 6...15)
            distance += gain
            showToast("Clean step! +\(gain)m")
        } else {
            let lost = Int.random(in: 10...25)
            energy -= lost
            showToast("Misstep in the mud! -\(lost)% energy")
            ranOutOfEnergy = energy <= 0
        }

        if ranOutOfEnergy {
            // Android shows two separate Toasts back-to-back here (they
            // queue and display sequentially); a short delay before the
            // second banner keeps that same "here's what happened, then
            // here's the round summary" beat instead of the first message
            // getting silently clobbered before it's ever seen.
            let strandedAt = distance
            energy = 100
            distance = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                showToast("Stuck in the mud at \(strandedAt)m! Starting over.")
            }
        }

        meterValue = 0
        rollNewSweetSpot()
    }

    private func showToast(_ text: String) {
        toastWorkItem?.cancel()
        toastMessage = text
        let workItem = DispatchWorkItem { toastMessage = nil }
        toastWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: workItem)
    }
}
