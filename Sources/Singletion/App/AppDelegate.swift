import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let closePopoverNotification = Notification.Name("SingletionClosePopover")

    private let environment = SingletionEnvironment.shared
    private let statusItemController = StatusItemController()
    private var settingsWindowController: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        environment.bootstrap()
        settingsWindowController = SettingsWindowController(environment: environment)
        environment.settingsWindowControllerProxy.openSettings = { [weak self] in
            self?.settingsWindowController?.present()
        }

        statusItemController.install(
            rootView: SingletionMenuView()
                .environmentObject(environment.registry)
                .environmentObject(environment.appState)
                .environmentObject(environment.launchAtLoginController)
                .environmentObject(environment.settingsWindowControllerProxy),
            target: self,
            action: #selector(togglePopover(_:))
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(closePopover(_:)),
            name: Self.closePopoverNotification,
            object: nil
        )
    }

    @objc
    private func togglePopover(_ sender: AnyObject?) {
        statusItemController.togglePopover(sender: sender)
    }

    @objc
    private func closePopover(_ notification: Notification) {
        statusItemController.closePopover()
    }
}
