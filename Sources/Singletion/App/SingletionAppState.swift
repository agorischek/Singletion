import Foundation

@MainActor
final class SingletionAppState: ObservableObject {
    @Published var currentActivity = "Idle"
}
