import Testing
@testable import Mime

struct HandPoseNormalizerTests {
    @Test func putsTheWristAtTheOriginAndTheMiddleKnuckleStraightUp() throws {
        let hand = try normalize(HandFixture(rotation: 0.7, scale: 0.3), .openPalm)

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
        let hand = try normalize(fixture, .vSign)

        for (joint, point) in HandShape.vSign.points {
            expectClose(hand.points[joint], point)
        }
    }

    @Test func reportsWhichWayIsUpInTheImage() throws {
        let upright = try normalize(HandFixture(), .openPalm)
        let quarterTurn = try normalize(HandFixture(rotation: .pi / 2), .openPalm)

        expectClose(upright.imageUp, SIMD2(0, 1))
        expectClose(quarterTurn.imageUp, SIMD2(1, 0))
    }

    @Test func keepsJointConfidence() throws {
        let hand = try normalize(HandFixture(confidence: 0.7), .fist)

        #expect(hand.confidences[.indexTip] == 0.7)
    }

    @Test func needsTheWristAndMiddleKnuckle() {
        var hand = HandFixture().hand(.openPalm)
        hand.joints[.middleMCP] = nil

        #expect(HandPoseNormalizer.normalize(hand, imageAspectRatio: 16.0 / 9.0) == nil)
    }

    private func normalize(_ fixture: HandFixture, _ shape: HandShape) throws -> NormalizedHand {
        try #require(HandPoseNormalizer.normalize(fixture.hand(shape), imageAspectRatio: fixture.imageAspectRatio))
    }
}
