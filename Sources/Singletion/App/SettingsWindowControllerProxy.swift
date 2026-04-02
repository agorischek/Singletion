import Foundation

@MainActor
final class SettingsWindowControllerProxy: ObservableObject {
    var openSettings: (() -> Void)?
}
