import AppKit
import SwiftUI

@main
struct PixelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var notches: NotchController?
    private var house: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let brain = PixelBrain.shared
        let notches = NotchController(brain: brain)
        notches.sync()
        self.notches = notches

        brain.onOpenHouse = { [weak self] in
            self?.showHouse()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        notches?.sync()
        showHouse()
        return false
    }

    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === house {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private func showHouse() {
        NSApp.setActivationPolicy(.regular)
        if house == nil {
            let root = NSHostingView(rootView: AppRootView(brain: .shared))
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 880, height: 620),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Pixel"
            window.contentView = root
            window.center()
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.setFrameAutosaveName("PixelHouse")
            house = window
        }
        house?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
