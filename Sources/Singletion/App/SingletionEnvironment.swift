import Foundation

@MainActor
final class SingletionEnvironment {
    static let shared = SingletionEnvironment()

    let registry = ManagedAppRegistry()
    let appState = SingletionAppState()
    let launchAtLoginController = LaunchAtLoginController()
    let settingsWindowControllerProxy = SettingsWindowControllerProxy()
    let installCoordinator = InstallCoordinator()
    lazy var watcher = ManagedAppWatcher(
        registry: registry,
        installCoordinator: installCoordinator,
        appState: appState
    )

    private init() {}

    func bootstrap() {
        registry.load()
        launchAtLoginController.refresh()
        watcher.start()
    }
}
