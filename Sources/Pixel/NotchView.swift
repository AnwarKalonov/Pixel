import AppKit
import SwiftUI

struct NotchView: View {
    @ObservedObject var brain: PixelBrain
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            EyesView(
                look: brain.look,
                blink: brain.blink,
                mood: brain.mood
            )
            .frame(height: 28)
            .padding(.top, 4)
            .contentShape(Rectangle())
            .onTapGesture {
                brain.toggleExpanded()
            }

            if brain.isExpanded {
                expandedBody
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, brain.isExpanded ? 16 : 18)
        .padding(.bottom, brain.isExpanded ? 14 : 6)
        .frame(
            width: brain.isExpanded ? NotchMetrics.expandedWidth : NotchMetrics.collapsedWidth,
            height: brain.isExpanded ? NotchMetrics.expandedHeight : NotchMetrics.collapsedHeight,
            alignment: .top
        )
        .background(NotchShape())
        .contextMenu {
            Button(brain.isExpanded ? "Collapse" : "Open") {
                brain.toggleExpanded()
            }
            Button("Ask Pixel to look") {
                Task { await brain.glance() }
            }
            Divider()
            Button("Quit Pixel") {
                NSApplication.shared.terminate(nil)
            }
        }
        .onChange(of: brain.isExpanded) { _, open in
            if open {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    inputFocused = true
                }
            } else {
                inputFocused = false
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: brain.isExpanded)
    }

    private var expandedBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !brain.status.isEmpty {
                Text(brain.status)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .lineLimit(3)
            }

            if brain.needsSetup {
                setupHints
            }

            HStack(spacing: 8) {
                TextField("", text: $brain.input, prompt: Text("Ask Pixel…").foregroundStyle(Color.white.opacity(0.28)))
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                    .focused($inputFocused)
                    .onSubmit {
                        Task { await brain.submit() }
                    }

                if brain.isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .colorScheme(.dark)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            if brain.showSettings {
                settings
            } else {
                HStack {
                    Button("Permissions") {
                        brain.requestPermissions()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.35))

                    Spacer()

                    Button(brain.showSettings ? "Done" : "Key") {
                        brain.showSettings.toggle()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.35))
                }
            }
        }
        .padding(.top, 6)
    }

    private var setupHints: some View {
        Text(brain.setupMessage)
            .font(.system(size: 10.5, weight: .regular, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.4))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 6) {
            SecureField("OpenAI API key", text: $brain.apiKey)
                .textFieldStyle(.plain)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white)
                .onChange(of: brain.apiKey) { _, value in
                    brain.saveAPIKey(value)
                }
            TextField("Model", text: $brain.model)
                .textFieldStyle(.plain)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.7))
                .onChange(of: brain.model) { _, value in
                    brain.saveModel(value)
                }
            Text("⌃⌥Space opens Pixel. It sees, types, and clicks only when you ask.")
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.32))
        }
    }
}

struct NotchShape: View {
    var body: some View {
        UnevenRoundedRectangle(
            cornerRadii: .init(
                topLeading: 0,
                bottomLeading: 16,
                bottomTrailing: 16,
                topTrailing: 0
            ),
            style: .continuous
        )
        .fill(Color.black)
    }
}
