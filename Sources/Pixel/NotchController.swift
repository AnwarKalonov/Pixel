import AppKit
import Combine
import SwiftUI

@MainActor
public final class NotchController {
    private let brain: PixelBrain
    private var panels: [CGDirectDisplayID: NotchPanel] = [:]
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var keyMonitor: Any?
    private var globalKeyMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    public init(brain: PixelBrain) {
        self.brain = brain

        brain.onSizeChange = { [weak self] in
            self?.repositionAll(animated: true)
        }

        // Observe notch position preference changes → smoothly reposition
        PixelSettings.shared.$notchOffsetX
            .combineLatest(PixelSettings.shared.$notchOffsetY)
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.repositionAll(animated: true)
            }
            .store(in: &cancellables)

        setupMonitors()
        handleScreenChange()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleScreenChange() }
        }
    }

    // MARK: - Screen Sync

    public func sync() {
        handleScreenChange()
    }

    private func handleScreenChange() {
        let screens = NSScreen.screens
        let liveIDs = Set(screens.map(\.displayID))

        // Remove panels for disconnected screens
        for (id, panel) in panels where !liveIDs.contains(id) {
            panel.close()
            panels[id] = nil
        }

        // Add / update panels for connected screens
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

    private func repositionAll(animated: Bool) {
        panels.values.forEach { $0.placeOnScreen(animated: animated) }
    }

    // MARK: - Event Monitors

    private func setupMonitors() {
        let handleMouse: (NSEvent) -> Void = { [weak self] event in
            guard let self else { return }
            let point = NSEvent.mouseLocation
            self.brain.trackMouse(point)

            // Collapse when clicking outside all notch panels
            guard event.type == .leftMouseDown,
                  self.brain.expansionLevel == .expanded else { return }

            let onAnyPanel = self.panels.values.contains { $0.frame.contains(point) }
            if !onAnyPanel {
                self.brain.collapse()
            }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDown]
        ) { event in
            handleMouse(event)
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDown],
            handler: handleMouse
        )

        // Global hotkey: Option+Space  OR  Ctrl+Option+Space
        let handleKey: (NSEvent) -> NSEvent? = { [weak self] event in
            guard let self else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let isOptionSpace = flags == [.option] && event.keyCode == 49
            let isCtrlOptionSpace = flags == [.control, .option] && event.keyCode == 49

            guard isOptionSpace || isCtrlOptionSpace else { return event }

            self.brain.toggleExpanded()
            if self.brain.expansionLevel == .expanded {
                let target = self.panel(near: NSEvent.mouseLocation)
                target?.makeKeyAndOrderFront(nil)
                target?.orderFrontRegardless()
            }
            return nil
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { handleKey($0) ?? $0 }
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { _ = handleKey($0) }

        brain.trackMouse(NSEvent.mouseLocation)
    }

    private func panel(near point: CGPoint) -> NotchPanel? {
        panels.values.first { $0.screenFrame.contains(point) } ?? panels.values.first
    }
}
