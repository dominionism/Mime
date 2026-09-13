/// A source of hand-pose samples that can be switched on and off.
protocol HandTracking: AnyObject {
    var samples: AsyncStream<HandPoseSample> { get }
    func start() async throws
    func stop() async
}

/// Feeds camera frames into Vision hand-pose detection.
final class CameraHandTracking: HandTracking {
    let samples: AsyncStream<HandPoseSample>
    private let capture: CameraCaptureService

    init() {
        let detector = HandPoseDetector()
        samples = detector.samples
        capture = CameraCaptureService(onFrame: detector.process)
    }

    func start() async throws {
        try await capture.start()
    }

    func stop() async {
        await capture.stop()
    }
}
