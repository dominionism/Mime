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

    @Test func swipeStartsAtMotionOnsetAfterAStationaryHold() {
        var recognizer = HandMotionRecognizer()
        for frame in 0...18 {
            _ = recognizer.update(HandFixture(wrist: SIMD2(0.7, 0.5)).sample(.fiveFingers, at: Double(frame) * 0.03))
        }
        _ = recognizer.update(HandFixture(wrist: SIMD2(0.65, 0.5)).sample(.fiveFingers, at: 0.6))
        _ = recognizer.update(HandFixture(wrist: SIMD2(0.6, 0.5)).sample(.fiveFingers, at: 0.65))
        #expect(recognizer.update(HandFixture(wrist: SIMD2(0.55, 0.5)).sample(.fiveFingers, at: 0.7)).gesture == .swipeRight)
    }

    @Test func raisingAFingerPoseDoesNotSuppressStaticCommands() {
        var recognizer = HandMotionRecognizer()
        _ = recognizer.update(HandFixture(wrist: SIMD2(0.5, 0.3)).sample(.threeFingers, at: 0))
        let raised = recognizer.update(HandFixture(wrist: SIMD2(0.5, 0.55)).sample(.threeFingers, at: 0.1))
        #expect(raised.gesture == nil)
        #expect(!raised.suppressesStaticCommands)
    }

    @Test func smallTrackingJitterDoesNotBlockFingerCommands() {
        var recognizer = HandMotionRecognizer()
        for frame in 0..<30 {
            let x = 0.5 + (frame.isMultiple(of: 2) ? 0.002 : -0.002)
            let result = recognizer.update(HandFixture(wrist: SIMD2(x, 0.5)).sample(.oneFinger, at: Double(frame) / 30))
            #expect(result.gesture == nil)
            #expect(!result.suppressesStaticCommands)
        }
    }

    @Test func losingPalmLandmarksDoesNotMoveAStationaryHand() {
        var recognizer = HandMotionRecognizer()
        _ = recognizer.update(HandFixture(scale: 0.4).sample(.fiveFingers, at: 0))
        var partial = HandFixture(scale: 0.4).sample(.fiveFingers, at: 0.04)
        partial.hand?.joints[.wrist]?.confidence = 0.1
        partial.hand?.joints[.indexMCP]?.confidence = 0.1
        let result = recognizer.update(partial)
        #expect(result.gesture == nil)
        #expect(!result.suppressesStaticCommands)
    }

    @Test func switchingHandsCannotBecomeASwipe() {
        var recognizer = HandMotionRecognizer()
        _ = recognizer.update(HandFixture(chirality: .right, wrist: SIMD2(0.7, 0.5)).sample(.fiveFingers, at: 0))
        let result = recognizer.update(HandFixture(chirality: .left, wrist: SIMD2(0.3, 0.5)).sample(.fiveFingers, at: 0.1))
        #expect(result.gesture == nil)
        #expect(!result.suppressesStaticCommands)
    }

    @Test func stillnessDuringCooldownRearmsTheNextSwipe() {
        var recognizer = HandMotionRecognizer()
        _ = recognizer.update(HandFixture(wrist: SIMD2(0.7, 0.5)).sample(.fiveFingers, at: 0))
        #expect(recognizer.update(HandFixture(wrist: SIMD2(0.4, 0.5)).sample(.fiveFingers, at: 0.15)).gesture == .swipeRight)
        _ = recognizer.update(HandFixture(wrist: SIMD2(0.4, 0.5)).sample(.fiveFingers, at: 0.2))
        _ = recognizer.update(HandFixture(wrist: SIMD2(0.4, 0.5)).sample(.fiveFingers, at: 0.3))
        _ = recognizer.update(HandFixture(wrist: SIMD2(0.4, 0.5)).sample(.fiveFingers, at: 0.36))
        #expect(recognizer.update(HandFixture(wrist: SIMD2(0.6, 0.5)).sample(.fiveFingers, at: 0.46)).gesture == .swipeLeft)
    }

    @Test func continuousReturnMotionDoesNotUndoTheSwipe() {
        var recognizer = HandMotionRecognizer()
        _ = recognizer.update(HandFixture(wrist: SIMD2(0.7, 0.5)).sample(.fiveFingers, at: 0))
        #expect(recognizer.update(HandFixture(wrist: SIMD2(0.4, 0.5)).sample(.fiveFingers, at: 0.15)).gesture == .swipeRight)
        for (timestamp, x) in [(0.2, 0.45), (0.3, 0.55), (0.4, 0.7)] {
            let result = recognizer.update(HandFixture(wrist: SIMD2(x, 0.5)).sample(.fiveFingers, at: timestamp))
            #expect(result.gesture == nil)
            #expect(result.suppressesStaticCommands)
        }
    }

    @Test func aSmallerHandCanMakeAPalmSizedSwipe() {
        var recognizer = HandMotionRecognizer()
        _ = recognizer.update(HandFixture(scale: 0.1, wrist: SIMD2(0.7, 0.5)).sample(.fiveFingers, at: 0))
        #expect(recognizer.update(HandFixture(scale: 0.1, wrist: SIMD2(0.62, 0.5)).sample(.fiveFingers, at: 0.15)).gesture == .swipeRight)
    }

    @Test func horizontalMotionSuppressesCommandsBeforeTheSwipeCompletes() {
        var recognizer = HandMotionRecognizer()
        _ = recognizer.update(HandFixture(wrist: SIMD2(0.7, 0.5)).sample(.fiveFingers, at: 0))
        let moving = recognizer.update(HandFixture(wrist: SIMD2(0.66, 0.5)).sample(.fiveFingers, at: 0.08))
        #expect(moving.gesture == nil)
        #expect(moving.suppressesStaticCommands)
    }


    @Test func reenteringAfterAReleaseCanSwipeImmediately() {
        var recognizer = HandMotionRecognizer()
        _ = recognizer.update(HandFixture(wrist: SIMD2(0.7, 0.5)).sample(.fiveFingers, at: 0))
        #expect(recognizer.update(HandFixture(wrist: SIMD2(0.4, 0.5)).sample(.fiveFingers, at: 0.1)).gesture == .swipeRight)
        _ = recognizer.update(HandPoseSample(timestamp: 0.15, hand: nil))
        _ = recognizer.update(HandPoseSample(timestamp: 0.25, hand: nil))
        _ = recognizer.update(HandFixture(wrist: SIMD2(0.4, 0.5)).sample(.fiveFingers, at: 0.35))
        #expect(recognizer.update(HandFixture(wrist: SIMD2(0.6, 0.5)).sample(.fiveFingers, at: 0.45)).gesture == .swipeLeft)
    }

}
