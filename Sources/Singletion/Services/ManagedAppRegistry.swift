import Foundation

@MainActor
final class ManagedAppRegistry: ObservableObject {
    @Published private(set) var configurations: [ManagedAppConfiguration] = []
    @Published private(set) var runtimeState = PersistedRuntimeState()
    @Published private(set) var lastLoadError: String?

    private let fileManager = FileManager.default
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    func load() {
        do {
            try SingletionPaths.ensureDirectoriesExist()
            configurations = try loadConfigurations()
            runtimeState = try loadRuntimeState()
            lastLoadError = nil
        } catch {
            lastLoadError = error.localizedDescription
        }
    }

    func save(configuration: ManagedAppConfiguration) throws {
        try SingletionPaths.ensureDirectoriesExist()
        let data = try encoder.encode(configuration)
        let url = configurationFileURL(for: configuration.id)
        try data.write(to: url, options: .atomic)
        load()
    }

    func delete(configurationID: UUID) throws {
        let url = configurationFileURL(for: configurationID)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        runtimeState.apps.removeValue(forKey: configurationID)
        try persistRuntimeState()
        load()
    }

    func state(for configurationID: UUID) -> ManagedAppState {
        runtimeState.apps[configurationID] ?? ManagedAppState()
    }

    func updateState(for configurationID: UUID, mutate: (inout ManagedAppState) -> Void) {
        var state = runtimeState.apps[configurationID] ?? ManagedAppState()
        mutate(&state)
        runtimeState.apps[configurationID] = state

        do {
            try persistRuntimeState()
            objectWillChange.send()
        } catch {
            lastLoadError = error.localizedDescription
        }
    }

    func allSnapshots() -> [ManagedAppSnapshot] {
        configurations.map { configuration in
            ManagedAppSnapshot(configuration: configuration, state: state(for: configuration.id))
        }
    }

    private func loadConfigurations() throws -> [ManagedAppConfiguration] {
        let urls = try fileManager.contentsOfDirectory(
            at: SingletionPaths.appsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        return try urls
            .filter { $0.pathExtension == "json" }
            .map { url in
                let data = try Data(contentsOf: url)
                return try decoder.decode(ManagedAppConfiguration.self, from: data)
            }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private func loadRuntimeState() throws -> PersistedRuntimeState {
        let url = SingletionPaths.runtimeStateURL
        guard fileManager.fileExists(atPath: url.path) else {
            return PersistedRuntimeState()
        }
        let data = try Data(contentsOf: url)
        return try decoder.decode(PersistedRuntimeState.self, from: data)
    }

    private func persistRuntimeState() throws {
        let data = try encoder.encode(runtimeState)
        try data.write(to: SingletionPaths.runtimeStateURL, options: .atomic)
    }

    private func configurationFileURL(for id: UUID) -> URL {
        SingletionPaths.appsDirectory.appendingPathComponent("\(id.uuidString.lowercased()).json")
    }
}
