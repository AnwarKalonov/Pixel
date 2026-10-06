import AppKit
import SwiftUI

@MainActor
final class NotchController {
    private let brain: PixelBrain
    private var panels: [CGDirectDisplayID: NotchPanel] = [:]
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var keyMonitor: Any?
    private var globalKeyMonitor: Any?

    init(brain: PixelBrain) {
        self.brain = brain
        brain.onSizeChange = { [weak self] in
            self?.panels.values.forEach { $0.placeOnScreen(animated: true) }
        }
        observe()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.sync()
            }
        }
    }

    func sync() {
        let screens = NSScreen.screens
        let live = Set(screens.map(\.displayID))
        for (id, panel) in panels where !live.contains(id) {
            panel.close()
            panels[id] = nil
        }
        for screen in screens {
            if let panel = panels[screen.displayID] {
                panel.attach(screen: screen)
                panel.placeOnScreen(animated: false)
                panel.orderFrontRegardless()
            } else {
                let panel = NotchPanel(screen: screen, brain: brain)
                panel.orderFrontRegardless()
                panels[screen.displayID] = panel
            }
        }
    }

    private func observe() {
        let mouse: (NSEvent) -> Void = { [weak self] event in
            guard let self else { return }
            self.brain.trackMouse(NSEvent.mouseLocation)
            guard event.type == .leftMouseDown, self.brain.isExpanded else { return }
            let point = NSEvent.mouseLocation
            let onNotch = self.panels.values.contains { $0.frame.contains(point) }
            let onHouse = NSApp.windows.contains { window in
                window.title == "Pixel" && !(window is NotchPanel) && window.isVisible && window.frame.contains(point)
            }
            if !onNotch && !onHouse {
                self.brain.collapse()
            }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown]) { event in
            mouse(event)
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown], handler: mouse)

        let hotkey: (NSEvent) -> NSEvent? = { [weak self] event in
            guard let self else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags == [.control, .option], event.keyCode == 49 {
                self.brain.toggleExpanded()
                if self.brain.isExpanded {
                    self.panel(near: NSEvent.mouseLocation)?.makeKeyAndOrderFront(nil)
                }
                return nil
            }
            return event
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            hotkey(event) ?? event
        }
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            _ = hotkey(event)
        }

        brain.trackMouse(NSEvent.mouseLocation)
    }

    private func panel(near point: CGPoint) -> NotchPanel? {
        panels.values.first { $0.screenFrame.contains(point) } ?? panels.values.first
    }
}
