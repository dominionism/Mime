import Testing
@testable import Mime

struct FrameRateMeterTests {
    @Test func needsTwoSamplesBeforeReportingARate() {
        var meter = FrameRateMeter()
        #expect(meter.framesPerSecond == nil)

        meter.record(10)
        #expect(meter.framesPerSecond == nil)
    }

    @Test func measuresASteadyRate() throws {
        var meter = FrameRateMeter()
        for frame in 0..<60 {
            meter.record(Double(frame) / 30)
        }

        let rate = try #require(meter.framesPerSecond)
        #expect(abs(rate - 30) < 0.01)
    }

    @Test func ignoresTimestampsThatGoBackwards() {
        var meter = FrameRateMeter()
        meter.record(2)
        meter.record(1)

        #expect(meter.framesPerSecond == nil)
    }
}
