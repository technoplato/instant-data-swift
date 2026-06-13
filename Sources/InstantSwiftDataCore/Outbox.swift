import Foundation

struct InstantOutboxUpdate: Hashable, Codable, Sendable {
  var mutation: PendingMutation
  var mutations: [PendingMutation]

  init(mutation: PendingMutation, mutations: [PendingMutation]) {
    self.mutation = mutation
    self.mutations = mutations
  }
}

struct InstantOutboxTransportUpdate: Hashable, Codable, Sendable {
  var confirmed: [PendingMutation]
  var failed: [PendingMutation]
  var mutations: [PendingMutation]
}

actor InstantOutbox {
  private var mutations: [PendingMutation]

  init(mutations: [PendingMutation] = []) {
    self.mutations = mutations.sorted(by: PendingMutation.creationOrder)
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

  func retrying(id: String) -> InstantOutboxUpdate? {
    Self.retrying(id: id, in: mutations)
  }

  static func retrying(id: String, in mutations: [PendingMutation]) -> InstantOutboxUpdate? {
    guard let index = mutations.firstIndex(where: { $0.id == id }) else { return nil }
    var nextMutations = mutations
    nextMutations[index].status = .pending
    nextMutations[index].failureMessage = nil
    return InstantOutboxUpdate(mutation: nextMutations[index], mutations: nextMutations)
  }

  static func confirmingPending(
    limit: Int?,
    in mutations: [PendingMutation]
  ) -> (confirmed: [PendingMutation], mutations: [PendingMutation]) {
    var confirmed: [PendingMutation] = []
    var remaining: [PendingMutation] = []
    var remainingLimit = limit ?? Int.max

    for mutation in mutations.sorted(by: PendingMutation.creationOrder) {
      guard mutation.status == .pending, remainingLimit > 0 else {
        remaining.append(mutation)
        continue
      }
      var confirmedMutation = mutation
      confirmedMutation.status = .confirmed
      confirmedMutation.failureMessage = nil
      confirmed.append(confirmedMutation)
      remainingLimit -= 1
    }

    return (confirmed, remaining.sorted(by: PendingMutation.creationOrder))
  }

  static func applyingTransportResults(
    _ results: [InstantMutationTransportResult],
    in mutations: [PendingMutation],
    allowedMutationIDs: Set<String>
  ) -> InstantOutboxTransportUpdate {
    var confirmed: [PendingMutation] = []
    var failed: [PendingMutation] = []
    var nextMutations = mutations

    for result in results {
      guard allowedMutationIDs.contains(result.mutationID),
        let index = nextMutations.firstIndex(where: { $0.id == result.mutationID }),
        nextMutations[index].status == .pending
      else { continue }

      switch result.outcome {
      case .confirmed:
        var mutation = nextMutations.remove(at: index)
        mutation.status = .confirmed
        mutation.failureMessage = nil
        confirmed.append(mutation)

      case .failed:
        nextMutations[index].status = .failed
        nextMutations[index].failureMessage = result.message
        failed.append(nextMutations[index])
      }
    }

    return InstantOutboxTransportUpdate(
      confirmed: confirmed.sorted(by: PendingMutation.creationOrder),
      failed: failed.sorted(by: PendingMutation.creationOrder),
      mutations: nextMutations.sorted(by: PendingMutation.creationOrder)
    )
  }

  func replace(with mutations: [PendingMutation]) {
    self.mutations = mutations.sorted(by: PendingMutation.creationOrder)
  }
}
