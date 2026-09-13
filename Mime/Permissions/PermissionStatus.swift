import ApplicationServices
import AVFoundation

/// Whether macOS privacy settings let Mime use the camera.
enum CameraAccess: Equatable {
    case notDetermined
    case authorized
    case denied
    case restricted

    init(_ status: AVAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .notDetermined
        case .authorized: self = .authorized
        case .denied: self = .denied
        case .restricted: self = .restricted
        @unknown default: self = .denied
        }
    }

    var label: String {
        switch self {
        case .notDetermined: "Not requested"
        case .authorized: "Allowed"
        case .denied: "Denied"
        case .restricted: "Restricted"
        }
    }
}

/// Whether macOS trusts Mime to post input events through the Accessibility API.
enum AccessibilityAccess: Equatable {
    case allowed
    case notAllowed

    init(isTrusted: Bool) {
        self = isTrusted ? .allowed : .notAllowed
    }

    var label: String {
        switch self {
        case .allowed: "Allowed"
        case .notAllowed: "Not allowed"
        }
    }
}

/// Reads permission state, and asks for camera access when the user has never been asked.
@MainActor
protocol PermissionStatusProviding {
    var cameraAccess: CameraAccess { get }
    var accessibilityAccess: AccessibilityAccess { get }
    func requestCameraAccess() async -> CameraAccess
}

struct SystemPermissionStatus: PermissionStatusProviding {
    private let camera = CameraPermissionController()

    var cameraAccess: CameraAccess {
        camera.access
    }

    var accessibilityAccess: AccessibilityAccess {
        AccessibilityAccess(isTrusted: AXIsProcessTrusted())
    }

    func requestCameraAccess() async -> CameraAccess {
        await camera.requestAccessIfNeeded()
    }
}
