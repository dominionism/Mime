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
    /// Retain feedback after the hand leaves view, so a completed attempt can be checked afterward.
    private(set) var lastDetectedPose: GestureDetection?
    private(set) var lastAcceptedCommand: GestureDetection?
    private(set) var acceptedCommandCount = 0
    private(set) var configuration = Configuration()
    private(set) var configurationError: String?
    private(set) var canEditBindings = true
    private(set) var isEditingBindings = false
    private(set) var applicationLaunchStatus = ApplicationLaunchStatus.idle
    private(set) var activationMode = GestureActivationMode.wakeThenCommand
    /// The safety gate's current phase, including wake and command stabilization progress.
    private(set) var gesturePhase = GestureGatePhase.listening(wakeProgress: 0)
    private(set) var trackingFramesPerSecond: Double?
    private(set) var cameraAccess: CameraAccess
    private(set) var accessibilityAccess: AccessibilityAccess
    private(set) var cameraError: CameraCaptureError?

    @ObservationIgnored private let permissions: any PermissionStatusProviding
    @ObservationIgnored private let handTracking: any HandTracking
    @ObservationIgnored private let configurationStore: any ConfigurationStoring
    @ObservationIgnored private let applicationLauncher: any ApplicationLaunching
    @ObservationIgnored private var launchTask: Task<Void, Never>?
    @ObservationIgnored private var launchID: UUID?
    @ObservationIgnored private var isCapturing = false
    @ObservationIgnored private var frameRateMeter = FrameRateMeter()
    @ObservationIgnored private var gestureGate = GestureGate()
    @ObservationIgnored private var sampleTask: Task<Void, Never>?
    @ObservationIgnored private var menuTrackingObserver: (any NSObjectProtocol)?

    init(
        permissions: any PermissionStatusProviding = SystemPermissionStatus(),
        handTracking: any HandTracking = CameraHandTracking(),
        configurationStore: any ConfigurationStoring = ConfigurationStore(),
        applicationLauncher: any ApplicationLaunching = ApplicationLauncher()
    ) {
        self.permissions = permissions
        self.handTracking = handTracking
        self.configurationStore = configurationStore
        self.applicationLauncher = applicationLauncher
        cameraAccess = permissions.cameraAccess
        accessibilityAccess = permissions.accessibilityAccess
        reloadConfiguration()

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
        launchTask?.cancel()
        if let menuTrackingObserver {
            NotificationCenter.default.removeObserver(menuTrackingObserver)
        }
    }

    func toggleRecognition() async {
        if isRecognitionActive {
            isRecognitionActive = false
            cancelPendingLaunch()
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

    func reloadConfiguration() {
        cancelPendingLaunch()
        do {
            let loaded = try configurationStore.load()
            configuration = loaded
            activationMode = loaded.activationMode
            resetGestureGate()
            configurationError = nil
            canEditBindings = true
        } catch {
            // Disable bindings when the saved configuration cannot be trusted; preserve the file for recovery.
            configuration = Configuration()
            activationMode = .wakeThenCommand
            resetGestureGate()
            configurationError = error.localizedDescription
            canEditBindings = false
        }
    }

    func resetConfiguration() {
        cancelPendingLaunch()
        resetGestureGate()
        do {
            configuration = try configurationStore.reset()
            configurationError = nil
            canEditBindings = true
        } catch {
            configurationError = error.localizedDescription
        }
    }

    func setApplication(_ application: ApplicationTarget?, for gesture: GestureID) {
        guard canEditBindings else { return }
        cancelPendingLaunch()
        resetGestureGate()
        do {
            var updated = configuration
            try updated.setApplication(application, for: gesture)
            try configurationStore.save(updated)
            configuration = updated
            configurationError = nil
        } catch {
            // Keep the last saved binding active if the replacement cannot be written.
            configurationError = error.localizedDescription
        }
    }

    func setActivationMode(_ mode: GestureActivationMode) {
        guard canEditBindings, mode != activationMode else { return }
        cancelPendingLaunch()
        var updated = configuration
        updated.activationMode = mode
        do {
            try configurationStore.save(updated)
            configuration = updated
            activationMode = mode
            resetGestureGate()
            configurationError = nil
        } catch {
            configurationError = error.localizedDescription
        }
    }

    func beginEditingBindings() {
        isEditingBindings = true
        cancelPendingLaunch()
        resetGestureGate()
    }

    func endEditingBindings() {
        isEditingBindings = false
        resetGestureGate()
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
        if let pose = classification?.pose {
            lastDetectedPose = GestureDetection(gesture: pose, detectedAt: Date())
        }
        if isRecognitionActive && !isEditingBindings {
            if let command = gestureGate.update(with: classification, at: sample.timestamp) {
                lastAcceptedCommand = GestureDetection(gesture: command, detectedAt: Date())
                acceptedCommandCount += 1
                openApplication(for: command)
            }
            gesturePhase = gestureGate.phase
        }
        frameRateMeter.record(sample.timestamp)
        trackingFramesPerSecond = frameRateMeter.framesPerSecond
    }

    private func resetGestureGate() {
        gestureGate = GestureGate(mode: activationMode)
        gesturePhase = gestureGate.phase
    }

    private func openApplication(for gesture: GestureID) {
        // Drop commands arriving during a launch rather than queuing a later surprise activation.
        guard launchTask == nil, canEditBindings else { return }
        guard let application = configuration.application(for: gesture) else {
            applicationLaunchStatus = .unassigned(gesture)
            return
        }
        let id = UUID()
        launchID = id
        applicationLaunchStatus = .opening(application)
        launchTask = Task { [weak self] in
            guard let self, !Task.isCancelled, self.isRecognitionActive, !self.isEditingBindings else { return }
            do {
                try await self.applicationLauncher.open(application)
                guard !Task.isCancelled, self.launchID == id else { return }
                self.applicationLaunchStatus = .opened(application)
            } catch {
                guard !Task.isCancelled, self.launchID == id else { return }
                self.applicationLaunchStatus = .failed(application: application, message: error.localizedDescription)
            }
            if self.launchID == id {
                self.launchTask = nil
                self.launchID = nil
            }
        }
    }

    private func cancelPendingLaunch() {
        launchTask?.cancel()
        launchTask = nil
        launchID = nil
        if case .opening = applicationLaunchStatus {
            applicationLaunchStatus = .idle
        }
    }
}
