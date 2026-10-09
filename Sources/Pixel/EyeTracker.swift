import AppKit
import SwiftUI

// MARK: - EyeTracker: Isolated 60fps cursor tracking

@MainActor
public final class EyeTracker: ObservableObject {
    public static let shared = EyeTracker()

    @Published public var look: CGPoint = .zero
    @Published public var blink: CGFloat = 0.0
    @Published public var showSmile: Bool = false

    private var blinkTask: Task<Void, Never>?
    private var smileTask: Task<Void, Never>?
    private var lastCursorUpdate: TimeInterval = 0

    public init() {
        startBlinkLoop()
    }

    /// Throttled to 60fps. Called from mouse tracking on main actor.
    public func updateCursor(location: CGPoint, notchCenter: CGPoint, screenSize: CGSize) {
        let now = CACurrentMediaTime()
        guard now - lastCursorUpdate > 0.0167 else { return } // 60fps gate
        lastCursorUpdate = now

        // Normalize cursor to [-1, 1] relative to notch center
        let rawX = (location.x - notchCenter.x) / max(1, screenSize.width * 0.5)
        let rawY = (notchCenter.y - location.y) / max(1, screenSize.height * 0.5)

        let target = CGPoint(
            x: max(-1.0, min(1.0, rawX)),
            y: max(-0.8, min(1.0, rawY * 0.85))
        )

        // Low-pass filter — snappy but not jittery
        look.x += (target.x - look.x) * 0.35
        look.y += (target.y - look.y) * 0.30
    }

    public func triggerSmile(duration: Double = 3.5) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            showSmile = true
        }
        smileTask?.cancel()
        smileTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                self.showSmile = false
            }
        }
    }

    private func startBlinkLoop() {
        blinkTask = Task { [weak self] in
            while !Task.isCancelled {
                let pause = UInt64.random(in: 2_500_000_000...6_000_000_000)
                try? await Task.sleep(nanoseconds: pause)
                guard let self, !Task.isCancelled else { return }

                // Quick double-blink occasionally
                let doDouble = Bool.random() && Bool.random()
                await self.doBlink()
                if doDouble {
                    try? await Task.sleep(nanoseconds: 120_000_000)
                    await self.doBlink()
                }
            }
        }
    }

    private func doBlink() async {
        blink = 1.0
        try? await Task.sleep(nanoseconds: 90_000_000)
        blink = 0.0
    }
}
