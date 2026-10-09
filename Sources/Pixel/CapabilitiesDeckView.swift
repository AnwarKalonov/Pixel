import AppKit
import SwiftUI
import UniformTypeIdentifiers

public enum CapabilityDeckTab: String, CaseIterable, Identifiable {
    case controls = "Controls"
    case timer    = "Timer"
    case shelf    = "Shelf"
    case chat     = "Chat"
    case vision   = "Vision"
    case search   = "Search"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .controls: return "slider.horizontal.3"
        case .timer:    return "timer"
        case .shelf:    return "tray.and.arrow.down.fill"
        case .chat:     return "bubble.left.and.bubble.right.fill"
        case .vision:   return "eye"
        case .search:   return "magnifyingglass"
        }
    }
}

// MARK: - Bouncy Animated Button Style (boring.notch signature)
struct BoringButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

@MainActor
public struct CapabilitiesDeckView: View {
    @ObservedObject var brain: PixelBrain
    @ObservedObject var settings: PixelSettings
    @ObservedObject private var controls: SystemControlsService
    @ObservedObject private var shelf: ShelfService
    @ObservedObject private var localSearch: LocalSearchService
    @ObservedObject private var focusTimer: FocusTimerService = .shared

    @Binding var currentTab: CapabilityDeckTab
    @State private var searchInput = ""
    @State private var isShelfTargeted = false
    @Namespace private var tabNamespace

    // Fast, bouncy spring — matches boring.notch
    private static let spring = Animation.spring(response: 0.28, dampingFraction: 0.74, blendDuration: 0)
    private static let microSpring = Animation.spring(response: 0.18, dampingFraction: 0.72)

    public init(brain: PixelBrain, settings: PixelSettings, currentTab: Binding<CapabilityDeckTab>) {
        self.brain = brain
        self.settings = settings
        self.controls = brain.controls
        self.shelf = brain.shelf
        self.localSearch = brain.localSearch
        self._currentTab = currentTab
    }

    public init(brain: PixelBrain, currentTab: Binding<CapabilityDeckTab>) {
        self.init(brain: brain, settings: .shared, currentTab: currentTab)
    }

    public var body: some View {
        VStack(spacing: 8) {
            // Authentic boring.notch Capsule Tab Bar
            tabBar

            // Tab Content
            tabContent
                .frame(maxWidth: .infinity)
                .frame(height: 320)
        }
    }

    // MARK: - boring.notch Style Tab Bar (Sliding Capsule Indicator)
    private var tabBar: some View {
        HStack(spacing: 1) {
            ForEach(CapabilityDeckTab.allCases) { tab in
                Button {
                    withAnimation(Self.spring) { currentTab = tab }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 10, weight: .semibold))
                        Text(tab.rawValue)
                            .font(.system(size: 10.5, weight: .semibold))

                        // Live badges
                        if tab == .timer && focusTimer.isRunning {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 5, height: 5)
                                .shadow(color: .orange, radius: 2)
                        } else if tab == .shelf && !shelf.items.isEmpty {
                            Text("\(shelf.items.count)")
                                .font(.system(size: 8, weight: .heavy, design: .monospaced))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.white.opacity(0.22), in: Capsule())
                        } else if tab == .chat && brain.chatMessages.count > 1 {
                            Circle()
                                .fill(Color.cyan)
                                .frame(width: 5, height: 5)
                                .shadow(color: .cyan, radius: 2)
                        }
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background {
                        if currentTab == tab {
                            Capsule()
                                .fill(Color.white.opacity(0.2))
                                .shadow(color: Color.white.opacity(0.08), radius: 4)
                                .matchedGeometryEffect(id: "activeTab", in: tabNamespace)
                        }
                    }
                    .foregroundStyle(currentTab == tab ? .white : Color.white.opacity(0.45))
                    .contentShape(Rectangle())
                }
                .buttonStyle(BoringButtonStyle())
            }
            Spacer()
        }
        .padding(3)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.07))
                .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 0.6))
        )
    }

    // MARK: - Tab Content Router
    @ViewBuilder
    private var tabContent: some View {
        Group {
            switch currentTab {
            case .controls: controlsTab
            case .timer:    timerTab
            case .shelf:    shelfTab
            case .chat:     chatTab
            case .vision:   visionTab
            case .search:   searchTab
            }
        }
        .transition(
            .asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.97, anchor: .top)),
                removal: .opacity.combined(with: .scale(scale: 0.97, anchor: .top))
            )
        )
        .animation(Self.spring, value: currentTab)
    }

    // MARK: - 1. Controls Tab
    private var controlsTab: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                mediaPlayerCard
                cameraCard
            }
            .frame(height: 156)

            volumeCard

            brightnessCard
        }
    }

    private var mediaPlayerCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(playerColor.opacity(0.18))
                        .frame(width: 22, height: 22)
                    Image(systemName: controls.activePlayer == "Spotify" ? "music.note" :
                          controls.activePlayer.contains("Music") ? "music.quarternote.3" : "play.circle")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(playerColor)
                }
                Text(controls.activePlayer)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                // Live status dot with glow
                Circle()
                    .fill(controls.isPlaying ? Color.green : Color.white.opacity(0.2))
                    .frame(width: 6, height: 6)
                    .shadow(color: controls.isPlaying ? .green : .clear, radius: 4)
                    .animation(Self.microSpring, value: controls.isPlaying)
            }
            .padding(.bottom, 6)

            // Track info
            VStack(alignment: .leading, spacing: 2) {
                Text(controls.trackTitle.isEmpty ? "Nothing Playing" : controls.trackTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(controls.trackArtist.isEmpty ? "—" : controls.trackArtist)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .lineLimit(1)
            }

            Spacer()

            // Playback Controls
            HStack(spacing: 0) {
                Spacer()
                mediaButton(icon: "backward.fill", size: 15) {
                    controls.previousTrack()
                    brain.triggerSmile()
                }
                Spacer()
                mediaButton(icon: controls.isPlaying ? "pause.circle.fill" : "play.circle.fill", size: 30) {
                    controls.togglePlayPause()
                    brain.triggerSmile()
                }
                Spacer()
                mediaButton(icon: "forward.fill", size: 15) {
                    controls.nextTrack()
                    brain.triggerSmile()
                }
                Spacer()
            }
        }
        .padding(12)
        .background(glassCard)
        .frame(maxWidth: .infinity)
    }

    private var playerColor: Color {
        switch controls.activePlayer {
        case "Spotify": return .green
        case "YouTube Music": return .red
        default: return Color(red: 0.98, green: 0.38, blue: 0.46) // Apple Music pink
        }
    }

    @ViewBuilder
    private func mediaButton(icon: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size))
                .foregroundStyle(.white)
        }
        .buttonStyle(BoringButtonStyle())
    }

    private var cameraCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.cyan)
                Text("Mirror")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    withAnimation(Self.microSpring) {
                        controls.toggleCamera()
                        if controls.isCameraActive { brain.triggerSmile() }
                    }
                } label: {
                    Text(controls.isCameraActive ? "Close" : "Open")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            controls.isCameraActive ? Color.red.opacity(0.25) : Color.cyan.opacity(0.18),
                            in: Capsule()
                        )
                        .foregroundStyle(controls.isCameraActive ? .red : .cyan)
                }
                .buttonStyle(BoringButtonStyle())
            }
            .padding(.bottom, 5)

            Spacer()

            if controls.isCameraActive {
                CameraPreviewView(session: controls.captureSession)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else if !controls.cameraError.isEmpty {
                VStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.system(size: 16))
                    Text(controls.cameraError)
                        .font(.system(size: 8.5))
                        .foregroundStyle(Color.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "camera.circle")
                        .font(.system(size: 26, weight: .thin))
                        .foregroundStyle(Color.white.opacity(0.2))
                    Text("Tap Open")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.white.opacity(0.3))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(10)
        .frame(width: 150)
        .background(glassCard)
    }

    private var volumeCard: some View {
        HStack(spacing: 10) {
            Button {
                controls.toggleMute()
                brain.triggerSmile()
            } label: {
                Image(systemName: controls.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(controls.isMuted ? Color.red : Color.white.opacity(0.75))
                    .frame(width: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(BoringButtonStyle())

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 4)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: controls.isMuted ? [.gray, .gray.opacity(0.5)] : [.white, .white.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * CGFloat(controls.volume) / 100, height: 4)
                        .animation(Self.microSpring, value: controls.volume)
                }
                .frame(height: geo.size.height)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            let pct = max(0, min(1, v.location.x / geo.size.width))
                            controls.setVolume(Double(pct * 100))
                        }
                )
            }
            .frame(height: 20)

            HStack(spacing: 2) {
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.white.opacity(0.3))
                Text("\(Int(controls.volume))")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .frame(width: 24, alignment: .trailing)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(glassCard)
    }

    private var brightnessCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "sun.min.fill")
                .font(.system(size: 12))
                .foregroundStyle(Color.yellow.opacity(0.7))
                .frame(width: 20)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 4)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.yellow.opacity(0.9), Color.orange.opacity(0.6)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * CGFloat(controls.brightness) / 100, height: 4)
                        .animation(Self.microSpring, value: controls.brightness)
                }
                .frame(height: geo.size.height)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            let pct = max(0, min(1, v.location.x / geo.size.width))
                            controls.setBrightness(Double(pct * 100))
                        }
                )
            }
            .frame(height: 20)

            Image(systemName: "sun.max.fill")
                .font(.system(size: 12))
                .foregroundStyle(Color.yellow.opacity(0.7))
                .frame(width: 20)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(glassCard)
    }

    // MARK: - 2. Focus Timer Tab (Cool Ring Timer)
    private var timerTab: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 14) {
                HStack {
                    sectionHeader("FOCUS TIMER")
                    Spacer()
                    if focusTimer.isRunning || focusTimer.remainingSeconds < focusTimer.totalSeconds {
                        Text(focusTimer.presetName)
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.orange.opacity(0.85))
                    }
                }

                // Animated Ring Timer
                ZStack {
                    // Track ring
                    Circle()
                        .stroke(Color.white.opacity(0.06), lineWidth: 10)
                        .frame(width: 148, height: 148)

                    // Pulsing glow when running
                    if focusTimer.isRunning {
                        Circle()
                            .stroke(Color.orange.opacity(0.12), lineWidth: 18)
                            .frame(width: 148, height: 148)
                            .blur(radius: 6)
                    }

                    // Progress arc
                    Circle()
                        .trim(from: 0, to: CGFloat(focusTimer.progress))
                        .stroke(
                            AngularGradient(
                                gradient: Gradient(colors: [.orange, .yellow, .orange]),
                                center: .center,
                                startAngle: .degrees(-90),
                                endAngle: .degrees(270)
                            ),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 148, height: 148)
                        .animation(.linear(duration: 1.0), value: focusTimer.remainingSeconds)

                    // Center display
                    VStack(spacing: 3) {
                        Text(focusTimer.formattedTime)
                            .font(.system(size: 34, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())

                        HStack(spacing: 4) {
                            if focusTimer.isRunning {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 5, height: 5)
                                    .shadow(color: .green, radius: 3)
                            }
                            Text(focusTimer.isRunning ? "FOCUSING" : (focusTimer.remainingSeconds == focusTimer.totalSeconds ? "READY" : "PAUSED"))
                                .font(.system(size: 8, weight: .black, design: .monospaced))
                                .foregroundStyle(focusTimer.isRunning ? Color.green : Color.white.opacity(0.4))
                                .tracking(1)
                        }
                    }
                }
                .padding(.vertical, 4)

                // Controls
                HStack(spacing: 10) {
                    Button {
                        focusTimer.pauseResume()
                        brain.triggerSmile()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: focusTimer.isRunning ? "pause.fill" : "play.fill")
                                .font(.system(size: 11, weight: .semibold))
                            Text(focusTimer.isRunning ? "Pause" : "Start")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .frame(width: 90)
                        .padding(.vertical, 8)
                        .background(
                            LinearGradient(colors: [.orange.opacity(0.4), .orange.opacity(0.25)],
                                           startPoint: .top, endPoint: .bottom),
                            in: Capsule()
                        )
                        .overlay(Capsule().stroke(Color.orange.opacity(0.3), lineWidth: 0.8))
                        .foregroundStyle(.orange)
                    }
                    .buttonStyle(BoringButtonStyle())

                    Button {
                        withAnimation(Self.microSpring) { focusTimer.reset() }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 10))
                            Text("Reset")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.07), in: Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 0.6))
                        .foregroundStyle(Color.white.opacity(0.65))
                    }
                    .buttonStyle(BoringButtonStyle())
                }

                // Presets
                VStack(alignment: .leading, spacing: 6) {
                    Text("PRESETS")
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.3))
                        .tracking(1.5)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                        timerPreset("25m", subtitle: "Pomodoro", duration: 25 * 60, color: .orange)
                        timerPreset("5m", subtitle: "Short Break", duration: 5 * 60, color: .green)
                        timerPreset("15m", subtitle: "Long Break", duration: 15 * 60, color: .mint)
                        timerPreset("45m", subtitle: "Deep Work", duration: 45 * 60, color: .purple)
                        timerPreset("60m", subtitle: "Deep Focus", duration: 60 * 60, color: .indigo)
                        timerPreset("10m", subtitle: "Quick Task", duration: 10 * 60, color: .cyan)
                    }
                }
            }
            .padding(.horizontal, 10)
        }
    }

    private func timerPreset(_ title: String, subtitle: String, duration: Int, color: Color) -> some View {
        Button {
            focusTimer.start(duration: duration, name: "\(title) \(subtitle)")
            brain.triggerSmile()
        } label: {
            VStack(spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)
                Text(subtitle)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.4))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(color.opacity(0.2), lineWidth: 0.7)
            )
        }
        .buttonStyle(BoringButtonStyle())
    }

    // MARK: - 3. Drop Shelf Tab (Drag-in / Drag-out)
    private var shelfTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionHeader("DROP SHELF")
                Spacer()
                if !shelf.items.isEmpty {
                    Button("Clear All") {
                        withAnimation(Self.spring) { shelf.clearAll() }
                        brain.triggerSmile()
                    }
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(Color.red.opacity(0.75))
                    .buttonStyle(.plain)
                }
            }

            // Drop zone (always shows as drag target)
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isShelfTargeted ? Color.cyan.opacity(0.12) : Color.white.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                isShelfTargeted
                                    ? Color.cyan.opacity(0.6)
                                    : Color.white.opacity(0.08),
                                style: StrokeStyle(lineWidth: 1.2, dash: isShelfTargeted ? [] : [4, 4])
                            )
                    )
                    .animation(Self.microSpring, value: isShelfTargeted)
                    .frame(height: 44)

                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.to.line")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isShelfTargeted ? Color.cyan : Color.white.opacity(0.3))
                    Text(isShelfTargeted ? "Drop to save" : "Drop files or text here")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isShelfTargeted ? Color.cyan : Color.white.opacity(0.35))
                }
            }
            .onDrop(
                of: [UTType.fileURL, UTType.text, UTType.plainText, UTType.url, UTType.item],
                isTargeted: $isShelfTargeted
            ) { providers in
                handleShelfDrop(providers: providers)
            }

            if shelf.items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 30, weight: .thin))
                        .foregroundStyle(Color.white.opacity(0.15))
                    Text("Drag files, images, or text snippets")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.4))
                    Text("Drag back out to paste anywhere on your Mac")
                        .font(.system(size: 9.5))
                        .foregroundStyle(Color.white.opacity(0.25))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 5) {
                        ForEach(shelf.items) { item in
                            shelfRow(item)
                                .transition(
                                    .asymmetric(
                                        insertion: .push(from: .top).combined(with: .opacity),
                                        removal: .push(from: .bottom).combined(with: .opacity)
                                    )
                                )
                        }
                    }
                }
            }
        }
    }

    private func handleShelfDrop(providers: [NSItemProvider]) -> Bool {
        var didHandle = false
        for provider in providers {
            // File URL
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in
                        _ = self.shelf.addFile(from: url)
                        self.brain.triggerSmile(duration: 3)
                    }
                }
                didHandle = true
            }
            // Plain text
            else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) ||
                    provider.hasItemConformingToTypeIdentifier(UTType.text.identifier) {
                _ = provider.loadObject(ofClass: String.self) { text, _ in
                    guard let text else { return }
                    Task { @MainActor in
                        _ = self.shelf.addSnippet(text: text)
                        self.brain.triggerSmile(duration: 3)
                    }
                }
                didHandle = true
            }
        }
        return didHandle
    }

    private func shelfRow(_ item: ShelfItem) -> some View {
        let isText = item.kind == "TEXT" || item.kind == "TXT" || item.kind == "MD"

        return HStack(spacing: 10) {
            // File type icon
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isText ? Color.cyan.opacity(0.15) : Color.white.opacity(0.08))
                    .frame(width: 32, height: 32)
                Image(systemName: isText ? "doc.text.fill" : fileIcon(for: item.kind))
                    .font(.system(size: 14))
                    .foregroundStyle(isText ? .cyan : Color.white.opacity(0.65))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.filename)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(item.kind)
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.white.opacity(0.08), in: Capsule())
                        .foregroundStyle(Color.white.opacity(0.5))
                    Text(item.fileSizeString)
                        .font(.system(size: 9))
                        .foregroundStyle(Color.white.opacity(0.35))
                }
            }

            Spacer()

            // Action buttons
            HStack(spacing: 8) {
                // Ask AI
                Button {
                    brain.askAIAboutShelfItem(item)
                } label: {
                    Image(systemName: "sparkle")
                        .font(.system(size: 10))
                        .padding(6)
                        .background(Color.cyan.opacity(0.14), in: Circle())
                        .foregroundStyle(.cyan)
                }
                .buttonStyle(BoringButtonStyle())
                .help("Ask AI about this file")

                // Copy to clipboard
                Button {
                    shelf.copyToPasteboard(item)
                    brain.triggerSmile()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.white.opacity(0.4))
                }
                .buttonStyle(BoringButtonStyle())
                .help("Copy to clipboard")

                // Remove
                Button {
                    withAnimation(Self.spring) { shelf.removeItem(item) }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.2))
                }
                .buttonStyle(BoringButtonStyle())
                .help("Remove from shelf")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 0.6)
        )
        // Drag FROM shelf back out to macOS
        .onDrag {
            NSItemProvider(contentsOf: item.fileURL) ?? NSItemProvider()
        }
    }

    private func fileIcon(for kind: String) -> String {
        switch kind.uppercased() {
        case "PDF": return "doc.richtext.fill"
        case "PNG", "JPG", "JPEG", "HEIC", "GIF", "WEBP": return "photo.fill"
        case "MP4", "MOV", "AVI": return "video.fill"
        case "MP3", "WAV", "FLAC", "AAC": return "music.note"
        case "ZIP", "RAR", "TAR", "GZ": return "archivebox.fill"
        case "SWIFT", "PY", "JS", "TS", "JSON", "YAML": return "terminal.fill"
        default: return "doc.fill"
        }
    }

    // MARK: - 4. AI Chat Tab
    private var chatTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionHeader("AI CHAT")
                Spacer()
                HStack(spacing: 3) {
                    Circle()
                        .fill(!settings.apiKey.isEmpty || settings.apiProvider == .ollama ? Color.green : Color.orange)
                        .frame(width: 5, height: 5)
                        .shadow(color: !settings.apiKey.isEmpty || settings.apiProvider == .ollama ? .green : .orange, radius: 2)
                    Text(settings.apiProvider.rawValue.uppercased())
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.4))
                }
            }

            if settings.apiKey.isEmpty && settings.apiProvider != .ollama {
                apiKeyNag
            } else {
                chatMessages
            }
        }
    }

    private var apiKeyNag: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.yellow.opacity(0.1))
                    .frame(width: 48, height: 48)
                Image(systemName: "key.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.yellow.opacity(0.7))
            }
            Text("Add your API key in Settings")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.8))
            Text("Works with OpenAI, Anthropic, Gemini, or Ollama locally")
                .font(.system(size: 10))
                .foregroundStyle(Color.white.opacity(0.4))
                .multilineTextAlignment(.center)
            Button {
                withAnimation { brain.showSettings = true }
            } label: {
                Text("Open Settings →")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(Color.cyan.opacity(0.18), in: Capsule())
                    .foregroundStyle(.cyan)
            }
            .buttonStyle(BoringButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var chatMessages: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(brain.chatMessages) { msg in
                        chatBubble(msg)
                            .id(msg.id)
                    }
                }
                .padding(.vertical, 2)
            }
            .onChange(of: brain.chatMessages.count) { _, _ in
                if let last = brain.chatMessages.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func chatBubble(_ msg: ChatMessage) -> some View {
        if msg.role == "user" {
            HStack {
                Spacer(minLength: 32)
                Text(msg.text)
                    .font(.system(size: 11))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 0.1, green: 0.35, blue: 1.0).opacity(0.85),
                                     Color(red: 0.05, green: 0.2, blue: 0.85).opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .stroke(Color.white.opacity(0.1), lineWidth: 0.6)
                    )
            }
        } else {
            HStack(alignment: .top, spacing: 7) {
                ZStack {
                    Circle()
                        .fill(Color.cyan.opacity(0.18))
                        .frame(width: 20, height: 20)
                    Image(systemName: "sparkle")
                        .font(.system(size: 8))
                        .foregroundStyle(.cyan)
                }
                .padding(.top, 4)

                Text(msg.text)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.88))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 0.6)
                    )
                Spacer(minLength: 20)
            }
        }
    }

    // MARK: - 5. Screen Vision Tab
    private var visionTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionHeader("SCREEN VISION")
                Spacer()
                Button {
                    Task { await brain.glance() }
                } label: {
                    HStack(spacing: 5) {
                        if brain.mood == .scanning {
                            ProgressView()
                                .controlSize(.mini)
                                .colorScheme(.dark)
                                .scaleEffect(0.9)
                        } else {
                            Image(systemName: "viewfinder.circle.fill")
                                .font(.system(size: 11))
                        }
                        Text(brain.mood == .scanning ? "Scanning…" : "Scan Screen")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        brain.mood == .scanning
                            ? Color.orange.opacity(0.2)
                            : Color.white.opacity(0.1),
                        in: Capsule()
                    )
                    .foregroundStyle(brain.mood == .scanning ? .orange : .white)
                }
                .buttonStyle(BoringButtonStyle())
                .disabled(brain.mood == .scanning)
            }

            // Commands hint
            HStack(spacing: 6) {
                Image(systemName: "cursorarrow.rays")
                    .font(.system(size: 10))
                    .foregroundStyle(.cyan)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        commandChip("click [text]")
                        Text("to click any button on screen")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.white.opacity(0.5))
                    }
                    HStack(spacing: 4) {
                        commandChip("type [text]")
                        Text("to type in active app")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.white.opacity(0.5))
                    }
                }
            }
            .padding(9)
            .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.07), lineWidth: 0.6))

            // OCR Result
            if brain.latestOCRText.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 24, weight: .thin))
                        .foregroundStyle(Color.white.opacity(0.2))
                    Text("Tap 'Scan Screen' to read all visible text")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.white.opacity(0.4))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    Text(brain.latestOCRText)
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.75))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func commandChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.cyan.opacity(0.15), in: Capsule())
            .foregroundStyle(.cyan)
    }

    // MARK: - 6. Local Search Tab
    private var searchTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("LOCAL SEARCH")

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.cyan.opacity(0.8))

                TextField("Search files by name or content…", text: $searchInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.white)
                    .onSubmit {
                        Task {
                            await localSearch.search(query: searchInput, in: settings.indexedDirectories)
                            brain.triggerSmile()
                        }
                    }

                if localSearch.isSearching {
                    ProgressView().controlSize(.small).colorScheme(.dark)
                } else if !searchInput.isEmpty {
                    Button {
                        searchInput = ""
                        localSearch.results.removeAll()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.white.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(9)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 0.7)
            )

            if localSearch.results.isEmpty {
                if !searchInput.isEmpty && !localSearch.isSearching {
                    emptyState(icon: "doc.text.magnifyingglass", message: "No files found", sub: "Try different keywords")
                } else {
                    emptyState(
                        icon: "folder.badge.magnifyingglass",
                        message: "Search \(settings.indexedDirectories.count) indexed folders",
                        sub: "100% local — no cloud uploads"
                    )
                }
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 4) {
                        ForEach(localSearch.results) { match in
                            HStack(spacing: 9) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: match.path))
                                    .resizable()
                                    .frame(width: 24, height: 24)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(match.title)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.white)
                                    Text(match.snippet)
                                        .font(.system(size: 9.5))
                                        .foregroundStyle(Color.white.opacity(0.4))
                                        .lineLimit(1)
                                }

                                Spacer()

                                Button("Show") {
                                    localSearch.openFileInFinder(path: match.path)
                                    brain.triggerSmile()
                                }
                                .font(.system(size: 9.5, weight: .semibold))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(Color.white.opacity(0.08), in: Capsule())
                                .foregroundStyle(Color.white.opacity(0.7))
                                .buttonStyle(BoringButtonStyle())
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 7)
                            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Shared UI Helpers

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 8.5, weight: .black, design: .monospaced))
            .foregroundStyle(Color.white.opacity(0.3))
            .tracking(1.5)
    }

    private func emptyState(icon: String, message: String, sub: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .thin))
                .foregroundStyle(Color.white.opacity(0.18))
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.4))
            Text(sub)
                .font(.system(size: 9.5))
                .foregroundStyle(Color.white.opacity(0.25))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var glassCard: some ShapeStyle {
        .regularMaterial
    }
}

// MARK: - Glass Card Background Extension
extension View {
    func glassCard(cornerRadius: CGFloat = 14) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.09), lineWidth: 0.7)
            )
    }
}
