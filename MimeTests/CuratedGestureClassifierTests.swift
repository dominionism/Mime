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

    @Test func theBackOfFiveFingersIsNotFiveFingers() throws {
        let classification = try #require(
            CuratedGestureClassifier.classify(HandFixture().sample(HandShape.fiveFingers.turnedAround))
        )

        #expect(classification.pose == nil)
        #expect(classification.score(for: .fiveFingers) < CuratedGestureClassifier.minimumScore)
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
