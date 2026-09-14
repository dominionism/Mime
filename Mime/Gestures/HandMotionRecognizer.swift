import simd

/// A dynamic gesture that controls the frontmost application.
enum MotionGesture: String, CaseIterable, Codable, Equatable, Sendable {
    case swipeLeft
    case swipeRight
    case pinch

    var name: String {
        switch self {
        case .swipeLeft: "Swipe left"
        case .swipeRight: "Swipe right"
        case .pinch: "Pinch"
        }
    }

    var emoji: String {
        switch self {
        case .swipeLeft: "←"
        case .swipeRight: "→"
        case .pinch: "🤏"
        }
    }
}

/// The result of feeding one hand-pose sample into the motion recognizer.
struct MotionRecognition: Equatable, Sendable {
    let gesture: MotionGesture?
    /// A moving or pinching hand should not simultaneously complete a static finger-count command.
    let suppressesStaticCommands: Bool
}

/// Recognizes short horizontal swipes and thumb-index pinches from raw hand landmarks.
///
/// Swipe positions stay in camera-image coordinates because the normalizer intentionally removes translation. The
/// x-axis is mirrored into the user's view so a hand moving right produces `swipeRight` for either hand. Pinch
/// distance is normalized by palm length, making the threshold independent of how close the hand is to the camera.
struct HandMotionRecognizer {
    static let minimumJointConfidence: Float = 0.5
    static let minimumSwipeDistance = 0.18
    static let maximumSwipeDuration = 0.65
    static let minimumSwipeSpeed = 0.45
    static let maximumVerticalDrift = 0.16
    static let movementSuppressionDistance = 0.035
    static let movementSuppressionSpeed = 0.35
    static let pinchThreshold = 0.28
    static let pinchReleaseThreshold = 0.40
    static let pinchHold = 0.04
    static let swipeCooldown = 0.55
    static let maximumSampleGap = 0.25

    private struct Stroke {
        var start: SIMD2<Double>
        var since: Double
    }

    private var lastTimestamp: Double?
    private var lastCenter: SIMD2<Double>?
    private var stroke: Stroke?
    private var swipeCooldownUntil: Double?
    private var pinchSince: Double?
    private var pinchLatched = false

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

        guard let hand = sample.hand, let center = center(of: hand) else {
            // A missing hand is also a natural pinch release and starts the next swipe cleanly.
            stroke = nil
            lastCenter = nil
            pinchSince = nil
            pinchLatched = false
            return MotionRecognition(gesture: nil, suppressesStaticCommands: false)
        }

        let movement = movement(from: lastCenter, to: center, previousTimestamp: previousTimestamp, timestamp: timestamp)
        lastCenter = center

        let pinch = pinchDistance(in: sample)
        let pinchGesture = updatePinch(distance: pinch, at: timestamp, isContinuous: isContinuous)
        let swipeGesture = updateSwipe(center: center, at: timestamp, isContinuous: isContinuous)

        // A tucked thumb can sit closer to the index than the release hysteresis (especially in a fist), but it is
        // not a pinch candidate until it crosses the trigger threshold. Once latched, keep suppressing static poses
        // until the fingers separate again.
        let suppressesStaticCommands = movement.isMeaningful || pinch.map { $0 <= Self.pinchThreshold } == true || pinchLatched
        return MotionRecognition(
            // Pinch is prioritized if a hand happens to close its fingers while moving.
            gesture: pinchGesture ?? swipeGesture,
            suppressesStaticCommands: suppressesStaticCommands
        )
    }

    mutating func reset() {
        self = HandMotionRecognizer()
    }

    private mutating func updatePinch(distance: Double?, at timestamp: Double, isContinuous: Bool) -> MotionGesture? {
        guard isContinuous, let distance else {
            pinchSince = nil
            pinchLatched = false
            return nil
        }

        if distance >= Self.pinchReleaseThreshold {
            pinchSince = nil
            pinchLatched = false
            return nil
        }
        guard !pinchLatched, distance <= Self.pinchThreshold else { return nil }

        pinchSince = pinchSince ?? timestamp
        guard timestamp - (pinchSince ?? timestamp) >= Self.pinchHold else { return nil }
        pinchLatched = true
        pinchSince = nil
        return .pinch
    }

    private mutating func updateSwipe(center: SIMD2<Double>, at timestamp: Double, isContinuous: Bool) -> MotionGesture? {
        if let cooldown = swipeCooldownUntil {
            guard timestamp >= cooldown else { return nil }
            swipeCooldownUntil = nil
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
        swipeCooldownUntil = timestamp + Self.swipeCooldown
        return delta.x >= 0 ? .swipeRight : .swipeLeft
    }

    private func movement(
        from previous: SIMD2<Double>?,
        to current: SIMD2<Double>,
        previousTimestamp: Double?,
        timestamp: Double
    ) -> (isMeaningful: Bool, speed: Double) {
        guard let previous, let previousTimestamp,
              timestamp > previousTimestamp,
              timestamp - previousTimestamp <= Self.maximumSampleGap
        else { return (false, 0) }

        let delta = current - previous
        let distance = simd_length(delta)
        let speed = distance / (timestamp - previousTimestamp)
        return (distance >= Self.movementSuppressionDistance && speed >= Self.movementSuppressionSpeed, speed)
    }

    private func center(of hand: DetectedHand) -> SIMD2<Double>? {
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

    private func pinchDistance(in sample: HandPoseSample) -> Double? {
        guard let hand = sample.hand,
              let wrist = confidentPoint(.wrist, in: hand),
              let middle = confidentPoint(.middleMCP, in: hand),
              let thumb = confidentPoint(.thumbTip, in: hand),
              let index = confidentPoint(.indexTip, in: hand)
        else { return nil }

        let aspect = max(sample.imageAspectRatio, 0.01)
        func corrected(_ point: SIMD2<Double>) -> SIMD2<Double> { SIMD2(point.x * aspect, point.y) }
        let palm = simd_length(corrected(middle - wrist))
        guard palm > 0 else { return nil }
        return simd_length(corrected(thumb - index)) / palm
    }

    private func confidentPoint(_ joint: HandJoint, in hand: DetectedHand) -> SIMD2<Double>? {
        guard let position = hand.joints[joint], position.confidence >= Self.minimumJointConfidence else { return nil }
        return SIMD2(position.x, position.y)
    }

    private mutating func clearTemporalState() {
        lastCenter = nil
        stroke = nil
        swipeCooldownUntil = nil
        pinchSince = nil
        pinchLatched = false
    }
}
