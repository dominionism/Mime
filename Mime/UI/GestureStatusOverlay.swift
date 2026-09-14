import AppKit
import SwiftUI

/// Owns the recognition HUD without making `AppModel` responsible for creating windows.
///
/// The panel is created only when recognition starts (or an error needs to be shown), so model-only tests never create
/// an AppKit window. It is nonactivating and ignores mouse input, leaving the current app in control.
@MainActor
final class GestureStatusOverlayController {
    private weak var model: AppModel?
    private var panel: NSPanel?
    private var hostingView: NSHostingView<GestureStatusHUD>?
    private var errorDismissTask: Task<Void, Never>?
    private var visibleError: String?
    private var reportedError: String?

    init(model: AppModel) {
        self.model = model
        observeModel()
    }

    isolated deinit {
        errorDismissTask?.cancel()
        panel?.orderOut(nil)
    }

    private func observeModel() {
        guard let model else { return }

        withObservationTracking {
            _ = model.isRecognitionActive
            _ = model.gesturePhase
            _ = model.cameraError
            _ = model.latestClassification
            _ = model.lastAcceptedCommand
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.refresh()
                self?.observeModel()
            }
        }

        refresh()
    }

    private func refresh() {
        guard let model else {
            hidePanel()
            return
        }

        if let cameraError = model.cameraError {
            if reportedError != cameraError.message {
                reportedError = cameraError.message
                showError(cameraError.message)
            }
        } else {
            reportedError = nil
        }

        guard model.isRecognitionActive || visibleError != nil else {
            hidePanel()
            return
        }

        let panel = makePanelIfNeeded(for: model)
        hostingView?.rootView = GestureStatusHUD(model: model, errorMessage: visibleError)
        position(panel)
        panel.orderFrontRegardless()
    }

    private func showError(_ message: String) {
        guard visibleError != message else { return }
        visibleError = message
        errorDismissTask?.cancel()
        errorDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.visibleError = nil
            self?.refresh()
        }
    }

    private func makePanelIfNeeded(for model: AppModel) -> NSPanel {
        if let panel { return panel }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 70),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = true
        panel.contentView = NSHostingView(rootView: GestureStatusHUD(model: model, errorMessage: visibleError))
        hostingView = panel.contentView as? NSHostingView<GestureStatusHUD>
        self.panel = panel
        return panel
    }

    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.screens.first else { return }
        let visibleFrame = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(
            NSPoint(x: visibleFrame.midX - size.width / 2, y: visibleFrame.maxY - size.height - 28)
        )
    }

    private func hidePanel() {
        panel?.orderOut(nil)
    }
}

/// Compact, click-through recognition state shown above the primary display.
struct GestureStatusHUD: View {
    let model: AppModel
    let errorMessage: String?

    var body: some View {
        HStack(spacing: 10) {
            Text(icon)
                .font(.system(size: 27))
                .frame(width: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(width: 320, height: 70)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.primary.opacity(0.12))
        }
        .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
        .padding(4)
    }

    private var icon: String {
        if errorMessage != nil { return "⚠️" }
        switch model.gesturePhase {
        case .listening: return "✊"
        case .armed(_, let candidate, _): return candidate?.emoji ?? "✊"
        case .cooldown(let command, _): return command.emoji
        }
    }

    private var title: String {
        if errorMessage != nil { return "Camera unavailable" }
        switch model.gesturePhase {
        case .listening(let progress):
            return progress > 0 ? "Hold closed fist…" : "Listening for wake"
        case .armed(_, let candidate, _):
            return candidate.map { "Ready for \($0.name)" } ?? "Ready for a command"
        case .cooldown(let command, let secondsLeft):
            return secondsLeft > 0 ? "Recognized \(command.name)" : "Release \(command.name)"
        }
    }

    private var detail: String {
        if let errorMessage { return errorMessage }
        switch model.gesturePhase {
        case .listening(let progress):
            if progress > 0 {
                return "\(Int((progress * 100).rounded()))% · keep holding"
            }
            if let result = model.lastAcceptedCommand {
                return "Last: \(result.gesture.name) · ✊ to wake"
            }
            return "Hold ✊ for 0.6 seconds"
        case .armed(let secondsLeft, let candidate, let progress):
            let countdown = "\(Int(ceil(secondsLeft)))s left"
            if let candidate {
                return "\(candidate.emoji) \(Int((progress * 100).rounded()))% · \(countdown)"
            }
            return "Show 1–5 fingers · \(countdown)"
        case .cooldown(let command, let secondsLeft):
            if secondsLeft > 0 {
                return "Release \(command.name) · \(Int(ceil(secondsLeft)))s cooldown"
            }
            return "Release fully to listen again"
        }
    }
}
