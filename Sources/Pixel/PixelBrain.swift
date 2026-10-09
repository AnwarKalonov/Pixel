import AppKit
import Foundation
import SwiftUI

public struct ChatMessage: Identifiable, Sendable {
    public let id: UUID
    public let role: String
    public let text: String
    public let timestamp: Date

    public init(id: UUID = UUID(), role: String, text: String, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = timestamp
    }
}

@MainActor
public final class PixelBrain: ObservableObject {
    public static let shared = PixelBrain()

    // MARK: - Notch Expansion & Eye State
    @Published public var expansionLevel: ExpansionLevel = .closed
    @Published public var isHovered: Bool = false
    @Published public var mood: EyeMood = .idle {
        didSet {
            if mood == .sleeping {
                eyeTracker.look = CGPoint(x: 0, y: 0.8)
            }
        }
    }

    // MARK: - Live Status & Command Bar
    @Published public var input: String = ""
    @Published public var status: String = "Watching display from notch"
    @Published public var activeActionSummary: String = ""
    @Published public var isBusy: Bool = false
    @Published public var showSettings: Bool = false

    // MARK: - Chat Conversation History
    @Published public var chatMessages: [ChatMessage] = [
        ChatMessage(role: "assistant", text: "Pixel is ready in your notch. Drop files, control media, or tell me to click and type anywhere.")
    ]

    // MARK: - Screen & Vision State
    @Published public var latestOCRText: String = ""
    @Published public var isProtectedByBlacklist: Bool = false

    // MARK: - Services
    public let shelf = ShelfService.shared
    public let controls = SystemControlsService.shared
    public let localSearch = LocalSearchService.shared
    public let eyeTracker = EyeTracker.shared

    public var onSizeChange: (() -> Void)?
    public var onOpenHouse: (() -> Void)?

    private let screen = ScreenSense()
    private let hands = Hands()
    private let client = ModelClient()
    private let overlay = GuideOverlay()

    private var glanceTask: Task<Void, Never>?
    private var hoverTimer: Task<Void, Never>?

    public init() {
        Permissions.promptAccessibility()
    }

    // MARK: - Expansion Level Control
    public func expand() {
        setExpansionLevel(.expanded)
    }

    public func collapse() {
        setExpansionLevel(.closed)
    }

    public func toggleExpanded() {
        if expansionLevel == .expanded {
            collapse()
        } else {
            expand()
        }
    }

    public func setExpansionLevel(_ level: ExpansionLevel) {
        guard expansionLevel != level else { return }
        expansionLevel = level

        switch level {
        case .closed:
            showSettings = false
            controls.stopCamera()
            if mood != .sleeping { mood = .idle }
            activeActionSummary = ""

        case .hoverPeek:
            controls.refreshMedia()
            controls.refreshVolume()
            if controls.isPlaying {
                status = "\(controls.trackTitle)"
            } else {
                status = "Pixel · Idle"
            }

        case .expanded:
            controls.refreshMedia()
            controls.refreshVolume()
            status = "Pixel AI Deck · ⌥ Space to hide"
        }

        onSizeChange?()
    }

    // MARK: - Mouse Hover Expansion
    public func handleMouseEnter() {
        guard expansionLevel == .closed else { return }
        isHovered = true

        let settings = PixelSettings.shared
        guard settings.hoverExpansionEnabled else { return }

        hoverTimer?.cancel()
        hoverTimer = Task { [weak self] in
            let delay = UInt64(settings.hoverDelaySeconds * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delay)
            guard let self, !Task.isCancelled, self.isHovered, self.expansionLevel == .closed else { return }

            let targetLevel: ExpansionLevel = settings.hoverExpandToFull ? .expanded : .hoverPeek
            self.setExpansionLevel(targetLevel)
        }
    }

    public func handleMouseExit() {
        isHovered = false
        hoverTimer?.cancel()
        if expansionLevel == .hoverPeek {
            setExpansionLevel(.closed)
        }
    }

    // MARK: - Mouse Tracking
    public func trackMouse(_ location: CGPoint) {
        guard let screen = NSScreen.main else { return }
        let settings = PixelSettings.shared

        let notchCenter = CGPoint(
            x: screen.frame.midX + settings.notchOffsetX,
            y: screen.frame.maxY + settings.notchOffsetY
        )

        // Pass to isolated EyeTracker
        eyeTracker.updateCursor(
            location: location,
            notchCenter: notchCenter,
            screenSize: screen.frame.size
        )

        // Notch bounds check
        let curSize = NotchMetrics.size(for: expansionLevel)
        let notchRect = CGRect(
            x: notchCenter.x - curSize.width / 2 - 8,
            y: screen.frame.maxY + settings.notchOffsetY - curSize.height - 8,
            width: curSize.width + 16,
            height: curSize.height + 16
        )

        let isInside = notchRect.contains(location)
        if isInside && !isHovered && expansionLevel == .closed {
            handleMouseEnter()
        } else if !isInside && isHovered && expansionLevel != .expanded {
            handleMouseExit()
        }
    }

    // MARK: - Eye Mood Triggers
    public func triggerSmile(duration: Double = 3.5) {
        eyeTracker.triggerSmile(duration: duration)
    }

    public func glance() async {
        glanceTask?.cancel()
        glanceTask = Task { [weak self] in
            guard let self else { return }
            self.mood = .scanning
            self.status = "Pixel scanning display OCR…"
            if let shot = await self.screen.capture() {
                self.latestOCRText = shot.ocr
                self.status = "Screen scanned (\(shot.words.count) elements found)"
            }
            try? await Task.sleep(nanoseconds: 800_000_000)
            self.mood = .idle
        }
    }

    // MARK: - Drop Shelf Integrations
    public func handleDroppedURL(_ url: URL) {
        guard let item = shelf.addFile(from: url) else { return }
        status = "Saved '\(item.filename)' to drop shelf"
        triggerSmile(duration: 4)

        if expansionLevel == .closed {
            setExpansionLevel(.hoverPeek)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                if self?.expansionLevel == .hoverPeek {
                    self?.setExpansionLevel(.closed)
                }
            }
        }
    }

    public func handleDroppedText(_ text: String) {
        guard let item = shelf.addSnippet(text: text) else { return }
        status = "Saved snippet to drop shelf"
        triggerSmile(duration: 4)
    }

    public func askAIAboutShelfItem(_ item: ShelfItem) {
        let content = shelf.readFileContent(for: item)
        input = "Analyze this file '\(item.filename)': \(content.prefix(300))"
        expand()
    }

    // MARK: - Real AI Interaction & Autonomous Screen Navigation
    public func submit() async {
        let prompt = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isBusy else { return }
        input = ""

        chatMessages.append(ChatMessage(role: "user", text: prompt))

        // Easter Egg
        let lower = prompt.lowercased()
        if lower.contains("smile") || lower.contains("pixel") || lower.contains("hello") || lower.contains("thank") {
            triggerSmile(duration: 4.5)
        }

        // Quick System Controls via Natural Language
        if lower.contains("mute") {
            controls.toggleMute()
            triggerSmile()
            let msg = controls.isMuted ? "Muted system volume." : "Unmuted system volume."
            chatMessages.append(ChatMessage(role: "assistant", text: msg))
            status = msg
            return
        } else if lower.contains("volume") {
            if let num = extractNumber(from: lower) {
                controls.setVolume(Double(num))
                triggerSmile()
                let msg = "Set system volume to \(num)%."
                chatMessages.append(ChatMessage(role: "assistant", text: msg))
                status = msg
                return
            }
        } else if lower.contains("play") || lower.contains("pause") {
            controls.togglePlayPause()
            triggerSmile()
            let msg = "Toggled music playback."
            chatMessages.append(ChatMessage(role: "assistant", text: msg))
            status = msg
            return
        } else if lower.contains("next song") || lower.contains("skip") {
            controls.nextTrack()
            triggerSmile()
            let msg = "Skipped to next track."
            chatMessages.append(ChatMessage(role: "assistant", text: msg))
            status = msg
            return
        } else if lower.contains("camera") || lower.contains("mirror") {
            controls.toggleCamera()
            triggerSmile()
            let msg = controls.isCameraActive ? "Opened camera mirror." : "Closed camera mirror."
            chatMessages.append(ChatMessage(role: "assistant", text: msg))
            status = msg
            return
        }

        // Focus & Pomodoro Timers: "timer 25", "pomodoro", "timer 10m"
        if lower.starts(with: "timer ") || lower == "pomodoro" || lower.contains("start timer") {
            let minutes = extractNumber(from: lower) ?? 25
            FocusTimerService.shared.start(duration: minutes * 60, name: "\(minutes)m Focus")
            triggerSmile()
            let msg = "Started \(minutes)-minute focus timer in the notch."
            chatMessages.append(ChatMessage(role: "assistant", text: msg))
            status = msg
            return
        } else if lower == "stop timer" || lower == "pause timer" {
            FocusTimerService.shared.pauseResume()
            triggerSmile()
            let msg = FocusTimerService.shared.isRunning ? "Resumed timer." : "Paused timer."
            chatMessages.append(ChatMessage(role: "assistant", text: msg))
            status = msg
            return
        }

        // Real Local File Finder
        if lower.starts(with: "find ") || lower.contains("search ") {
            let q = prompt.replacingOccurrences(of: "find ", with: "", options: .caseInsensitive)
                          .replacingOccurrences(of: "search ", with: "", options: .caseInsensitive)
            await localSearch.search(query: q, in: PixelSettings.shared.indexedDirectories)
            triggerSmile()
            let msg = "Found \(localSearch.results.count) matching local files on disk."
            chatMessages.append(ChatMessage(role: "assistant", text: msg))
            status = msg
            return
        }

        // Autonomous Screen Navigation: "click [button/text]"
        if lower.starts(with: "click ") || lower.starts(with: "tap ") {
            let target = prompt.replacingOccurrences(of: "click ", with: "", options: .caseInsensitive)
                               .replacingOccurrences(of: "tap ", with: "", options: .caseInsensitive)
                               .trimmingCharacters(in: .whitespacesAndNewlines)
            await executeClickOnScreen(target: target)
            return
        }

        // Autonomous Typing: "type [text]"
        if lower.starts(with: "type ") {
            let textToType = prompt.replacingOccurrences(of: "type ", with: "", options: .caseInsensitive)
            mood = .executing
            status = "Typing: \(textToType)…"
            hands.type(textToType)
            triggerSmile()
            let msg = "Typed '\(textToType)' into the active application."
            chatMessages.append(ChatMessage(role: "assistant", text: msg))
            status = msg
            mood = .idle
            return
        }

        // Execute via Custom User AI API or Local Engine
        await runModelTask(prompt: prompt)
    }

    // Autonomous Screen Action: Find target via Vision and click it
    public func executeClickOnScreen(target: String) async {
        isBusy = true
        mood = .scanning
        status = "Scanning display for '\(target)'…"

        guard let shot = await screen.capture() else {
            isBusy = false
            mood = .idle
            let msg = "Could not capture display to locate '\(target)'."
            chatMessages.append(ChatMessage(role: "assistant", text: msg))
            return
        }

        latestOCRText = shot.ocr

        if let wordBox = shot.findText(target) {
            mood = .executing
            status = "Found '\(target)'. Clicking…"
            activeActionSummary = "Clicking: \(wordBox.text)"

            // Show visual guide overlay
            overlay.show(rect: wordBox.rect, message: "Pixel Clicking Here")

            // Look toward target
            let center = CGPoint(x: wordBox.rect.midX, y: wordBox.rect.midY)
            hands.moveAndClick(center)
            triggerSmile(duration: 3)

            let msg = "Clicked '\(wordBox.text)' at screen coordinates (\(Int(center.x)), \(Int(center.y)))."
            chatMessages.append(ChatMessage(role: "assistant", text: msg))
            status = msg
        } else {
            let msg = "Could not find '\(target)' on screen. Make sure the window is visible."
            chatMessages.append(ChatMessage(role: "assistant", text: msg))
            status = msg
        }

        isBusy = false
        mood = .idle
        activeActionSummary = ""
    }

    private func extractNumber(from text: String) -> Int? {
        let comps = text.components(separatedBy: CharacterSet.decimalDigits.inverted)
        for c in comps {
            if let num = Int(c), num >= 0, num <= 100 { return num }
        }
        return nil
    }

    private func runModelTask(prompt: String) async {
        isBusy = true
        mood = .thinking
        status = "AI thinking…"
        defer {
            isBusy = false
            mood = .idle
        }

        let settings = PixelSettings.shared

        // If user provided custom API Key or Endpoint
        if !settings.apiBaseURL.isEmpty {
            var modelMessages: [ModelClient.Message] = [
                .init(role: "system", content: .text("You are Pixel, a fast native macOS notch assistant with full control over the user's Mac. Be helpful, concise, and direct."))
            ]

            // Include recent conversation
            for msg in chatMessages.suffix(6) {
                modelMessages.append(.init(role: msg.role, content: .text(msg.text)))
            }

            do {
                let reply = try await client.complete(
                    endpoint: settings.apiBaseURL,
                    apiKey: settings.apiKey,
                    model: settings.modelName,
                    messages: modelMessages
                )
                if let text = reply.text, !text.isEmpty {
                    chatMessages.append(ChatMessage(role: "assistant", text: text))
                    status = text
                    triggerSmile()
                    return
                }
            } catch {
                let errText = "API Error: \(error.localizedDescription)"
                chatMessages.append(ChatMessage(role: "assistant", text: errText))
                status = errText
                return
            }
        }

        // Fallback on-device analysis
        mood = .scanning
        status = "Analyzing display context on-device…"
        if let shot = await screen.capture() {
            latestOCRText = shot.ocr
        }
        try? await Task.sleep(nanoseconds: 600_000_000)
        mood = .executing
        let localReply = "Analyzed screen context (\(latestOCRText.components(separatedBy: "\n").count) visible items). You can ask questions or tell me to click any button."
        chatMessages.append(ChatMessage(role: "assistant", text: localReply))
        status = localReply
        triggerSmile()
    }
}
