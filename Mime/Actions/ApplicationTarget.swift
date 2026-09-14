import Foundation

/// The identity of an app selected by the user. Its URL is a fallback if Launch Services cannot resolve its identifier.
struct ApplicationTarget: Codable, Equatable, Sendable {
    let bundleIdentifier: String
    let fallbackURL: URL
    let name: String

    func validate() throws {
        let identifierCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-.")
        guard !bundleIdentifier.isEmpty,
              bundleIdentifier.unicodeScalars.allSatisfy(identifierCharacters.contains),
              bundleIdentifier.split(separator: ".", omittingEmptySubsequences: false).allSatisfy({ !$0.isEmpty })
        else {
            throw ConfigurationError.invalidConfiguration("An app has an invalid bundle identifier.")
        }

        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
        else {
            throw ConfigurationError.invalidConfiguration("An app is missing a valid name.")
        }

        guard fallbackURL.isFileURL,
              fallbackURL.path.hasPrefix("/"),
              fallbackURL.pathExtension.lowercased() == "app",
              fallbackURL.deletingPathExtension().lastPathComponent.isEmpty == false,
              fallbackURL.host == nil || fallbackURL.host == "" || fallbackURL.host == "localhost",
              fallbackURL.query == nil,
              fallbackURL.fragment == nil
        else {
            throw ConfigurationError.invalidConfiguration("An app must point to a local .app bundle.")
        }
    }
}
