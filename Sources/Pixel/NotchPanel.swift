import AppKit
import SwiftUI

// MARK: - NotchPanel

@MainActor
public final class NotchPanel: NSPanel {
    private let brain: PixelBrain
    private(set) var screenFrame: NSRect
    private(set) var displayID: CGDirectDisplayID

    public init(screen: NSScreen, brain: PixelBrain) {
        self.brain = brain
        self.screenFrame = screen.frame
        self.displayID = screen.displayID
        let initialSize = NotchMetrics.size(for: brain.expansionLevel)

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: initialSize.width, height: initialSize.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false

        // Top-of-everything window level: sits on top of all screens, menu bars, and spaces
        isFloatingPanel = false
        level = .screenSaver

        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        isMovable = false
        becomesKeyOnlyIfNeeded = false
        hidesOnDeactivate = false
        animationBehavior = .none
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        ignoresMouseEvents = false

        let host = NSHostingView(rootView: NotchView(brain: brain))
        host.frame = contentView?.bounds ?? .zero
        host.autoresizingMask = [.width, .height]
        contentView = host

        placeOnScreen(animated: false)
    }

    // CRITICAL: Prevent AppKit from constraining below the menu bar
    public override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        return frameRect
    }

    public override var canBecomeKey: Bool {
        return brain.expansionLevel == .expanded
    }

    public func attach(screen: NSScreen) {
        screenFrame = screen.frame
        displayID = screen.displayID
    }

    public func placeOnScreen(animated: Bool) {
        let size = NotchMetrics.size(for: brain.expansionLevel)
        let settings = PixelSettings.shared

        // Center on the screen, flush with the very top edge
        let x = screenFrame.midX - size.width / 2 + settings.notchOffsetX
        // screenFrame.maxY IS the top of the screen in AppKit's flipped coords
        let y = screenFrame.maxY - size.height + settings.notchOffsetY

        let frame = NSRect(x: x, y: y, width: size.width, height: size.height)

        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.22
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.46, 0.45, 0.94)
                animator().setFrame(frame, display: true)
            }
        } else {
            setFrame(frame, display: true)
        }

        level = .screenSaver
        orderFrontRegardless()
    }
}
