import SwiftUI

@main
struct MimeApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra("Mime", systemImage: model.isRecognitionActive ? "hand.raised.fill" : "hand.raised") {
            MenuBarContentView(model: model)
        }

        Settings {
            SettingsView(model: model)
        }
    }
}
