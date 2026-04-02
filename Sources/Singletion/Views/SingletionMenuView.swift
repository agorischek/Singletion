import AppKit
import SwiftUI

struct SingletionMenuView: View {
    @EnvironmentObject private var registry: ManagedAppRegistry
    @EnvironmentObject private var appState: SingletionAppState
    @EnvironmentObject private var launchAtLoginController: LaunchAtLoginController
    @EnvironmentObject private var settingsProxy: SettingsWindowControllerProxy

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Singletion")
                    .font(.system(size: 16, weight: .semibold))

                Text(SingletionPaths.appsDirectory.path)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Divider()

            if registry.configurations.isEmpty {
                Text("No managed apps yet. Open settings to add one.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 0) {
                    ForEach(registry.allSnapshots()) { snapshot in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(snapshot.configuration.displayName)
                                    .font(.system(size: 13, weight: .medium))
                                Spacer()
                                Text(statusText(for: snapshot))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }

                            if let event = snapshot.state.lastEventMessage {
                                Text(event)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 2)
                    }
                }
            }

            Divider()

            VStack(spacing: 0) {
                MenuActionRow(title: "Open Settings...", systemImage: "slider.horizontal.3") {
                    NotificationCenter.default.post(name: AppDelegate.closePopoverNotification, object: nil)
                    settingsProxy.openSettings?()
                }

                MenuActionRow(title: launchAtLoginController.isEnabled ? "Disable Launch at Login" : "Enable Launch at Login", systemImage: "power") {
                    launchAtLoginController.setEnabled(!launchAtLoginController.isEnabled)
                }

                MenuActionRow(title: "Reveal Config Folder", systemImage: "folder") {
                    NSWorkspace.shared.open(SingletionPaths.appsDirectory)
                }

                MenuActionRow(title: "Reload Config", systemImage: "arrow.clockwise") {
                    registry.load()
                }
            }

            if let lastLoadError = registry.lastLoadError {
                Divider()
                Text("Error: \(lastLoadError)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            Text(appState.currentActivity)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            MenuActionRow(title: "Quit Singletion", systemImage: "xmark.rectangle") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(14)
        .frame(width: 350, alignment: .leading)
    }

    private func statusText(for snapshot: ManagedAppSnapshot) -> String {
        if let error = snapshot.state.lastError, !error.isEmpty {
            return "Error"
        }
        if snapshot.state.lastInstallDate != nil {
            return "Installed"
        }
        return snapshot.configuration.enabled ? "Watching" : "Paused"
    }
}
