import SwiftUI

// Mirrors ConfettiView.kt: a win celebration overlay every game screen can
// trigger. Usage mirrors the Android call site exactly - hold one
// `@StateObject var confetti = ConfettiController()` per game screen, call
// `confetti.start()` on a win, and place `.confettiOverlay(confetti)` on the
// root view.
// Always owned as a @StateObject by a game View (MainActor-isolated), so
// isolating the whole class keeps the delayed-reset closure below on the
// same actor as `self` instead of racing across domains.
@MainActor
final class ConfettiController: ObservableObject {
    @Published fileprivate var isActive = false
    fileprivate var burstID = UUID()

    func start() {
        burstID = UUID()
        isActive = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
            self?.isActive = false
        }
    }
}

private struct ConfettiPiece: Identifiable {
    let id = UUID()
    let x: CGFloat          // 0...1, horizontal position
    let delay: Double
    let duration: Double
    let color: Color
    let rotationSpeed: Double
    let swayAmplitude: CGFloat
}

private let confettiColors: [Color] = [.red, .orange, .yellow, .green, .blue, .purple, .pink]

private func makePieces(count: Int = 60) -> [ConfettiPiece] {
    (0..<count).map { _ in
        ConfettiPiece(
            x: .random(in: 0...1),
            delay: .random(in: 0...0.4),
            duration: .random(in: 1.4...2.2),
            color: confettiColors.randomElement()!,
            rotationSpeed: .random(in: 180...720),
            swayAmplitude: .random(in: 10...40)
        )
    }
}

private struct ConfettiOverlay: View {
    let burstID: UUID
    @State private var pieces: [ConfettiPiece] = []
    @State private var animate = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(pieces) { piece in
                    Rectangle()
                        .fill(piece.color)
                        .frame(width: 8, height: 8)
                        .rotationEffect(.degrees(animate ? piece.rotationSpeed : 0))
                        .offset(
                            x: animate ? sin(piece.rotationSpeed) * piece.swayAmplitude : 0,
                            y: animate ? geo.size.height + 20 : -20
                        )
                        .position(x: piece.x * geo.size.width, y: 0)
                        .animation(
                            .easeIn(duration: piece.duration).delay(piece.delay),
                            value: animate
                        )
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            pieces = makePieces()
            animate = false
            DispatchQueue.main.async { animate = true }
        }
        .onChange(of: burstID) { _ in
            pieces = makePieces()
            animate = false
            DispatchQueue.main.async { animate = true }
        }
    }
}

private struct ConfettiOverlayModifier: ViewModifier {
    @ObservedObject var controller: ConfettiController

    func body(content: Content) -> some View {
        // The no-alignment trailing-closure `.overlay {}` needs iOS 15 -
        // this is the `.overlay(_:alignment:)` (iOS 13+) equivalent.
        content.overlay(
            Group {
                if controller.isActive {
                    ConfettiOverlay(burstID: controller.burstID)
                        .transition(.opacity)
                }
            }
        )
    }
}

extension View {
    func confettiOverlay(_ controller: ConfettiController) -> some View {
        modifier(ConfettiOverlayModifier(controller: controller))
    }
}
