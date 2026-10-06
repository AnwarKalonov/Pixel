import ApplicationServices
import CoreGraphics
import Foundation

enum Permissions {
    static var accessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    static var screenTrusted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    static func promptAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func promptScreen() {
        _ = CGRequestScreenCaptureAccess()
    }
}
