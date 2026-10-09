import SwiftUI

// MARK: - Pixel Eyes: White minimal dots with cursor tracking, blink, and rich easter eggs

public struct EyesView: View {
    @ObservedObject private var tracker = EyeTracker.shared
    public var mood: EyeMood
    public var isCompact: Bool

    @State private var orbitAngle: Double = 0.0
    @State private var scanSweep: CGFloat = -1.0
    @State private var winkLeft: Bool = false
    @State private var winkRight: Bool = false
    @State private var isWinking: Bool = false
    @State private var pulseScale: CGFloat = 1.0

    public init(mood: EyeMood = .idle, isCompact: Bool = false) {
        self.mood = mood
        self.isCompact = isCompact
    }

    // Eye dimensions
    private var eyeW: CGFloat { isCompact ? 9.0  : 11.0 }
    private var eyeH: CGFloat { isCompact ? 9.0  : 11.0 }
    private var eyeGap: CGFloat { isCompact ? 9.0 : 13.0 }

    public var body: some View {
        VStack(spacing: 2.5) {
            Group {
                switch mood {
                case .thinking:
                    thinkingView
                default:
                    eyesRow
                }
            }

            // Easter Egg Smile (pixel blocks)
            if tracker.showSmile {
                PixelSmileView(isCompact: isCompact)
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.2).combined(with: .opacity),
                            removal:   .scale(scale: 0.2).combined(with: .opacity)
                        )
                    )
                    .animation(.spring(response: 0.2, dampingFraction: 0.6), value: tracker.showSmile)
            }
        }
        .onAppear {
            startContinuousAnims()
        }
        .onChange(of: mood) { _, m in
            if m == .scanning { startScanSweep() }
        }
        .onTapGesture(count: 2) {
            // Easter egg: double-tap winks then smiles
            triggerWink()
        }
    }

    // MARK: - Normal Eyes Row
    private var eyesRow: some View {
        HStack(spacing: eyeGap) {
            eyeShape(isLeft: true)
            eyeShape(isLeft: false)
        }
        .offset(x: gazeOffset.x, y: gazeOffset.y)
        .animation(.interactiveSpring(response: 0.18, dampingFraction: 0.68, blendDuration: 0), value: tracker.look)
        .animation(.easeOut(duration: 0.07), value: tracker.blink)
        .scaleEffect(pulseScale)
        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulseScale)
    }

    @ViewBuilder
    private func eyeShape(isLeft: Bool) -> some View {
        let isThisWinking = (isLeft && winkLeft) || (!isLeft && winkRight)
        let isBlinking = tracker.blink > 0.6

        let height: CGFloat = {
            if isThisWinking || isBlinking { return 1.8 }
            if mood == .sleeping { return 1.8 }
            if mood == .scanning { return eyeH * 1.35 }
            if mood == .executing { return eyeH * 1.1 }
            return eyeH
        }()

        if mood == .sleeping {
            // Closed sleeping arc
            Capsule()
                .fill(Color.white.opacity(0.55))
                .frame(width: eyeW * 1.2, height: 2.0)
                .shadow(color: Color.white.opacity(0.25), radius: 3)
                .animation(.spring(response: 0.3), value: mood)
        } else {
            Capsule()
                .fill(Color.white)
                .frame(width: eyeW, height: height)
                // Inner glow
                .overlay(
                    Capsule()
                        .fill(Color.white.opacity(0.4))
                        .blur(radius: 1)
                )
                // Outer glow (signature boring.notch eyes look)
                .shadow(color: Color.white, radius: 3)
                .shadow(color: Color.white.opacity(0.5), radius: 7)
                .animation(.spring(response: 0.14, dampingFraction: 0.7), value: height)
        }
    }

    // MARK: - Thinking Orbit Animation
    private var thinkingView: some View {
        HStack(spacing: eyeGap) {
            ForEach(0..<2, id: \.self) { i in
                ZStack {
                    // Track
                    Capsule()
                        .fill(Color.white.opacity(0.14))
                        .frame(width: isCompact ? 14 : 16, height: 3.5)

                    // Orbiting dot
                    Circle()
                        .fill(Color.white)
                        .frame(width: 4.5, height: 4.5)
                        .shadow(color: .white, radius: 4)
                        .offset(
                            x: cos(orbitAngle + Double(i) * .pi) * (isCompact ? 5 : 5.5),
                            y: sin(orbitAngle + Double(i) * .pi) * 1.2
                        )
                }
                .frame(width: isCompact ? 16 : 18, height: 11)
            }
        }
    }

    // MARK: - Gaze offset (cursor tracking)
    private var gazeOffset: CGPoint {
        let travel: CGFloat = isCompact ? 2.8 : 3.5
        switch mood {
        case .scanning:
            return CGPoint(x: scanSweep * 4.5, y: 3.2)
        case .executing:
            return CGPoint(x: tracker.look.x * 4.5, y: max(2.0, tracker.look.y * 3.5))
        case .sleeping:
            return CGPoint(x: 0, y: 1.5)
        default:
            return CGPoint(
                x: max(-travel, min(travel, tracker.look.x * travel)),
                y: max(-2.0, min(travel * 0.65, tracker.look.y * travel * 0.65))
            )
        }
    }

    // MARK: - Easter Egg: Double-tap Wink
    private func triggerWink() {
        guard !isWinking else { return }
        isWinking = true
        withAnimation(.spring(response: 0.12)) { winkLeft = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            withAnimation(.spring(response: 0.12)) { winkLeft = false }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.spring(response: 0.12)) { winkRight = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            withAnimation(.spring(response: 0.12)) { winkRight = false }
            tracker.triggerSmile(duration: 3.5)
            isWinking = false
        }
    }

    private func startContinuousAnims() {
        // Orbit spin
        withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) {
            orbitAngle = .pi * 2
        }
        // Subtle idle pulse (only when idle)
        if mood == .idle {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                    pulseScale = 1.06
                }
            }
        }
    }

    private func startScanSweep() {
        scanSweep = -1.0
        withAnimation(.easeInOut(duration: 0.65).repeatForever(autoreverses: true)) {
            scanSweep = 1.0
        }
    }
}

// MARK: - Pixel Smile View (Pixelated block aesthetic + glow)
public struct PixelSmileView: View {
    public var isCompact: Bool

    // Classic 5-column pixel smile curve: 0,1 → down, 2 → straight, 3,4 → up
    private let yOffsets: [CGFloat] = [1.5, 0.0, -0.8, 0.0, 1.5]

    public var body: some View {
        HStack(spacing: isCompact ? 1.8 : 2.2) {
            ForEach(0..<5, id: \.self) { i in
                RoundedRectangle(cornerRadius: 0.8)
                    .fill(Color.white)
                    .frame(
                        width:  isCompact ? 2.2 : 2.8,
                        height: isCompact ? 1.8 : 2.2
                    )
                    .offset(y: yOffsets[i])
            }
        }
        .shadow(color: .white, radius: 2)
        .shadow(color: Color.white.opacity(0.4), radius: 5)
        .padding(.top, 1)
    }
}
