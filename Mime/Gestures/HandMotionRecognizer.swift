import simd

/// A dynamic gesture that controls the frontmost application.
enum MotionGesture: String, CaseIterable, Codable, Equatable, Sendable {
    case swipeLeft
    case swipeRight

    var name: String {
        switch self {
        case .swipeLeft: "Swipe left"
        case .swipeRight: "Swipe right"
        }
    }

    var emoji: String {
        switch self {
        case .swipeLeft: "←"
        case .swipeRight: "→"
        }
    }
}

/// The result of feeding one hand-pose sample into the motion recognizer.
struct MotionRecognition: Equatable, Sendable {
    let gesture: MotionGesture?
    /// A moving hand should not simultaneously complete a static finger-count command.
    let suppressesStaticCommands: Bool
}

/// Recognizes short horizontal swipes from raw hand landmarks.
///
/// Swipe positions stay in camera-image coordinates because the normalizer intentionally removes translation. The
/// x-axis is mirrored into the user's view so a hand moving right produces `swipeRight` for either hand.
struct HandMotionRecognizer {
    static let minimumJointConfidence: Float = 0.5
    /// A hand-width swipe is easy to make in the camera preview without requiring an exaggerated throw.
    static let minimumSwipeDistance = 0.12
    static let maximumSwipeDuration = 0.8
    static let minimumSwipeSpeed = 0.25
    static let maximumVerticalDrift = 0.2
    /// Movement cancels a pending finger-count command as soon as the hand leaves its still position.
    static let movementSuppressionDistance = 0.018
    static let movementSuppressionSpeed = 0.18
    static let swipeCooldown = 0.55
    static let swipeRearmHold = 0.18
    static let maximumSampleGap = 0.25

    private struct Stroke {
        var start: SIMD2<Double>
        var since: Double
    }

    private struct Movement {
        var distance: Double
        var speed: Double

        var isMeaningful: Bool {
            distance >= HandMotionRecognizer.movementSuppressionDistance
                || speed >= HandMotionRecognizer.movementSuppressionSpeed
        }
    }

    private var lastTimestamp: Double?
    private var lastCenter: SIMD2<Double>?
    private var stroke: Stroke?
    private var swipeCooldownUntil: Double?
    private var swipeNeedsRearm = false
    private var swipeRearmSince: Double?

    /// Feed a sample and return at most one dynamic gesture.
    mutating func update(_ sample: HandPoseSample) -> MotionRecognition {
        let timestamp = sample.timestamp
        let previousTimestamp = lastTimestamp
        let isContinuous = previousTimestamp.map {
            timestamp >= $0 && timestamp - $0 <= Self.maximumSampleGap
        } ?? true

        if !isContinuous {
            clearTemporalState()
        }
        lastTimestamp = timestamp

        guard sample.hand != nil, let center = center(of: sample.hand) else {
            // A missing hand starts the next swipe cleanly.
            stroke = nil
            lastCenter = nil
            swipeNeedsRearm = false
            swipeRearmSince = nil
            return MotionRecognition(gesture: nil, suppressesStaticCommands: false)
        }

        let movement = movement(from: lastCenter, to: center, previousTimestamp: previousTimestamp, timestamp: timestamp)
        lastCenter = center
        let swipeGesture = updateSwipe(center: center, movement: movement, at: timestamp, isContinuous: isContinuous)

        return MotionRecognition(
            gesture: swipeGesture,
            suppressesStaticCommands: movement.isMeaningful
        )
    }

    mutating func reset() {
        self = HandMotionRecognizer()
    }

    private mutating func updateSwipe(
        center: SIMD2<Double>,
        movement: Movement,
        at timestamp: Double,
        isContinuous: Bool
    ) -> MotionGesture? {
        if let cooldown = swipeCooldownUntil {
            guard timestamp >= cooldown else { return nil }
            swipeCooldownUntil = nil
        }

        if swipeNeedsRearm {
            if movement.speed <= Self.movementSuppressionSpeed {
                swipeRearmSince = swipeRearmSince ?? timestamp
                guard timestamp - (swipeRearmSince ?? timestamp) >= Self.swipeRearmHold else { return nil }
                swipeNeedsRearm = false
                swipeRearmSince = nil
                stroke = Stroke(start: center, since: timestamp)
            } else {
                swipeRearmSince = nil
            }
            return nil
        }

        guard isContinuous else {
            stroke = Stroke(start: center, since: timestamp)
            return nil
        }
        guard let stroke else {
            self.stroke = Stroke(start: center, since: timestamp)
            return nil
        }

        let elapsed = timestamp - stroke.since
        guard elapsed <= Self.maximumSwipeDuration else {
            self.stroke = Stroke(start: center, since: timestamp)
            return nil
        }

        let delta = center - stroke.start
        let horizontal = abs(delta.x)
        let vertical = abs(delta.y)
        guard horizontal >= Self.minimumSwipeDistance,
              horizontal >= vertical,
              vertical <= Self.maximumVerticalDrift,
              horizontal / max(elapsed, 0.001) >= Self.minimumSwipeSpeed
        else { return nil }

        self.stroke = nil
        swipeNeedsRearm = true
        swipeRearmSince = nil
        swipeCooldownUntil = timestamp + Self.swipeCooldown
        return delta.x >= 0 ? .swipeRight : .swipeLeft
    }

    private func movement(
        from previous: SIMD2<Double>?,
        to current: SIMD2<Double>,
        previousTimestamp: Double?,
        timestamp: Double
    ) -> Movement {
        guard let previous, let previousTimestamp,
              timestamp > previousTimestamp,
              timestamp - previousTimestamp <= Self.maximumSampleGap
        else { return Movement(distance: 0, speed: 0) }

        let delta = current - previous
        let distance = simd_length(delta)
        let speed = distance / (timestamp - previousTimestamp)
        return Movement(distance: distance, speed: speed)
    }

    private func center(of hand: DetectedHand?) -> SIMD2<Double>? {
        guard let hand else { return nil }
        let joints: [HandJoint] = [.wrist, .indexMCP, .middleMCP, .ringMCP, .littleMCP]
        let points = joints.compactMap { joint -> SIMD2<Double>? in
            guard let position = hand.joints[joint], position.confidence >= Self.minimumJointConfidence else { return nil }
            // Mirror x into the user's view. y already has the camera's bottom-left origin, which is fine for
            // comparing vertical drift.
            return SIMD2(1 - position.x, position.y)
        }
        guard !points.isEmpty else { return nil }
        return points.reduce(.zero, +) / Double(points.count)
    }

    private mutating func clearTemporalState() {
        lastCenter = nil
        stroke = nil
        swipeCooldownUntil = nil
        swipeNeedsRearm = false
        swipeRearmSince = nil
    }
}
