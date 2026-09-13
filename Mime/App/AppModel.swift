import AppKit
import Observation

/// Composition root and shared state for the menu bar and Settings window.
@MainActor
@Observable
final class AppModel {
    private(set) var isRecognitionActive = false
    private(set) var cameraAccess: CameraAccess
    private(set) var accessibilityAccess: AccessibilityAccess

    @ObservationIgnored private let permissions: any PermissionStatusProviding
    @ObservationIgnored private var menuTrackingObserver: (any NSObjectProtocol)?

    init(permissions: any PermissionStatusProviding = SystemPermissionStatus()) {
        self.permissions = permissions
        cameraAccess = permissions.cameraAccess
        accessibilityAccess = permissions.accessibilityAccess

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
        if let menuTrackingObserver {
            NotificationCenter.default.removeObserver(menuTrackingObserver)
        }
    }

    func toggleRecognition() {
        isRecognitionActive.toggle()
    }

    func refreshPermissions() {
        cameraAccess = permissions.cameraAccess
        accessibilityAccess = permissions.accessibilityAccess
    }
}
