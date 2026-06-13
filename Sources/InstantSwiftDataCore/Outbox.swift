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

  func pending() -> [PendingMutation] {
    mutations.filter { $0.status == .pending }
  }

  func all() -> [PendingMutation] {
    mutations
  }

  func confirming(id: String) -> InstantOutboxUpdate? {
    Self.confirming(id: id, in: mutations)
  }

  static func confirming(id: String, in mutations: [PendingMutation]) -> InstantOutboxUpdate? {
    guard let index = mutations.firstIndex(where: { $0.id == id }) else { return nil }
    var nextMutations = mutations
    var mutation = nextMutations.remove(at: index)
    mutation.status = .confirmed
    mutation.failureMessage = nil
    return InstantOutboxUpdate(mutation: mutation, mutations: nextMutations)
  }

  func failing(id: String, message: String) -> InstantOutboxUpdate? {
    Self.failing(id: id, message: message, in: mutations)
  }

  static func failing(
    id: String,
    message: String,
    in mutations: [PendingMutation]
  ) -> InstantOutboxUpdate? {
    guard let index = mutations.firstIndex(where: { $0.id == id }) else { return nil }
    var nextMutations = mutations
    nextMutations[index].status = .failed
    nextMutations[index].failureMessage = message
    return InstantOutboxUpdate(mutation: nextMutations[index], mutations: nextMutations)
  }

  func replace(with mutations: [PendingMutation]) {
    self.mutations = mutations.sorted { $0.createdAt < $1.createdAt }
  }
}
