import Foundation

struct ManagedAppState: Codable, Equatable, Sendable {
    var lastObservedFingerprint: String?
    var lastInstalledFingerprint: String?
    var lastInstallDate: Date?
    var lastError: String?
    var lastEventMessage: String?
    var lastSourceModificationDate: Date?
}

struct PersistedRuntimeState: Codable, Sendable {
    var apps: [UUID: ManagedAppState] = [:]
}
