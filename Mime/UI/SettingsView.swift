import SwiftUI

struct SettingsView: View {
    let model: AppModel

    var body: some View {
        Form {
            Section("Recognition") {
                LabeledContent("Status", value: model.isRecognitionActive ? "On" : "Off")
            }

            Section("Permissions") {
                LabeledContent("Camera", value: model.cameraAccess.label)
                LabeledContent("Accessibility", value: model.accessibilityAccess.label)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .onAppear {
            model.refreshPermissions()
        }
    }
}
