import AppKit
import Observation

/// Composition root and shared state for the menu bar and Settings window.
@MainActor
@Observable
final class AppModel {
    private(set) var isRecognitionActive = false
    /// Whether Settings is showing the live hand-tracking skeleton.
    private(set) var isDiagnosticsActive = false
    private(set) var latestHandPose: HandPoseSample?
    /// The newest classification is exposed for diagnostics and tuning; it never triggers an action by itself.
    private(set) var latestClassification: PoseClassification?
    /// The safety gate's current phase, including wake and command stabilization progress.
    private(set) var gesturePhase = GestureGatePhase.listening(wakeProgress: 0)
    private(set) var trackingFramesPerSecond: Double?
    private(set) var cameraAccess: CameraAccess
    private(set) var accessibilityAccess: AccessibilityAccess
    private(set) var cameraError: CameraCaptureError?

    @ObservationIgnored private let permissions: any PermissionStatusProviding
    @ObservationIgnored private let handTracking: any HandTracking
    @ObservationIgnored private var isCapturing = false
    @ObservationIgnored private var frameRateMeter = FrameRateMeter()
    @ObservationIgnored private var gestureGate = GestureGate()
    @ObservationIgnored private var sampleTask: Task<Void, Never>?
    @ObservationIgnored private var menuTrackingObserver: (any NSObjectProtocol)?

    init(
        permissions: any PermissionStatusProviding = SystemPermissionStatus(),
        handTracking: any HandTracking = CameraHandTracking()
    ) {
        self.permissions = permissions
        self.handTracking = handTracking
        cameraAccess = permissions.cameraAccess
        accessibilityAccess = permissions.accessibilityAccess

        let samples = handTracking.samples
        sampleTask = Task { [weak self] in
            for await sample in samples {
                self?.receive(sample)
            }
        }

        // Permissions can change in System Settings while Mime runs, so re-read them
        // whenever a menu opens. AppKit posts this notification on the main thread.
        menuTrackingObserver = NotificationCenter.default.addObserver(
            forName: NSMenu.didBeginTrackingNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshPermissions()
            }
        }
    }

    isolated deinit {
        sampleTask?.cancel()
        if let menuTrackingObserver {
            NotificationCenter.default.removeObserver(menuTrackingObserver)
        }
    }

    func toggleRecognition() async {
        if isRecognitionActive {
            isRecognitionActive = false
        } else {
            guard await obtainCameraAccess() else { return }
            isRecognitionActive = true
        }
        resetGestureGate()
        await updateCapture()
    }

    func setDiagnosticsActive(_ isActive: Bool) async {
        guard isActive != isDiagnosticsActive else { return }
        if isActive {
            guard await obtainCameraAccess() else { return }
        }
        isDiagnosticsActive = isActive
        await updateCapture()
    }

    func refreshPermissions() {
        cameraAccess = permissions.cameraAccess
        accessibilityAccess = permissions.accessibilityAccess
    }

    private func obtainCameraAccess() async -> Bool {
        cameraAccess = await permissions.requestCameraAccess()
        return cameraAccess == .authorized
    }

    /// Keeps the camera on exactly while recognition or diagnostics needs it.
    private func updateCapture() async {
        let shouldCapture = isRecognitionActive || isDiagnosticsActive
        guard shouldCapture != isCapturing else { return }
        isCapturing = shouldCapture

        guard shouldCapture else {
            await handTracking.stop()
            latestHandPose = nil
            latestClassification = nil
            trackingFramesPerSecond = nil
            frameRateMeter = FrameRateMeter()
            return
        }

        do {
            try await handTracking.start()
            cameraError = nil
        } catch {
            isCapturing = false
            isRecognitionActive = false
            isDiagnosticsActive = false
            resetGestureGate()
            cameraError = error as? CameraCaptureError ?? .configurationFailed
        }
    }

    private func receive(_ sample: HandPoseSample) {
        guard isCapturing else { return }
        latestHandPose = sample
        let classification = CuratedGestureClassifier.classify(sample)
        latestClassification = classification
        if isRecognitionActive {
            _ = gestureGate.update(with: classification, at: sample.timestamp)
            gesturePhase = gestureGate.phase
        }
        frameRateMeter.record(sample.timestamp)
        trackingFramesPerSecond = frameRateMeter.framesPerSecond
    }

    private func resetGestureGate() {
        gestureGate.reset()
        gesturePhase = gestureGate.phase
    }
}
