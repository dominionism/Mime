import Testing
@testable import Mime

private let placements = [
    HandFixture(),
    HandFixture(chirality: .left),
    HandFixture(rotation: 0.35, scale: 0.15, wrist: SIMD2(0.3, 0.4)),
    HandFixture(chirality: .left, rotation: -0.3, scale: 0.3, imageAspectRatio: 4.0 / 3.0),
]

struct CuratedGestureClassifierTests {
    @Test(arguments: placements, [GestureID.openPalm, .fist, .vSign, .indexPoint])
    func recognizesUprightPoses(placement: HandFixture, gesture: GestureID) {
        let classification = CuratedGestureClassifier.classify(placement.sample(shape(for: gesture)))

        #expect(classification?.pose == gesture)
    }

    @Test(arguments: [
        HandFixture(rotation: .pi / 2),
        HandFixture(chirality: .left, rotation: .pi / 2),
        HandFixture(rotation: .pi / 2 + 0.3, scale: 0.15),
        HandFixture(chirality: .left, rotation: .pi / 2 - 0.3, imageAspectRatio: 4.0 / 3.0),
    ])
    func recognizesThumbsUp(placement: HandFixture) {
        #expect(CuratedGestureClassifier.classify(placement.sample(.thumbsUp))?.pose == .thumbsUp)
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

    @Test func thumbPointingDownIsNotAThumbsUp() throws {
        let classification = try #require(
            CuratedGestureClassifier.classify(HandFixture(rotation: -.pi / 2).sample(.thumbsUp))
        )

        #expect(classification.pose == nil)
        #expect(classification.score(for: .thumbsUp) == 0)
    }

    @Test func backOfAnOpenHandIsNotAnOpenPalm() throws {
        let classification = try #require(
            CuratedGestureClassifier.classify(HandFixture().sample(HandShape.openPalm.turnedAround))
        )

        #expect(classification.pose == nil)
        #expect(classification.score(for: .openPalm) < CuratedGestureClassifier.minimumScore)
    }

    @Test func halfBentFingersAreTooAmbiguousToRecognize() throws {
        let classification = try #require(CuratedGestureClassifier.classify(HandFixture().sample(.halfBent)))

        #expect(classification.pose == nil)
    }

    @Test func jointsAtTheConfidenceFloorStillCount() {
        let sample = HandFixture(confidence: CuratedGestureClassifier.minimumJointConfidence).sample(.fist)

        #expect(CuratedGestureClassifier.classify(sample)?.pose == .fist)
    }

    @Test func jointsBelowTheConfidenceFloorCountForNothing() throws {
        let sample = HandFixture(confidence: CuratedGestureClassifier.minimumJointConfidence - 0.01).sample(.fist)
        let classification = try #require(CuratedGestureClassifier.classify(sample))

        #expect(classification.pose == nil)
        #expect(GestureID.allCases.allSatisfy { classification.score(for: $0) == 0 })
    }

    @Test func oneUncertainRequiredJointRejectsThePose() throws {
        var sample = HandFixture().sample(.indexPoint)
        sample.hand?.joints[.indexTip]?.confidence = 0.3

        let classification = try #require(CuratedGestureClassifier.classify(sample))

        #expect(classification.pose == nil)
        #expect(classification.score(for: .indexPoint) == 0)
    }

    @Test func noHandMeansNoClassification() {
        #expect(CuratedGestureClassifier.classify(HandPoseSample(timestamp: 0, hand: nil)) == nil)
    }

    @Test func recognizesTheBestPoseAtTheScoreFloor() {
        #expect(CuratedGestureClassifier.recognizedPose(in: [.fist: 0.85, .thumbsUp: 0.6]) == .fist)
    }

    @Test func rejectsABestPoseBelowTheScoreFloor() {
        #expect(CuratedGestureClassifier.recognizedPose(in: [.fist: 0.84, .thumbsUp: 0]) == nil)
    }

    @Test func recognizesAPoseThatWinsByExactlyTheMargin() {
        #expect(CuratedGestureClassifier.recognizedPose(in: [.vSign: 1, .openPalm: 0.85]) == .vSign)
    }

    @Test func rejectsPosesTooCloseToCall() {
        #expect(CuratedGestureClassifier.recognizedPose(in: [.vSign: 0.95, .indexPoint: 0.85]) == nil)
        #expect(CuratedGestureClassifier.recognizedPose(in: [.fist: 0.9, .thumbsUp: 0.9]) == nil)
    }

    private func shape(for gesture: GestureID) -> HandShape {
        switch gesture {
        case .openPalm: .openPalm
        case .fist: .fist
        case .thumbsUp: .thumbsUp
        case .vSign: .vSign
        case .indexPoint: .indexPoint
        }
    }
}
