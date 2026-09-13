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
    let samples = AsyncStream<HandPoseSample> { _ in }
    var startError: CameraCaptureError?
    private(set) var isRunning = false
    private(set) var startCount = 0

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
}
