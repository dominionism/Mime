import AppKit
import Testing
@testable import Mime

@MainActor
struct AppModelTests {
    @Test func recognitionStartsOff() {
        let tracking = FakeHandTracking()
        let model = AppModel(permissions: FakePermissionStatus(), handTracking: tracking)

        #expect(!model.isRecognitionActive)
        #expect(tracking.startCount == 0)
    }

    @Test func startingRecognitionTurnsOnTheCamera() async {
        let tracking = FakeHandTracking()
        let model = AppModel(permissions: FakePermissionStatus(cameraAccess: .authorized), handTracking: tracking)

        await model.toggleRecognition()

        #expect(model.isRecognitionActive)
        #expect(tracking.isRunning)
    }

    @Test func recognitionClassifiesSamplesAndAdvancesTheSafetyGate() async {
        let tracking = FakeHandTracking()
        let model = AppModel(permissions: FakePermissionStatus(cameraAccess: .authorized), handTracking: tracking)

        await model.toggleRecognition()
        for index in 0...20 {
            tracking.send(HandFixture().sample(.openPalm, at: 1 + Double(index) / 32))
            await Task.yield()
        }
        await allowSampleTaskToRun()

        #expect(model.latestClassification?.pose == .openPalm)
        #expect(model.gesturePhase.stage == .armed)
    }

    @Test func diagnosticsClassifySamplesWithoutAdvancingTheSafetyGate() async {
        let tracking = FakeHandTracking()
        let model = AppModel(permissions: FakePermissionStatus(cameraAccess: .authorized), handTracking: tracking)

        await model.setDiagnosticsActive(true)
        tracking.send(HandFixture().sample(.openPalm, at: 1))
        await allowSampleTaskToRun()

        #expect(model.latestClassification?.pose == .openPalm)
        #expect(model.gesturePhase == .listening(wakeProgress: 0))
    }

    @Test func stoppingRecognitionResetsTheSafetyGateAndClearsSamples() async {
        let tracking = FakeHandTracking()
        let model = AppModel(permissions: FakePermissionStatus(cameraAccess: .authorized), handTracking: tracking)

        await model.toggleRecognition()
        for index in 0...20 {
            tracking.send(HandFixture().sample(.openPalm, at: 1 + Double(index) / 32))
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
        let model = AppModel(permissions: FakePermissionStatus(cameraAccess: .authorized), handTracking: tracking)

        await model.toggleRecognition()
        await model.toggleRecognition()

        #expect(!model.isRecognitionActive)
        #expect(!tracking.isRunning)
    }

    @Test func firstStartAsksForCameraAccess() async {
        let permissions = FakePermissionStatus(cameraAccess: .notDetermined, cameraPromptAnswer: .authorized)
        let tracking = FakeHandTracking()
        let model = AppModel(permissions: permissions, handTracking: tracking)

        await model.toggleRecognition()

        #expect(permissions.cameraPromptCount == 1)
        #expect(model.cameraAccess == .authorized)
        #expect(tracking.isRunning)
    }

    @Test func recognitionStaysOffWhenCameraAccessIsDenied() async {
        let permissions = FakePermissionStatus(cameraAccess: .notDetermined, cameraPromptAnswer: .denied)
        let tracking = FakeHandTracking()
        let model = AppModel(permissions: permissions, handTracking: tracking)

        await model.toggleRecognition()

        #expect(!model.isRecognitionActive)
        #expect(model.cameraAccess == .denied)
        #expect(tracking.startCount == 0)
    }

    @Test func diagnosticsKeepTheCameraOnAfterRecognitionStops() async {
        let tracking = FakeHandTracking()
        let model = AppModel(permissions: FakePermissionStatus(cameraAccess: .authorized), handTracking: tracking)

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
        let model = AppModel(permissions: FakePermissionStatus(cameraAccess: .authorized), handTracking: tracking)

        await model.toggleRecognition()

        #expect(!model.isRecognitionActive)
        #expect(model.cameraError == .noCamera)
        #expect(!tracking.isRunning)
    }

    @Test func readsPermissionsAtLaunch() {
        let permissions = FakePermissionStatus(cameraAccess: .denied, accessibilityAccess: .allowed)

        let model = AppModel(permissions: permissions, handTracking: FakeHandTracking())

        #expect(model.cameraAccess == .denied)
        #expect(model.accessibilityAccess == .allowed)
    }

    @Test func refreshesPermissionsWhenAMenuOpens() {
        let permissions = FakePermissionStatus()
        let model = AppModel(permissions: permissions, handTracking: FakeHandTracking())
        permissions.cameraAccess = .authorized
        permissions.accessibilityAccess = .allowed

        NotificationCenter.default.post(name: NSMenu.didBeginTrackingNotification, object: NSMenu())

        #expect(model.cameraAccess == .authorized)
        #expect(model.accessibilityAccess == .allowed)
    }
}

private func allowSampleTaskToRun() async {
    for _ in 0..<8 {
        await Task.yield()
    }
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
