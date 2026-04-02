import Foundation
import SwiftUI

struct SettingsRootView: View {
    @EnvironmentObject private var registry: ManagedAppRegistry
    @EnvironmentObject private var appState: SingletionAppState
    @EnvironmentObject private var launchAtLoginController: LaunchAtLoginController
    @EnvironmentObject private var settingsProxy: SettingsWindowControllerProxy

    @State private var selectedID: UUID?
    @State private var draft = ManagedAppConfiguration()
    @State private var hasUnsavedChanges = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedID) {
                ForEach(registry.configurations) { configuration in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(configuration.displayName)
                            .font(.system(size: 13, weight: .medium))
                        Text(configuration.installedAppPath)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .tag(configuration.id)
                }
            }
            .toolbar {
                ToolbarItemGroup {
                    Button {
                        let configuration = ManagedAppConfiguration(
                            displayName: "Managed App \(registry.configurations.count + 1)"
                        )
                        draft = configuration
                        selectedID = configuration.id
                        hasUnsavedChanges = true
                    } label: {
                        Image(systemName: "plus")
                    }

                    Button {
                        guard let selectedID else { return }
                        try? registry.delete(configurationID: selectedID)
                        self.selectedID = registry.configurations.first?.id
                        if let first = registry.configurations.first {
                            draft = first
                        }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(selectedID == nil)
                }
            }
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Singletion")
                        .font(.system(size: 24, weight: .bold))

                    settingsSummary
                    form

                    HStack(spacing: 12) {
                        Button("Save") {
                            saveDraft()
                        }
                        .disabled(!draft.isValid)

                        Button("Autofill") {
                            autofillDraft()
                        }
                        .disabled(draft.sourceAppPath.isEmpty)

                        Button("Install Now") {
                            saveDraft()
                            SingletionEnvironment.shared.watcher.installNow(draft)
                        }
                        .disabled(!draft.isValid)

                        if hasUnsavedChanges {
                            Text("Unsaved changes")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            if let first = registry.configurations.first {
                selectedID = first.id
                draft = first
            }
        }
        .onChange(of: selectedID) { _, newValue in
            guard let newValue,
                  let configuration = registry.configurations.first(where: { $0.id == newValue }) else { return }
            draft = configuration
            hasUnsavedChanges = false
        }
    }

    private var settingsSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Launch Singletion at login", isOn: Binding(
                get: { launchAtLoginController.isEnabled },
                set: { launchAtLoginController.setEnabled($0) }
            ))

            Text("Configurations are stored as JSON files in Application Support, while this window provides the editor.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Text("Current activity: \(appState.currentActivity)")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private var form: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
            labeledField("Display Name") {
                TextField("Scenes", text: binding(\.displayName))
            }
            labeledField("Source App Path") {
                TextField("/path/to/build/Products/Release/App.app", text: binding(\.sourceAppPath))
            }
            labeledField("Installed App Path") {
                TextField("~/Applications/App.app", text: binding(\.installedAppPath))
            }
            labeledField("Bundle Identifier") {
                TextField("dev.umeboshi.App", text: binding(\.bundleIdentifier))
            }
            labeledField("Process Match") {
                TextField("/App.app/Contents/MacOS/App", text: binding(\.processMatch))
            }
            labeledField("Watch Mode") {
                Picker("Watch Mode", selection: binding(\.watchMode)) {
                    ForEach(WatchMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }
            if draft.watchMode == .polling {
                labeledField("Poll Interval (s)") {
                    TextField("2", value: binding(\.pollIntervalSeconds), format: .number)
                }
            }
            labeledField("Debounce (s)") {
                TextField("1.5", value: binding(\.debounceSeconds), format: .number)
            }
            labeledField("Quit Timeout (s)") {
                TextField("3", value: binding(\.gracefulQuitTimeoutSeconds), format: .number)
            }
            labeledField("Relaunch Delay (ms)") {
                TextField("300", value: binding(\.relaunchDelayMilliseconds), format: .number)
            }
            labeledField("Enabled") {
                Toggle("", isOn: binding(\.enabled))
                    .labelsHidden()
            }
            labeledField("Relaunch After Install") {
                Toggle("", isOn: binding(\.relaunchAfterInstall))
                    .labelsHidden()
            }
            labeledField("Self Managed") {
                Toggle("", isOn: binding(\.selfManaged))
                    .labelsHidden()
            }
        }
        .textFieldStyle(.roundedBorder)
    }

    private func labeledField<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        Group {
            GridRow {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 180, alignment: .leading)
                content()
            }
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<ManagedAppConfiguration, Value>) -> Binding<Value> {
        Binding(
            get: { draft[keyPath: keyPath] },
            set: {
                draft[keyPath: keyPath] = $0
                hasUnsavedChanges = true
            }
        )
    }

    private func saveDraft() {
        do {
            try registry.save(configuration: draft)
            selectedID = draft.id
            hasUnsavedChanges = false
        } catch {
            appState.currentActivity = "Save failed: \(error.localizedDescription)"
        }
    }

    private func autofillDraft() {
        let sourceURL = draft.sourceURL
        guard let bundle = Bundle(url: sourceURL) else { return }

        if draft.bundleIdentifier.isEmpty {
            draft.bundleIdentifier = bundle.bundleIdentifier ?? draft.bundleIdentifier
        }

        if draft.installedAppPath.isEmpty {
            let appName = sourceURL.lastPathComponent
            draft.installedAppPath = "~/Applications/\(appName)"
        }

        if draft.processMatch.isEmpty,
           let executableName = bundle.object(forInfoDictionaryKey: kCFBundleExecutableKey as String) as? String {
            let installedExecutable = URL(fileURLWithPath: NSString(string: draft.installedAppPath).expandingTildeInPath)
                .appendingPathComponent("Contents/MacOS", isDirectory: true)
                .appendingPathComponent(executableName, isDirectory: false)
            draft.processMatch = installedExecutable.path
        }

        if draft.displayName == "New Managed App" || draft.displayName.hasPrefix("Managed App ") {
            draft.displayName = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? sourceURL.deletingPathExtension().lastPathComponent
        }

        hasUnsavedChanges = true
    }
}
