import AppKit
import SwiftUI

@MainActor
final class NotchPanel: NSPanel {
    private let brain: PixelBrain
    private(set) var screenFrame: NSRect

    init(screen: NSScreen, brain: PixelBrain) {
        self.brain = brain
        self.screenFrame = screen.frame
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: NotchMetrics.collapsedWidth, height: NotchMetrics.collapsedHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isMovable = false
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        animationBehavior = .none
        titleVisibility = .hidden
        titlebarAppearsTransparent = true

        let host = NSHostingView(rootView: NotchView(brain: brain, displayID: screen.displayID))
        host.frame = contentView?.bounds ?? .zero
        host.autoresizingMask = [.width, .height]
        contentView = host
        placeOnScreen(animated: false)
    }

    func attach(screen: NSScreen) {
        screenFrame = screen.frame
    }

    func placeOnScreen(animated: Bool) {
        let size = brain.isExpanded ? NotchMetrics.expandedSize : NotchMetrics.collapsedSize
        let frame = NSRect(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.26
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                animator().setFrame(frame, display: true)
            }
        } else {
            setFrame(frame, display: true)
        }
    }
}

enum NotchMetrics {
    static let collapsedWidth: CGFloat = 132
    static let collapsedHeight: CGFloat = 32
    static let expandedWidth: CGFloat = 380
    static let expandedHeight: CGFloat = 448
    static var collapsedSize: NSSize { NSSize(width: collapsedWidth, height: collapsedHeight) }
    static var expandedSize: NSSize { NSSize(width: expandedWidth, height: expandedHeight) }
}
