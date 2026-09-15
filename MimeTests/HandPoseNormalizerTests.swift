import Testing
@testable import Mime

struct HandPoseNormalizerTests {
    @Test func putsTheWristAtTheOriginAndTheMiddleKnuckleStraightUp() throws {
        let hand = try normalize(HandFixture(rotation: 0.7, scale: 0.3), .fiveFingers)

        expectClose(hand.points[.wrist], SIMD2(0, 0))
        expectClose(hand.points[.middleMCP], SIMD2(0, 1))
    }

    @Test(arguments: [
        HandFixture(rotation: .pi / 5),
        HandFixture(rotation: -2.5),
        HandFixture(scale: 0.1, wrist: SIMD2(0.2, 0.7)),
        HandFixture(imageAspectRatio: 4.0 / 3.0),
        HandFixture(chirality: .left),
        HandFixture(chirality: .left, rotation: 1.2, scale: 0.15, imageAspectRatio: 4.0 / 3.0),
    ])
    func recoversTheSameShapeWhereverTheHandIs(fixture: HandFixture) throws {
        let hand = try normalize(fixture, .twoFingers)

        for (joint, point) in HandShape.twoFingers.points {
            expectClose(hand.points[joint], point)
        }
    }

    @Test func reportsWhichWayIsUpInTheImage() throws {
        let upright = try normalize(HandFixture(), .fiveFingers)
        let quarterTurn = try normalize(HandFixture(rotation: .pi / 2), .fiveFingers)

        expectClose(upright.imageUp, SIMD2(0, 1))
        expectClose(quarterTurn.imageUp, SIMD2(1, 0))
    }

    @Test func keepsJointConfidence() throws {
        let hand = try normalize(HandFixture(confidence: 0.7), .fist)

        #expect(hand.confidences[.indexTip] == 0.7)
    }

    @Test func needsTheWristAndMiddleKnuckle() {
        var hand = HandFixture().hand(.fiveFingers)
        hand.joints[.middleMCP] = nil

        #expect(HandPoseNormalizer.normalize(hand, imageAspectRatio: 16.0 / 9.0) == nil)
    }

    @Test(arguments: [Double.nan, .infinity, 0, -1])
    func rejectsInvalidImageProportions(aspectRatio: Double) {
        #expect(HandPoseNormalizer.normalize(HandFixture().hand(.fiveFingers), imageAspectRatio: aspectRatio) == nil)
    }

    @Test func rejectsNonFiniteOrCollapsedPalmAxes() {
        var hand = HandFixture().hand(.fiveFingers)
        hand.joints[.wrist]?.x = .infinity
        #expect(HandPoseNormalizer.normalize(hand, imageAspectRatio: 16.0 / 9.0) == nil)
        hand = HandFixture().hand(.fiveFingers)
        hand.joints[.middleMCP] = hand.joints[.wrist]
        #expect(HandPoseNormalizer.normalize(hand, imageAspectRatio: 16.0 / 9.0) == nil)
    }

    private func normalize(_ fixture: HandFixture, _ shape: HandShape) throws -> NormalizedHand {
        try #require(HandPoseNormalizer.normalize(fixture.hand(shape), imageAspectRatio: fixture.imageAspectRatio))
    }
}
