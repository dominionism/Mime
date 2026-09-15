import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Assigns apps to command gestures and keeps the last launch result available after the HUD disappears.
struct ApplicationBindingsView: View {
    let model: AppModel

    @State private var applicationPanel: NSOpenPanel?
    @State private var selectionError: String?
    @State private var isConfirmingReset = false

    var body: some View {
        Section("Open Apps") {
            Text(model.activationMode == .quick
                 ? "Choose an app for each finger count, then show that many fingers. Any combination counts, including your thumb."
                 : "Choose an app for each finger count. Hold a closed fist to wake Mime, then show that many fingers.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(GestureID.commands, id: \.rawValue) { gesture in
                applicationRow(for: gesture)
            }

            if model.isEditingBindings {
                Label("Recognition is paused while you choose an app.", systemImage: "pause.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let configurationError = model.configurationError {
                Text(configurationError)
                    .font(.callout)
                    .foregroundStyle(.red)

                if !model.canEditBindings {
                    HStack {
                        Button("Retry Loading") { model.reloadConfiguration() }
                        Button("Reset Mappings…", role: .destructive) {
                            isConfirmingReset = true
                        }
                    }
                }
            }

            if let selectionError {
                Text(selectionError)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            LabeledContent("Last app action") {
                launchResult
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
            }
        }
        .confirmationDialog("Reset all app mappings?", isPresented: $isConfirmingReset) {
            Button("Reset Mappings", role: .destructive) { model.resetConfiguration() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes the saved mappings. You can choose apps again afterward.")
        }
    }

    private func applicationRow(for gesture: GestureID) -> some View {
        let application = model.configuration.application(for: gesture)

        return HStack(spacing: 10) {
            Text(gesture.emoji)
                .font(.title3)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(gesture.name)
                Text(application?.name ?? "No app assigned")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            Button(application == nil ? "Choose…" : "Change…") {
                chooseApplication(for: gesture)
            }
            .accessibilityLabel("Choose app for \(gesture.name)")

            if application != nil {
                Button(role: .destructive) {
                    selectionError = nil
                    model.setApplication(nil, for: gesture)
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .help("Remove app for \(gesture.name)")
                .accessibilityLabel("Remove app for \(gesture.name)")
            }
        }
        .padding(.vertical, 3)
        .disabled(!model.canEditBindings || model.isEditingBindings)
    }

    @ViewBuilder
    private var launchResult: some View {
        switch model.applicationLaunchStatus {
        case .idle:
            Text("None yet")
                .foregroundStyle(.secondary)
        case .opening(let application):
            Text("Opening \(application.name)…")
        case .opened(let application):
            Text("Opened \(application.name)")
        case .failed(let application, let message):
            VStack(alignment: .trailing, spacing: 3) {
                Text("Couldn’t open \(application.name)")
                Text(message)
                    .font(.caption)
            }
            .foregroundStyle(.red)
        case .unassigned(let gesture):
            Text("No app assigned to \(gesture.name.lowercased())")
                .foregroundStyle(.secondary)
        }
    }

    private func chooseApplication(for gesture: GestureID) {
        guard model.canEditBindings, applicationPanel == nil else { return }
        selectionError = nil
        model.beginEditingBindings()

        let panel = NSOpenPanel()
        panel.title = "Choose an app for \(gesture.name.lowercased())"
        panel.prompt = "Choose App"
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        applicationPanel = panel

        panel.begin { response in
            Task { @MainActor in
                defer {
                    model.endEditingBindings()
                    applicationPanel = nil
                }
                guard response == .OK, let url = panel.url else { return }
                do {
                    let application = try ApplicationTarget.fromApplication(at: url)
                    model.setApplication(application, for: gesture)
                } catch {
                    selectionError = error.localizedDescription
                }
            }
        }
    }
}
