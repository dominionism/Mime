import SwiftUI

struct SettingsView: View {
    let model: AppModel

    var body: some View {
        Form {
            Section("Recognition") {
                LabeledContent("Status", value: model.isRecognitionActive ? "On" : "Off")
            }

            Section("Hand Tracking") {
                Toggle("Show hand tracking", isOn: diagnosticsBinding)
                if let cameraError = model.cameraError {
                    Text(cameraError.message)
                        .foregroundStyle(.red)
                }
                HandTrackingDiagnosticsView(
                    isActive: model.isDiagnosticsActive,
                    sample: model.latestHandPose,
                    framesPerSecond: model.trackingFramesPerSecond
                )
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
        .onDisappear {
            // Closing Settings must never leave the camera running just for the preview.
            Task { await model.setDiagnosticsActive(false) }
        }
    }

    private var diagnosticsBinding: Binding<Bool> {
        Binding(
            get: { model.isDiagnosticsActive },
            set: { isOn in
                Task { await model.setDiagnosticsActive(isOn) }
            }
        )
    }
}
