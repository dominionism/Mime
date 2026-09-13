import CoreGraphics
import Testing
@testable import Mime

struct HandSkeletonTests {
    @Test func mirrorsAndFlipsJointPositionsIntoViewSpace() {
        let size = CGSize(width: 160, height: 90)

        #expect(HandSkeleton.viewPoint(for: HandJointPosition(x: 0, y: 0, confidence: 1), in: size) == CGPoint(x: 160, y: 90))
        #expect(HandSkeleton.viewPoint(for: HandJointPosition(x: 0.25, y: 0.75, confidence: 1), in: size) == CGPoint(x: 120, y: 22.5))
    }

    @Test func connectsEveryJoint() {
        let connected = Set(HandSkeleton.bones.flatMap { [$0.0, $0.1] })

        #expect(connected == Set(HandJoint.allCases))
    }
}
