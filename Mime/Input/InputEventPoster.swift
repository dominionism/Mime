import AppKit
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

/// A stable list of running user apps, independent of the system's changing most-recently-used order.
@MainActor
protocol ApplicationSwitchWorkspace {
    var applicationProcessIdentifiers: [Int32] { get }
    var frontmostProcessIdentifier: Int32? { get }
    func activate(processIdentifier: Int32) -> Bool
}

@MainActor
struct SystemApplicationSwitchWorkspace: ApplicationSwitchWorkspace {
    var applicationProcessIdentifiers: [Int32] {
        NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isTerminated && $0 != .current
        }.map(\.processIdentifier)
    }

    var frontmostProcessIdentifier: Int32? {
        NSWorkspace.shared.frontmostApplication?.processIdentifier
    }

    func activate(processIdentifier: Int32) -> Bool {
        guard let application = NSRunningApplication(processIdentifier: processIdentifier),
              !application.isTerminated else { return false }
        if application.isHidden { _ = application.unhide() }
        return application.activate(options: [])
    }
}

enum ApplicationSwitchError: LocalizedError, Equatable {
    case noOtherApplications
    case activationRefused

    var errorDescription: String? {
        switch self {
        case .noOtherApplications: "Open another app to switch to."
        case .activationRefused: "macOS could not activate that app. Try the swipe again."
        }
    }
}

@MainActor
protocol ApplicationCycling {
    func cycle(_ direction: ApplicationSwitchDirection) throws
}

/// Keep a stable ring so repeated swipes traverse all apps and reversing a swipe retraces that order.
/// Releasing Command after every synthetic Tab would instead toggle the two most recently used apps.
@MainActor
final class RunningApplicationCycler: ApplicationCycling {
    static let pendingActivationLifetime = 0.75

    private struct PendingActivation {
        let selection: Int32
        let origin: Int32?
        let intermediates: Set<Int32>
        let requestedAt: Double
    }

    private let workspace: any ApplicationSwitchWorkspace
    private let now: () -> Double
    private var order: [Int32] = []
    private var pending: PendingActivation?

    init(
        workspace: any ApplicationSwitchWorkspace = SystemApplicationSwitchWorkspace(),
        now: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.workspace = workspace
        self.now = now
    }

    func cycle(_ direction: ApplicationSwitchDirection) throws {
        let running = workspace.applicationProcessIdentifiers
        let available = Set(running)
        order.removeAll { !available.contains($0) }
        for processIdentifier in running where !order.contains(processIdentifier) {
            order.append(processIdentifier)
        }
        let frontmost = workspace.frontmostProcessIdentifier
        let timestamp = now()
        // Focus can pass through earlier requested apps while several activations are in flight. Continue from
        // the latest selection during that interval, including when an intermediate activation arrives late.
        // Bound the history so a stale request cannot indefinitely override the app the user is actually using.
        let current: Int32?
        if let pending,
           timestamp >= pending.requestedAt, timestamp - pending.requestedAt <= Self.pendingActivationLifetime,
           available.contains(pending.selection), frontmost != pending.selection,
           frontmost == pending.origin || frontmost.map({ pending.intermediates.contains($0) }) == true {
            current = pending.selection
        } else {
            pending = nil
            current = frontmost
        }
        guard !order.isEmpty, order.count > 1 || order.first != current else {
            throw ApplicationSwitchError.noOtherApplications
        }
        let nextIndex: Int
        if let index = current.flatMap({ order.firstIndex(of: $0) }) {
            let offset = direction == .next ? 1 : -1
            nextIndex = (index + offset + order.count) % order.count
        } else {
            nextIndex = direction == .next ? 0 : order.count - 1
        }
        let selected = order[nextIndex]
        guard workspace.activate(processIdentifier: selected) else {
            throw ApplicationSwitchError.activationRefused
        }
        var intermediates = pending?.intermediates ?? []
        if let previousSelection = pending?.selection { intermediates.insert(previousSelection) }
        pending = PendingActivation(
            selection: selected,
            origin: pending?.origin ?? frontmost,
            intermediates: intermediates.intersection(available),
            requestedAt: timestamp
        )
    }
}

@MainActor
protocol SystemActionExecuting {
    func perform(_ action: SystemGestureAction) throws
}

@MainActor
struct SystemActionExecutor: SystemActionExecuting {
    static let commandKeyCode: CGKeyCode = 55
    static let wKeyCode: CGKeyCode = 13

    private let poster: any InputEventPosting
    private let applicationCycler: any ApplicationCycling

    init(
        poster: any InputEventPosting = SystemInputEventPoster(),
        applicationCycler: any ApplicationCycling = RunningApplicationCycler()
    ) {
        self.poster = poster
        self.applicationCycler = applicationCycler
    }

    func perform(_ action: SystemGestureAction) throws {
        switch action {
        case .nextApplication:
            try applicationCycler.cycle(.next)
        case .previousApplication:
            try applicationCycler.cycle(.previous)
        case .closeCurrentTabOrWindow:
            try poster.postKeyChord([
                (keyCode: Self.commandKeyCode, keyDown: true, flags: [.maskCommand]),
                (keyCode: Self.wKeyCode, keyDown: true, flags: [.maskCommand]),
                (keyCode: Self.wKeyCode, keyDown: false, flags: [.maskCommand]),
                (keyCode: Self.commandKeyCode, keyDown: false, flags: [])
            ])
        }
    }
}
