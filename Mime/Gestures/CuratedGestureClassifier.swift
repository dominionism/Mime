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

/// Recognizes Mime's wake pose and five curated finger-count commands from finger geometry.
///
/// Counts clearly extended fingers, including the thumb, in any combination. Every finger needs positive evidence
/// that it is extended or folded; an uncertain finger never silently counts as folded.
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
        let scores = HandMeasurements(hand).scores()
        return PoseClassification(scores: scores, pose: recognizedPose(in: scores))
    }

    /// The best-scoring pose, if it scores high enough and clearly beats the runner-up.
    static func recognizedPose(in scores: [GestureID: Double]) -> GestureID? {
        let ranked = scores.filter { $0.value.isFinite }.sorted { $0.value > $1.value }
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
    private enum Finger: CaseIterable {
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

    func scores() -> [GestureID: Double] {
        let poses: [GestureID] = [.fist, .oneFinger, .twoFingers, .threeFingers, .fourFingers, .fiveFingers]
        var scores = Dictionary(uniqueKeysWithValues: poses.map { ($0, 0.0) })
        // Every measurement is relative to the wrist and middle knuckle, so both must be reliable.
        guard point(.wrist) != nil, point(.middleMCP) != nil else { return scores }

        let fingers = Finger.allCases.map(evidence) + [thumbEvidence]
        // Different combinations with the same count are the same command. Keep the strongest supported
        // combination; within each combination, even one ambiguous finger limits the entire pose's score.
        for mask in 0..<32 {
            let score = fingers.enumerated().reduce(1.0) { score, item in
                min(score, mask & (1 << item.offset) == 0 ? item.element.folded : item.element.extended)
            }
            let gesture = poses[mask.nonzeroBitCount]
            scores[gesture] = max(scores[gesture] ?? 0, score)
        }
        return scores
    }

    /// A joint's position, or `nil` if Vision couldn't place it confidently.
    private func point(_ joint: HandJoint) -> SIMD2<Double>? {
        guard let confidence = hand.confidences[joint], confidence.isFinite,
              confidence >= CuratedGestureClassifier.minimumJointConfidence,
              let point = hand.points[joint], point.x.isFinite, point.y.isFinite
        else { return nil }
        return point
    }

    private struct FingerEvidence {
        var extended = 0.0
        var folded = 0.0
    }

    private func evidence(_ finger: Finger) -> FingerEvidence {
        let joints = finger.joints
        guard let mcp = point(joints.mcp), let pip = point(joints.pip),
              simd_length(pip - mcp) > 1e-6, simd_length(pip) > 1e-6
        else { return FingerEvidence() }

        var result = FingerEvidence()
        if let tip = point(joints.tip), simd_length(tip - pip) > 1e-6 {
            // Measure against this finger's own proximal bone, not the whole palm: short little fingers and
            // fingers splayed sideways should not need to reach as far from the wrist as a middle finger.
            let reach = ratio(simd_length(tip - mcp), simd_length(pip - mcp))
            let bend = angle(at: pip, between: mcp, and: tip)
            result.extended = min(ramp(reach, from: 1.35, to: 1.75), ramp(bend, from: 105, to: 145))
            if let dip = point(joints.dip), simd_length(dip - pip) > 1e-6, simd_length(tip - dip) > 1e-6 {
                // A visible hook at the fingertip is conflicting evidence, even if the PIP is straight.
                result.extended = min(result.extended, ramp(angle(at: dip, between: pip, and: tip), from: 100, to: 145))
            }
            let foldsTowardPalm = ramp(ratio(simd_length(tip), simd_length(pip)), from: 1.15, to: 1.02)
            let foldedShape = max(ramp(bend, from: 135, to: 95), ramp(reach, from: 1.35, to: 0.85))
            result.folded = min(foldsTowardPalm, foldedShape)
        } else if let dip = point(joints.dip), simd_length(dip - pip) > 1e-6 {
            // Folded fingertips often disappear behind the palm. A confidently located DIP already bending
            // back inside the PIP is positive curl evidence; missing landmarks alone are never sufficient.
            result.folded = min(
                ramp(angle(at: pip, between: mcp, and: dip), from: 120, to: 90),
                ramp(ratio(simd_length(dip), simd_length(pip)), from: 1.05, to: 0.98)
            )
        }
        return result
    }

    private var thumbEvidence: FingerEvidence {
        guard let mp = point(.thumbMP), let ip = point(.thumbIP), let tip = point(.thumbTip),
              let index = point(.indexMCP), let little = point(.littleMCP),
              simd_length(mp - ip) > 1e-6, simd_length(tip - ip) > 1e-6
        else { return FingerEvidence() }
        let width = simd_length(index - little)
        guard width > 1e-6 else { return FingerEvidence() }

        // The knuckle line, rather than chirality's sign, tells us which side is the thumb side. This also works
        // from the back of the hand and while Vision briefly reports unknown or incorrect chirality.
        let outward = index - little
        let lateralReach = simd_dot(tip - index, outward / width) / width
        let upwardReach = (tip.y - index.y) / width
        let separated = max(
            ramp(lateralReach, from: 0.08, to: 0.28),
            min(ramp(upwardReach, from: 0.05, to: 0.3), ramp(lateralReach, from: 0, to: 0.12))
        )
        return FingerEvidence(
            extended: min(separated, ramp(angle(at: ip, between: mp, and: tip), from: 115, to: 150)),
            // A thumb resting across the palm can be quite straight. Its location shows that it is tucked;
            // requiring a sharp thumb bend needlessly rejects otherwise clear one-to-four counts.
            folded: 1 - separated
        )
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
