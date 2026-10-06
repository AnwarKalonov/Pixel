import AppKit
import Foundation
import SwiftUI

enum PixelMood: Equatable {
    case idle
    case watching
    case thinking
    case acting
}

@MainActor
final class PixelBrain: ObservableObject {
    @Published var isExpanded = false
    @Published var look = CGPoint(x: 0, y: 0.42)
    @Published var blink: CGFloat = 0
    @Published var mood: PixelMood = .idle
    @Published var input = ""
    @Published var status = "I live in the notch. Ask me to look."
    @Published var isBusy = false
    @Published var showSettings = false
    @Published var apiKey = ""
    @Published var model = "gpt-4o"

    var onSizeChange: (() -> Void)?

    private let screen = ScreenSense()
    private let hands = Hands()
    private let guide = GuideOverlay()
    private let client = ModelClient()
    private var blinkTask: Task<Void, Never>?
    private var glanceTask: Task<Void, Never>?
    private var lastMouse = NSEvent.mouseLocation

    var needsSetup: Bool {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !Permissions.screenTrusted
            || !Permissions.accessibilityTrusted
    }

    var setupMessage: String {
        var parts: [String] = []
        if !Permissions.screenTrusted { parts.append("Allow Screen Recording.") }
        if !Permissions.accessibilityTrusted { parts.append("Allow Accessibility so I can type.") }
        if apiKey.isEmpty { parts.append("Add an API key to talk.") }
        return parts.joined(separator: " ")
    }

    init() {
        apiKey = UserDefaults.standard.string(forKey: "pixel.apiKey") ?? ""
        model = UserDefaults.standard.string(forKey: "pixel.model") ?? "gpt-4o"
        startLoops()
        Permissions.promptAccessibility()
    }

    func expand() {
        isExpanded = true
        onSizeChange?()
    }

    func collapse() {
        isExpanded = false
        showSettings = false
        onSizeChange?()
        NSApp.windows.first { $0 is NotchPanel }?.makeFirstResponder(nil)
    }

    func toggleExpanded() {
        isExpanded ? collapse() : expand()
    }

    func saveAPIKey(_ value: String) {
        UserDefaults.standard.set(value, forKey: "pixel.apiKey")
    }

    func saveModel(_ value: String) {
        UserDefaults.standard.set(value, forKey: "pixel.model")
    }

    func requestPermissions() {
        Permissions.promptAccessibility()
        Task { _ = await screen.capture() }
        status = setupMessage.isEmpty ? "Ready." : setupMessage
    }

    func trackMouse(_ location: CGPoint) {
        lastMouse = location
        guard let screen = NSScreen.main else { return }
        let nx = ((location.x - screen.frame.midX) / (screen.frame.width * 0.42))
        let nyFromTop = (screen.frame.maxY - location.y) / (screen.frame.height * 0.5)
        let target = CGPoint(
            x: max(-1, min(1, nx)),
            y: max(-1, min(1, nyFromTop * 0.9 - 0.05))
        )
        look.x += (target.x - look.x) * 0.28
        look.y += (target.y - look.y) * 0.22
        if mood == .idle { mood = .watching }
    }

    func glance() async {
        mood = .watching
        expand()
        if let shot = await screen.capture() {
            status = shot.ocr.isEmpty ? "I can see the screen." : shot.ocr.split(separator: "\n").prefix(3).joined(separator: " · ")
        } else {
            status = "I need Screen Recording permission to see."
        }
    }

    func submit() async {
        let prompt = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isBusy else { return }
        input = ""
        await run(prompt: prompt)
    }

    private func run(prompt: String) async {
        isBusy = true
        mood = .thinking
        status = "Looking…"
        defer {
            isBusy = false
            mood = .idle
        }

        guard !apiKey.isEmpty else {
            status = "Add an OpenAI key (click Key) so I can think."
            showSettings = true
            return
        }

        var shot = await screen.capture()
        if shot == nil {
            status = "I cannot see yet. Enable Screen Recording for Pixel."
            return
        }

        var messages: [ModelClient.Message] = [
            .init(role: "system", content: .text(Self.systemPrompt)),
            .init(role: "user", content: .multimodal(prompt: prompt, imageJPEG: shot!.jpeg))
        ]

        for step in 0..<8 {
            do {
                let reply = try await client.complete(
                    apiKey: apiKey,
                    model: model,
                    messages: messages,
                    tools: Self.tools
                )
                if let text = reply.text, reply.toolCalls.isEmpty {
                    status = text
                    return
                }
                if reply.toolCalls.isEmpty {
                    status = reply.text ?? "Done."
                    return
                }
                messages.append(.init(role: "assistant", content: .toolCalls(reply.toolCalls, text: reply.text)))
                for call in reply.toolCalls {
                    mood = .acting
                    status = label(for: call)
                    let result = await execute(call, shot: &shot)
                    messages.append(.init(role: "tool", content: .toolResult(id: call.id, output: result)))
                }
                if step == 7 {
                    status = "Stopped after a few moves."
                }
            } catch {
                status = error.localizedDescription
                return
            }
        }
    }

    private func execute(_ call: ModelClient.ToolCall, shot: inout ScreenSense.Shot?) async -> String {
        let args = call.arguments
        switch call.name {
        case "look":
            shot = await screen.capture()
            guard let shot else { return "No screenshot. Grant Screen Recording." }
            return "OCR:\n\(shot.ocr.prefix(3500))"
        case "click":
            guard let nx = number(args, "nx"), let ny = number(args, "ny") else {
                return "Need nx and ny between 0 and 1."
            }
            let current = await existingOrCapture(shot)
            guard let current else { return "No screen map." }
            let point = current.point(normalized: CGPoint(x: nx, y: ny))
            hands.moveAndClick(point)
            return "Clicked \(Int(point.x)),\(Int(point.y))."
        case "type":
            let text = args["text"] as? String ?? ""
            guard Permissions.accessibilityTrusted else { return "Need Accessibility permission to type." }
            hands.type(text)
            return "Typed \(text.count) characters."
        case "hotkey":
            let keys = args["keys"] as? String ?? ""
            guard Permissions.accessibilityTrusted else { return "Need Accessibility permission for keys." }
            hands.hotkey(keys)
            return "Pressed \(keys)."
        case "highlight":
            let nx = number(args, "nx") ?? 0
            let ny = number(args, "ny") ?? 0
            let nw = number(args, "nw") ?? 0.12
            let nh = number(args, "nh") ?? 0.08
            let message = args["message"] as? String ?? ""
            let current = await existingOrCapture(shot)
            guard let current else { return "No screen map." }
            let rect = current.rect(normalized: CGRect(x: nx, y: ny, width: nw, height: nh))
            guide.show(rect: rect, message: message)
            return "Highlighted. \(message)"
        case "wait":
            let ms = number(args, "ms") ?? 400
            try? await Task.sleep(for: .milliseconds(min(max(ms, 50), 4000)))
            return "Waited \(Int(ms))ms."
        default:
            return "Unknown tool \(call.name)."
        }
    }

    private func number(_ args: [String: Any], _ key: String) -> Double? {
        if let value = args[key] as? Double { return value }
        if let value = args[key] as? Int { return Double(value) }
        if let value = args[key] as? NSNumber { return value.doubleValue }
        return nil
    }

    private func existingOrCapture(_ shot: ScreenSense.Shot?) async -> ScreenSense.Shot? {
        if let shot { return shot }
        return await screen.capture()
    }

    private func label(for call: ModelClient.ToolCall) -> String {
        switch call.name {
        case "look": return "Looking…"
        case "click": return "Clicking…"
        case "type": return "Typing…"
        case "hotkey": return "Pressing keys…"
        case "highlight": return "Pointing…"
        case "wait": return "Waiting…"
        default: return call.name
        }
    }

    private func startLoops() {
        blinkTask = Task { [weak self] in
            while !Task.isCancelled {
                let pause = UInt64.random(in: 2_200_000_000...5_400_000_000)
                try? await Task.sleep(nanoseconds: pause)
                guard let self, !Task.isCancelled else { return }
                self.blink = 1
                try? await Task.sleep(nanoseconds: 90_000_000)
                self.blink = 0
            }
        }
        glanceTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 7_000_000_000)
                guard let self, !Task.isCancelled else { return }
                if self.mood == .watching {
                    self.mood = .idle
                    self.look.y = 0.42
                    self.look.x *= 0.4
                }
            }
        }
    }

    private static let systemPrompt = """
    You are Pixel, a pair of eyes living in a black notch at the top of the Mac.
    You help by seeing the screen and, when asked, clicking, typing, or pointing.
    Be brief. Prefer doing over explaining.
    Coordinates nx, ny, nw, nh are 0...1 of the latest screenshot, origin top-left.
    After look, use the new OCR. Click the center of the control you mean.
    Do not run destructive actions (quit apps, delete files, send messages) unless the user clearly asked.
    When guiding without taking over, use highlight plus one short sentence.
    """

    private static let tools: [[String: Any]] = [
        [
            "type": "function",
            "function": [
                "name": "look",
                "description": "Capture the screen and read visible text.",
                "parameters": ["type": "object", "properties": [:] as [String: Any]]
            ]
        ],
        [
            "type": "function",
            "function": [
                "name": "click",
                "description": "Click a point on the screenshot.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "nx": ["type": "number"],
                        "ny": ["type": "number"]
                    ],
                    "required": ["nx", "ny"]
                ]
            ]
        ],
        [
            "type": "function",
            "function": [
                "name": "type",
                "description": "Type text into the focused field.",
                "parameters": [
                    "type": "object",
                    "properties": ["text": ["type": "string"]],
                    "required": ["text"]
                ]
            ]
        ],
        [
            "type": "function",
            "function": [
                "name": "hotkey",
                "description": "Press a key combo like cmd+c or return.",
                "parameters": [
                    "type": "object",
                    "properties": ["keys": ["type": "string"]],
                    "required": ["keys"]
                ]
            ]
        ],
        [
            "type": "function",
            "function": [
                "name": "highlight",
                "description": "Draw a guide box on screen with a short message.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "nx": ["type": "number"],
                        "ny": ["type": "number"],
                        "nw": ["type": "number"],
                        "nh": ["type": "number"],
                        "message": ["type": "string"]
                    ],
                    "required": ["nx", "ny", "message"]
                ]
            ]
        ],
        [
            "type": "function",
            "function": [
                "name": "wait",
                "description": "Pause briefly for UI to settle.",
                "parameters": [
                    "type": "object",
                    "properties": ["ms": ["type": "number"]]
                ]
            ]
        ]
    ]
}
