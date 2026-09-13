import AVFoundation

/// Checks and requests camera access.
///
/// macOS shows its permission prompt only while access is undetermined. After the user answers, access can
/// only be changed in System Settings.
@MainActor
struct CameraPermissionController {
    /// The Camera page in System Settings › Privacy & Security.
    static let privacySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!

    var authorizationStatus: @MainActor () -> AVAuthorizationStatus = {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    var requestSystemAccess: @MainActor () async -> Bool = {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    var access: CameraAccess {
        CameraAccess(authorizationStatus())
    }

    /// Returns the current camera access, asking the user first if they have never been asked.
    func requestAccessIfNeeded() async -> CameraAccess {
        let current = access
        guard current == .notDetermined else { return current }
        return await requestSystemAccess() ? .authorized : .denied
    }
}
