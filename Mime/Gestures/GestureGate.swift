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
/// seconds emits once, then requires a 2-second cooldown and 0.3-second release. Quick mode accepts its first
/// command immediately and latches it to avoid repeats. A different count needs only 0.06 seconds of consistent
/// evidence; lowering the hand for 0.12 seconds allows the same count again.
///
/// Time comes from each sample's timestamp, so the gate behaves the same in tests as it does with a live camera.
struct GestureGate {
    static let wakeHold = 0.6
    static let armedDuration = 3.0
    static let commandHold = 0.4
    /// Quick mode skips the wake pose and accepts the first confident command classification.
    static let quickCommandHold = 0.0
    static let cooldownDuration = 2.0
    static let quickMinimumInterval = 0.12
    static let quickChangeHold = 0.06
    static let quickReleaseHold = 0.12
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
        /// A swipe with no classified pose must consume its endpoint before static commands resume.
        case motionCooldown(until: Double, releasedSince: Double?)
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

    /// Check the incoming sample's clock before dispatching a motion action, since update has not run yet.
    func isArmed(at timestamp: Double) -> Bool {
        guard timestamp.isFinite, let lastTimestamp, timestamp >= lastTimestamp,
              case .armed(let deadline) = state else { return false }
        return timestamp < deadline
    }

    init(mode: GestureActivationMode = .wakeThenCommand) {
        self.mode = mode
    }

    /// Processes the classification for one sample, or `nil` when the sample has no hand, and returns the command
    /// this sample completed, if any.
    @discardableResult
    mutating func update(
        with classification: PoseClassification?,
        at timestamp: Double,
        commandsAllowed: Bool = true
    ) -> GestureID? {
        guard timestamp.isFinite else { return nil }
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

        if let pose = classification?.pose, commandsAllowed || (mode == .wakeThenCommand && !isArmed && pose.isWake) {
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
                return acceptQuick(hold.pose, at: timestamp)
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

        case .motionCooldown(let deadline, let releasedSince):
            if let pose = classification?.pose, pose.isCommand {
                state = .cooldown(command: pose, until: deadline, releasedSince: nil)
                hold = nil
            } else {
                let releaseStart = isContinuous ? releasedSince ?? timestamp : timestamp
                if timestamp >= deadline, timestamp - releaseStart >= Self.quickReleaseHold {
                    state = .listening
                    hold = nil
                } else {
                    state = .motionCooldown(until: deadline, releasedSince: releaseStart)
                }
            }
            return nil

        case .cooldown(let command, let deadline, let releasedSince):
            if mode == .quick {
                // A brief intermediate count while fingers unfold must not steal the next app selection.
                if timestamp >= deadline, let hold, hold.pose.isCommand, hold.pose != command,
                   timestamp - hold.since >= Self.quickChangeHold {
                    return acceptQuick(hold.pose, at: timestamp)
                }
                // Only a neutral pose or absent hand rearms the same count. A different count takes the
                // short stability path above; an ambiguous single frame cannot unlatch a held command.
                let isNeutral = classification?.pose?.isCommand != true
                    && (classification?.score(for: command) ?? 0) < Self.releaseScore
                let releaseStart = isNeutral ? (isContinuous ? releasedSince ?? timestamp : timestamp) : nil
                if let releaseStart, timestamp >= deadline, timestamp - releaseStart >= Self.quickReleaseHold {
                    state = .listening
                    hold = nil
                } else {
                    state = .cooldown(command: command, until: deadline, releasedSince: releaseStart)
                }
                return nil
            }
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

    /// Consume the pose used for a swipe so its stationary endpoint cannot reopen the mapped app.
    mutating func consumeMotion(with classification: PoseClassification?, at timestamp: Double) {
        reset()
        guard mode == .quick, timestamp.isFinite else { return }
        lastTimestamp = timestamp
        let deadline = timestamp + Self.quickMinimumInterval
        if let pose = classification?.pose, pose.isCommand {
            state = .cooldown(command: pose, until: deadline, releasedSince: nil)
        } else {
            state = .motionCooldown(until: deadline, releasedSince: nil)
        }
        phase = currentPhase(at: timestamp)
    }

    private mutating func acceptQuick(_ command: GestureID, at timestamp: Double) -> GestureID {
        state = .cooldown(command: command, until: timestamp + Self.quickMinimumInterval, releasedSince: nil)
        hold = nil
        return command
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

        case .motionCooldown:
            return .listening(wakeProgress: 0)

        case .cooldown(let command, let deadline, _):
            return .cooldown(command: command, secondsLeft: max(deadline - timestamp, 0))
        }
    }
}
