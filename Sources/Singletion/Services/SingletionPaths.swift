import Foundation

enum SingletionPaths {
    static var supportDirectory: URL {
        let fileManager = FileManager.default
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("Singletion", isDirectory: true)
    }

    static var appsDirectory: URL {
        supportDirectory.appendingPathComponent("apps", isDirectory: true)
    }

    static var runtimeStateURL: URL {
        supportDirectory.appendingPathComponent("runtime-state.json")
    }

    static func ensureDirectoriesExist() throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: appsDirectory, withIntermediateDirectories: true)
    }
}
