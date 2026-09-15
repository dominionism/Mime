import Testing
@testable import Mime

private let placements = [
    HandFixture(),
    HandFixture(chirality: .left),
    HandFixture(rotation: 0.35, scale: 0.15, wrist: SIMD2(0.3, 0.4)),
    HandFixture(chirality: .left, rotation: -0.3, scale: 0.3, imageAspectRatio: 4.0 / 3.0),
]

struct CuratedGestureClassifierTests {
    @Test(arguments: placements, GestureID.allCases)
    func recognizesFingerCounts(placement: HandFixture, gesture: GestureID) {
        #expect(CuratedGestureClassifier.classify(placement.sample(shape(for: gesture)))?.pose == gesture)
    }

    @Test(arguments: GestureID.allCases)
    func scoresLeftAndRightHandsTheSame(gesture: GestureID) throws {
        let shape = shape(for: gesture)
        let right = try #require(CuratedGestureClassifier.classify(HandFixture(rotation: 0.4).sample(shape)))
        let left = try #require(
            CuratedGestureClassifier.classify(HandFixture(chirality: .left, rotation: 0.4).sample(shape))
        )

        for pose in GestureID.allCases {
            #expect(abs(right.score(for: pose) - left.score(for: pose)) < 1e-9)
        }
    }

    @Test(arguments: placements, Array(0..<32))
    func countsAnyCombinationOfRaisedFingers(placement: HandFixture, mask: Int) {
        let shape = HandShape(
            index: mask & 1 == 0 ? .curled : .extended(degrees: 8),
            middle: mask & 2 == 0 ? .curled : .extended(degrees: 0),
            ring: mask & 4 == 0 ? .curled : .extended(degrees: -6),
            little: mask & 8 == 0 ? .curled : .extended(degrees: -14),
            thumb: mask & 16 == 0 ? .tucked : .spread
        )
        let poses: [GestureID] = [.fist, .oneFinger, .twoFingers, .threeFingers, .fourFingers, .fiveFingers]
        #expect(CuratedGestureClassifier.classify(placement.sample(shape))?.pose == poses[mask.nonzeroBitCount])
    }

    @Test(arguments: GestureID.allCases)
    func recognizesCountsFromEitherSideOfTheHand(gesture: GestureID) {
        let sample = HandFixture().sample(shape(for: gesture).turnedAround)
        #expect(CuratedGestureClassifier.classify(sample)?.pose == gesture)
    }

    @Test(arguments: GestureID.allCases)
    func chiralityUncertaintyDoesNotChangeTheCount(gesture: GestureID) {
        var sample = HandFixture(chirality: .left).sample(shape(for: gesture))
        sample.hand?.chirality = .unknown
        #expect(CuratedGestureClassifier.classify(sample)?.pose == gesture)
        sample.hand?.chirality = .right
        #expect(CuratedGestureClassifier.classify(sample)?.pose == gesture)
    }

    @Test(arguments: placements)
    func acceptsNaturalFingerBendsAndSplayedShortFingers(placement: HandFixture) throws {
        var shape = HandShape(
            index: .relaxed(degrees: 30), middle: .relaxed(degrees: 0), ring: .relaxed(degrees: -20),
            little: .extended(degrees: -75), thumb: .spread
        )
        let knuckle = try #require(shape.points[.littleMCP])
        for joint in [HandJoint.littlePIP, .littleDIP, .littleTip] {
            shape.points[joint] = knuckle + 0.6 * (try #require(shape.points[joint]) - knuckle)
        }
        #expect(CuratedGestureClassifier.classify(placement.sample(shape))?.pose == .fiveFingers)
    }

    @Test(arguments: GestureID.allCases)
    func anOccludedDIPDoesNotDiscardOtherClearFingerEvidence(gesture: GestureID) {
        var sample = HandFixture().sample(shape(for: gesture))
        sample.hand?.joints[.indexDIP] = nil
        sample.hand?.joints[.middleDIP]?.confidence = 0.2
        sample.hand?.joints[.ringDIP]?.confidence = 0.1
        sample.hand?.joints[.littleDIP] = nil
        #expect(CuratedGestureClassifier.classify(sample)?.pose == gesture)
    }

    @Test func clearlyFoldedDIPsCanIdentifyOccludedCurledTips() {
        var sample = HandFixture().sample(.oneFinger)
        sample.hand?.joints[.middleTip] = nil
        sample.hand?.joints[.ringTip]?.confidence = 0.2
        sample.hand?.joints[.littleTip] = nil
        #expect(CuratedGestureClassifier.classify(sample)?.pose == .oneFinger)
    }

    @Test func missingDistalEvidenceDoesNotAssumeAFingerIsFolded() {
        var sample = HandFixture().sample(.oneFinger)
        sample.hand?.joints[.middleDIP] = nil
        sample.hand?.joints[.middleTip] = nil
        #expect(CuratedGestureClassifier.classify(sample)?.pose == nil)
    }

    @Test func aTuckedThumbNeedNotBeSharplyBent() {
        var shape = HandShape.fourFingers
        shape.points[.thumbMP] = SIMD2(0.35, 0.5)
        shape.points[.thumbIP] = SIMD2(0.2, 0.7)
        shape.points[.thumbTip] = SIMD2(0.05, 0.9)
        #expect(CuratedGestureClassifier.classify(HandFixture().sample(shape))?.pose == .fourFingers)
    }

    @Test func aHookedRaisedFingerIsAmbiguous() {
        var shape = HandShape.oneFinger
        shape.points[.indexDIP] = SIMD2(0.32, 1.62)
        shape.points[.indexTip] = SIMD2(0.32, 1.42)
        #expect(CuratedGestureClassifier.classify(HandFixture().sample(shape))?.pose == nil)
    }

    @Test func nonFiniteOrCollapsedRequiredGeometryIsRejected() {
        var sample = HandFixture().sample(.oneFinger)
        sample.hand?.joints[.indexTip]?.x = .nan
        #expect(CuratedGestureClassifier.classify(sample)?.pose == nil)
        sample = HandFixture().sample(.oneFinger)
        if let indexMCP = sample.hand?.joints[.indexMCP] {
            sample.hand?.joints[.indexPIP] = indexMCP
        }
        #expect(CuratedGestureClassifier.classify(sample)?.pose == nil)
    }

    @Test func halfBentFingersAreTooAmbiguousToRecognize() throws {
        let classification = try #require(CuratedGestureClassifier.classify(HandFixture().sample(.halfBent)))

        #expect(classification.pose == nil)
    }

    @Test func jointsAtTheConfidenceFloorStillCount() {
        let sample = HandFixture(confidence: CuratedGestureClassifier.minimumJointConfidence).sample(.twoFingers)

        #expect(CuratedGestureClassifier.classify(sample)?.pose == .twoFingers)
    }

    @Test func jointsBelowTheConfidenceFloorCountForNothing() throws {
        let sample = HandFixture(confidence: CuratedGestureClassifier.minimumJointConfidence - 0.01).sample(.twoFingers)
        let classification = try #require(CuratedGestureClassifier.classify(sample))

        #expect(classification.pose == nil)
        #expect(GestureID.allCases.allSatisfy { classification.score(for: $0) == 0 })
    }

    @Test func oneUncertainRequiredJointRejectsThePose() throws {
        var sample = HandFixture().sample(.oneFinger)
        sample.hand?.joints[.indexTip]?.confidence = 0.3

        let classification = try #require(CuratedGestureClassifier.classify(sample))

        #expect(classification.pose == nil)
        #expect(classification.score(for: .oneFinger) == 0)
    }

    @Test func noHandMeansNoClassification() {
        #expect(CuratedGestureClassifier.classify(HandPoseSample(timestamp: 0, hand: nil)) == nil)
    }

    @Test func recognizesTheBestPoseAtTheScoreFloor() {
        #expect(CuratedGestureClassifier.recognizedPose(in: [.oneFinger: 0.85, .twoFingers: 0.6]) == .oneFinger)
    }

    @Test func rejectsABestPoseBelowTheScoreFloor() {
        #expect(CuratedGestureClassifier.recognizedPose(in: [.oneFinger: 0.84, .twoFingers: 0]) == nil)
    }

    @Test func recognizesAPoseThatWinsByExactlyTheMargin() {
        #expect(CuratedGestureClassifier.recognizedPose(in: [.threeFingers: 1, .twoFingers: 0.85]) == .threeFingers)
    }

    @Test func rejectsPosesTooCloseToCall() {
        #expect(CuratedGestureClassifier.recognizedPose(in: [.threeFingers: 0.95, .twoFingers: 0.85]) == nil)
        #expect(CuratedGestureClassifier.recognizedPose(in: [.fist: 0.9, .oneFinger: 0.9]) == nil)
    }

    private func shape(for gesture: GestureID) -> HandShape {
        switch gesture {
        case .fist: .fist
        case .oneFinger: .oneFinger
        case .twoFingers: .twoFingers
        case .threeFingers: .threeFingers
        case .fourFingers: .fourFingers
        case .fiveFingers: .fiveFingers
        }
    }
}
