import SwiftUI

struct SettingsView: View {
    let model: AppModel

    var body: some View {
        Form {
            Section("Recognition") {
                LabeledContent("Status", value: model.isRecognitionActive ? "On" : "Off")
                if model.isRecognitionActive {
                    Text(recognitionGuidance)
                        .font(.callout)
                }
                GestureResultRow("Last pose seen", detection: model.lastDetectedPose)
                GestureResultRow("Last command accepted", detection: model.lastAcceptedCommand)
                LabeledContent("Commands accepted", value: "\(model.acceptedCommandCount)")
                Text("A pose is what the camera recognized. A command is accepted after the closed-fist wake and a held finger count. Results stay here until you quit Mime.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Gesture speed") {
                Picker("Activation", selection: activationModeBinding) {
                    ForEach(GestureActivationMode.allCases, id: \.self) { mode in
                        Text(mode.name).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
                Text(model.activationMode.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if model.activationMode == .quick {
                    Label("Quick mode may open an app when you casually hold up a finger count.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            ApplicationBindingsView(model: model)

            Section("Hand Tracking") {
                Toggle("Show hand tracking", isOn: diagnosticsBinding)
                if let cameraError = model.cameraError {
                    Text(cameraError.message)
                        .foregroundStyle(.red)
                }
                HandTrackingDiagnosticsView(
                    isActive: model.isDiagnosticsActive,
                    sample: model.latestHandPose,
                    classification: model.latestClassification,
                    framesPerSecond: model.trackingFramesPerSecond
                )
            }

            Section("Permissions") {
                LabeledContent("Camera", value: model.cameraAccess.label)
                LabeledContent("Accessibility", value: model.accessibilityAccess.label)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 680)
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

    private var activationModeBinding: Binding<GestureActivationMode> {
        Binding(
            get: { model.activationMode },
            set: { model.setActivationMode($0) }
        )
    }

    private var recognitionGuidance: String {
        if model.isEditingBindings {
            return "Recognition is paused while you choose an app."
        }
        if model.activationMode == .quick {
            switch model.gesturePhase {
            case .listening(let progress):
                return progress > 0 ? "Keep holding the finger count…" : "Show 1–5 fingers to launch directly."
            default: break
            }
        }
        switch model.gesturePhase {
        case .listening(let progress):
            return progress > 0 ? "Keep holding your closed fist…" : "Hold a closed fist to wake Mime."
        case .armed:
            return "Ready: show 1–5 fingers and hold briefly."
        case .cooldown(let command, _):
            return "Accepted \(command.name). You can lower your hand."
        }
    }
}

private struct GestureResultRow: View {
    let title: String
    let detection: GestureDetection?

    init(_ title: String, detection: GestureDetection?) {
        self.title = title
        self.detection = detection
    }

    var body: some View {
        LabeledContent(title) {
            if let detection {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(detection.gesture.emoji) \(detection.gesture.name)")
                    Text(detection.detectedAt, format: .dateTime.hour().minute().second())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("None yet")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
