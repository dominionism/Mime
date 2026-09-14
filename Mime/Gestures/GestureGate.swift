/// What the safety gate is doing, for the status display.
enum GestureGatePhase: Equatable, Sendable {
    /// Waiting for a wake fist in safe mode or a command pose in quick mode. Progress runs from 0 to 1 while held.
    case listening(wakeProgress: Double)
    /// Awake and waiting for a command pose. `commandProgress` runs from 0 to 1 while `candidate` is held.
    case armed(secondsLeft: Double, candidate: GestureID?, commandProgress: Double)
    /// Just recognized `command`. When `secondsLeft` reaches 0, the gate still waits for the pose to be released.
    case cooldown(command: GestureID, secondsLeft: Double)
}

/// Turns a stream of pose classifications into deliberate commands.
///
/// In safe mode, a closed fist held for 0.6 seconds arms the gate for 3 seconds, then a command pose held for 0.4
/// seconds emits once. Quick mode accepts a recognized command pose on its first frame. Both modes cool down for
/// 2 seconds and wait until the pose has been released for 0.3 seconds before listening again. A missing hand,
/// unrecognized pose, or gap between samples restarts whatever pose was being held.
///
/// Time comes from each sample's timestamp, so the gate behaves the same in tests as it does with a live camera.
struct GestureGate {
    static let wakeHold = 0.6
    static let armedDuration = 3.0
    static let commandHold = 0.4
    /// Quick mode skips the wake pose and accepts the first confident command classification.
    static let quickCommandHold = 0.0
    static let cooldownDuration = 2.0
    /// A command pose scoring below this counts as released.
    static let releaseScore = 0.6
    static let releaseHold = 0.3
    /// Samples further apart than this can't show that a pose was held in between.
    static let maximumSampleGap = 0.25

    let mode: GestureActivationMode

    private enum State {
        case listening
        case armed(until: Double)
        case cooldown(command: GestureID, until: Double, releasedSince: Double?)
    }

    private(set) var phase = GestureGatePhase.listening(wakeProgress: 0)

    private var state = State.listening
    /// The recognized pose held in consecutive samples, and the timestamp of the first of them.
    private var hold: (pose: GestureID, since: Double)?
    private var lastTimestamp: Double?

    /// Whether safe mode has accepted its wake pose and is waiting for a command.
    var isArmed: Bool {
        if case .armed = state { return true }
        return false
    }

    init(mode: GestureActivationMode = .wakeThenCommand) {
        self.mode = mode
    }

    /// Processes the classification for one sample, or `nil` when the sample has no hand, and returns the command
    /// this sample completed, if any.
    @discardableResult
    mutating func update(with classification: PoseClassification?, at timestamp: Double) -> GestureID? {
        let previousTimestamp = lastTimestamp
        // A restarted or reset capture clock must not inherit an armed or cooling-down state. Treat the first sample
        // from the new clock as a fresh listening sample so a command can never bypass the wake gesture.
        if let previousTimestamp, timestamp < previousTimestamp {
            state = .listening
            hold = nil
        }

        let isContinuous = previousTimestamp.map { timestamp >= $0 && timestamp - $0 <= Self.maximumSampleGap } ?? false
        lastTimestamp = timestamp
        defer { phase = currentPhase(at: timestamp) }

        if let pose = classification?.pose {
            if !isContinuous || hold?.pose != pose {
                hold = (pose, timestamp)
            }
        } else {
            hold = nil
        }

        switch state {
        case .listening:
            if mode == .quick {
                guard let hold, hold.pose.isCommand,
                      timestamp - hold.since >= Self.quickCommandHold else { return nil }
                state = .cooldown(command: hold.pose, until: timestamp + Self.cooldownDuration, releasedSince: nil)
                self.hold = nil
                return hold.pose
            }
            guard let hold, hold.pose.isWake, timestamp - hold.since >= Self.wakeHold else { return nil }
            state = .armed(until: timestamp + Self.armedDuration)
            // A command has to be a new pose, not a continuation of the fist that woke the gate.
            self.hold = nil
            return nil

        case .armed(let deadline):
            if timestamp >= deadline {
                state = .listening
                hold = nil
                return nil
            }
            guard let hold, hold.pose.isCommand, timestamp - hold.since >= Self.commandHold else { return nil }
            state = .cooldown(command: hold.pose, until: timestamp + Self.cooldownDuration, releasedSince: nil)
            self.hold = nil
            return hold.pose

        case .cooldown(let command, let deadline, let releasedSince):
            let isReleased = (classification?.score(for: command) ?? 0) < Self.releaseScore
            let releaseStart = isReleased ? (isContinuous ? releasedSince ?? timestamp : timestamp) : nil
            if let releaseStart, timestamp >= deadline, timestamp - releaseStart >= Self.releaseHold {
                state = .listening
                // A fist held during the cooldown has to be held again once the gate is listening.
                hold = nil
            } else {
                state = .cooldown(command: command, until: deadline, releasedSince: releaseStart)
            }
            return nil
        }
    }

    /// Returns to listening and forgets any held pose, as when recognition stops.
    mutating func reset() {
        self = GestureGate(mode: mode)
    }

    /// Cancels only the pose currently being stabilized, preserving a safe-mode armed window.
    mutating func cancelPendingCommand() {
        hold = nil
        if let lastTimestamp {
            phase = currentPhase(at: lastTimestamp)
        }
    }

    private func currentPhase(at timestamp: Double) -> GestureGatePhase {
        switch state {
        case .listening:
            guard let hold else { return .listening(wakeProgress: 0) }
            let holdDuration = mode == .quick ? Self.quickCommandHold : Self.wakeHold
            guard mode == .quick ? hold.pose.isCommand : hold.pose.isWake else {
                return .listening(wakeProgress: 0)
            }
            let progress = holdDuration > 0 ? (timestamp - hold.since) / holdDuration : 1
            return .listening(wakeProgress: min(progress, 1))

        case .armed(let deadline):
            let secondsLeft = max(deadline - timestamp, 0)
            guard let hold, hold.pose.isCommand else {
                return .armed(secondsLeft: secondsLeft, candidate: nil, commandProgress: 0)
            }
            let progress = min((timestamp - hold.since) / Self.commandHold, 1)
            return .armed(secondsLeft: secondsLeft, candidate: hold.pose, commandProgress: progress)

        case .cooldown(let command, let deadline, _):
            return .cooldown(command: command, secondsLeft: max(deadline - timestamp, 0))
        }
    }
}
