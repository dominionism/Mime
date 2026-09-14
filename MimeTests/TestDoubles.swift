import Foundation
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

@MainActor
final class FakeConfigurationStore: ConfigurationStoring {
    var configuration = Configuration()
    var loadError: (any Error)?
    var saveError: (any Error)?
    private(set) var saveCount = 0

    func load() throws -> Configuration {
        if let loadError { throw loadError }
        return configuration
    }

    func save(_ configuration: Configuration) throws {
        if let saveError { throw saveError }
        self.configuration = configuration
        saveCount += 1
    }

    func reset() throws -> Configuration {
        configuration = Configuration()
        loadError = nil
        return configuration
    }
}

@MainActor
final class FakeApplicationLauncher: ApplicationLaunching {
    var error: (any Error)?
    var waitsForCompletion = false
    private(set) var applications: [ApplicationTarget] = []
    private var completions: [CheckedContinuation<Void, any Error>] = []

    func open(_ application: ApplicationTarget) async throws {
        applications.append(application)
        if let error { throw error }
        if waitsForCompletion {
            try await withCheckedThrowingContinuation { completions.append($0) }
        }
    }

    func completeNext() {
        completions.removeFirst().resume()
    }
}

@MainActor
final class FakeSystemActionExecutor: SystemActionExecuting {
    var error: (any Error)?
    private(set) var actions: [SystemGestureAction] = []

    func perform(_ action: SystemGestureAction) throws {
        actions.append(action)
        if let error { throw error }
    }
}
