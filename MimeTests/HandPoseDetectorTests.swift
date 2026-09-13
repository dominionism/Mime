import Testing
import Vision
@testable import Mime

struct HandPoseDetectorTests {
    @Test func deliversOnlyTheNewestSample() async {
        let detector = HandPoseDetector()
        for timestamp in [1.0, 2.0, 3.0] {
            detector.publish(HandPoseSample(timestamp: timestamp, hand: nil))
        }

        var iterator = detector.samples.makeAsyncIterator()
        let delivered = await iterator.next()

        #expect(delivered?.timestamp == 3)
    }

    @Test func mapsEveryVisionJoint() {
        let visionJoints: [VNHumanHandPoseObservation.JointName] = [
            .wrist,
            .thumbCMC, .thumbMP, .thumbIP, .thumbTip,
            .indexMCP, .indexPIP, .indexDIP, .indexTip,
            .middleMCP, .middlePIP, .middleDIP, .middleTip,
            .ringMCP, .ringPIP, .ringDIP, .ringTip,
            .littleMCP, .littlePIP, .littleDIP, .littleTip,
        ]

        let mapped = visionJoints.compactMap { HandJoint(visionName: $0) }

        #expect(mapped.count == visionJoints.count)
        #expect(Set(mapped) == Set(HandJoint.allCases))
    }

    @Test func mapsChirality() {
        #expect(HandChirality(VNChirality.left) == .left)
        #expect(HandChirality(VNChirality.right) == .right)
        #expect(HandChirality(VNChirality.unknown) == .unknown)
    }
}
