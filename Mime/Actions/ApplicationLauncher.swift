import AppKit

@MainActor
protocol ApplicationLaunching {
    func open(_ application: ApplicationTarget) async throws
}

/// The narrow system boundary used to resolve, open, or activate an application.
@MainActor
protocol ApplicationWorkspace {
    func applicationURL(for bundleIdentifier: String) -> URL?
    func openApplication(at url: URL) async throws
}

@MainActor
struct SystemApplicationWorkspace: ApplicationWorkspace {
    func applicationURL(for bundleIdentifier: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }

    func openApplication(at url: URL) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = false
        _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
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

    var errorDescription: String? {
        switch self {
        case .invalidApplication: "Choose a macOS application (.app)."
        case .notFound(let name): "\(name) could not be found. Choose the app again in Settings."
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
