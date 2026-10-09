import Foundation
import SwiftUI

@MainActor
public final class FocusTimerService: ObservableObject {
    public static let shared = FocusTimerService()

    @Published public var isRunning: Bool = false
    @Published public var remainingSeconds: Int = 25 * 60
    @Published public var totalSeconds: Int = 25 * 60
    @Published public var presetName: String = "Pomodoro (25m)"

    private var timer: Timer?

    public init() {}

    public var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return Double(totalSeconds - remainingSeconds) / Double(totalSeconds)
    }

    public var formattedTime: String {
        let mins = remainingSeconds / 60
        let secs = remainingSeconds % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    public func start(duration: Int = 25 * 60, name: String = "Focus") {
        stop()
        self.totalSeconds = duration
        self.remainingSeconds = duration
        self.presetName = name
        self.isRunning = true

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.remainingSeconds > 0 {
                    self.remainingSeconds -= 1
                } else {
                    self.stop()
                    NSSound.beep()
                    PixelBrain.shared.status = "Focus timer '\(self.presetName)' completed! 🎉"
                    PixelBrain.shared.triggerSmile(duration: 6)
                }
            }
        }
    }

    public func pauseResume() {
        if isRunning {
            timer?.invalidate()
            timer = nil
            isRunning = false
        } else {
            guard remainingSeconds > 0 else {
                start(duration: totalSeconds, name: presetName)
                return
            }
            isRunning = true
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if self.remainingSeconds > 0 {
                        self.remainingSeconds -= 1
                    } else {
                        self.stop()
                        NSSound.beep()
                        PixelBrain.shared.status = "Timer completed! 🎉"
                        PixelBrain.shared.triggerSmile(duration: 6)
                    }
                }
            }
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
    }

    public func reset() {
        stop()
        remainingSeconds = totalSeconds
    }
}
