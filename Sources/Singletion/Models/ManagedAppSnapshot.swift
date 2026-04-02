import Foundation

struct ManagedAppSnapshot: Identifiable, Equatable {
    let configuration: ManagedAppConfiguration
    let state: ManagedAppState

    var id: UUID { configuration.id }
}
