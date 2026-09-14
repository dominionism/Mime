import Foundation

@MainActor
protocol ConfigurationStoring {
    func load() throws -> Configuration
    func save(_ configuration: Configuration) throws
    /// Explicit recovery only: preserve any existing file, then replace its contents with empty mappings.
    func reset() throws -> Configuration
}

@MainActor
final class ConfigurationStore: ConfigurationStoring {
    nonisolated static var defaultFileURL: URL {
        URL.applicationSupportDirectory
            .appendingPathComponent("Mime", isDirectory: true)
            .appendingPathComponent("configuration.json")
    }

    let fileURL: URL

    init(fileURL: URL = ConfigurationStore.defaultFileURL) {
        self.fileURL = fileURL
    }

    func load() throws -> Configuration {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return Configuration()
        } catch {
            throw ConfigurationError.unreadable(error.localizedDescription)
        }

        do {
            return try JSONDecoder().decode(Configuration.self, from: data)
        } catch let error as ConfigurationError {
            throw error
        } catch {
            throw ConfigurationError.invalidConfiguration("The saved file is not a supported configuration. \(error.localizedDescription)")
        }
    }

    func save(_ configuration: Configuration) throws {
        try configuration.validate()
        // Recheck disk on every save, including saves attempted after a failed load. An invalid or newer file must
        // survive until the user explicitly chooses reset; a valid in-memory value alone is not permission to replace it.
        _ = try load()
        try write(configuration)
    }

    func reset() throws -> Configuration {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let backupURL = fileURL.deletingLastPathComponent()
                .appendingPathComponent("configuration.backup-\(UUID().uuidString).json")
            do {
                try FileManager.default.copyItem(at: fileURL, to: backupURL)
            } catch {
                throw ConfigurationError.backupFailed(error.localizedDescription)
            }
        }
        let configuration = Configuration()
        try write(configuration)
        return configuration
    }

    private func write(_ configuration: Configuration) throws {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(configuration)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw ConfigurationError.unwritable(error.localizedDescription)
        }
    }
}
