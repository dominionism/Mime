import ApplicationServices
import CoreGraphics

/// The direction used when cycling through frontmost applications.
enum ApplicationSwitchDirection: Equatable, Sendable {
    case next
    case previous
}

/// A system-level action driven by a dynamic hand gesture.
enum SystemGestureAction: Equatable, Sendable {
    case nextApplication
    case previousApplication
    case closeCurrentTabOrWindow
}

/// Errors that can occur before a synthetic keyboard shortcut reaches the frontmost app.
enum InputEventError: LocalizedError, Equatable, Sendable {
    case accessibilityNotAllowed
    case eventSourceUnavailable
    case eventCreationFailed

    var errorDescription: String? {
        switch self {
        case .accessibilityNotAllowed:
            "Allow Mime in System Settings › Privacy & Security › Accessibility to control other apps."
        case .eventSourceUnavailable:
            "Mime could not create a keyboard event source."
        case .eventCreationFailed:
            "Mime could not create the requested keyboard event."
        }
    }
}

/// The narrow boundary around CGEvent posting, kept injectable for deterministic tests.
@MainActor
protocol InputEventPosting {
    func postKeyPress(keyCode: CGKeyCode, flags: CGEventFlags) throws
}

/// Posts one balanced key-down/key-up pair to the frontmost application.
@MainActor
struct SystemInputEventPoster: InputEventPosting {
    var isAccessibilityTrusted: () -> Bool = { AXIsProcessTrusted() }

    func postKeyPress(keyCode: CGKeyCode, flags: CGEventFlags) throws {
        guard isAccessibilityTrusted() else {
            throw InputEventError.accessibilityNotAllowed
        }
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            throw InputEventError.eventSourceUnavailable
        }
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else {
            throw InputEventError.eventCreationFailed
        }

        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}

/// Translates Mime's dynamic gestures to the native macOS shortcuts users already know.
@MainActor
protocol SystemActionExecuting {
    func perform(_ action: SystemGestureAction) throws
}

@MainActor
struct SystemActionExecutor: SystemActionExecuting {
    static let tabKeyCode: CGKeyCode = 48
    static let wKeyCode: CGKeyCode = 13

    private let poster: any InputEventPosting

    init(poster: any InputEventPosting = SystemInputEventPoster()) {
        self.poster = poster
    }

    func perform(_ action: SystemGestureAction) throws {
        switch action {
        case .nextApplication:
            try poster.postKeyPress(keyCode: Self.tabKeyCode, flags: [.maskCommand])
        case .previousApplication:
            try poster.postKeyPress(keyCode: Self.tabKeyCode, flags: [.maskCommand, .maskShift])
        case .closeCurrentTabOrWindow:
            // Cmd-W closes the active tab in tab-aware apps and the active window otherwise.
            try poster.postKeyPress(keyCode: Self.wKeyCode, flags: [.maskCommand])
        }
    }
}
