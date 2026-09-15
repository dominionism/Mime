import AppKit
import Testing
@testable import Mime

@MainActor
struct ApplicationLauncherTests {
    @Test func activatesARunningAppWithoutResolvingOrReopeningItsBundle() async throws {
        let workspace = FakeApplicationWorkspace()
        workspace.activationSucceeds = true
        let target = ApplicationTarget(bundleIdentifier: "com.example.Running", fallbackURL: URL(fileURLWithPath: "/missing/Running.app"), name: "Running")

        try await ApplicationLauncher(workspace: workspace).open(target)

        #expect(workspace.activationRequests == [target.bundleIdentifier])
        #expect(workspace.resolutionRequests.isEmpty)
        #expect(workspace.openedURLs.isEmpty)
    }

    @Test func failedFastActivationFallsBackToOpeningTheVerifiedApp() async throws {
        let location = ApplicationLauncherTestLocation()
        defer { location.remove() }
        let target = try location.makeApplication(name: "Sample", identifier: "com.example.Sample")
        let workspace = FakeApplicationWorkspace()
        workspace.resolvedURL = target.fallbackURL

        try await ApplicationLauncher(workspace: workspace).open(target)

        #expect(workspace.activationRequests == [target.bundleIdentifier])
        #expect(workspace.openedURLs == [target.fallbackURL])
    }

    @Test func movedApplicationUsesItsResolvedLocation() async throws {
        let location = ApplicationLauncherTestLocation()
        defer { location.remove() }
        let moved = try location.makeApplication(name: "Moved", identifier: "com.example.Sample")
        let original = ApplicationTarget(bundleIdentifier: moved.bundleIdentifier, fallbackURL: URL(fileURLWithPath: "/missing/Sample.app"), name: "Sample")
        let workspace = FakeApplicationWorkspace()
        workspace.resolvedURL = moved.fallbackURL

        try await ApplicationLauncher(workspace: workspace).open(original)

        #expect(workspace.openedURLs == [moved.fallbackURL])
    }

    @Test func mismatchedResolvedBundleUsesTheValidFallback() async throws {
        let location = ApplicationLauncherTestLocation()
        defer { location.remove() }
        let target = try location.makeApplication(name: "Sample", identifier: "com.example.Sample")
        let replacement = try location.makeApplication(name: "Replacement", identifier: "com.example.Different")
        let workspace = FakeApplicationWorkspace()
        workspace.resolvedURL = replacement.fallbackURL

        try await ApplicationLauncher(workspace: workspace).open(target)

        #expect(workspace.openedURLs == [target.fallbackURL])
    }

    @Test func neverOpensAnUnverifiedReplacement() async {
        let workspace = FakeApplicationWorkspace()
        let target = ApplicationTarget(bundleIdentifier: "com.example.Missing", fallbackURL: URL(fileURLWithPath: "/missing/Missing.app"), name: "Missing")

        await #expect(throws: ApplicationLaunchError.self) {
            try await ApplicationLauncher(workspace: workspace).open(target)
        }
        #expect(workspace.openedURLs.isEmpty)
    }

    @Test func canceledCommandDoesNotActivateOrOpenAnything() async {
        let workspace = FakeApplicationWorkspace()
        workspace.activationSucceeds = true
        let target = ApplicationTarget(bundleIdentifier: "com.example.Sample", fallbackURL: URL(fileURLWithPath: "/Applications/Sample.app"), name: "Sample")
        let task = Task { try await ApplicationLauncher(workspace: workspace).open(target) }
        task.cancel()

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(workspace.activationRequests.isEmpty)
        #expect(workspace.openedURLs.isEmpty)
    }

    @Test func onlyAVisibleNormalWindowPermitsTheFastPath() {
        func window(pid: Int, layer: Int = 0, visible: Bool = true) -> [String: Any] {
            [kCGWindowOwnerPID as String: pid, kCGWindowLayer as String: layer, kCGWindowIsOnscreen as String: visible]
        }

        #expect(SystemApplicationWorkspace.hasVisibleWindow(for: 42, in: [window(pid: 42)]))
        #expect(!SystemApplicationWorkspace.hasVisibleWindow(for: 42, in: [window(pid: 7)]))
        #expect(!SystemApplicationWorkspace.hasVisibleWindow(for: 42, in: [window(pid: 42, layer: 25)]))
        #expect(!SystemApplicationWorkspace.hasVisibleWindow(for: 42, in: [window(pid: 42, visible: false)]))
        #expect(!SystemApplicationWorkspace.hasVisibleWindow(for: 42, in: []))
    }
}

@MainActor
private final class FakeApplicationWorkspace: ApplicationWorkspace {
    var activationSucceeds = false
    var resolvedURL: URL?
    private(set) var activationRequests: [String] = []
    private(set) var resolutionRequests: [String] = []
    private(set) var openedURLs: [URL] = []

    func activateRunningApplication(bundleIdentifier: String) -> Bool {
        activationRequests.append(bundleIdentifier)
        return activationSucceeds
    }

    func applicationURL(for bundleIdentifier: String) -> URL? {
        resolutionRequests.append(bundleIdentifier)
        return resolvedURL
    }

    func openApplication(at url: URL) async throws {
        openedURLs.append(url)
    }
}

private struct ApplicationLauncherTestLocation {
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Mime-LauncherTests-\(UUID().uuidString)")

    func makeApplication(name: String, identifier: String) throws -> ApplicationTarget {
        let url = directory.appendingPathComponent("\(name).app")
        let contents = url.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let info = ["CFBundleIdentifier": identifier, "CFBundleName": name, "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        return ApplicationTarget(bundleIdentifier: identifier, fallbackURL: url, name: name)
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}
