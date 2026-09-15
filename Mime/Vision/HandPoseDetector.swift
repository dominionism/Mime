import CoreMedia
import CoreVideo
import Vision

/// Finds a hand in camera frames with Vision and publishes the newest result.
///
/// Call `process(_:)` only from the capture queue. Each frame is analyzed synchronously on that queue, so at
/// most one Vision request runs at a time and the capture output discards frames that arrive meanwhile.
final class HandPoseDetector {
    /// Samples in arrival order. Only the newest unread sample is buffered, so a slow reader never falls behind.
    let samples: AsyncStream<HandPoseSample>

    private let continuation: AsyncStream<HandPoseSample>.Continuation
    private let request = VNDetectHumanHandPoseRequest()

    init() {
        (samples, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
        request.maximumHandCount = 1
    }

    deinit {
        continuation.finish()
    }

    func process(_ sampleBuffer: CMSampleBuffer) {
        let started = ContinuousClock.now
        let timestamp = sampleBuffer.presentationTimeStamp.seconds
        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .up, options: [:])

        let hand: DetectedHand?
        do {
            try handler.perform([request])
            hand = request.results?.first.flatMap { DetectedHand($0) }
        } catch {
            hand = nil
        }

        var sample = HandPoseSample(timestamp: timestamp, hand: hand)
        if let image = sampleBuffer.imageBuffer, CVPixelBufferGetHeight(image) > 0 {
            sample.imageAspectRatio = Double(CVPixelBufferGetWidth(image)) / Double(CVPixelBufferGetHeight(image))
        }
        let elapsed = started.duration(to: .now).components
        sample.processingDuration = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
        publish(sample)
    }

    func publish(_ sample: HandPoseSample) {
        continuation.yield(sample)
    }
}

extension DetectedHand {
    /// Copies joint positions out of a Vision observation, skipping joints Vision could not place.
    init?(_ observation: VNHumanHandPoseObservation) {
        guard let points = try? observation.recognizedPoints(.all) else { return nil }

        var joints: [HandJoint: HandJointPosition] = [:]
        for (name, point) in points where point.confidence > 0 {
            guard let joint = HandJoint(visionName: name) else { continue }
            joints[joint] = HandJointPosition(x: point.location.x, y: point.location.y, confidence: point.confidence)
        }

        self.init(chirality: HandChirality(observation.chirality), confidence: observation.confidence, joints: joints)
    }
}

extension HandJoint {
    init?(visionName: VNHumanHandPoseObservation.JointName) {
        guard let joint = Self.byVisionName[visionName] else { return nil }
        self = joint
    }

    private static let byVisionName: [VNHumanHandPoseObservation.JointName: HandJoint] = [
        .wrist: .wrist,
        .thumbCMC: .thumbCMC, .thumbMP: .thumbMP, .thumbIP: .thumbIP, .thumbTip: .thumbTip,
        .indexMCP: .indexMCP, .indexPIP: .indexPIP, .indexDIP: .indexDIP, .indexTip: .indexTip,
        .middleMCP: .middleMCP, .middlePIP: .middlePIP, .middleDIP: .middleDIP, .middleTip: .middleTip,
        .ringMCP: .ringMCP, .ringPIP: .ringPIP, .ringDIP: .ringDIP, .ringTip: .ringTip,
        .littleMCP: .littleMCP, .littlePIP: .littlePIP, .littleDIP: .littleDIP, .littleTip: .littleTip,
    ]
}

extension HandChirality {
    init(_ chirality: VNChirality) {
        switch chirality {
        case .left: self = .left
        case .right: self = .right
        case .unknown: self = .unknown
        @unknown default: self = .unknown
        }
    }
}
