import simd

/// A hand's joints in a frame that ignores where the hand is in the image, how large it appears, how it's tilted, and
/// whether it's a left or right hand.
///
/// The wrist sits at the origin and the middle finger's knuckle at `(0, 1)`, so one unit is one palm length. Left hands
/// are mirrored so every hand has the shape of a right hand: a palm facing the camera has its thumb on the positive x
/// side.
struct NormalizedHand: Equatable, Sendable {
    /// Joint positions in palm lengths. Joints Vision couldn't place are absent.
    var points: [HandJoint: SIMD2<Double>]
    /// Vision's confidence in each joint in `points`.
    var confidences: [HandJoint: Float]
    /// The camera image's upward direction in this frame, as a unit vector.
    var imageUp: SIMD2<Double>
}

/// Converts Vision's joint positions into a `NormalizedHand`.
enum HandPoseNormalizer {
    /// Returns `nil` when the wrist or middle knuckle is missing, because those two joints define the frame.
    ///
    /// A hand whose chirality Vision couldn't determine is treated as a right hand.
    static func normalize(_ hand: DetectedHand, imageAspectRatio: Double) -> NormalizedHand? {
        guard imageAspectRatio.isFinite, imageAspectRatio > 0,
              let wristPosition = hand.joints[.wrist], let knucklePosition = hand.joints[.middleMCP],
              wristPosition.x.isFinite, wristPosition.y.isFinite,
              knucklePosition.x.isFinite, knucklePosition.y.isFinite
        else {
            return nil
        }

        // Vision scales x and y separately to 0...1, so stretch x back to true proportions. Mirroring left hands here
        // lets every later measurement treat both hands the same way.
        let mirror: Double = hand.chirality == .left ? -1 : 1
        func imagePoint(_ position: HandJointPosition) -> SIMD2<Double> {
            SIMD2(position.x * imageAspectRatio * mirror, position.y)
        }

        let wrist = imagePoint(wristPosition)
        let palmAxis = imagePoint(knucklePosition) - wrist
        let palmLength = simd_length(palmAxis)
        guard palmLength.isFinite, palmLength > 1e-6 else { return nil }

        // Rotates any vector by the angle that turns the palm axis straight up.
        let up = palmAxis / palmLength
        func rotate(_ vector: SIMD2<Double>) -> SIMD2<Double> {
            SIMD2(vector.x * up.y - vector.y * up.x, vector.x * up.x + vector.y * up.y)
        }

        var points: [HandJoint: SIMD2<Double>] = [:]
        var confidences: [HandJoint: Float] = [:]
        for (joint, position) in hand.joints {
            let point = rotate(imagePoint(position) - wrist) / palmLength
            guard point.x.isFinite, point.y.isFinite, position.confidence.isFinite else { continue }
            points[joint] = point
            confidences[joint] = position.confidence
        }
        return NormalizedHand(points: points, confidences: confidences, imageUp: rotate(SIMD2(0, 1)))
    }
}
