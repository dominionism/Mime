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

/// Feedback for the most recent dynamic gesture action.
enum SystemActionStatus: Equatable, Sendable {
    case idle
    case performed(MotionGesture)
    case failed(MotionGesture, message: String)
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
    func postKeyChord(_ events: [(keyCode: CGKeyCode, keyDown: Bool, flags: CGEventFlags)]) throws
}

/// Posts balanced keyboard events to the frontmost application.
@MainActor
struct SystemInputEventPoster: InputEventPosting {
    var isAccessibilityTrusted: () -> Bool = { AXIsProcessTrusted() }

    func postKeyPress(keyCode: CGKeyCode, flags: CGEventFlags) throws {
        try postKeyChord([
            (keyCode: keyCode, keyDown: true, flags: flags),
            (keyCode: keyCode, keyDown: false, flags: flags)
        ])
    }

    func postKeyChord(_ events: [(keyCode: CGKeyCode, keyDown: Bool, flags: CGEventFlags)]) throws {
        guard isAccessibilityTrusted() else {
            throw InputEventError.accessibilityNotAllowed
        }
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            throw InputEventError.eventSourceUnavailable
        }
        guard !events.isEmpty else {
            throw InputEventError.eventCreationFailed
        }

        // Create the whole sequence before posting anything. If Quartz cannot create one event, no partial
        // shortcut reaches the frontmost app.
        let keyEvents = events.compactMap { event -> CGEvent? in
            guard let keyEvent = CGEvent(
                keyboardEventSource: source,
                virtualKey: event.keyCode,
                keyDown: event.keyDown
            ) else { return nil }
            keyEvent.flags = event.flags
            return keyEvent
        }
        guard keyEvents.count == events.count else {
            throw InputEventError.eventCreationFailed
        }
        for event in keyEvents {
            event.post(tap: .cghidEventTap)
        }
    }
}

/// Translates Mime's dynamic gestures to the native macOS shortcuts users already know.
@MainActor
protocol SystemActionExecuting {
    func perform(_ action: SystemGestureAction) throws
}

@MainActor
struct SystemActionExecutor: SystemActionExecuting {
    static let commandKeyCode: CGKeyCode = 55
    static let shiftKeyCode: CGKeyCode = 56
    static let tabKeyCode: CGKeyCode = 48
    static let wKeyCode: CGKeyCode = 13

    private let poster: any InputEventPosting

    init(poster: any InputEventPosting = SystemInputEventPoster()) {
        self.poster = poster
    }

    func perform(_ action: SystemGestureAction) throws {
        switch action {
        case .nextApplication:
            // Keep Command held while Tab is pressed so the system application switcher receives a real shortcut.
            try poster.postKeyChord([
                (keyCode: Self.commandKeyCode, keyDown: true, flags: [.maskCommand]),
                (keyCode: Self.tabKeyCode, keyDown: true, flags: [.maskCommand]),
                (keyCode: Self.tabKeyCode, keyDown: false, flags: [.maskCommand]),
                (keyCode: Self.commandKeyCode, keyDown: false, flags: [])
            ])
        case .previousApplication:
            // Shift is held only for the Tab press, yielding the previous-app direction in the switcher.
            try poster.postKeyChord([
                (keyCode: Self.commandKeyCode, keyDown: true, flags: [.maskCommand]),
                (keyCode: Self.shiftKeyCode, keyDown: true, flags: [.maskCommand, .maskShift]),
                (keyCode: Self.tabKeyCode, keyDown: true, flags: [.maskCommand, .maskShift]),
                (keyCode: Self.tabKeyCode, keyDown: false, flags: [.maskCommand, .maskShift]),
                (keyCode: Self.shiftKeyCode, keyDown: false, flags: [.maskCommand]),
                (keyCode: Self.commandKeyCode, keyDown: false, flags: [])
            ])
        case .closeCurrentTabOrWindow:
            // Cmd-W closes the active tab in tab-aware apps and the active window otherwise.
            try poster.postKeyChord([
                (keyCode: Self.commandKeyCode, keyDown: true, flags: [.maskCommand]),
                (keyCode: Self.wKeyCode, keyDown: true, flags: [.maskCommand]),
                (keyCode: Self.wKeyCode, keyDown: false, flags: [.maskCommand]),
                (keyCode: Self.commandKeyCode, keyDown: false, flags: [])
            ])
        }
    }
}
