import AppKit
import SwiftUI

struct MenuBarContentView: View {
    let model: AppModel

    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button(model.isRecognitionActive ? "Stop Recognition" : "Start Recognition") {
            model.toggleRecognition()
        }

        Divider()

        Text("Camera: \(model.cameraAccess.label)")
        Text("Accessibility: \(model.accessibilityAccess.label)")

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
