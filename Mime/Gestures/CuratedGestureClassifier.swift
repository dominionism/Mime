import Foundation
import simd

/// How closely one hand matches each curated pose.
struct PoseClassification: Equatable, Sendable {
    /// A score from 0 to 1 for every curated pose.
    var scores: [GestureID: Double]
    /// The clearly recognized pose, or `nil` when no pose scores high enough or two poses are too close to call.
    var pose: GestureID?

    func score(for gesture: GestureID) -> Double {
        scores[gesture] ?? 0
    }
}

/// Recognizes Mime's five curated poses from finger geometry.
///
/// Each pose is a set of requirements, such as "index finger extended" or "thumb points up", and each requirement
/// scores from 0 to 1. A pose scores as its weakest requirement, so every requirement must hold at once.
enum CuratedGestureClassifier {
    /// A joint Vision is less confident about than this can't count toward any pose.
    static let minimumJointConfidence: Float = 0.5
    /// The best pose must score at least this to be recognized.
    static let minimumScore = 0.85
    /// The best pose must also beat the runner-up by at least this much.
    static let minimumMargin = 0.15

    /// Returns `nil` when the sample has no hand.
    static func classify(_ sample: HandPoseSample) -> PoseClassification? {
        guard let detected = sample.hand else { return nil }
        guard let hand = HandPoseNormalizer.normalize(detected, imageAspectRatio: sample.imageAspectRatio) else {
            return PoseClassification(scores: [:], pose: nil)
        }
        return classify(hand)
    }

    static func classify(_ hand: NormalizedHand) -> PoseClassification {
        let measurements = HandMeasurements(hand)
        var scores: [GestureID: Double] = [:]
        for gesture in GestureID.allCases {
            scores[gesture] = measurements.score(gesture)
        }
        return PoseClassification(scores: scores, pose: recognizedPose(in: scores))
    }

    /// The best-scoring pose, if it scores high enough and clearly beats the runner-up.
    static func recognizedPose(in scores: [GestureID: Double]) -> GestureID? {
        let ranked = scores.sorted { $0.value > $1.value }
        guard let best = ranked.first, best.value >= minimumScore else { return nil }
        let runnerUp = ranked.dropFirst().first?.value ?? 0
        return best.value - runnerUp >= minimumMargin ? best.key : nil
    }
}

/// Scores a normalized hand against each curated pose's requirements.
///
/// A measurement is `nil` when a joint it needs is missing or below the confidence floor, and a `nil` requirement
/// fails its pose.
private struct HandMeasurements {
    private enum Finger {
        case index, middle, ring, little

        var joints: (mcp: HandJoint, pip: HandJoint, dip: HandJoint, tip: HandJoint) {
            switch self {
            case .index: (.indexMCP, .indexPIP, .indexDIP, .indexTip)
            case .middle: (.middleMCP, .middlePIP, .middleDIP, .middleTip)
            case .ring: (.ringMCP, .ringPIP, .ringDIP, .ringTip)
            case .little: (.littleMCP, .littlePIP, .littleDIP, .littleTip)
            }
        }
    }

    private let hand: NormalizedHand

    init(_ hand: NormalizedHand) {
        self.hand = hand
    }

    func score(_ gesture: GestureID) -> Double {
        // Every measurement is relative to the wrist and middle knuckle, so both must be reliable.
        guard point(.wrist) != nil, point(.middleMCP) != nil else { return 0 }

        let requirements: [Double?] = switch gesture {
        case .openPalm:
            [extended(.index), extended(.middle), extended(.ring), extended(.little), thumbExtended, palmFacesCamera]
        case .fist:
            [curled(.index), curled(.middle), curled(.ring), curled(.little), thumbExtended.map { 1 - $0 }]
        case .thumbsUp:
            [curled(.index), curled(.middle), curled(.ring), curled(.little), thumbExtended, thumbPointsUp]
        case .vSign:
            [extended(.index), extended(.middle), curled(.ring), curled(.little), fingertipsSpread]
        case .indexPoint:
            [extended(.index), curled(.middle), curled(.ring), curled(.little)]
        }
        return requirements.reduce(1) { min($0, $1 ?? 0) }
    }

    /// A joint's position, or `nil` if Vision couldn't place it confidently.
    private func point(_ joint: HandJoint) -> SIMD2<Double>? {
        guard let confidence = hand.confidences[joint],
              confidence >= CuratedGestureClassifier.minimumJointConfidence
        else { return nil }
        return hand.points[joint]
    }

    /// 1 for a straight finger reaching away from the wrist, 0 for one folded back toward the palm.
    private func extended(_ finger: Finger) -> Double? {
        let joints = finger.joints
        guard let mcp = point(joints.mcp), let pip = point(joints.pip), let dip = point(joints.dip),
              let tip = point(joints.tip)
        else { return nil }

        // Seen from the wrist, an extended fingertip lies well beyond the finger's middle joint, while a curled
        // fingertip folds back inside it.
        let reach = ramp(ratio(simd_length(tip), simd_length(pip)), from: 1, to: 1.2)
        let straightness = ramp(angle(at: pip, between: mcp, and: dip), from: 100, to: 150)
        return min(reach, straightness)
    }

    private func curled(_ finger: Finger) -> Double? {
        extended(finger).map { 1 - $0 }
    }

    /// 1 for a straight thumb reaching away from the fingers, 0 for one folded across them.
    private var thumbExtended: Double? {
        guard let mp = point(.thumbMP), let ip = point(.thumbIP), let tip = point(.thumbTip),
              let littleKnuckle = point(.littleMCP)
        else { return nil }

        // A folded thumb's tip moves toward the little finger, and an extended thumb's tip moves away from it.
        let reach = ramp(ratio(simd_length(tip - littleKnuckle), simd_length(ip - littleKnuckle)), from: 1, to: 1.1)
        let straightness = ramp(angle(at: ip, between: mp, and: tip), from: 120, to: 155)
        return min(reach, straightness)
    }

    /// 1 when the thumb points straight up in the camera image, falling to 0 as it tilts 55° away.
    private var thumbPointsUp: Double? {
        guard let mp = point(.thumbMP), let tip = point(.thumbTip) else { return nil }
        return ramp(cosine(tip - mp, hand.imageUp), from: cos(55 * .pi / 180), to: cos(30 * .pi / 180))
    }

    /// 1 when the palm faces the camera, 0 when the hand is edge-on or shows its back.
    private var palmFacesCamera: Double? {
        guard let index = point(.indexMCP), let little = point(.littleMCP) else { return nil }
        // In right-hand space, a palm facing the camera puts the index knuckle on the positive x side.
        return ramp(index.x - little.x, from: 0.1, to: 0.35)
    }

    /// 1 when the index and middle fingertips are clearly apart, as in a V sign.
    private var fingertipsSpread: Double? {
        guard let index = point(.indexTip), let middle = point(.middleTip) else { return nil }
        return ramp(simd_length(index - middle), from: 0.2, to: 0.4)
    }
}

/// Maps `value` from 0 at `start` to 1 at `end`, clamped to `0...1`.
private func ramp(_ value: Double, from start: Double, to end: Double) -> Double {
    min(max((value - start) / (end - start), 0), 1)
}

/// `numerator / denominator`, or 0 when the denominator is 0.
private func ratio(_ numerator: Double, _ denominator: Double) -> Double {
    denominator > 0 ? numerator / denominator : 0
}

/// The cosine of the angle between two vectors, or 0 when either has no length.
private func cosine(_ u: SIMD2<Double>, _ v: SIMD2<Double>) -> Double {
    let lengths = simd_length(u) * simd_length(v)
    return lengths > 0 ? simd_dot(u, v) / lengths : 0
}

/// The angle at `vertex` between the directions to `a` and `b`, in degrees.
private func angle(at vertex: SIMD2<Double>, between a: SIMD2<Double>, and b: SIMD2<Double>) -> Double {
    acos(min(max(cosine(a - vertex, b - vertex), -1), 1)) * 180 / .pi
}
