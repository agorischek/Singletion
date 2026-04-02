import Foundation

enum ManagedAppInspector {
    static func fingerprint(forAppAt url: URL) throws -> String {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else {
            throw NSError(domain: "Singletion", code: 1, userInfo: [NSLocalizedDescriptionKey: "App bundle not found at \(url.path)"])
        }

        let values = try url.resourceValues(forKeys: [.contentModificationDateKey])
        let modificationDate = values.contentModificationDate ?? .distantPast

        let bundle = Bundle(url: url)
        let shortVersion = bundle?.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let buildVersion = bundle?.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let executableURL = bundle?.executableURL
        let executableDate = try executableURL?.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? modificationDate

        return "\(shortVersion)|\(buildVersion)|\(modificationDate.timeIntervalSince1970)|\(executableDate.timeIntervalSince1970)"
    }

    static func modificationDate(forAppAt url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}
