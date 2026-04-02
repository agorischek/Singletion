import Combine
import Darwin
import Foundation

@MainActor
final class ManagedAppWatcher {
    private struct WatchRegistration {
        let fileDescriptor: Int32
        let source: DispatchSourceFileSystemObject
    }

    private struct WatchContext {
        var lastSeenFingerprint: String?
        var lastChangeDate: Date?
        var lastAttemptedFingerprint: String?
        var lastCheckedAt: Date?
    }

    private var task: Task<Void, Never>?
    private var configurationCancellable: AnyCancellable?
    private var contexts: [UUID: WatchContext] = [:]
    private var watchRegistrations: [UUID: [WatchRegistration]] = [:]
    private var debounceTasks: [UUID: Task<Void, Never>] = [:]
    private let registry: ManagedAppRegistry
    private let installCoordinator: InstallCoordinator
    private let appState: SingletionAppState
    private let fileEventQueue = DispatchQueue(label: "dev.umeboshi.Singletion.watch", qos: .utility)

    init(registry: ManagedAppRegistry, installCoordinator: InstallCoordinator, appState: SingletionAppState) {
        self.registry = registry
        self.installCoordinator = installCoordinator
        self.appState = appState
    }

    func start() {
        stop()
        configurationCancellable = registry.$configurations
            .receive(on: RunLoop.main)
            .sink { [weak self] configurations in
                self?.reconfigureWatchers(for: configurations)
            }

        reconfigureWatchers(for: registry.configurations)
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        configurationCancellable?.cancel()
        configurationCancellable = nil
        for configurationID in Array(watchRegistrations.keys) {
            teardownWatchers(for: configurationID)
        }
        for debounceTask in debounceTasks.values {
            debounceTask.cancel()
        }
        debounceTasks.removeAll()
    }

    func installNow(_ configuration: ManagedAppConfiguration) {
        Task { [weak self] in
            await self?.performInstall(for: configuration, reason: "Manual install")
        }
    }

    private func tick() async {
        for configuration in registry.configurations where configuration.enabled {
            guard configuration.watchMode == .polling else { continue }
            await inspect(configuration)
        }
    }

    private func inspect(_ configuration: ManagedAppConfiguration, ignorePollInterval: Bool = false) async {
        var context = contexts[configuration.id] ?? WatchContext()
        if !ignorePollInterval,
           let lastCheckedAt = context.lastCheckedAt,
           Date().timeIntervalSince(lastCheckedAt) < configuration.pollIntervalSeconds {
            return
        }
        context.lastCheckedAt = Date()

        do {
            let fingerprint = try ManagedAppInspector.fingerprint(forAppAt: configuration.sourceURL)
            let modificationDate = ManagedAppInspector.modificationDate(forAppAt: configuration.sourceURL)

            if context.lastSeenFingerprint != fingerprint {
                context.lastSeenFingerprint = fingerprint
                context.lastChangeDate = Date()
                contexts[configuration.id] = context

                registry.updateState(for: configuration.id) { state in
                    state.lastObservedFingerprint = fingerprint
                    state.lastSourceModificationDate = modificationDate
                    state.lastEventMessage = "Detected new build output."
                    state.lastError = nil
                }
                return
            }

            guard let lastChangeDate = context.lastChangeDate else {
                contexts[configuration.id] = context
                return
            }

            if Date().timeIntervalSince(lastChangeDate) < configuration.debounceSeconds {
                contexts[configuration.id] = context
                return
            }

            if context.lastAttemptedFingerprint == fingerprint {
                contexts[configuration.id] = context
                return
            }

            context.lastAttemptedFingerprint = fingerprint
            contexts[configuration.id] = context
            await performInstall(for: configuration, reason: "Detected fresh build")
        } catch {
            registry.updateState(for: configuration.id) { state in
                state.lastError = error.localizedDescription
                state.lastEventMessage = "Watch failed."
            }
        }
    }

    private func reconfigureWatchers(for configurations: [ManagedAppConfiguration]) {
        let activeIDs = Set(configurations.map(\.id))

        for configurationID in Array(watchRegistrations.keys) where !activeIDs.contains(configurationID) {
            teardownWatchers(for: configurationID)
        }

        for configuration in configurations where configuration.enabled {
            switch configuration.watchMode {
            case .fileWatcher:
                installWatchers(for: configuration)
                Task { [weak self] in
                    await self?.inspect(configuration, ignorePollInterval: true)
                }
            case .polling, .manualOnly:
                teardownWatchers(for: configuration.id)
            }
        }
    }

    private func installWatchers(for configuration: ManagedAppConfiguration) {
        teardownWatchers(for: configuration.id)

        let candidateURLs = [
            configuration.sourceURL,
            configuration.sourceURL.deletingLastPathComponent()
        ]

        var registrations: [WatchRegistration] = []

        for url in candidateURLs {
            guard let registration = makeWatchRegistration(for: url, configurationID: configuration.id) else {
                continue
            }
            registrations.append(registration)
        }

        if registrations.isEmpty == false {
            watchRegistrations[configuration.id] = registrations
        }
    }

    private func makeWatchRegistration(for url: URL, configurationID: UUID) -> WatchRegistration? {
        let fileDescriptor = open(url.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return nil }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename, .attrib, .extend, .link, .revoke],
            queue: fileEventQueue
        )

        source.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                self?.recordFileSystemEvent(for: configurationID)
            }
        }

        source.setCancelHandler {
            close(fileDescriptor)
        }

        source.resume()
        return WatchRegistration(fileDescriptor: fileDescriptor, source: source)
    }

    private func teardownWatchers(for configurationID: UUID) {
        if let registrations = watchRegistrations.removeValue(forKey: configurationID) {
            for registration in registrations {
                registration.source.cancel()
            }
        }

        if let debounceTask = debounceTasks.removeValue(forKey: configurationID) {
            debounceTask.cancel()
        }
    }

    private func recordFileSystemEvent(for configurationID: UUID) {
        guard let configuration = registry.configurations.first(where: { $0.id == configurationID }) else {
            teardownWatchers(for: configurationID)
            return
        }

        var context = contexts[configurationID] ?? WatchContext()
        context.lastChangeDate = Date()
        contexts[configurationID] = context

        registry.updateState(for: configurationID) { state in
            state.lastEventMessage = "Detected filesystem change."
            state.lastError = nil
        }

        debounceTasks[configurationID]?.cancel()
        debounceTasks[configurationID] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(configuration.debounceSeconds))
            guard !Task.isCancelled else { return }
            await self?.inspect(configuration, ignorePollInterval: true)
        }
    }

    private func performInstall(for configuration: ManagedAppConfiguration, reason: String) async {
        appState.currentActivity = "\(reason): \(configuration.displayName)"

        do {
            let currentState = registry.state(for: configuration.id)
            let outcome = try await installCoordinator.installIfNeeded(configuration: configuration, currentState: currentState)
            switch outcome {
            case let .installed(fingerprint):
                registry.updateState(for: configuration.id) { state in
                    state.lastInstalledFingerprint = fingerprint
                    state.lastInstallDate = Date()
                    state.lastError = nil
                    state.lastEventMessage = "Installed and relaunched."
                }
            case let .skipped(message):
                registry.updateState(for: configuration.id) { state in
                    state.lastError = nil
                    state.lastEventMessage = message
                }
            }
        } catch {
            registry.updateState(for: configuration.id) { state in
                state.lastError = error.localizedDescription
                state.lastEventMessage = "Install failed."
            }
        }

        appState.currentActivity = "Idle"
    }
}
