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
}
