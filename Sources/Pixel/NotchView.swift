import AppKit
import SwiftUI
import UniformTypeIdentifiers

public struct NotchView: View {
    @ObservedObject var brain: PixelBrain
    @ObservedObject var settings: PixelSettings = .shared
    @FocusState private var inputFocused: Bool
    @State private var deckTab: CapabilityDeckTab = .controls
    @State private var isDropTargeted: Bool = false
    @State private var dropFeedbackScale: CGFloat = 1.0

    public init(brain: PixelBrain) {
        self.brain = brain
    }

    // boring.notch springs: ultra snappy, bouncy but precise
    private static let notchSpring = Animation.spring(response: 0.32, dampingFraction: 0.72, blendDuration: 0)
    private static let fastSpring  = Animation.spring(response: 0.20, dampingFraction: 0.72, blendDuration: 0)
    private static let ultraFast   = Animation.spring(response: 0.15, dampingFraction: 0.78, blendDuration: 0)

    public var body: some View {
        ZStack(alignment: .top) {
            // Notch background shell
            BoringNotchBackground(
                expansionLevel: brain.expansionLevel,
                cornerRadius: NotchMetrics.cornerRadius(for: brain.expansionLevel)
            )
            .animation(Self.notchSpring, value: brain.expansionLevel)

            // Drop-zone cyan glow rim
            if isDropTargeted {
                NotchShape(
                    topCornerRadius: topCornerRadius,
                    bottomCornerRadius: bottomCornerRadius
                )
                .stroke(
                    LinearGradient(
                        colors: [.cyan, .blue.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.8
                )
                .animation(Self.fastSpring, value: isDropTargeted)
            }

            // Content
            VStack(spacing: 0) {
                topBar
                    .frame(height: NotchMetrics.closedHeight)

                // Level 2: Hover Peek
                if brain.expansionLevel == .hoverPeek {
                    hoverPeekContent
                        .padding(.horizontal, 14)
                        .padding(.bottom, 8)
                        .transition(
                            .asymmetric(
                                insertion: .push(from: .top).combined(with: .opacity),
                                removal:   .push(from: .bottom).combined(with: .opacity)
                            )
                        )
                }

                // Level 3: Full Expanded
                if brain.expansionLevel == .expanded {
                    expandedDeck
                        .padding(.horizontal, 14)
                        .padding(.bottom, 14)
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .top)),
                                removal:   .opacity.combined(with: .scale(scale: 0.96, anchor: .top))
                            )
                        )
                }
            }
            .frame(
                width: NotchMetrics.size(for: brain.expansionLevel).width,
                alignment: .top
            )
            .animation(Self.notchSpring, value: brain.expansionLevel)
        }
        .frame(
            width:  NotchMetrics.size(for: brain.expansionLevel).width,
            height: NotchMetrics.size(for: brain.expansionLevel).height,
            alignment: .top
        )
        .scaleEffect(dropFeedbackScale)
        .clipped()
        .animation(Self.notchSpring, value: brain.expansionLevel)
        // Global drop target on the whole notch area
        .onDrop(
            of: [UTType.fileURL, UTType.text, UTType.plainText, UTType.image, UTType.item],
            isTargeted: $isDropTargeted
        ) { providers in
            handleDrop(providers: providers)
        }
        .onChange(of: isDropTargeted) { _, targeted in
            withAnimation(Self.ultraFast) {
                dropFeedbackScale = targeted ? 1.02 : 1.0
            }
        }
        .onChange(of: brain.expansionLevel) { _, level in
            if level == .expanded {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                    inputFocused = true
                }
            } else {
                inputFocused = false
            }
        }
        .contextMenu { contextMenuItems }
    }

    // MARK: - Corner Radii (animate with level)
    private var topCornerRadius: CGFloat {
        switch brain.expansionLevel {
        case .closed: return 6
        case .hoverPeek: return 10
        case .expanded: return 14
        }
    }
    private var bottomCornerRadius: CGFloat {
        switch brain.expansionLevel {
        case .closed: return 14
        case .hoverPeek: return 18
        case .expanded: return 24
        }
    }

    // MARK: - Top Bar: Eyes always centered when closed
    private var topBar: some View {
        ZStack {
            if brain.expansionLevel == .closed {
                // CLOSED: Eyes perfectly centered in notch
                HStack(spacing: 0) {
                    Spacer()
                    EyesView(mood: brain.mood, isCompact: false)
                        .frame(width: 54, height: NotchMetrics.closedHeight)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            brain.triggerSmile()
                            withAnimation(Self.notchSpring) { brain.toggleExpanded() }
                        }
                    Spacer()
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            } else {
                // PEEK / EXPANDED: Eyes left-aligned + controls
                HStack(spacing: 10) {
                    EyesView(mood: brain.mood, isCompact: true)
                        .frame(width: 30, height: NotchMetrics.closedHeight)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            brain.triggerSmile()
                            withAnimation(Self.notchSpring) { brain.toggleExpanded() }
                        }

                    if brain.expansionLevel == .hoverPeek {
                        peekStatusRow
                        Spacer()
                        peekQuickActions
                    } else {
                        expandedTopRow
                    }
                }
                .padding(.horizontal, 14)
                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .leading)))
            }
        }
        .frame(height: NotchMetrics.closedHeight)
        .animation(Self.notchSpring, value: brain.expansionLevel)
    }

    // MARK: - Peek Status Row (scrolling title)
    private var peekStatusRow: some View {
        HStack(spacing: 6) {
            if brain.controls.isPlaying {
                Image(systemName: "waveform")
                    .font(.system(size: 9))
                    .foregroundStyle(.green)
                    .symbolEffect(.variableColor.iterative.dimInactiveLayers, options: .repeating)
            }
            Text(
                brain.controls.isPlaying
                    ? "\(brain.controls.trackTitle) · \(brain.controls.trackArtist)"
                    : brain.status
            )
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.88))
            .lineLimit(1)
        }
    }

    // MARK: - Peek Quick Actions
    private var peekQuickActions: some View {
        HStack(spacing: 8) {
            if brain.controls.isPlaying {
                peekMediaBtn("backward.fill") { brain.controls.previousTrack() }
                peekMediaBtn(brain.controls.isPlaying ? "pause.fill" : "play.fill") {
                    brain.controls.togglePlayPause()
                    brain.triggerSmile()
                }
                peekMediaBtn("forward.fill") { brain.controls.nextTrack() }
            }

            // Expand chevron
            Button {
                withAnimation(Self.notchSpring) { brain.expand() }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.65))
                    .frame(width: 22, height: 22)
                    .background(Color.white.opacity(0.14), in: Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private func peekMediaBtn(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.75))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Expanded Top Row (Pixel branding + close)
    private var expandedTopRow: some View {
        HStack(spacing: 7) {
            // Brand pill
            HStack(spacing: 5) {
                Text("PIXEL")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .tracking(2.5)

                if brain.isProtectedByBlacklist {
                    Label("PRIVATE", systemImage: "eye.slash.fill")
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.2), in: Capsule())
                        .foregroundStyle(.red)
                } else if brain.mood != .idle {
                    Text(moodLabel)
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(moodColor.opacity(0.2), in: Capsule())
                        .foregroundStyle(moodColor)
                        .animation(.easeInOut(duration: 0.2), value: brain.mood)
                }
            }

            Spacer()

            // Settings + Close
            HStack(spacing: 10) {
                Button {
                    withAnimation(Self.fastSpring) { brain.showSettings.toggle() }
                } label: {
                    Image(systemName: brain.showSettings ? "gearshape.fill" : "gearshape")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(brain.showSettings ? Color.cyan : Color.white.opacity(0.55))
                        .rotationEffect(.degrees(brain.showSettings ? 30 : 0))
                        .animation(Self.fastSpring, value: brain.showSettings)
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(Self.notchSpring) { brain.collapse() }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.white.opacity(0.3))
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var moodLabel: String {
        switch brain.mood {
        case .scanning:  return "SCANNING"
        case .thinking:  return "THINKING"
        case .executing: return "ACTING"
        case .sleeping:  return "SLEEP"
        default:         return brain.mood.rawValue.uppercased()
        }
    }

    private var moodColor: Color {
        switch brain.mood {
        case .scanning:  return .orange
        case .thinking:  return .cyan
        case .executing: return .green
        case .sleeping:  return .indigo
        default:         return .white
        }
    }

    // MARK: - Hover Peek Content
    private var hoverPeekContent: some View {
        EmptyView()
    }

    // MARK: - Level 3: Full Expanded Work Deck
    private var expandedDeck: some View {
        VStack(alignment: .leading, spacing: 10) {
            if brain.showSettings {
                SettingsDeckView(settings: settings, brain: brain)
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.97, anchor: .top).combined(with: .opacity),
                            removal:   .scale(scale: 0.97, anchor: .top).combined(with: .opacity)
                        )
                    )
            } else {
                CapabilitiesDeckView(brain: brain, settings: settings, currentTab: $deckTab)
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.97, anchor: .top).combined(with: .opacity),
                            removal:   .scale(scale: 0.97, anchor: .top).combined(with: .opacity)
                        )
                    )

                commandBar
            }
        }
        .animation(Self.notchSpring, value: brain.showSettings)
    }

    // MARK: - Command / Input Bar
    private var commandBar: some View {
        VStack(spacing: 4) {
            HStack(spacing: 9) {
                // Animated state indicator
                ZStack {
                    if brain.isBusy {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12))
                            .foregroundStyle(
                                LinearGradient(colors: [.cyan, .blue], startPoint: .top, endPoint: .bottom)
                            )
                            .symbolEffect(.pulse, options: .repeating)
                    } else {
                        Image(systemName: "sparkle")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.white.opacity(0.35))
                    }
                }
                .animation(Self.fastSpring, value: brain.isBusy)
                .frame(width: 18)

                TextField(
                    "",
                    text: $brain.input,
                    prompt: Text("Ask Pixel, say 'click [text]', 'type [words]', 'timer 25m'…")
                        .foregroundStyle(Color.white.opacity(0.25))
                )
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .focused($inputFocused)
                .onSubmit {
                    Task { await brain.submit() }
                }

                // Right side
                Group {
                    if brain.isBusy {
                        ProgressView()
                            .controlSize(.small)
                            .colorScheme(.dark)
                            .scaleEffect(0.85)
                    } else if !brain.input.isEmpty {
                        Button {
                            Task { await brain.submit() }
                        } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(
                                    LinearGradient(colors: [.cyan, .blue], startPoint: .top, endPoint: .bottom)
                                )
                        }
                        .buttonStyle(.plain)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                    }
                }
                .animation(Self.fastSpring, value: brain.isBusy)
                .animation(Self.fastSpring, value: brain.input.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(inputFocused ? 0.10 : 0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(inputFocused ? 0.25 : 0.09), lineWidth: 0.9)
                    )
            )
            .animation(Self.fastSpring, value: inputFocused)

            // Footer hints
            HStack {
                Text("⌥ Space")
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.25))
                Text("to toggle")
                    .font(.system(size: 8.5))
                    .foregroundStyle(Color.white.opacity(0.2))
                Spacer()
                if !brain.activeActionSummary.isEmpty {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 4, height: 4)
                        Text(brain.activeActionSummary)
                            .font(.system(size: 8.5, design: .monospaced))
                            .foregroundStyle(Color.green.opacity(0.85))
                    }
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Context Menu
    @ViewBuilder
    private var contextMenuItems: some View {
        Button(brain.expansionLevel == .expanded ? "Collapse Pixel" : "Open AI Work Deck") {
            withAnimation(Self.notchSpring) { brain.toggleExpanded() }
        }
        Button("Smile 😊") { brain.triggerSmile(duration: 5) }
        Button("Scan Screen") { Task { await brain.glance() } }
        Divider()
        Menu("Timers") {
            Button("25m Pomodoro") { FocusTimerService.shared.start(duration: 25 * 60, name: "Pomodoro") }
            Button("5m Break") { FocusTimerService.shared.start(duration: 5 * 60, name: "Short Break") }
            Button("45m Deep Work") { FocusTimerService.shared.start(duration: 45 * 60, name: "Deep Work") }
        }
        Divider()
        Button("Settings") {
            brain.expand()
            brain.showSettings = true
        }
        Divider()
        Button("Quit Pixel") { NSApplication.shared.terminate(nil) }
    }

    // MARK: - Drop Handler (files and text dropped onto the notch)
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    DispatchQueue.main.async {
                        brain.handleDroppedURL(url)
                        // Switch to Shelf tab so user sees it landed
                    }
                }
                handled = true
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) ||
                      provider.hasItemConformingToTypeIdentifier(UTType.text.identifier) {
                _ = provider.loadObject(ofClass: String.self) { text, _ in
                    guard let text else { return }
                    DispatchQueue.main.async {
                        brain.handleDroppedText(text)
                    }
                }
                handled = true
            }
        }
        return handled
    }
}
