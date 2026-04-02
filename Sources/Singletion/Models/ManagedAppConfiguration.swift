import Foundation

struct ManagedAppConfiguration: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var displayName: String
    var sourceAppPath: String
    var installedAppPath: String
    var bundleIdentifier: String
    var processMatch: String
    var watchMode: WatchMode
    var pollIntervalSeconds: Double
    var debounceSeconds: Double
    var gracefulQuitTimeoutSeconds: Double
    var relaunchAfterInstall: Bool
    var relaunchDelayMilliseconds: Int
    var launchAtLogin: Bool
    var enabled: Bool
    var selfManaged: Bool

    init(
        id: UUID = UUID(),
        displayName: String = "New Managed App",
        sourceAppPath: String = "",
        installedAppPath: String = "",
        bundleIdentifier: String = "",
        processMatch: String = "",
        watchMode: WatchMode = .polling,
        pollIntervalSeconds: Double = 2,
        debounceSeconds: Double = 1.5,
        gracefulQuitTimeoutSeconds: Double = 3,
        relaunchAfterInstall: Bool = true,
        relaunchDelayMilliseconds: Int = 300,
        launchAtLogin: Bool = false,
        enabled: Bool = true,
        selfManaged: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.sourceAppPath = sourceAppPath
        self.installedAppPath = installedAppPath
        self.bundleIdentifier = bundleIdentifier
        self.processMatch = processMatch
        self.watchMode = watchMode
        self.pollIntervalSeconds = pollIntervalSeconds
        self.debounceSeconds = debounceSeconds
        self.gracefulQuitTimeoutSeconds = gracefulQuitTimeoutSeconds
        self.relaunchAfterInstall = relaunchAfterInstall
        self.relaunchDelayMilliseconds = relaunchDelayMilliseconds
        self.launchAtLogin = launchAtLogin
        self.enabled = enabled
        self.selfManaged = selfManaged
    }

    var sourceURL: URL {
        URL(fileURLWithPath: NSString(string: sourceAppPath).expandingTildeInPath)
    }

    var installedURL: URL {
        URL(fileURLWithPath: NSString(string: installedAppPath).expandingTildeInPath)
    }

    var isValid: Bool {
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !sourceAppPath.isEmpty &&
            !installedAppPath.isEmpty
    }
}

enum WatchMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case polling
    case manualOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .polling:
            return "Polling"
        case .manualOnly:
            return "Manual Only"
        }
    }
}
