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
