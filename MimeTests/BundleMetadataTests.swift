import Foundation
import Testing

/// Unit tests run inside Mime.app, so `Bundle.main` is the built app bundle.
struct BundleMetadataTests {
    @Test func usesStableBundleIdentifier() {
        #expect(Bundle.main.bundleIdentifier == "com.dominionism.Mime")
    }

    @Test func runsAsMenuBarOnlyApp() {
        #expect(infoValue("LSUIElement") as? Bool == true)
    }

    @Test func explainsCameraUse() {
        let description = infoValue("NSCameraUsageDescription") as? String

        #expect(description?.isEmpty == false)
    }

    @Test func turnsOffSystemReactionGesturesInCameraFeed() {
        #expect(infoValue("NSCameraReactionEffectGesturesEnabledDefault") as? Bool == false)
    }

    private func infoValue(_ key: String) -> Any? {
        Bundle.main.object(forInfoDictionaryKey: key)
    }
}
