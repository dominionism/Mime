/// A hand joint Vision can locate, named after the finger bone it sits on.
enum HandJoint: String, CaseIterable, Sendable {
    case wrist
    case thumbCMC, thumbMP, thumbIP, thumbTip
    case indexMCP, indexPIP, indexDIP, indexTip
    case middleMCP, middlePIP, middleDIP, middleTip
    case ringMCP, ringPIP, ringDIP, ringTip
    case littleMCP, littlePIP, littleDIP, littleTip
}

/// Which hand Vision believes it saw.
enum HandChirality: Sendable {
    case left
    case right
    case unknown
}

/// Where a joint sits in the camera image, and how sure Vision is about it.
///
/// `x` and `y` are normalized to `0...1`, with the origin at the image's bottom-left corner.
struct HandJointPosition: Equatable, Sendable {
    var x: Double
    var y: Double
    var confidence: Float
}

/// One hand found in a camera frame.
struct DetectedHand: Equatable, Sendable {
    var chirality: HandChirality
    var confidence: Float
    var joints: [HandJoint: HandJointPosition]
}

/// What hand tracking found in one camera frame.
///
/// A sample holds derived joint positions only, never image data. Like camera frames, samples are never saved
/// or uploaded.
struct HandPoseSample: Equatable, Sendable {
    /// Seconds on the capture clock, for measuring the time between samples.
    var timestamp: Double
    /// The detected hand, or `nil` when no hand was found.
    var hand: DetectedHand?
}
