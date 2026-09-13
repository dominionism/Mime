import Foundation
import Testing
@testable import Mime

/// A synthetic hand in the normalized hand frame: wrist at the origin, middle knuckle at `(0, 1)`, shaped like a right
/// hand whose palm faces the camera.
struct HandShape: Sendable {
    enum Finger: Sendable {
        /// Straight, pointing this many degrees away from the palm axis, toward the thumb when positive.
        case extended(degrees: Double)
        /// Folded into the palm.
        case curled
        /// Bent halfway, neither clearly extended nor curled.
        case halfBent
    }

    enum Thumb: Sendable {
        /// Straight and spread away from the fingers, as in an open palm.
        case spread
        /// Straight and at a right angle to the palm axis, as in a thumbs-up.
        case sideways
        /// Folded across the fingers, as in a fist.
        case tucked
    }

    static let openPalm = HandShape(
        index: .extended(degrees: 8), middle: .extended(degrees: 0), ring: .extended(degrees: -6),
        little: .extended(degrees: -14), thumb: .spread
    )
    static let fist = HandShape(index: .curled, middle: .curled, ring: .curled, little: .curled, thumb: .tucked)
    /// The thumb points sideways in the hand frame, so place it with a quarter turn counterclockwise to point it up.
    static let thumbsUp = HandShape(index: .curled, middle: .curled, ring: .curled, little: .curled, thumb: .sideways)
    static let vSign = HandShape(
        index: .extended(degrees: 15), middle: .extended(degrees: -12), ring: .curled, little: .curled, thumb: .tucked
    )
    static let indexPoint = HandShape(
        index: .extended(degrees: 5), middle: .curled, ring: .curled, little: .curled, thumb: .tucked
    )
    /// Index and middle fingers bent halfway, somewhere between a fist and a V sign.
    static let halfBent = HandShape(index: .halfBent, middle: .halfBent, ring: .curled, little: .curled, thumb: .tucked)

    var points: [HandJoint: SIMD2<Double>]

    /// The same shape seen from the back of the hand.
    var turnedAround: HandShape {
        HandShape(points: points.mapValues { SIMD2(-$0.x, $0.y) })
    }

    init(index: Finger, middle: Finger, ring: Finger, little: Finger, thumb: Thumb) {
        var points: [HandJoint: SIMD2<Double>] = [.wrist: SIMD2(0, 0)]
        Self.add(index, (.indexMCP, .indexPIP, .indexDIP, .indexTip), knuckle: SIMD2(0.32, 0.95), lengths: (0.42, 0.25, 0.2), to: &points)
        Self.add(middle, (.middleMCP, .middlePIP, .middleDIP, .middleTip), knuckle: SIMD2(0, 1), lengths: (0.45, 0.28, 0.22), to: &points)
        Self.add(ring, (.ringMCP, .ringPIP, .ringDIP, .ringTip), knuckle: SIMD2(-0.28, 0.95), lengths: (0.42, 0.26, 0.21), to: &points)
        Self.add(little, (.littleMCP, .littlePIP, .littleDIP, .littleTip), knuckle: SIMD2(-0.52, 0.85), lengths: (0.33, 0.2, 0.18), to: &points)
        Self.add(thumb, to: &points)
        self.points = points
    }

    private init(points: [HandJoint: SIMD2<Double>]) {
        self.points = points
    }

    private static func add(
        _ finger: Finger,
        _ joints: (knuckle: HandJoint, pip: HandJoint, dip: HandJoint, tip: HandJoint),
        knuckle: SIMD2<Double>,
        lengths: (Double, Double, Double),
        to points: inout [HandJoint: SIMD2<Double>]
    ) {
        points[joints.knuckle] = knuckle
        switch finger {
        case .extended(let degrees):
            let direction = unitVector(degrees: degrees)
            points[joints.pip] = knuckle + lengths.0 * direction
            points[joints.dip] = knuckle + (lengths.0 + lengths.1) * direction
            points[joints.tip] = knuckle + (lengths.0 + lengths.1 + lengths.2) * direction
        case .curled:
            points[joints.pip] = knuckle + SIMD2(0, 0.2)
            points[joints.dip] = knuckle + SIMD2(0.03, 0.02)
            points[joints.tip] = knuckle + SIMD2(0.02, -0.15)
        case .halfBent:
            points[joints.pip] = knuckle + SIMD2(0, 0.4)
            points[joints.dip] = knuckle + SIMD2(0.164, 0.515)
            points[joints.tip] = knuckle + SIMD2(0.264, 0.515)
        }
    }

    private static func add(_ thumb: Thumb, to points: inout [HandJoint: SIMD2<Double>]) {
        let base = SIMD2<Double>(0.22, 0.22)
        points[.thumbCMC] = base
        switch thumb {
        case .spread, .sideways:
            let direction = unitVector(degrees: thumb == .spread ? 50 : 80)
            points[.thumbMP] = base + 0.35 * direction
            points[.thumbIP] = base + 0.65 * direction
            points[.thumbTip] = base + 0.9 * direction
        case .tucked:
            points[.thumbMP] = SIMD2(0.35, 0.5)
            points[.thumbIP] = SIMD2(0.2, 0.75)
            points[.thumbTip] = SIMD2(-0.05, 0.8)
        }
    }

    private static func unitVector(degrees: Double) -> SIMD2<Double> {
        let radians = degrees * .pi / 180
        return SIMD2(sin(radians), cos(radians))
    }
}

/// Places a `HandShape` in a camera image and reports it the way Vision would.
struct HandFixture: Sendable, CustomTestStringConvertible {
    var chirality: HandChirality = .right
    /// Counterclockwise rotation in the image, in radians.
    var rotation: Double = 0
    /// Palm length as a fraction of the image height.
    var scale: Double = 0.22
    /// Where the wrist sits, in Vision's normalized image coordinates.
    var wrist = SIMD2<Double>(0.5, 0.5)
    var imageAspectRatio = 16.0 / 9.0
    var confidence: Float = 0.9

    var testDescription: String {
        "\(chirality) hand rotated \(Int((rotation * 180 / .pi).rounded()))° at scale \(scale), aspect \(imageAspectRatio)"
    }

    func hand(_ shape: HandShape) -> DetectedHand {
        let cosine = cos(rotation)
        let sine = sin(rotation)
        var joints: [HandJoint: HandJointPosition] = [:]
        for (joint, point) in shape.points {
            var offset = scale * SIMD2(point.x * cosine - point.y * sine, point.x * sine + point.y * cosine)
            // A left hand is the mirror image of the same right hand.
            if chirality == .left {
                offset.x = -offset.x
            }
            joints[joint] = HandJointPosition(
                x: wrist.x + offset.x / imageAspectRatio,
                y: wrist.y + offset.y,
                confidence: confidence
            )
        }
        return DetectedHand(chirality: chirality, confidence: confidence, joints: joints)
    }

    func sample(_ shape: HandShape, at timestamp: Double = 0) -> HandPoseSample {
        HandPoseSample(timestamp: timestamp, hand: hand(shape), imageAspectRatio: imageAspectRatio)
    }
}

func expectClose(
    _ actual: SIMD2<Double>?,
    _ expected: SIMD2<Double>,
    tolerance: Double = 1e-9,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    guard let actual else {
        Issue.record("Expected a point close to \(expected), found none", sourceLocation: sourceLocation)
        return
    }
    #expect(
        abs(actual.x - expected.x) <= tolerance && abs(actual.y - expected.y) <= tolerance,
        "\(actual) is not close to \(expected)",
        sourceLocation: sourceLocation
    )
}
