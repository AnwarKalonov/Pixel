import AppKit
import SwiftUI

@MainActor
public struct SettingsDeckView: View {
    @ObservedObject var settings: PixelSettings
    @ObservedObject var brain: PixelBrain
    @State private var selectedTab: SettingsTab = .ai
    @State private var showAPIKey = false
    @State private var newBlacklistApp = ""

    private static let spring = Animation.spring(response: 0.28, dampingFraction: 0.8)

    public enum SettingsTab: String, CaseIterable, Identifiable {
        case ai       = "AI & API"
        case notch    = "Position"
        case search   = "Search"
        case safety   = "Safety"
        case audio    = "Audio"

        public var id: String { rawValue }
        public var icon: String {
            switch self {
            case .ai:     return "sparkles"
            case .notch:  return "slider.horizontal.below.rectangle"
            case .search: return "folder"
            case .safety: return "shield"
            case .audio:  return "mic"
            }
        }
    }

    public init(settings: PixelSettings, brain: PixelBrain) {
        self.settings = settings
        self.brain = brain
    }

    public init(brain: PixelBrain) {
        self.settings = .shared
        self.brain = brain
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Color.white.opacity(0.08))
            tabBar
            Divider().background(Color.white.opacity(0.06))
            tabContent
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(white: 0.07, opacity: 0.98))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 0.7)
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            HStack(spacing: 7) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.cyan)
                Text("Pixel Preferences")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white)
            }
            Spacer()
            Button {
                withAnimation(Self.spring) { brain.showSettings = false }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.white.opacity(0.35))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 3) {
                ForEach(SettingsTab.allCases) { tab in
                    Button {
                        withAnimation(Self.spring) { selectedTab = tab }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 10, weight: .medium))
                            Text(tab.rawValue)
                                .font(.system(size: 10.5, weight: .medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            selectedTab == tab ? Color.white.opacity(0.15) : Color.clear,
                            in: Capsule()
                        )
                        .foregroundStyle(selectedTab == tab ? .white : Color.white.opacity(0.45))
                    }
                    .buttonStyle(.plain)
                    .animation(Self.spring, value: selectedTab)
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.vertical, 6)
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            Group {
                switch selectedTab {
                case .ai:     aiTab
                case .notch:  positionTab
                case .search: searchTab
                case .safety: safetyTab
                case .audio:  audioTab
                }
            }
            .padding(14)
        }
        .frame(height: 330)
    }

    // MARK: - AI & API Tab

    private var aiTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("PROVIDER")

            // Provider picker
            HStack(spacing: 6) {
                ForEach(APIProvider.allCases, id: \.self) { p in
                    Button {
                        withAnimation(Self.spring) {
                            settings.apiProvider = p
                            settings.apiBaseURL = p.defaultBaseURL
                            if settings.modelName.isEmpty {
                                settings.modelName = p.defaultModel
                            }
                        }
                    } label: {
                        Text(p.rawValue)
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(
                                settings.apiProvider == p ? Color.cyan.opacity(0.25) : Color.white.opacity(0.06),
                                in: Capsule()
                            )
                            .foregroundStyle(settings.apiProvider == p ? .cyan : Color.white.opacity(0.55))
                    }
                    .buttonStyle(.plain)
                }
            }

            sectionHeader("ENDPOINT")

            settingsField("Base URL", placeholder: "https://api.openai.com/v1", binding: $settings.apiBaseURL)

            sectionHeader("AUTHENTICATION")

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("API Key")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.5))
                    Spacer()
                    Button(showAPIKey ? "Hide" : "Show") { showAPIKey.toggle() }
                        .font(.system(size: 9.5))
                        .foregroundStyle(.cyan)
                        .buttonStyle(.plain)
                }
                Group {
                    if showAPIKey {
                        TextField("sk-...", text: $settings.apiKey)
                    } else {
                        SecureField("sk-...", text: $settings.apiKey)
                    }
                }
                .textFieldStyle(.plain)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white)
                .padding(8)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
            }

            settingsField("Model", placeholder: "gpt-4o, claude-3.5-sonnet, llama3.2", binding: $settings.modelName)

            // Test button + status
            HStack(spacing: 10) {
                Button {
                    Task {
                        await settings.testAPIConnection()
                        brain.triggerSmile()
                    }
                } label: {
                    HStack(spacing: 5) {
                        if settings.isTestingConnection {
                            ProgressView().controlSize(.mini).colorScheme(.dark)
                        } else {
                            Image(systemName: "bolt.fill")
                        }
                        Text(settings.isTestingConnection ? "Testing…" : "Test Connection")
                    }
                    .font(.system(size: 10.5, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.cyan)
                .disabled(settings.isTestingConnection || settings.apiBaseURL.isEmpty)

                if !settings.connectionStatus.isEmpty && settings.connectionStatus != "Not verified yet" {
                    Text(settings.connectionStatus)
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(
                            settings.connectionStatus.contains("Connected") ? Color.green : Color.red.opacity(0.8)
                        )
                        .lineLimit(2)
                }
            }

            // Quick presets
            sectionHeader("QUICK PRESETS")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                presetButton("GPT-4o", url: "https://api.openai.com/v1", model: "gpt-4o")
                presetButton("Claude 3.5", url: "https://api.anthropic.com/v1", model: "claude-3-5-sonnet-20241022")
                presetButton("OpenRouter", url: "https://openrouter.ai/api/v1", model: "anthropic/claude-3.5-sonnet")
                presetButton("Ollama", url: "http://localhost:11434/v1", model: "llama3.2")
            }
        }
    }

    private func presetButton(_ label: String, url: String, model: String) -> some View {
        Button {
            settings.apiBaseURL = url
            settings.modelName = model
            brain.triggerSmile()
        } label: {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
                .foregroundStyle(Color.white.opacity(0.7))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Position Tab

    private var positionTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionHeader("NOTCH POSITION")
                Spacer()
                Button("Reset") {
                    withAnimation(Self.spring) {
                        settings.resetNotchPosition()
                        brain.triggerSmile()
                    }
                }
                .font(.system(size: 10))
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }

            sliderRow("Horizontal (X)", value: $settings.notchOffsetX, range: -300...300, unit: "pt")
            sliderRow("Vertical (Y)", value: $settings.notchOffsetY, range: -50...120, unit: "pt")

            Divider().background(Color.white.opacity(0.08))
            sectionHeader("HOVER EXPANSION")

            toggleRow("Expand on Hover", isOn: $settings.hoverExpansionEnabled,
                      detail: "Notch expands when cursor enters its bounds")

            if settings.hoverExpansionEnabled {
                sliderRow("Hover Delay",
                          value: Binding(
                            get: { settings.hoverDelaySeconds },
                            set: { settings.hoverDelaySeconds = $0 }
                          ),
                          range: 0.0...2.0,
                          unit: "s",
                          format: "%.2f")

                toggleRow("Skip Peek → Open Full Deck directly", isOn: $settings.hoverExpandToFull)
            }
        }
    }

    // MARK: - Search Tab

    private var searchTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionHeader("INDEXED FOLDERS")
                Spacer()
                Button("Add Folder…") { chooseFolder() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(.cyan)
                    .font(.system(size: 10, weight: .semibold))
            }

            if settings.indexedDirectories.isEmpty {
                Text("No folders added yet. Tap 'Add Folder' to index your files.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.white.opacity(0.4))
            } else {
                VStack(spacing: 4) {
                    ForEach(settings.indexedDirectories, id: \.self) { dir in
                        HStack {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.cyan)
                            Text(dir)
                                .font(.system(size: 10.5))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Spacer()
                            Button {
                                settings.indexedDirectories.removeAll { $0 == dir }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(Color.white.opacity(0.3))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
                    }
                }
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Re-index Files")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                    Text("\(brain.localSearch.indexedFileCount) files indexed")
                        .font(.system(size: 9.5))
                        .foregroundStyle(Color.white.opacity(0.4))
                }
                Spacer()
                Button {
                    Task {
                        await brain.localSearch.countIndexedFiles()
                        brain.triggerSmile()
                    }
                } label: {
                    Text("Re-index Now")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .font(.system(size: 10))
            }
        }
    }

    // MARK: - Safety Tab

    private var safetyTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("OCR SCANNING RATE")

            Picker("", selection: $settings.ocrInterval) {
                ForEach(OCRInterval.allCases, id: \.self) { opt in
                    Text(opt.rawValue).tag(opt)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)

            Divider().background(Color.white.opacity(0.08))
            sectionHeader("BLACKLISTED APPS")
            Text("Vision and OCR auto-disables in these apps")
                .font(.system(size: 9.5))
                .foregroundStyle(Color.white.opacity(0.4))

            VStack(spacing: 4) {
                ForEach(settings.blacklistedApps, id: \.self) { app in
                    HStack {
                        Image(systemName: "shield.slash.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.red.opacity(0.75))
                        Text(app)
                            .font(.system(size: 11))
                            .foregroundStyle(.white)
                        Spacer()
                        Button {
                            settings.blacklistedApps.removeAll { $0 == app }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(Color.white.opacity(0.3))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
                }

                HStack {
                    TextField("App name (e.g. 1Password)", text: $newBlacklistApp)
                        .textFieldStyle(.plain)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white)
                    Button("Add") {
                        let t = newBlacklistApp.trimmingCharacters(in: .whitespaces)
                        if !t.isEmpty {
                            settings.blacklistedApps.append(t)
                            newBlacklistApp = ""
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .font(.system(size: 10))
                    .disabled(newBlacklistApp.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(7)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
            }
        }
    }

    // MARK: - Audio Tab

    private var audioTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            toggleRow("Auto-Detect Video Calls", isOn: $settings.autoDetectCalls,
                      detail: "Zoom, Google Meet, Teams, FaceTime")

            Divider().background(Color.white.opacity(0.08))
            sectionHeader("MEETING NOTES STORAGE")

            settingsField("Storage Path",
                          placeholder: "~/Documents/Meeting Notes",
                          binding: $settings.summaryStoragePath)

            Text("Meeting transcripts are stored locally on your Mac. Zero cloud upload.")
                .font(.system(size: 9.5))
                .foregroundStyle(Color.white.opacity(0.35))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 8.5, weight: .black, design: .monospaced))
            .foregroundStyle(Color.white.opacity(0.3))
            .tracking(1.5)
    }

    private func settingsField(_ label: String, placeholder: String, binding: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.5))
            TextField(placeholder, text: binding)
                .textFieldStyle(.plain)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(.white)
                .padding(8)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
        }
    }

    private func sliderRow(
        _ label: String,
        value: Binding<CGFloat>,
        range: ClosedRange<CGFloat>,
        unit: String,
        format: String = "%.0f"
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.7))
                Spacer()
                Text(String(format: format, value.wrappedValue) + " " + unit)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.cyan)
            }
            Slider(value: value, in: range)
                .tint(.cyan)
        }
        .padding(8)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }

    private func sliderRow(
        _ label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        unit: String,
        format: String = "%.0f"
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.7))
                Spacer()
                Text(String(format: format, value.wrappedValue) + " " + unit)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.cyan)
            }
            Slider(value: value, in: range)
                .tint(.cyan)
        }
        .padding(8)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }

    private func toggleRow(_ label: String, isOn: Binding<Bool>, detail: String? = nil) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                if let d = detail {
                    Text(d)
                        .font(.system(size: 9.5))
                        .foregroundStyle(Color.white.opacity(0.4))
                }
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Index This Folder"
        if panel.runModal() == .OK, let url = panel.url {
            let path = url.path
            if !settings.indexedDirectories.contains(path) {
                settings.indexedDirectories.append(path)
                Task { await brain.localSearch.countIndexedFiles() }
            }
        }
    }
}
