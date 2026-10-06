import AppKit
import CoreGraphics

struct Hands {
    func moveAndClick(_ appKitPoint: CGPoint) {
        let q = quartz(from: appKitPoint)
        let source = CGEventSource(stateID: .hidSystemState)
        CGWarpMouseCursorPosition(q)
        postMouse(.mouseMoved, q, source)
        postMouse(.leftMouseDown, q, source)
        postMouse(.leftMouseUp, q, source)
    }

    func type(_ string: String) {
        let utf16 = Array(string.utf16)
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        var i = 0
        while i < utf16.count {
            var chars = [UniChar](repeating: 0, count: 2)
            var length = 1
            chars[0] = utf16[i]
            if i + 1 < utf16.count, (0xD800...0xDBFF).contains(utf16[i]) {
                chars[1] = utf16[i + 1]
                length = 2
                i += 2
            } else {
                i += 1
            }
            if chars[0] == 10 || chars[0] == 13 {
                hotkey("return")
                continue
            }
            let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
            down?.keyboardSetUnicodeString(stringLength: length, unicodeString: &chars)
            down?.post(tap: .cghidEventTap)
            let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            up?.keyboardSetUnicodeString(stringLength: length, unicodeString: &chars)
            up?.post(tap: .cghidEventTap)
            usleep(7000)
        }
    }

    func hotkey(_ spec: String) {
        let parts = spec.lowercased().split(separator: "+").map(String.init)
        var flags: CGEventFlags = []
        var key = parts.last ?? ""
        for part in parts.dropLast() {
            switch part {
            case "cmd", "command", "⌘": flags.insert(.maskCommand)
            case "shift": flags.insert(.maskShift)
            case "opt", "option", "alt": flags.insert(.maskAlternate)
            case "ctrl", "control": flags.insert(.maskControl)
            default: break
            }
        }
        if parts.count == 1 { key = parts[0] }
        let code = virtualKey(key)
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        if let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true) {
            down.flags = flags
            down.post(tap: .cghidEventTap)
        }
        if let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false) {
            up.flags = flags
            up.post(tap: .cghidEventTap)
        }
    }

    private func postMouse(_ type: CGEventType, _ point: CGPoint, _ source: CGEventSource?) {
        let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
        event?.post(tap: .cghidEventTap)
    }

    private func quartz(from appKit: CGPoint) -> CGPoint {
        let height = NSScreen.screens.map(\.frame.maxY).max() ?? 0
        return CGPoint(x: appKit.x, y: height - appKit.y)
    }

    private func virtualKey(_ name: String) -> CGKeyCode {
        switch name {
        case "return", "enter": return 36
        case "tab": return 48
        case "esc", "escape": return 53
        case "space": return 49
        case "delete", "backspace": return 51
        case "up": return 126
        case "down": return 125
        case "left": return 123
        case "right": return 124
        case "a": return 0
        case "c": return 8
        case "v": return 9
        case "x": return 7
        case "z": return 6
        case "t": return 17
        case "n": return 45
        case "w": return 13
        case "s": return 1
        case "f": return 3
        case "l": return 37
        case "k": return 40
        default: return 0
        }
    }
}
