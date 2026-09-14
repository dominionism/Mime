import ApplicationServices
import Foundation

/// Links to the macOS privacy pane needed for gestures that post shortcuts to other applications.
struct AccessibilityPermissionController {
    static let privacySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    /// Ask macOS to show its one-time trust prompt. The Settings link remains available when the user dismisses it.
    static func requestAccessPrompt() {
        // The SDK exposes kAXTrustedCheckOptionPrompt as a mutable C global, which Swift 6 correctly rejects from
        // concurrent code. Its documented key is stable, so use the equivalent immutable string literal here.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
