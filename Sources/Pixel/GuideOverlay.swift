import AppKit
import SwiftUI

@MainActor
final class GuideOverlay {
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    func show(rect: CGRect, message: String) {
        hideTask?.cancel()
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let host = NSHostingView(rootView: GuideView(rect: rect, message: message))
        host.frame = panel.contentView?.bounds ?? .zero
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        panel.orderFrontRegardless()

        hideTask = Task {
            try? await Task.sleep(for: .seconds(3.2))
            guard !Task.isCancelled else { return }
            panel.orderOut(nil)
        }
    }

    private func makePanel() -> NSPanel {
        let screen = NSScreen.main?.frame ?? .zero
        let panel = NSPanel(
            contentRect: screen,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .screenSaver
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isFloatingPanel = true
        return panel
    }
}

private struct GuideView: View {
    var rect: CGRect
    var message: String

    var body: some View {
        GeometryReader { geo in
            let local = toLocal(rect, in: geo.size)
            ZStack(alignment: .topLeading) {
                Color.clear
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.9), lineWidth: 2)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
                    .frame(width: local.width, height: local.height)
                    .position(x: local.midX, y: local.midY)

                if !message.isEmpty {
                    Text(message)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.86), in: Capsule())
                        .position(x: local.midX, y: max(22, local.minY - 18))
                }
            }
        }
        .ignoresSafeArea()
    }

    private func toLocal(_ rect: CGRect, in size: CGSize) -> CGRect {
        guard let screen = NSScreen.main else { return rect }
        let x = rect.minX - screen.frame.minX
        let yFromBottom = rect.minY - screen.frame.minY
        let y = size.height - yFromBottom - rect.height
        return CGRect(x: x, y: y, width: rect.width, height: rect.height)
    }
}
