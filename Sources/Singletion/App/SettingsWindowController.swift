import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    init(environment: SingletionEnvironment) {
        let view = SettingsRootView()
            .environmentObject(environment.registry)
            .environmentObject(environment.appState)
            .environmentObject(environment.launchAtLoginController)
            .environmentObject(environment.settingsWindowControllerProxy)

        let hostingController = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Singletion Settings"
        window.setContentSize(NSSize(width: 880, height: 560))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func present() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
