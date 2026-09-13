import AVFoundation
import Testing
@testable import Mime

struct PermissionStatusTests {
    @Test(arguments: [
        (AVAuthorizationStatus.notDetermined, CameraAccess.notDetermined),
        (.authorized, .authorized),
        (.denied, .denied),
        (.restricted, .restricted),
    ])
    func mapsCameraAuthorizationStatus(status: AVAuthorizationStatus, expected: CameraAccess) {
        #expect(CameraAccess(status) == expected)
    }

    @Test func mapsAccessibilityTrust() {
        #expect(AccessibilityAccess(isTrusted: true) == .allowed)
        #expect(AccessibilityAccess(isTrusted: false) == .notAllowed)
    }
}
