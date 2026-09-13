import SwiftUI

@main
struct MimeApp: App {
    @State private var model: AppModel
    private let gestureOverlay: GestureStatusOverlayController

    init() {
        let model = AppModel()
        _model = State(initialValue: model)
        gestureOverlay = GestureStatusOverlayController(model: model)
    }

    var body: some Scene {
        MenuBarExtra("Mime", systemImage: model.isRecognitionActive ? "hand.raised.fill" : "hand.raised") {
            MenuBarContentView(model: model)
        }

        Settings {
            SettingsView(model: model)
        }
    }
}
