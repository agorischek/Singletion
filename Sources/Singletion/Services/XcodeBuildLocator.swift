import Foundation

struct XcodeBuildLocator {
    struct Match: Sendable {
        let appURL: URL
        let modificationDate: Date
    }

    enum LocatorError: LocalizedError {
        case noDerivedDataDirectory
        case noMatchingBuild

        var errorDescription: String? {
            switch self {
            case .noDerivedDataDirectory:
                return "Xcode DerivedData was not found."
            case .noMatchingBuild:
                return "No matching Xcode build was found in DerivedData."
            }
        }
    }

    func findLatestBuild(matching configuration: ManagedAppConfiguration) throws -> Match {
        let derivedDataURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Developer/Xcode/DerivedData", isDirectory: true)

        guard FileManager.default.fileExists(atPath: derivedDataURL.path) else {
            throw LocatorError.noDerivedDataDirectory
        }

        let preferredNames = candidateNames(from: configuration)
        let matches = try collectMatches(in: derivedDataURL, preferredNames: preferredNames)

        guard let bestMatch = matches.sorted(by: compareMatches(_:_:)).first else {
            throw LocatorError.noMatchingBuild
        }

        return bestMatch
    }

    private func collectMatches(in derivedDataURL: URL, preferredNames: [String]) throws -> [Match] {
        let resourceKeys: Set<URLResourceKey> = [.isDirectoryKey, .contentModificationDateKey, .nameKey]
        let enumerator = FileManager.default.enumerator(
            at: derivedDataURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: nil
        )

        var matches: [Match] = []

        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "app" else { continue }
            guard isInBuildProducts(url) else { continue }

            let modificationDate = ManagedAppInspector.modificationDate(forAppAt: url) ?? .distantPast
            matches.append(Match(appURL: url, modificationDate: modificationDate))
        }

        if preferredNames.isEmpty {
            return matches
        }

        let normalizedPreferredNames = preferredNames.map(normalizeName(_:))
        let namedMatches = matches.filter { match in
            let appName = normalizeName(match.appURL.deletingPathExtension().lastPathComponent)
            return normalizedPreferredNames.contains(appName)
        }

        return namedMatches.isEmpty ? matches : namedMatches
    }

    private func isInBuildProducts(_ url: URL) -> Bool {
        let components = url.pathComponents
        guard let buildIndex = components.firstIndex(of: "Build") else { return false }
        guard components.indices.contains(buildIndex + 1), components[buildIndex + 1] == "Products" else { return false }

        return components.contains("Debug") || components.contains("Release")
    }

    private func candidateNames(from configuration: ManagedAppConfiguration) -> [String] {
        var names: [String] = []

        let installedName = configuration.installedURL.deletingPathExtension().lastPathComponent
        if !installedName.isEmpty && installedName != "." {
            names.append(installedName)
        }

        let sourceName = configuration.sourceURL.deletingPathExtension().lastPathComponent
        if !sourceName.isEmpty && sourceName != "." {
            names.append(sourceName)
        }

        let trimmedDisplayName = configuration.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedDisplayName.isEmpty,
           trimmedDisplayName != "New Managed App",
           !trimmedDisplayName.hasPrefix("Managed App ") {
            names.append(trimmedDisplayName)
        }

        return Array(NSOrderedSet(array: names)) as? [String] ?? names
    }

    private func normalizeName(_ name: String) -> String {
        name
            .replacingOccurrences(of: ".app", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func compareMatches(_ lhs: Match, _ rhs: Match) -> Bool {
        if lhs.modificationDate != rhs.modificationDate {
            return lhs.modificationDate > rhs.modificationDate
        }

        return lhs.appURL.path < rhs.appURL.path
    }
}
