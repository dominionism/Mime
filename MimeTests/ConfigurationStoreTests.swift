import Foundation
import Testing
@testable import Mime

@MainActor
struct ConfigurationStoreTests {
    @Test func missingFileLoadsEmptyMappingsWithoutWriting() throws {
        let location = ConfigurationTestLocation()
        defer { location.remove() }
        let store = ConfigurationStore(fileURL: location.fileURL)

        #expect(try store.load() == Configuration())
        #expect(!FileManager.default.fileExists(atPath: location.directory.path))
    }

    @Test func savesAndReloadsAssignmentsAndRemovals() throws {
        let location = ConfigurationTestLocation()
        defer { location.remove() }
        let store = ConfigurationStore(fileURL: location.fileURL)
        var configuration = Configuration()
        try configuration.setApplication(testApplication(), for: .fiveFingers)
        try configuration.setApplication(testApplication(name: "Second App"), for: .oneFinger)
        try store.save(configuration)

        let relaunchedStore = ConfigurationStore(fileURL: location.fileURL)
        #expect(try relaunchedStore.load() == configuration)
        try configuration.setApplication(testApplication(name: "Replacement"), for: .fiveFingers)
        try configuration.setApplication(nil, for: .oneFinger)
        try relaunchedStore.save(configuration)

        let reloaded = try store.load()
        #expect(reloaded.bindings.count == 1)
        #expect(reloaded.application(for: .fiveFingers)?.name == "Replacement")
        #expect(reloaded.application(for: .oneFinger) == nil)
    }

    @Test func legacyConfigurationDefaultsToTheSafeActivationMode() throws {
        let location = ConfigurationTestLocation()
        defer { location.remove() }
        try location.write(Data(#"{"schemaVersion":1,"bindings":[]}"#.utf8))

        let configuration = try ConfigurationStore(fileURL: location.fileURL).load()

        #expect(configuration.activationMode == .wakeThenCommand)
    }

    @Test func quickActivationModeRoundTripsWithMappings() throws {
        let location = ConfigurationTestLocation()
        defer { location.remove() }
        let store = ConfigurationStore(fileURL: location.fileURL)
        var configuration = Configuration(activationMode: .quick)
        try configuration.setApplication(testApplication(), for: .fiveFingers)
        try store.save(configuration)

        #expect(try store.load() == configuration)
        #expect(String(data: try Data(contentsOf: location.fileURL), encoding: .utf8)?.contains("quick") == true)
    }

    @Test(arguments: [
        "not JSON",
        #"{"schemaVersion":1,"bindings":[{"gesture":"unknown","application":{}}]}"#,
        #"{"schemaVersion":1}"#,
        #"{"bindings":[]}"#,
        #"{"schemaVersion":1,"bindings":"wrong type"}"#,
    ])
    func malformedFilesAreRejectedAndPreserved(contents: String) throws {
        let location = ConfigurationTestLocation()
        defer { location.remove() }
        let original = Data(contents.utf8)
        try location.write(original)
        let store = ConfigurationStore(fileURL: location.fileURL)

        #expect(throws: ConfigurationError.self) { try store.load() }
        #expect(throws: ConfigurationError.self) { try store.save(Configuration()) }
        #expect(try Data(contentsOf: location.fileURL) == original)
    }

    @Test func newerSchemaIsReportedBeforeAttemptingItsUnknownFields() throws {
        let location = ConfigurationTestLocation()
        defer { location.remove() }
        let original = Data(#"{"schemaVersion":99,"newBindingsFormat":{}}"#.utf8)
        try location.write(original)
        let store = ConfigurationStore(fileURL: location.fileURL)

        #expect(throws: ConfigurationError.unsupportedSchema(99)) { try store.load() }
        #expect(throws: ConfigurationError.unsupportedSchema(99)) { try store.save(Configuration()) }
        #expect(try Data(contentsOf: location.fileURL) == original)
    }

    @Test func rechecksTheFileBeforeSaving() throws {
        let location = ConfigurationTestLocation()
        defer { location.remove() }
        let store = ConfigurationStore(fileURL: location.fileURL)
        let configuration = try store.load()
        let changedContents = Data("unexpected file replacement".utf8)
        try location.write(changedContents)

        #expect(throws: ConfigurationError.self) { try store.save(configuration) }
        #expect(try Data(contentsOf: location.fileURL) == changedContents)
    }

    @Test func explicitResetPreservesTheOriginalFileAsABackup() throws {
        let location = ConfigurationTestLocation()
        defer { location.remove() }
        let original = Data(#"{"schemaVersion":99,"valuableFutureMappings":[1,2,3]}"#.utf8)
        try location.write(original)
        let store = ConfigurationStore(fileURL: location.fileURL)

        #expect(try store.reset() == Configuration())
        #expect(try store.load() == Configuration())
        let backups = try FileManager.default.contentsOfDirectory(at: location.directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("configuration.backup-") }
        #expect(backups.count == 1)
        #expect(try Data(contentsOf: #require(backups.first)) == original)

        var configuration = Configuration()
        try configuration.setApplication(testApplication(), for: .twoFingers)
        try store.save(configuration)
        #expect(try store.load() == configuration)
    }

    @Test func invalidMappingsCannotReplaceAValidFile() throws {
        let location = ConfigurationTestLocation()
        defer { location.remove() }
        let store = ConfigurationStore(fileURL: location.fileURL)
        let original = Configuration(bindings: [GestureBinding(gesture: .oneFinger, application: testApplication())])
        try store.save(original)
        let invalidConfigurations = [
            Configuration(schemaVersion: 0),
            Configuration(bindings: [GestureBinding(gesture: .fist, application: testApplication())]),
            Configuration(bindings: [
                GestureBinding(gesture: .twoFingers, application: testApplication()),
                GestureBinding(gesture: .twoFingers, application: testApplication(name: "Duplicate")),
            ]),
        ]

        for invalid in invalidConfigurations {
            #expect(throws: ConfigurationError.self) { try store.save(invalid) }
            #expect(try store.load() == original)
        }
    }

    @Test(arguments: [
        testApplication(bundleIdentifier: ""),
        testApplication(bundleIdentifier: "com.example.Bad App"),
        testApplication(bundleIdentifier: "com..example"),
        testApplication(name: " \n"),
        testApplication(fallbackURL: URL(string: "https://example.com/App.app")!),
        testApplication(fallbackURL: URL(string: "file://remote-host/Applications/App.app")!),
        testApplication(fallbackURL: URL(fileURLWithPath: "/Applications/document.txt")),
    ])
    func invalidAppDataIsRejectedOnSaveAndLoad(application: ApplicationTarget) throws {
        let location = ConfigurationTestLocation()
        defer { location.remove() }
        let store = ConfigurationStore(fileURL: location.fileURL)
        let configuration = Configuration(bindings: [GestureBinding(gesture: .fiveFingers, application: application)])

        #expect(throws: ConfigurationError.self) { try store.save(configuration) }
        #expect(!FileManager.default.fileExists(atPath: location.fileURL.path))
        try location.write(JSONEncoder().encode(configuration))
        #expect(throws: ConfigurationError.self) { try store.load() }
    }

    @Test func failedAssignmentKeepsExistingMappingsIntact() throws {
        var configuration = Configuration(bindings: [GestureBinding(gesture: .fiveFingers, application: testApplication())])
        let original = configuration

        #expect(throws: ConfigurationError.self) { try configuration.setApplication(testApplication(), for: .fist) }
        #expect(configuration == original)
        #expect(throws: ConfigurationError.self) {
            try configuration.setApplication(testApplication(bundleIdentifier: ""), for: .fiveFingers)
        }
        #expect(configuration == original)
    }

    @Test func fileSystemFailuresAreReportedWithoutReplacingOtherFiles() throws {
        let location = ConfigurationTestLocation()
        defer { location.remove() }
        try FileManager.default.createDirectory(at: location.directory, withIntermediateDirectories: true)
        let blockerURL = location.directory.appendingPathComponent("a-file")
        let original = Data("keep this file".utf8)
        try original.write(to: blockerURL)
        let store = ConfigurationStore(fileURL: blockerURL.appendingPathComponent("configuration.json"))

        #expect(throws: ConfigurationError.self) { try store.save(Configuration()) }
        #expect(try Data(contentsOf: blockerURL) == original)
    }
}

private func testApplication(
    bundleIdentifier: String = "com.example.TestApp",
    fallbackURL: URL = URL(fileURLWithPath: "/Applications/Test App.app"),
    name: String = "Test App"
) -> ApplicationTarget {
    ApplicationTarget(bundleIdentifier: bundleIdentifier, fallbackURL: fallbackURL, name: name)
}

private struct ConfigurationTestLocation {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Mime-ConfigurationTests-\(UUID().uuidString)")
    var fileURL: URL { directory.appendingPathComponent("configuration.json") }

    func write(_ data: Data) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: fileURL)
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}
