import AppKit
import Testing
@testable import Mime

@MainActor
struct AppModelTests {
    @Test func recognitionStartsOff() {
        let tracking = FakeHandTracking()
        let model = AppModel(permissions: FakePermissionStatus(), handTracking: tracking, configurationStore: FakeConfigurationStore(), applicationLauncher: FakeApplicationLauncher())

        #expect(!model.isRecognitionActive)
        #expect(tracking.startCount == 0)
    }

    @Test func startingRecognitionTurnsOnTheCamera() async {
        let tracking = FakeHandTracking()
        let model = AppModel(permissions: FakePermissionStatus(cameraAccess: .authorized), handTracking: tracking, configurationStore: FakeConfigurationStore(), applicationLauncher: FakeApplicationLauncher())

        await model.toggleRecognition()

        #expect(model.isRecognitionActive)
        #expect(tracking.isRunning)
    }

    @Test func recognitionClassifiesSamplesAndAdvancesTheSafetyGate() async {
        let tracking = FakeHandTracking()
        let model = AppModel(permissions: FakePermissionStatus(cameraAccess: .authorized), handTracking: tracking, configurationStore: FakeConfigurationStore(), applicationLauncher: FakeApplicationLauncher())

        await model.toggleRecognition()
        for index in 0...20 {
            tracking.send(HandFixture().sample(.fist, at: 1 + Double(index) / 32))
            await Task.yield()
        }
        await allowSampleTaskToRun()

        #expect(model.latestClassification?.pose == .fist)
        #expect(model.gesturePhase.stage == .armed)
    }

    @Test func diagnosticsClassifySamplesWithoutAdvancingTheSafetyGate() async {
        let tracking = FakeHandTracking()
        let model = AppModel(permissions: FakePermissionStatus(cameraAccess: .authorized), handTracking: tracking, configurationStore: FakeConfigurationStore(), applicationLauncher: FakeApplicationLauncher())

        await model.setDiagnosticsActive(true)
        tracking.send(HandFixture().sample(.fiveFingers, at: 1))
        await allowSampleTaskToRun()

        #expect(model.latestClassification?.pose == .fiveFingers)
        #expect(model.lastDetectedPose?.gesture == .fiveFingers)
        #expect(model.lastAcceptedCommand == nil)
        #expect(model.acceptedCommandCount == 0)
        #expect(model.gesturePhase == .listening(wakeProgress: 0))
    }

    @Test func detectedPoseRemainsAfterHandLeavesViewAndCaptureStops() async {
        let tracking = FakeHandTracking()
        let model = AppModel(permissions: FakePermissionStatus(cameraAccess: .authorized), handTracking: tracking, configurationStore: FakeConfigurationStore(), applicationLauncher: FakeApplicationLauncher())

        await model.setDiagnosticsActive(true)
        tracking.send(HandFixture().sample(.oneFinger, at: 1))
        await allowSampleTaskToRun()
        let detection = model.lastDetectedPose
        #expect(detection?.gesture == .oneFinger)

        tracking.send(HandPoseSample(timestamp: 2, hand: nil))
        await allowSampleTaskToRun()
        #expect(model.latestClassification == nil)
        #expect(model.lastDetectedPose == detection)

        await model.setDiagnosticsActive(false)
        #expect(model.latestHandPose == nil)
        #expect(model.lastDetectedPose == detection)
        #expect(model.lastAcceptedCommand == nil)
    }

    @Test func fingerPoseWithoutWakeIsSeenButNeverCountedAsACommand() async {
        let tracking = FakeHandTracking()
        let model = AppModel(permissions: FakePermissionStatus(cameraAccess: .authorized), handTracking: tracking, configurationStore: FakeConfigurationStore(), applicationLauncher: FakeApplicationLauncher())

        await model.toggleRecognition()
        for index in 0...40 {
            tracking.send(HandFixture().sample(.oneFinger, at: 1 + Double(index) / 32))
        }
        await allowSampleTaskToRun()

        #expect(model.lastDetectedPose?.gesture == .oneFinger)
        #expect(model.lastAcceptedCommand == nil)
        #expect(model.acceptedCommandCount == 0)
    }

    @Test func acceptedCommandIsCountedOnceAndRemainsAfterReleaseAndRestart() async {
        let tracking = FakeHandTracking()
        let permissions = FakePermissionStatus(cameraAccess: .authorized)
        let model = AppModel(permissions: permissions, handTracking: tracking, configurationStore: FakeConfigurationStore(), applicationLauncher: FakeApplicationLauncher())

        await model.toggleRecognition()
        for index in 0...20 {
            tracking.send(HandFixture().sample(.fist, at: 1 + Double(index) / 32))
        }
        for index in 21...110 {
            tracking.send(HandFixture().sample(.oneFinger, at: 1 + Double(index) / 32))
        }
        await allowSampleTaskToRun()
        let accepted = model.lastAcceptedCommand
        #expect(accepted?.gesture == .oneFinger)
        #expect(model.acceptedCommandCount == 1)

        for index in 111...130 {
            tracking.send(HandPoseSample(timestamp: 1 + Double(index) / 32, hand: nil))
        }
        await allowSampleTaskToRun()
        #expect(model.gesturePhase == .listening(wakeProgress: 0))
        #expect(model.lastAcceptedCommand == accepted)
        #expect(model.acceptedCommandCount == 1)

        await model.toggleRecognition()
        await model.toggleRecognition()
        #expect(model.lastAcceptedCommand == accepted)
        #expect(model.acceptedCommandCount == 1)

        for index in 0...20 {
            tracking.send(HandFixture().sample(.fist, at: 10 + Double(index) / 32))
        }
        for index in 21...40 {
            tracking.send(HandFixture().sample(.twoFingers, at: 10 + Double(index) / 32))
        }
        await allowSampleTaskToRun()
        #expect(model.lastAcceptedCommand?.gesture == .twoFingers)
        #expect(model.acceptedCommandCount == 2)

        let freshModel = AppModel(permissions: permissions, handTracking: FakeHandTracking(), configurationStore: FakeConfigurationStore(), applicationLauncher: FakeApplicationLauncher())
        #expect(freshModel.lastDetectedPose == nil)
        #expect(freshModel.lastAcceptedCommand == nil)
        #expect(freshModel.acceptedCommandCount == 0)
    }

    @Test func stoppingRecognitionResetsTheSafetyGateAndClearsSamples() async {
        let tracking = FakeHandTracking()
        let model = AppModel(permissions: FakePermissionStatus(cameraAccess: .authorized), handTracking: tracking, configurationStore: FakeConfigurationStore(), applicationLauncher: FakeApplicationLauncher())

        await model.toggleRecognition()
        for index in 0...20 {
            tracking.send(HandFixture().sample(.fist, at: 1 + Double(index) / 32))
            await Task.yield()
        }
        await allowSampleTaskToRun()
        #expect(model.gesturePhase.stage == .armed)

        await model.toggleRecognition()

        #expect(model.gesturePhase == .listening(wakeProgress: 0))
        #expect(model.latestHandPose == nil)
        #expect(model.latestClassification == nil)
    }

    @Test func stoppingRecognitionTurnsOffTheCamera() async {
        let tracking = FakeHandTracking()
        let model = AppModel(permissions: FakePermissionStatus(cameraAccess: .authorized), handTracking: tracking, configurationStore: FakeConfigurationStore(), applicationLauncher: FakeApplicationLauncher())

        await model.toggleRecognition()
        await model.toggleRecognition()

        #expect(!model.isRecognitionActive)
        #expect(!tracking.isRunning)
    }

    @Test func firstStartAsksForCameraAccess() async {
        let permissions = FakePermissionStatus(cameraAccess: .notDetermined, cameraPromptAnswer: .authorized)
        let tracking = FakeHandTracking()
        let model = AppModel(permissions: permissions, handTracking: tracking, configurationStore: FakeConfigurationStore(), applicationLauncher: FakeApplicationLauncher())

        await model.toggleRecognition()

        #expect(permissions.cameraPromptCount == 1)
        #expect(model.cameraAccess == .authorized)
        #expect(tracking.isRunning)
    }

    @Test func recognitionStaysOffWhenCameraAccessIsDenied() async {
        let permissions = FakePermissionStatus(cameraAccess: .notDetermined, cameraPromptAnswer: .denied)
        let tracking = FakeHandTracking()
        let model = AppModel(permissions: permissions, handTracking: tracking, configurationStore: FakeConfigurationStore(), applicationLauncher: FakeApplicationLauncher())

        await model.toggleRecognition()

        #expect(!model.isRecognitionActive)
        #expect(model.cameraAccess == .denied)
        #expect(tracking.startCount == 0)
    }

    @Test func diagnosticsKeepTheCameraOnAfterRecognitionStops() async {
        let tracking = FakeHandTracking()
        let model = AppModel(permissions: FakePermissionStatus(cameraAccess: .authorized), handTracking: tracking, configurationStore: FakeConfigurationStore(), applicationLauncher: FakeApplicationLauncher())

        await model.toggleRecognition()
        await model.setDiagnosticsActive(true)
        await model.toggleRecognition()
        #expect(tracking.isRunning)

        await model.setDiagnosticsActive(false)
        #expect(!tracking.isRunning)
    }

    @Test func cameraFailureTurnsRecognitionOffAndExplainsWhy() async {
        let tracking = FakeHandTracking()
        tracking.startError = .noCamera
        let model = AppModel(permissions: FakePermissionStatus(cameraAccess: .authorized), handTracking: tracking, configurationStore: FakeConfigurationStore(), applicationLauncher: FakeApplicationLauncher())

        await model.toggleRecognition()

        #expect(!model.isRecognitionActive)
        #expect(model.cameraError == .noCamera)
        #expect(!tracking.isRunning)
    }

    @Test func readsPermissionsAtLaunch() {
        let permissions = FakePermissionStatus(cameraAccess: .denied, accessibilityAccess: .allowed)

        let model = AppModel(permissions: permissions, handTracking: FakeHandTracking(), configurationStore: FakeConfigurationStore(), applicationLauncher: FakeApplicationLauncher())

        #expect(model.cameraAccess == .denied)
        #expect(model.accessibilityAccess == .allowed)
    }

    @Test func refreshesPermissionsWhenAMenuOpens() {
        let permissions = FakePermissionStatus()
        let model = AppModel(permissions: permissions, handTracking: FakeHandTracking(), configurationStore: FakeConfigurationStore(), applicationLauncher: FakeApplicationLauncher())
        permissions.cameraAccess = .authorized
        permissions.accessibilityAccess = .allowed

        NotificationCenter.default.post(name: NSMenu.didBeginTrackingNotification, object: NSMenu())

        #expect(model.cameraAccess == .authorized)
        #expect(model.accessibilityAccess == .allowed)
    }

    @Test func swipeRightCyclesToTheNextApplication() async {
        let tracking = FakeHandTracking()
        let actions = FakeSystemActionExecutor()
        let model = AppModel(
            permissions: FakePermissionStatus(cameraAccess: .authorized, accessibilityAccess: .allowed),
            handTracking: tracking,
            configurationStore: FakeConfigurationStore(),
            applicationLauncher: FakeApplicationLauncher(),
            systemActionExecutor: actions
        )

        await model.toggleRecognition()
        tracking.send(HandFixture(wrist: SIMD2(0.70, 0.5)).sample(.fiveFingers, at: 1))
        tracking.send(HandFixture(wrist: SIMD2(0.40, 0.5)).sample(.fiveFingers, at: 1.15))
        await allowSampleTaskToRun()

        #expect(actions.actions == [.nextApplication])
        #expect(model.lastMotionGesture?.gesture == .swipeRight)
        #expect(model.systemActionStatus == .performed(.swipeRight))
    }

    @Test func pinchClosesTheActiveTabOrWindow() async {
        let tracking = FakeHandTracking()
        let actions = FakeSystemActionExecutor()
        let model = AppModel(
            permissions: FakePermissionStatus(cameraAccess: .authorized, accessibilityAccess: .allowed),
            handTracking: tracking,
            configurationStore: FakeConfigurationStore(),
            applicationLauncher: FakeApplicationLauncher(),
            systemActionExecutor: actions
        )

        await model.toggleRecognition()
        tracking.send(pinchSample(at: 1))
        tracking.send(pinchSample(at: 1.10))
        await allowSampleTaskToRun()

        #expect(actions.actions == [.closeCurrentTabOrWindow])
        #expect(model.lastMotionGesture?.gesture == .pinch)
    }

    @Test func aSwipeCancelsAQuickStaticCommandWhileItIsMoving() async {
        let store = FakeConfigurationStore()
        store.configuration.activationMode = .quick
        let tracking = FakeHandTracking()
        let actions = FakeSystemActionExecutor()
        let model = AppModel(
            permissions: FakePermissionStatus(cameraAccess: .authorized, accessibilityAccess: .allowed),
            handTracking: tracking,
            configurationStore: store,
            applicationLauncher: FakeApplicationLauncher(),
            systemActionExecutor: actions
        )

        await model.toggleRecognition()
        tracking.send(HandFixture(wrist: SIMD2(0.70, 0.5)).sample(.fiveFingers, at: 1))
        tracking.send(HandFixture(wrist: SIMD2(0.40, 0.5)).sample(.fiveFingers, at: 1.15))
        await allowSampleTaskToRun()

        #expect(model.acceptedCommandCount == 0)
        #expect(actions.actions == [.nextApplication])
    }

    @Test func motionGesturesWaitForRecognitionInsteadOfDiagnostics() async {
        let tracking = FakeHandTracking()
        let actions = FakeSystemActionExecutor()
        let model = AppModel(
            permissions: FakePermissionStatus(cameraAccess: .authorized, accessibilityAccess: .allowed),
            handTracking: tracking,
            configurationStore: FakeConfigurationStore(),
            applicationLauncher: FakeApplicationLauncher(),
            systemActionExecutor: actions
        )

        await model.setDiagnosticsActive(true)
        tracking.send(HandFixture(wrist: SIMD2(0.70, 0.5)).sample(.fiveFingers, at: 1))
        tracking.send(HandFixture(wrist: SIMD2(0.40, 0.5)).sample(.fiveFingers, at: 1.15))
        await allowSampleTaskToRun()

        #expect(actions.actions.isEmpty)
        #expect(model.lastMotionGesture == nil)
    }

    private func pinchSample(at timestamp: Double) -> HandPoseSample {
        let fixture = HandFixture()
        var hand = fixture.hand(.oneFinger)
        let index = hand.joints[.indexTip]!
        hand.joints[.thumbTip] = HandJointPosition(x: index.x + 0.02 * fixture.scale, y: index.y, confidence: 0.9)
        return HandPoseSample(timestamp: timestamp, hand: hand, imageAspectRatio: fixture.imageAspectRatio)
    }
}

private func allowSampleTaskToRun() async {
    for _ in 0..<8 {
        await Task.yield()
    }
    try? await Task.sleep(for: .milliseconds(5))
}

private enum AppModelPhaseStage {
    case listening, armed, cooldown
}

private extension GestureGatePhase {
    var stage: AppModelPhaseStage {
        switch self {
        case .listening: .listening
        case .armed: .armed
        case .cooldown: .cooldown
        }
    }
}
