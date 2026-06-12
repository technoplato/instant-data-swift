import Foundation

struct InstantOutboxUpdate: Hashable, Codable, Sendable {
  var mutation: PendingMutation
  var mutations: [PendingMutation]

  init(mutation: PendingMutation, mutations: [PendingMutation]) {
    self.mutation = mutation
    self.mutations = mutations
  }
}

actor InstantOutbox {
  private var mutations: [PendingMutation]

  init(mutations: [PendingMutation] = []) {
    self.mutations = mutations.sorted { $0.createdAt < $1.createdAt }
  }

  func enqueue(_ mutation: PendingMutation) -> [PendingMutation] {
    mutations.append(mutation)
    mutations.sort { $0.createdAt < $1.createdAt }
    return mutations
  }

  func pending() -> [PendingMutation] {
    mutations.filter { $0.status == .pending }
  }

  func all() -> [PendingMutation] {
    mutations
  }

  func markConfirmed(id: String) -> InstantOutboxUpdate? {
    guard let index = mutations.firstIndex(where: { $0.id == id }) else { return nil }
    mutations[index].status = .confirmed
    mutations[index].failureMessage = nil
    return InstantOutboxUpdate(mutation: mutations[index], mutations: mutations)
  }

  func markFailed(id: String, message: String) -> InstantOutboxUpdate? {
    guard let index = mutations.firstIndex(where: { $0.id == id }) else { return nil }
    mutations[index].status = .failed
    mutations[index].failureMessage = message
    return InstantOutboxUpdate(mutation: mutations[index], mutations: mutations)
  }
}
