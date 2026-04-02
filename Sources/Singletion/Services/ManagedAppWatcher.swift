import Foundation

@MainActor
final class ManagedAppWatcher {
    private struct WatchContext {
        var lastSeenFingerprint: String?
        var lastChangeDate: Date?
        var lastAttemptedFingerprint: String?
    }

    private var task: Task<Void, Never>?
    private var contexts: [UUID: WatchContext] = [:]
    private let registry: ManagedAppRegistry
    private let installCoordinator: InstallCoordinator
    private let appState: SingletionAppState

    init(registry: ManagedAppRegistry, installCoordinator: InstallCoordinator, appState: SingletionAppState) {
        self.registry = registry
        self.installCoordinator = installCoordinator
        self.appState = appState
    }

    func start() {
        stop()
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

    private func inspect(_ configuration: ManagedAppConfiguration) async {
        do {
            let fingerprint = try ManagedAppInspector.fingerprint(forAppAt: configuration.sourceURL)
            let modificationDate = ManagedAppInspector.modificationDate(forAppAt: configuration.sourceURL)
            var context = contexts[configuration.id] ?? WatchContext()

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
