import AppKit
import Testing
@testable import Mime

@MainActor
struct AppModelTests {
    @Test func recognitionStartsOff() {
        let model = AppModel(permissions: FakePermissionStatus())

        #expect(!model.isRecognitionActive)
    }

    @Test func toggleRecognitionStartsAndStops() {
        let model = AppModel(permissions: FakePermissionStatus())

        model.toggleRecognition()
        #expect(model.isRecognitionActive)

        model.toggleRecognition()
        #expect(!model.isRecognitionActive)
    }

    @Test func readsPermissionsAtLaunch() {
        let permissions = FakePermissionStatus(cameraAccess: .denied, accessibilityAccess: .allowed)

        let model = AppModel(permissions: permissions)

        #expect(model.cameraAccess == .denied)
        #expect(model.accessibilityAccess == .allowed)
    }

    @Test func refreshesPermissionsWhenAMenuOpens() {
        let permissions = FakePermissionStatus()
        let model = AppModel(permissions: permissions)
        permissions.cameraAccess = .authorized
        permissions.accessibilityAccess = .allowed

        NotificationCenter.default.post(name: NSMenu.didBeginTrackingNotification, object: NSMenu())

        #expect(model.cameraAccess == .authorized)
        #expect(model.accessibilityAccess == .allowed)
    }
}

@MainActor
private final class FakePermissionStatus: PermissionStatusProviding {
    var cameraAccess: CameraAccess
    var accessibilityAccess: AccessibilityAccess

    init(cameraAccess: CameraAccess = .notDetermined, accessibilityAccess: AccessibilityAccess = .notAllowed) {
        self.cameraAccess = cameraAccess
        self.accessibilityAccess = accessibilityAccess
    }
}
