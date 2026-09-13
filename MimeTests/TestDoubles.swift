@testable import Mime

@MainActor
final class FakePermissionStatus: PermissionStatusProviding {
    var cameraAccess: CameraAccess
    var accessibilityAccess: AccessibilityAccess
    /// The answer the user gives if Mime asks for camera access.
    var cameraPromptAnswer: CameraAccess
    private(set) var cameraPromptCount = 0

    init(
        cameraAccess: CameraAccess = .notDetermined,
        accessibilityAccess: AccessibilityAccess = .notAllowed,
        cameraPromptAnswer: CameraAccess = .denied
    ) {
        self.cameraAccess = cameraAccess
        self.accessibilityAccess = accessibilityAccess
        self.cameraPromptAnswer = cameraPromptAnswer
    }

    func requestCameraAccess() async -> CameraAccess {
        guard cameraAccess == .notDetermined else { return cameraAccess }
        cameraPromptCount += 1
        cameraAccess = cameraPromptAnswer
        return cameraAccess
    }
}

final class FakeHandTracking: HandTracking {
    let samples: AsyncStream<HandPoseSample>
    private let continuation: AsyncStream<HandPoseSample>.Continuation
    var startError: CameraCaptureError?
    private(set) var isRunning = false
    private(set) var startCount = 0

    init() {
        var streamContinuation: AsyncStream<HandPoseSample>.Continuation?
        samples = AsyncStream { continuation in
            streamContinuation = continuation
        }
        continuation = streamContinuation!
    }

    func start() async throws {
        startCount += 1
        if let startError {
            throw startError
        }
        isRunning = true
    }

    func stop() async {
        isRunning = false
    }

    func send(_ sample: HandPoseSample) {
        continuation.yield(sample)
    }
}
