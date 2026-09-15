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

struct MotionRecognition: Equatable, Sendable {
    let gesture: MotionGesture?
    /// Horizontal swipe intent temporarily takes priority over finger-count commands.
    let suppressesStaticCommands: Bool
}

/// Recognizes horizontal translation of the palm in the user's mirrored camera view.
struct HandMotionRecognizer {
    static let minimumJointConfidence: Float = 0.5
    static let minimumSwipeDistance = 0.07
    static let maximumSwipeDistance = 0.14
    static let maximumSwipeDuration = 0.6
    static let minimumSwipeSpeed = 0.25
    static let movementSuppressionDistance = 0.025
    static let swipeCooldown = 0.2
    static let swipeRearmHold = 0.1
    static let maximumSampleGap = 0.25

    private struct Palm {
        let points: [HandJoint: SIMD2<Double>]
        let chirality: HandChirality
        let length: Double?
    }

    private struct Stroke {
        let start: SIMD2<Double>
        let since: Double
        let direction: Double
    }

    private var lastTimestamp: Double?
    private var lastPalm: Palm?
    private var position = SIMD2<Double>.zero
    private var stroke: Stroke?
    private var quietSince: Double?
    private var swipeCooldownUntil: Double?
    private var swipeNeedsRearm = false

    mutating func update(_ sample: HandPoseSample) -> MotionRecognition {
        let timestamp = sample.timestamp
        guard timestamp.isFinite else {
            reset()
            return result()
        }
        if let previous = lastTimestamp,
           timestamp <= previous || timestamp - previous > Self.maximumSampleGap {
            reset()
        }
        let previousTimestamp = lastTimestamp
        lastTimestamp = timestamp

        guard let palm = palm(in: sample) else {
            lastPalm = nil
            stroke = nil
            quietSince = quietSince ?? timestamp
            rearmIfReady(at: timestamp)
            return result()
        }
        defer { lastPalm = palm }
        guard let previous = lastPalm, let previousTimestamp else {
            // Time with no tracked hand counts as release. Consume that interval before the new stroke moves
            // and clears quietSince, otherwise a hand re-entering after cooldown would need another pause.
            rearmIfReady(at: timestamp)
            return result(suppresses: swipeNeedsRearm)
        }
        if previous.chirality != .unknown && palm.chirality != .unknown && previous.chirality != palm.chirality {
            stroke = nil
            quietSince = nil
            position = .zero
            return result()
        }

        // Compare the same landmarks in both frames. Averaging whichever joints happen to be confident in each
        // frame makes a stationary hand appear to jump when a wrist or knuckle drops out of tracking.
        let displacements = palm.points.compactMap { joint, point in
            previous.points[joint].map { point - $0 }
        }
        guard displacements.count >= 3 else {
            stroke = nil
            quietSince = nil
            return result()
        }
        let delta = SIMD2(median(displacements.map(\.x)), median(displacements.map(\.y)))
        let elapsed = timestamp - previousTimestamp
        let distance = simd_length(delta)
        let speed = distance / elapsed
        let previousPosition = position
        position += delta
        let isQuiet = distance < 0.008 && speed < 0.15
        quietSince = isQuiet ? (quietSince ?? previousTimestamp) : nil

        if swipeNeedsRearm {
            rearmIfReady(at: timestamp)
            return result(suppresses: swipeNeedsRearm)
        }

        let horizontalStep = abs(delta.x) > 0.0025 && abs(delta.x) > abs(delta.y) * 1.25
        if horizontalStep {
            let direction = delta.x >= 0 ? 1.0 : -1.0
            if stroke == nil || (stroke?.direction != direction && abs(delta.x) > 0.004) {
                // A stroke starts when motion starts, never when an idle hand first appeared.
                stroke = Stroke(start: previousPosition, since: previousTimestamp, direction: direction)
            }
        }
        guard let stroke else { return result() }
        let duration = timestamp - stroke.since
        let travel = position - stroke.start
        let horizontal = abs(travel.x)
        let vertical = abs(travel.y)
        if duration > Self.maximumSwipeDuration || (vertical > 0.025 && vertical > horizontal)
            || quietSince.map({ timestamp - $0 >= Self.swipeRearmHold }) == true {
            self.stroke = nil
            return result()
        }

        let hasIntent = horizontal >= Self.movementSuppressionDistance && horizontal > vertical * 1.25
        let palmDistance = (palm.length ?? Self.minimumSwipeDistance) * 0.9
        let requiredDistance = min(Self.maximumSwipeDistance, max(Self.minimumSwipeDistance, palmDistance))
        guard horizontal >= requiredDistance, horizontal > vertical * 1.5,
              horizontal / duration >= Self.minimumSwipeSpeed else {
            return result(suppresses: hasIntent)
        }

        self.stroke = nil
        swipeNeedsRearm = true
        quietSince = nil
        swipeCooldownUntil = timestamp + Self.swipeCooldown
        return MotionRecognition(gesture: travel.x >= 0 ? .swipeRight : .swipeLeft, suppressesStaticCommands: true)
    }

    mutating func reset() {
        self = HandMotionRecognizer()
    }

    private mutating func rearmIfReady(at timestamp: Double) {
        guard swipeNeedsRearm,
              timestamp >= (swipeCooldownUntil ?? timestamp),
              let quietSince, timestamp - quietSince >= Self.swipeRearmHold else { return }
        // Stillness accumulates during cooldown, so the waits overlap instead of adding to every gesture.
        swipeNeedsRearm = false
        swipeCooldownUntil = nil
        stroke = nil
    }

    private func result(suppresses: Bool = false) -> MotionRecognition {
        MotionRecognition(gesture: nil, suppressesStaticCommands: suppresses)
    }

    private func palm(in sample: HandPoseSample) -> Palm? {
        guard let hand = sample.hand, sample.imageAspectRatio.isFinite, sample.imageAspectRatio > 0 else { return nil }
        let joints: [HandJoint] = [.wrist, .indexMCP, .middleMCP, .ringMCP, .littleMCP]
        var points: [HandJoint: SIMD2<Double>] = [:]
        for joint in joints {
            guard let point = hand.joints[joint], point.confidence >= Self.minimumJointConfidence,
                  point.x.isFinite, point.y.isFinite else { continue }
            // Scale y to image-width units so horizontal/vertical comparisons are physically meaningful.
            points[joint] = SIMD2(1 - point.x, point.y / sample.imageAspectRatio)
        }
        guard points.count >= 3 else { return nil }
        let lengths = points[.wrist].map { wrist in
            [.indexMCP, .middleMCP, .ringMCP, .littleMCP].compactMap { points[$0].map { simd_length($0 - wrist) } }
        } ?? []
        return Palm(points: points, chirality: hand.chirality, length: lengths.isEmpty ? nil : median(lengths))
    }

    private func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}
