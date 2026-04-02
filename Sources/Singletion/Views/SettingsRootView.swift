import AppKit
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
    @State private var showsAdvancedOptions = false
    @State private var discoveredBuilds: [XcodeBuildLocator.Match] = []
    @State private var isShowingBuildBrowser = false
    private let buildLocator = XcodeBuildLocator()

    var body: some View {
        NavigationSplitView {
            Group {
                if registry.configurations.isEmpty {
                    ContentUnavailableView {
                        Label("No Managed Apps", systemImage: "square.stack.3d.up.slash")
                    } description: {
                        Text("Create your first managed app with the + button.")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
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
        .sheet(isPresented: $isShowingBuildBrowser) {
            discoveredBuildBrowser
        }
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
            showsAdvancedOptions = false
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

    private var discoveredBuildBrowser: some View {
        NavigationStack {
            Group {
                if discoveredBuilds.isEmpty {
                    ContentUnavailableView {
                        Label("No Xcode Builds Found", systemImage: "hammer")
                    } description: {
                        Text("Singletion looked in DerivedData but did not find any app bundles to choose from.")
                    }
                } else {
                    List(discoveredBuilds) { match in
                        Button {
                            selectDiscoveredBuild(match)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 8) {
                                    Text(match.appURL.lastPathComponent)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(.primary)

                                    if match.isPreferredMatch {
                                        Text("Suggested")
                                            .font(.system(size: 11, weight: .semibold))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 2)
                                            .background(.tertiary.opacity(0.8), in: Capsule())
                                    }
                                }

                                Text(match.appURL.path)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)

                                Text("Modified \(match.modificationDate.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("DerivedData Builds")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        isShowingBuildBrowser = false
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Refresh") {
                        browseDiscoveredBuilds()
                    }
                }
            }
        }
        .frame(minWidth: 760, minHeight: 460)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 18) {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
                labeledField("Source App Path") {
                    HStack(spacing: 10) {
                        TextField("/path/to/build/Products/Release/App.app", text: sourceAppPathBinding)
                        Button("Find Latest Xcode Build") {
                            chooseLatestXcodeBuild()
                        }
                        Button("Browse DerivedData...") {
                            browseDiscoveredBuilds()
                        }
                        Button("Browse...") {
                            chooseSourceApp()
                        }
                    }
                }
                labeledField("Display Name") {
                    TextField("Scenes", text: binding(\.displayName))
                }
                labeledField("Install To") {
                    TextField("~/Applications/App.app", text: binding(\.installedAppPath))
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Singletion can derive the bundle identifier, process path, and sensible defaults from the source app.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                if !draft.bundleIdentifier.isEmpty {
                    Text("Bundle ID: \(draft.bundleIdentifier)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                if !draft.processMatch.isEmpty {
                    Text("Process Match: \(draft.processMatch)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            DisclosureGroup("Advanced Options", isExpanded: $showsAdvancedOptions) {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
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
                .padding(.top, 12)
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

    private var sourceAppPathBinding: Binding<String> {
        Binding(
            get: { draft.sourceAppPath },
            set: { newValue in
                draft.sourceAppPath = newValue
                hasUnsavedChanges = true
                autofillDraft(force: false)
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

    private func chooseSourceApp() {
        let panel = NSOpenPanel()
        panel.title = "Choose Source App"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Choose App"
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser

        if panel.runModal() == .OK, let url = panel.url, url.pathExtension == "app" {
            draft.sourceAppPath = url.path
            hasUnsavedChanges = true
            autofillDraft(force: true)
            appState.currentActivity = "Selected source app: \(url.lastPathComponent)"
        }
    }

    private func chooseLatestXcodeBuild() {
        do {
            let match = try buildLocator.findLatestBuild(matching: draft)
            selectDiscoveredBuild(match)
            appState.currentActivity = "Found latest Xcode build: \(match.appURL.lastPathComponent)"
        } catch {
            appState.currentActivity = error.localizedDescription
        }
    }

    private func browseDiscoveredBuilds() {
        do {
            discoveredBuilds = try buildLocator.discoverBuilds(matching: draft)
            isShowingBuildBrowser = true
            appState.currentActivity = discoveredBuilds.isEmpty
                ? "No Xcode builds found in DerivedData."
                : "Discovered \(discoveredBuilds.count) Xcode build\(discoveredBuilds.count == 1 ? "" : "s")."
        } catch {
            discoveredBuilds = []
            appState.currentActivity = error.localizedDescription
            isShowingBuildBrowser = true
        }
    }

    private func selectDiscoveredBuild(_ match: XcodeBuildLocator.Match) {
        draft.sourceAppPath = match.appURL.path
        hasUnsavedChanges = true
        autofillDraft(force: true)
        appState.currentActivity = "Selected Xcode build: \(match.appURL.lastPathComponent)"
        isShowingBuildBrowser = false
    }

    private func autofillDraft(force: Bool = true) {
        let sourceURL = draft.sourceURL
        guard let bundle = Bundle(url: sourceURL) else { return }

        if force || draft.bundleIdentifier.isEmpty {
            draft.bundleIdentifier = bundle.bundleIdentifier ?? draft.bundleIdentifier
        }

        if force || draft.installedAppPath.isEmpty {
            let appName = sourceURL.lastPathComponent
            draft.installedAppPath = "~/Applications/\(appName)"
        }

        if (force || draft.processMatch.isEmpty),
           let executableName = bundle.object(forInfoDictionaryKey: kCFBundleExecutableKey as String) as? String {
            let installedExecutable = URL(fileURLWithPath: NSString(string: draft.installedAppPath).expandingTildeInPath)
                .appendingPathComponent("Contents/MacOS", isDirectory: true)
                .appendingPathComponent(executableName, isDirectory: false)
            draft.processMatch = installedExecutable.path
        }

        if force || draft.displayName == "New Managed App" || draft.displayName.hasPrefix("Managed App ") {
            draft.displayName = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? sourceURL.deletingPathExtension().lastPathComponent
        }

        hasUnsavedChanges = true
    }
}
