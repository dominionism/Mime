import Testing
@testable import Mime

struct HandMotionRecognizerTests {
    @Test func recognizesASwipeRightInTheUsersView() {
        var recognizer = HandMotionRecognizer()

        #expect(recognizer.update(HandFixture(wrist: SIMD2(0.70, 0.5)).sample(.fiveFingers, at: 0)).gesture == nil)
        let result = recognizer.update(HandFixture(wrist: SIMD2(0.40, 0.5)).sample(.fiveFingers, at: 0.15))

        #expect(result.gesture == .swipeRight)
        #expect(result.suppressesStaticCommands)
    }

    @Test func recognizesASwipeLeftInTheUsersView() {
        var recognizer = HandMotionRecognizer()

        _ = recognizer.update(HandFixture(wrist: SIMD2(0.30, 0.5)).sample(.fiveFingers, at: 0))
        let result = recognizer.update(HandFixture(wrist: SIMD2(0.60, 0.5)).sample(.fiveFingers, at: 0.15))

        #expect(result.gesture == .swipeLeft)
    }

    @Test func rejectsMostlyVerticalMovement() {
        var recognizer = HandMotionRecognizer()

        _ = recognizer.update(HandFixture(wrist: SIMD2(0.5, 0.3)).sample(.fiveFingers, at: 0))
        let result = recognizer.update(HandFixture(wrist: SIMD2(0.52, 0.65)).sample(.fiveFingers, at: 0.15))

        #expect(result.gesture == nil)
    }

    @Test func aLongOrBrokenStrokeStartsOver() {
        var recognizer = HandMotionRecognizer()

        _ = recognizer.update(HandFixture(wrist: SIMD2(0.70, 0.5)).sample(.fiveFingers, at: 0))
        #expect(recognizer.update(HandFixture(wrist: SIMD2(0.40, 0.5)).sample(.fiveFingers, at: 0.8)).gesture == nil)
        #expect(recognizer.update(HandFixture(wrist: SIMD2(0.40, 0.5)).sample(.fiveFingers, at: 1.1)).gesture == nil)
    }

    @Test func oneStrokeEmitsOnlyOnceUntilAnotherStroke() {
        var recognizer = HandMotionRecognizer()

        _ = recognizer.update(HandFixture(wrist: SIMD2(0.70, 0.5)).sample(.fiveFingers, at: 0))
        #expect(recognizer.update(HandFixture(wrist: SIMD2(0.40, 0.5)).sample(.fiveFingers, at: 0.15)).gesture == .swipeRight)
        #expect(recognizer.update(HandFixture(wrist: SIMD2(0.40, 0.5)).sample(.fiveFingers, at: 0.25)).gesture == nil)
    }

    @Test func recognizesAPinchAfterAShortHoldAndRequiresRelease() {
        var recognizer = HandMotionRecognizer()
        let first = pinchSample(at: 0)
        let second = pinchSample(at: 0.05)

        #expect(recognizer.update(first).gesture == nil)
        #expect(recognizer.update(second).gesture == .pinch)
        #expect(recognizer.update(pinchSample(at: 0.10)).gesture == nil)

        _ = recognizer.update(HandFixture().sample(.oneFinger, at: 0.20))
        #expect(recognizer.update(pinchSample(at: 0.25)).gesture == nil)
    }

    @Test func pinchThresholdScalesWithHandSize() {
        for scale in [0.1, 0.22, 0.4] {
            var recognizer = HandMotionRecognizer()
            #expect(recognizer.update(pinchSample(scale: scale, at: 0)).gesture == nil)
            #expect(recognizer.update(pinchSample(scale: scale, at: 0.05)).gesture == .pinch)
        }
    }

    @Test func lowConfidencePinchJointsAreIgnored() {
        var recognizer = HandMotionRecognizer()
        var sample = pinchSample(at: 0)
        sample.hand?.joints[.thumbTip]?.confidence = 0.49

        _ = recognizer.update(sample)
        sample.timestamp = 0.1
        #expect(recognizer.update(sample).gesture == nil)
    }

    private func pinchSample(scale: Double = 0.22, at timestamp: Double) -> HandPoseSample {
        let fixture = HandFixture(scale: scale)
        var hand = fixture.hand(.oneFinger)
        let indexTip = hand.joints[.indexTip]!.x
        let indexY = hand.joints[.indexTip]!.y
        hand.joints[.thumbTip] = HandJointPosition(
            x: indexTip + 0.02 * scale,
            y: indexY,
            confidence: 0.9
        )
        return HandPoseSample(timestamp: timestamp, hand: hand, imageAspectRatio: fixture.imageAspectRatio)
    }
}
