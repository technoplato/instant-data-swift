import Foundation

public actor InstantOutbox {
  private var mutations: [PendingMutation]

  public init(mutations: [PendingMutation] = []) {
    self.mutations = mutations.sorted { $0.createdAt < $1.createdAt }
  }

  public func enqueue(_ mutation: PendingMutation) -> [PendingMutation] {
    mutations.append(mutation)
    mutations.sort { $0.createdAt < $1.createdAt }
    return mutations
  }

  public func pending() -> [PendingMutation] {
    mutations.filter { $0.status == .pending }
  }

  public func all() -> [PendingMutation] {
    mutations
  }

  public func markConfirmed(ids: Set<String>) -> [PendingMutation] {
    for index in mutations.indices where ids.contains(mutations[index].id) {
      mutations[index].status = .confirmed
      mutations[index].failureMessage = nil
    }
    return mutations
  }

  public func markFailed(id: String, message: String) -> [PendingMutation] {
    for index in mutations.indices where mutations[index].id == id {
      mutations[index].status = .failed
      mutations[index].failureMessage = message
    }
    return mutations
  }
}
