import AppKit

@MainActor
protocol ApplicationLaunching {
    func open(_ application: ApplicationTarget) async throws
}

/// The narrow system boundary used to resolve, open, or activate an application.
@MainActor
protocol ApplicationWorkspace {
    /// Returns true when an existing visible app accepted an activation request.
    func activateRunningApplication(bundleIdentifier: String) -> Bool
    func applicationURL(for bundleIdentifier: String) -> URL?
    func openApplication(at url: URL) async throws
}

@MainActor
struct SystemApplicationWorkspace: ApplicationWorkspace {
    func activateRunningApplication(bundleIdentifier: String) -> Bool {
        guard let application = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .first(where: { !$0.isTerminated && $0.isFinishedLaunching }),
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]],
              Self.hasVisibleWindow(for: application.processIdentifier, in: windows) else { return false }

        // Activation alone does not send an app its reopen event. Use the regular open path below when all of
        // its windows are minimized, hidden, or closed, so showing a finger can still bring a usable window back.
        return application.activate(options: [])
    }

    static func hasVisibleWindow(for processIdentifier: pid_t, in windows: [[String: Any]]) -> Bool {
        windows.contains {
            ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == processIdentifier
                && ($0[kCGWindowLayer as String] as? NSNumber)?.intValue == 0
                && ($0[kCGWindowIsOnscreen as String] as? Bool) == true
        }
    }

    func applicationURL(for bundleIdentifier: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }

    func openApplication(at url: URL) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        // A newer finger command may supersede this launch while Launch Services is starting the process.
        // Starting in the background keeps a canceled old launch from taking focus after the newer command.
        configuration.activates = false
        configuration.createsNewApplicationInstance = false
        let application = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        try Task.checkCancellation()
        guard application.activate(options: []) else {
            throw ApplicationLaunchError.activationFailed(application.localizedName ?? url.deletingPathExtension().lastPathComponent)
        }
    }
}

@MainActor
struct ApplicationLauncher: ApplicationLaunching {
    private let workspace: any ApplicationWorkspace

    init(workspace: any ApplicationWorkspace = SystemApplicationWorkspace()) {
        self.workspace = workspace
    }

    func open(_ application: ApplicationTarget) async throws {
        try Task.checkCancellation()
        if workspace.activateRunningApplication(bundleIdentifier: application.bundleIdentifier) { return }
        // Launch Services can find an application after it moves. Only use a saved path when it still belongs
        // to the selected app, so a different bundle replacing the old path cannot silently become the binding.
        let candidates = [workspace.applicationURL(for: application.bundleIdentifier), application.fallbackURL]
        guard let url = candidates.compactMap({ $0 }).first(where: {
            guard let target = try? ApplicationTarget.fromApplication(at: $0) else { return false }
            return target.bundleIdentifier == application.bundleIdentifier
        }) else {
            throw ApplicationLaunchError.notFound(application.name)
        }
        try Task.checkCancellation()
        try await workspace.openApplication(at: url)
    }
}

extension ApplicationTarget {
    static func fromApplication(at url: URL) throws -> ApplicationTarget {
        guard url.isFileURL, url.pathExtension.lowercased() == "app",
              let bundle = Bundle(url: url),
              bundle.object(forInfoDictionaryKey: "CFBundlePackageType") as? String == "APPL",
              let identifier = bundle.bundleIdentifier, !identifier.isEmpty else {
            throw ApplicationLaunchError.invalidApplication
        }
        let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        return ApplicationTarget(bundleIdentifier: identifier, fallbackURL: url, name: name)
    }
}

enum ApplicationLaunchError: LocalizedError {
    case invalidApplication
    case notFound(String)
    case activationFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidApplication: "Choose a macOS application (.app)."
        case .notFound(let name): "\(name) could not be found. Choose the app again in Settings."
        case .activationFailed(let name): "\(name) opened but could not be brought forward. Try the gesture again."
        }
    }
}

enum ApplicationLaunchStatus: Equatable, Sendable {
    case idle
    case opening(ApplicationTarget)
    case opened(ApplicationTarget)
    case failed(application: ApplicationTarget, message: String)
    case unassigned(GestureID)
}
