import Foundation
import Testing
@testable import Mime

@MainActor
struct ApplicationBindingTests {
    private let application = ApplicationTarget(
        bundleIdentifier: "com.example.Sample", fallbackURL: URL(fileURLWithPath: "/Applications/Sample.app"), name: "Sample"
    )

    @Test func bindingPersistsAndCanBeRemoved() throws {
        let store = FakeConfigurationStore()
        let model = makeModel(store: store)
        model.setApplication(application, for: .fiveFingers)
        #expect(model.configuration.application(for: .fiveFingers) == application)
        #expect(store.configuration.application(for: .fiveFingers) == application)

        let reopened = makeModel(store: store)
        #expect(reopened.configuration.application(for: .fiveFingers) == application)
        reopened.setApplication(nil, for: .fiveFingers)
        #expect(store.configuration.application(for: .fiveFingers) == nil)
        #expect(store.saveCount == 2)
    }

    @Test func saveFailurePreservesThePreviousBindingAndReportsError() throws {
        let store = FakeConfigurationStore()
        try store.configuration.setApplication(application, for: .fiveFingers)
        let model = makeModel(store: store)
        store.saveError = NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Disk is full"])
        model.setApplication(nil, for: .fiveFingers)
        #expect(model.configuration.application(for: .fiveFingers) == application)
        #expect(model.configurationError == "Disk is full")
    }

    @Test func brokenConfigurationDisablesSavingUntilExplicitRecovery() {
        let store = FakeConfigurationStore()
        store.loadError = NSError(domain: "Test", code: 2)
        let model = makeModel(store: store)
        #expect(!model.canEditBindings)
        model.setApplication(application, for: .fiveFingers)
        #expect(store.saveCount == 0)
        model.resetConfiguration()
        #expect(model.canEditBindings)
        #expect(model.configurationError == nil)
    }

    @Test func wakeAndHeldCommandOpenTheBoundAppOnce() async throws {
        let (model, tracking, launcher) = try boundModel()
        await model.toggleRecognition()
        sendSequence(tracking)
        for index in 41...150 {
            tracking.send(HandFixture().sample(.fiveFingers, at: 1 + Double(index) / 32))
        }
        await drain()
        #expect(model.acceptedCommandCount == 1)
        #expect(launcher.applications == [application])
        #expect(model.applicationLaunchStatus == .opened(application))
    }

    @Test func commandWithoutWakeAndDiagnosticsOnlyNeverLaunchApps() async throws {
        let (model, tracking, launcher) = try boundModel()
        await model.setDiagnosticsActive(true)
        sendSequence(tracking)
        await drain()
        #expect(launcher.applications.isEmpty)
        await model.toggleRecognition()
        for index in 0...50 {
            tracking.send(HandFixture().sample(.fiveFingers, at: 10 + Double(index) / 32))
        }
        await drain()
        #expect(launcher.applications.isEmpty)
    }

    @Test func pickerPausesCommandsAndRequiresANewWakeAfterItCloses() async throws {
        let (model, tracking, launcher) = try boundModel()
        await model.toggleRecognition()
        model.beginEditingBindings()
        sendSequence(tracking)
        await drain()
        #expect(model.latestClassification?.pose == .fiveFingers)
        #expect(model.acceptedCommandCount == 0)
        #expect(launcher.applications.isEmpty)
        model.endEditingBindings()
        for index in 0...50 {
            tracking.send(HandFixture().sample(.fiveFingers, at: 10 + Double(index) / 32))
        }
        await drain()
        #expect(launcher.applications.isEmpty)
        sendSequence(tracking, start: 20)
        await drain()
        #expect(launcher.applications == [application])
    }

    @Test func unassignedCommandIsAcceptedWithoutLaunching() async {
        let tracking = FakeHandTracking()
        let launcher = FakeApplicationLauncher()
        let model = makeModel(tracking: tracking, launcher: launcher)
        await model.toggleRecognition()
        sendSequence(tracking)
        await drain()
        #expect(model.applicationLaunchStatus == .unassigned(.fiveFingers))
        #expect(launcher.applications.isEmpty)
    }

    @Test func launchFailureStaysVisible() async throws {
        let (model, tracking, launcher) = try boundModel()
        launcher.error = NSError(domain: "Test", code: 3, userInfo: [NSLocalizedDescriptionKey: "App is unavailable"])
        await model.toggleRecognition()
        sendSequence(tracking)
        await drain()
        #expect(model.applicationLaunchStatus == .failed(application: application, message: "App is unavailable"))
    }

    @Test func commandsDuringAnOutstandingLaunchAreNotQueued() async throws {
        let (model, tracking, launcher) = try boundModel()
        launcher.waitsForCompletion = true
        await model.toggleRecognition()
        sendSequence(tracking)
        await drain()
        sendRelease(tracking)
        sendSequence(tracking, start: 10)
        await drain()
        #expect(model.acceptedCommandCount == 2)
        #expect(launcher.applications == [application])
        launcher.completeNext()
        await drain()
        #expect(launcher.applications == [application])
        #expect(model.applicationLaunchStatus == .opened(application))
    }

    @Test func stoppedRecognitionIgnoresLateLaunchCompletion() async throws {
        let (model, tracking, launcher) = try boundModel()
        launcher.waitsForCompletion = true
        await model.toggleRecognition()
        sendSequence(tracking)
        await drain()
        await model.toggleRecognition()
        launcher.completeNext()
        await drain()
        #expect(model.applicationLaunchStatus == .idle)
        #expect(launcher.applications.count == 1)
    }

    private func makeModel(
        tracking: FakeHandTracking = FakeHandTracking(),
        store: FakeConfigurationStore = FakeConfigurationStore(),
        launcher: FakeApplicationLauncher = FakeApplicationLauncher()
    ) -> AppModel {
        AppModel(permissions: FakePermissionStatus(cameraAccess: .authorized), handTracking: tracking,
                 configurationStore: store, applicationLauncher: launcher)
    }

    private func boundModel() throws -> (AppModel, FakeHandTracking, FakeApplicationLauncher) {
        let store = FakeConfigurationStore()
        try store.configuration.setApplication(application, for: .fiveFingers)
        let tracking = FakeHandTracking()
        let launcher = FakeApplicationLauncher()
        return (makeModel(tracking: tracking, store: store, launcher: launcher), tracking, launcher)
    }

    private func sendSequence(_ tracking: FakeHandTracking, start: Double = 1) {
        for index in 0...20 {
            tracking.send(HandFixture().sample(.fist, at: start + Double(index) / 32))
        }
        for index in 21...40 {
            tracking.send(HandFixture().sample(.fiveFingers, at: start + Double(index) / 32))
        }
    }

    private func sendRelease(_ tracking: FakeHandTracking) {
        for index in 41...140 {
            tracking.send(HandPoseSample(timestamp: 1 + Double(index) / 32, hand: nil))
        }
    }

    private func drain() async {
        for _ in 0..<8 { await Task.yield() }
        try? await Task.sleep(for: .milliseconds(5))
    }
}
