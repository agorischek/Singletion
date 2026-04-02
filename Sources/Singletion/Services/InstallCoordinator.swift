import AppKit
import Foundation

enum InstallOutcome: Equatable {
    case installed(String)
    case skipped(String)
}

enum InstallCoordinatorError: LocalizedError {
    case invalidConfiguration(String)
    case failedToPrepareHelper(String)

    var errorDescription: String? {
        switch self {
        case let .invalidConfiguration(message):
            return message
        case let .failedToPrepareHelper(message):
            return message
        }
    }
}

@MainActor
final class InstallCoordinator {
    private let fileManager = FileManager.default

    func installIfNeeded(configuration: ManagedAppConfiguration, currentState: ManagedAppState) async throws -> InstallOutcome {
        guard configuration.isValid else {
            throw InstallCoordinatorError.invalidConfiguration("Missing required fields for \(configuration.displayName).")
        }

        let sourceURL = configuration.sourceURL
        let targetURL = configuration.installedURL
        let sourceFingerprint = try ManagedAppInspector.fingerprint(forAppAt: sourceURL)

        if currentState.lastInstalledFingerprint == sourceFingerprint,
           fileManager.fileExists(atPath: targetURL.path) {
            return .skipped("Already installed")
        }

        if configuration.selfManaged,
           configuration.bundleIdentifier == Bundle.main.bundleIdentifier,
           targetURL.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL {
            try await installSelf(configuration: configuration, sourceFingerprint: sourceFingerprint)
            return .installed(sourceFingerprint)
        }

        try stopManagedApp(configuration: configuration)
        try replaceInstalledBundle(from: sourceURL, to: targetURL)

        if configuration.relaunchAfterInstall {
            try await relaunchManagedApp(configuration: configuration)
        }

        return .installed(sourceFingerprint)
    }

    private func stopManagedApp(configuration: ManagedAppConfiguration) throws {
        if !configuration.bundleIdentifier.isEmpty {
            let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: configuration.bundleIdentifier)
            for app in runningApps {
                app.terminate()
            }
        }

        let deadline = Date().addingTimeInterval(configuration.gracefulQuitTimeoutSeconds)
        while Date() < deadline {
            if isManagedAppRunning(configuration: configuration) == false {
                return
            }
            Thread.sleep(forTimeInterval: 0.15)
        }

        guard !configuration.processMatch.isEmpty else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        process.arguments = ["-f", configuration.processMatch]
        try process.run()
        process.waitUntilExit()
    }

    private func isManagedAppRunning(configuration: ManagedAppConfiguration) -> Bool {
        if !configuration.bundleIdentifier.isEmpty,
           !NSRunningApplication.runningApplications(withBundleIdentifier: configuration.bundleIdentifier).isEmpty {
            return true
        }

        guard !configuration.processMatch.isEmpty else { return false }
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-f", configuration.processMatch]
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func replaceInstalledBundle(from sourceURL: URL, to targetURL: URL) throws {
        let targetDirectory = targetURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: targetDirectory, withIntermediateDirectories: true)

        let temporaryURL = targetDirectory.appendingPathComponent(".\(targetURL.lastPathComponent).incoming")
        if fileManager.fileExists(atPath: temporaryURL.path) {
            try fileManager.removeItem(at: temporaryURL)
        }
        if fileManager.fileExists(atPath: targetURL.path) {
            try fileManager.removeItem(at: targetURL)
        }

        try fileManager.copyItem(at: sourceURL, to: temporaryURL)
        try fileManager.moveItem(at: temporaryURL, to: targetURL)
    }

    private func relaunchManagedApp(configuration: ManagedAppConfiguration) async throws {
        if configuration.relaunchDelayMilliseconds > 0 {
            try await Task.sleep(for: .milliseconds(configuration.relaunchDelayMilliseconds))
        }

        let workspace = NSWorkspace.shared
        if !configuration.bundleIdentifier.isEmpty {
            let configurationObject = NSWorkspace.OpenConfiguration()
            if workspace.urlForApplication(withBundleIdentifier: configuration.bundleIdentifier) != nil {
                _ = try await workspace.openApplication(at: configuration.installedURL, configuration: configurationObject)
                return
            }
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [configuration.installedURL.path]
        try process.run()
        process.waitUntilExit()
    }

    private func installSelf(configuration: ManagedAppConfiguration, sourceFingerprint: String) async throws {
        let helperDirectory = SingletionPaths.supportDirectory.appendingPathComponent("helpers", isDirectory: true)
        try fileManager.createDirectory(at: helperDirectory, withIntermediateDirectories: true)
        let helperURL = helperDirectory.appendingPathComponent("self-install.sh")
        let escapedSource = configuration.sourceURL.path.replacingOccurrences(of: "\"", with: "\\\"")
        let escapedTarget = configuration.installedURL.path.replacingOccurrences(of: "\"", with: "\\\"")
        let bundleIdentifier = (Bundle.main.bundleIdentifier ?? configuration.bundleIdentifier).replacingOccurrences(of: "\"", with: "\\\"")

        let script = """
        #!/bin/zsh
        set -euo pipefail
        sleep 1
        osascript -e 'tell application id "\(bundleIdentifier)" to quit' >/dev/null 2>&1 || true
        sleep 1
        pkill -f '/Singletion.app/Contents/MacOS/Singletion' || true
        rm -rf "\(escapedTarget)"
        ditto "\(escapedSource)" "\(escapedTarget)"
        open "\(escapedTarget)"
        """

        do {
            try script.write(to: helperURL, atomically: true, encoding: .utf8)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helperURL.path)
        } catch {
            throw InstallCoordinatorError.failedToPrepareHelper(error.localizedDescription)
        }

        let process = Process()
        process.executableURL = helperURL
        try process.run()
        _ = sourceFingerprint
    }
}
