import Foundation
import SwiftUI

public enum APIProvider: String, CaseIterable, Codable, Sendable {
    case openRouter = "OpenRouter"
    case openAI = "OpenAI"
    case ollama = "Local Ollama"
    case custom = "Custom Endpoint"

    public var defaultBaseURL: String {
        switch self {
        case .openRouter: return "https://openrouter.ai/api/v1"
        case .openAI: return "https://api.openai.com/v1"
        case .ollama: return "http://localhost:11434/v1"
        case .custom: return "https://api.openai.com/v1"
        }
    }

    public var defaultModel: String {
        switch self {
        case .openRouter: return "anthropic/claude-3.5-sonnet"
        case .openAI: return "gpt-4o"
        case .ollama: return "llama3.2"
        case .custom: return "gpt-4o"
        }
    }
}

public enum OCRInterval: String, CaseIterable, Codable, Sendable {
    case realtime = "Real-time (30fps)"
    case balanced = "Balanced (10fps)"
    case lowBattery = "Low Battery (2fps)"
}

public enum SafetyMode: String, CaseIterable, Codable, Sendable {
    case autoPilot = "Auto-Pilot"
    case promptFirst = "Prompt First"
}

@MainActor
public final class PixelSettings: ObservableObject {
    public static let shared = PixelSettings()

    // MARK: - Notch Physical Location Customization
    @Published public var notchOffsetX: CGFloat {
        didSet { UserDefaults.standard.set(Double(notchOffsetX), forKey: "pixel.notchOffsetX") }
    }
    @Published public var notchOffsetY: CGFloat {
        didSet { UserDefaults.standard.set(Double(notchOffsetY), forKey: "pixel.notchOffsetY") }
    }

    // MARK: - Hover Behavior
    @Published public var hoverExpansionEnabled: Bool {
        didSet { UserDefaults.standard.set(hoverExpansionEnabled, forKey: "pixel.hoverExpansionEnabled") }
    }
    @Published public var hoverDelaySeconds: Double {
        didSet { UserDefaults.standard.set(hoverDelaySeconds, forKey: "pixel.hoverDelaySeconds") }
    }
    @Published public var hoverExpandToFull: Bool {
        didSet { UserDefaults.standard.set(hoverExpandToFull, forKey: "pixel.hoverExpandToFull") }
    }

    // MARK: - Custom AI Model & API Configuration
    @Published public var apiProvider: APIProvider {
        didSet {
            UserDefaults.standard.set(apiProvider.rawValue, forKey: "pixel.apiProvider")
            if apiBaseURL.isEmpty || apiProvider != .custom {
                apiBaseURL = apiProvider.defaultBaseURL
            }
        }
    }
    @Published public var apiBaseURL: String {
        didSet { UserDefaults.standard.set(apiBaseURL, forKey: "pixel.apiBaseURL") }
    }
    @Published public var apiKey: String {
        didSet { UserDefaults.standard.set(apiKey, forKey: "pixel.apiKey") }
    }
    @Published public var modelName: String {
        didSet { UserDefaults.standard.set(modelName, forKey: "pixel.modelName") }
    }
    @Published public var connectionStatus: String = "Not verified yet"
    @Published public var isTestingConnection: Bool = false

    // MARK: - Screen & Drop Shelf
    @Published public var dropShelfEnabled: Bool {
        didSet { UserDefaults.standard.set(dropShelfEnabled, forKey: "pixel.dropShelfEnabled") }
    }
    @Published public var ocrInterval: OCRInterval {
        didSet { UserDefaults.standard.set(ocrInterval.rawValue, forKey: "pixel.ocrInterval") }
    }
    @Published public var safetyMode: SafetyMode {
        didSet { UserDefaults.standard.set(safetyMode.rawValue, forKey: "pixel.safetyMode") }
    }
    @Published public var blacklistedApps: [String] {
        didSet { UserDefaults.standard.set(blacklistedApps, forKey: "pixel.blacklistedApps") }
    }

    // MARK: - Local Search & Folders
    @Published public var indexedDirectories: [String] {
        didSet { UserDefaults.standard.set(indexedDirectories, forKey: "pixel.indexedDirectories") }
    }
    @Published public var ignoredExtensions: [String] {
        didSet { UserDefaults.standard.set(ignoredExtensions, forKey: "pixel.ignoredExtensions") }
    }

    // MARK: - Meetings & Audio
    @Published public var autoDetectCalls: Bool {
        didSet { UserDefaults.standard.set(autoDetectCalls, forKey: "pixel.autoDetectCalls") }
    }
    @Published public var summaryStoragePath: String {
        didSet { UserDefaults.standard.set(summaryStoragePath, forKey: "pixel.summaryStoragePath") }
    }

    public init() {
        let def = UserDefaults.standard

        self.notchOffsetX = CGFloat(def.double(forKey: "pixel.notchOffsetX"))
        self.notchOffsetY = CGFloat(def.double(forKey: "pixel.notchOffsetY"))

        self.hoverExpansionEnabled = def.object(forKey: "pixel.hoverExpansionEnabled") != nil ? def.bool(forKey: "pixel.hoverExpansionEnabled") : true
        self.hoverDelaySeconds = def.object(forKey: "pixel.hoverDelaySeconds") != nil ? def.double(forKey: "pixel.hoverDelaySeconds") : 0.25
        self.hoverExpandToFull = def.bool(forKey: "pixel.hoverExpandToFull")

        // API
        let provRaw = def.string(forKey: "pixel.apiProvider") ?? APIProvider.openAI.rawValue
        let prov = APIProvider(rawValue: provRaw) ?? .openAI
        self.apiProvider = prov
        self.apiBaseURL = def.string(forKey: "pixel.apiBaseURL") ?? prov.defaultBaseURL
        self.apiKey = def.string(forKey: "pixel.apiKey") ?? ""
        self.modelName = def.string(forKey: "pixel.modelName") ?? prov.defaultModel

        self.dropShelfEnabled = def.object(forKey: "pixel.dropShelfEnabled") != nil ? def.bool(forKey: "pixel.dropShelfEnabled") : true

        let ocrRaw = def.string(forKey: "pixel.ocrInterval") ?? OCRInterval.balanced.rawValue
        self.ocrInterval = OCRInterval(rawValue: ocrRaw) ?? .balanced

        let safetyRaw = def.string(forKey: "pixel.safetyMode") ?? SafetyMode.promptFirst.rawValue
        self.safetyMode = SafetyMode(rawValue: safetyRaw) ?? .promptFirst

        self.blacklistedApps = def.stringArray(forKey: "pixel.blacklistedApps") ?? [
            "1Password",
            "Keychain Access",
            "Bitwarden",
            "Bank of America",
            "Chase"
        ]

        self.indexedDirectories = def.stringArray(forKey: "pixel.indexedDirectories") ?? [
            "~/Documents",
            "~/Desktop",
            "~/Downloads"
        ]
        self.ignoredExtensions = def.stringArray(forKey: "pixel.ignoredExtensions") ?? [
            ".env",
            ".git",
            ".tmp",
            "node_modules"
        ]

        self.autoDetectCalls = def.object(forKey: "pixel.autoDetectCalls") != nil ? def.bool(forKey: "pixel.autoDetectCalls") : true
        self.summaryStoragePath = def.string(forKey: "pixel.summaryStoragePath") ?? "~/Documents/Meeting Notes"
    }

    public func resetNotchPosition() {
        self.notchOffsetX = 0
        self.notchOffsetY = 0
    }

    public func testAPIConnection() async {
        isTestingConnection = true
        connectionStatus = "Testing connection to \(apiBaseURL)…"

        let client = ModelClient()
        do {
            let res = try await client.testConnection(
                endpoint: apiBaseURL,
                apiKey: apiKey,
                model: modelName
            )
            self.connectionStatus = "Connected! Model replied: \(res)"
        } catch {
            self.connectionStatus = "Connection Failed: \(error.localizedDescription)"
        }
        self.isTestingConnection = false
    }
}
