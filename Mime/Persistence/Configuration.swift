import Foundation

struct GestureBinding: Codable, Equatable, Sendable {
    let gesture: GestureID
    let application: ApplicationTarget
}

/// Only user-selected app mappings are persisted. Camera frames and hand measurements never enter this schema.
struct Configuration: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    var bindings: [GestureBinding]
    var activationMode: GestureActivationMode

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        bindings: [GestureBinding] = [],
        activationMode: GestureActivationMode = .wakeThenCommand
    ) {
        self.schemaVersion = schemaVersion
        self.bindings = bindings
        self.activationMode = activationMode
    }

    func application(for gesture: GestureID) -> ApplicationTarget? {
        bindings.first(where: { $0.gesture == gesture })?.application
    }

    mutating func setApplication(_ application: ApplicationTarget?, for gesture: GestureID) throws {
        try validate()
        guard gesture.isCommand else {
            throw ConfigurationError.invalidConfiguration("The closed fist is reserved for waking Mime.")
        }
        var updated = self
        updated.bindings.removeAll(where: { $0.gesture == gesture })
        if let application {
            updated.bindings.append(GestureBinding(gesture: gesture, application: application))
        }
        try updated.validate()
        self = updated
    }

    func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ConfigurationError.unsupportedSchema(schemaVersion)
        }
        var seen: Set<GestureID> = []
        for binding in bindings {
            guard binding.gesture.isCommand else {
                throw ConfigurationError.invalidConfiguration("The closed fist is reserved for waking Mime.")
            }
            guard seen.insert(binding.gesture).inserted else {
                throw ConfigurationError.invalidConfiguration("\(binding.gesture.name) has more than one app mapping.")
            }
            try binding.application.validate()
        }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case bindings
        case activationMode
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        // Check the version before decoding fields whose shape may change in future schemas.
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ConfigurationError.unsupportedSchema(schemaVersion)
        }
        bindings = try container.decode([GestureBinding].self, forKey: .bindings)
        // Configurations written before Quick mode existed default to the safe gate.
        activationMode = try container.decodeIfPresent(GestureActivationMode.self, forKey: .activationMode) ?? .wakeThenCommand
        try validate()
    }
}

enum ConfigurationError: LocalizedError, Equatable {
    case unsupportedSchema(Int)
    case invalidConfiguration(String)
    case unreadable(String)
    case unwritable(String)
    case backupFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version):
            "The saved app mappings use an unsupported format (version \(version)). Reload them with a compatible version of Mime, or reset the mappings."
        case .invalidConfiguration(let reason):
            "The app mappings are invalid. \(reason)"
        case .unreadable(let reason):
            "Mime could not read the saved app mappings. \(reason)"
        case .unwritable(let reason):
            "Mime could not save the app mappings. \(reason)"
        case .backupFailed(let reason):
            "Mime could not back up the saved app mappings, so they were not reset. \(reason)"
        }
    }
}
