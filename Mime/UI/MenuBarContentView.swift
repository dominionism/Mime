import AppKit
import SwiftUI

struct MenuBarContentView: View {
    let model: AppModel

    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button(model.isRecognitionActive ? "Stop Recognition" : "Start Recognition") {
            Task { await model.toggleRecognition() }
        }

        Divider()

        Text("Camera: \(model.cameraAccess.label)")
        if let cameraError = model.cameraError {
            Text(cameraError.message)
        }
        if model.cameraAccess == .denied {
            Button("Open Camera Privacy Settings…") {
                NSWorkspace.shared.open(CameraPermissionController.privacySettingsURL)
            }
        }
        Text("Accessibility: \(model.accessibilityAccess.label)")
        if model.accessibilityAccess == .notAllowed {
            Button("Open Accessibility Settings…") {
                AccessibilityPermissionController.requestAccessPrompt()
                NSWorkspace.shared.open(AccessibilityPermissionController.privacySettingsURL)
            }
        }

        Divider()

        Button("Settings…") {
            // Mime has no Dock icon, so bring it forward or Settings opens behind other apps.
            NSApp.activate()
            openSettings()
        }
        .keyboardShortcut(",")

        Button("Quit Mime") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
