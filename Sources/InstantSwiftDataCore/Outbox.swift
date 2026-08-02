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

  func confirming(
    id: String,
    source: InstantMutationConfirmationSource = .manual
  ) -> InstantOutboxUpdate? {
    Self.confirming(id: id, source: source, in: mutations)
  }

  static func confirming(
    id: String,
    source: InstantMutationConfirmationSource = .manual,
    in mutations: [PendingMutation]
  ) -> InstantOutboxUpdate? {
    guard let index = mutations.firstIndex(where: { $0.id == id }) else { return nil }
    var nextMutations = mutations
    var mutation = nextMutations[index]
    mutation.status = .confirmed
    mutation.failureMessage = nil
    mutation.failure = nil
    mutation.confirmationSource = source
    if source.provesServerAcceptance {
      nextMutations.remove(at: index)
    } else {
      nextMutations[index] = mutation
    }
    return InstantOutboxUpdate(mutation: mutation, mutations: nextMutations)
  }

  static func accepting(
    id: String,
    serverTransactionID: String,
    in mutations: [PendingMutation]
  ) -> InstantOutboxUpdate? {
    guard let index = mutations.firstIndex(where: { $0.id == id }) else { return nil }
    var nextMutations = mutations
    nextMutations[index].status = .confirmed
    nextMutations[index].failureMessage = nil
    nextMutations[index].failure = nil
    nextMutations[index].serverTransactionID = serverTransactionID
    nextMutations[index].confirmationSource = .webSocketTransactOK
    return InstantOutboxUpdate(
      mutation: nextMutations[index],
      mutations: nextMutations
    )
  }

  static func pruningConfirmed(
    through processedTransactionID: String,
    in mutations: [PendingMutation]
  ) -> [PendingMutation] {
    mutations.filter { mutation in
      guard mutation.status == .confirmed,
        let serverTransactionID = mutation.serverTransactionID
      else { return true }
      return !transactionID(
        serverTransactionID,
        isCoveredBy: processedTransactionID
      )
    }
  }

  private static func transactionID(
    _ transactionID: String,
    isCoveredBy processedTransactionID: String
  ) -> Bool {
    if transactionID == processedTransactionID {
      return true
    }
    guard let transactionNumber = Int64(transactionID),
      let processedTransactionNumber = Int64(processedTransactionID)
    else { return false }
    return transactionNumber <= processedTransactionNumber
  }

  func failing(id: String, message: String) -> InstantOutboxUpdate? {
    Self.failing(id: id, message: message, in: mutations)
  }

  static func failing(
    id: String,
    message: String,
    in mutations: [PendingMutation]
  ) -> InstantOutboxUpdate? {
    failing(
      id: id,
      failure: InstantMutationFailure(
        code: PendingMutation.failureCode(message: message),
        message: message
      ),
      in: mutations
    )
  }

  static func failing(
    id: String,
    failure: InstantMutationFailure,
    in mutations: [PendingMutation]
  ) -> InstantOutboxUpdate? {
    guard let index = mutations.firstIndex(where: { $0.id == id }) else { return nil }
    var nextMutations = mutations
    nextMutations[index].status = .failed
    nextMutations[index].failureMessage = failure.message
    nextMutations[index].failure = failure
    nextMutations[index].serverTransactionID = nil
    nextMutations[index].confirmationSource = nil
    return InstantOutboxUpdate(mutation: nextMutations[index], mutations: nextMutations)
  }

  static func discardingFailed(
    id: String,
    in mutations: [PendingMutation]
  ) -> InstantOutboxUpdate? {
    guard let index = mutations.firstIndex(where: { $0.id == id }),
      mutations[index].status == .failed
    else { return nil }
    var nextMutations = mutations
    let mutation = nextMutations.remove(at: index)
    return InstantOutboxUpdate(
      mutation: mutation,
      mutations: nextMutations.sorted(by: PendingMutation.creationOrder)
    )
  }

  func retrying(id: String) -> InstantOutboxUpdate? {
    Self.retrying(id: id, in: mutations)
  }

  static func retrying(id: String, in mutations: [PendingMutation]) -> InstantOutboxUpdate? {
    guard let index = mutations.firstIndex(where: { $0.id == id }) else { return nil }
    var nextMutations = mutations
    nextMutations[index].status = .pending
    nextMutations[index].failureMessage = nil
    nextMutations[index].failure = nil
    nextMutations[index].serverTransactionID = nil
    nextMutations[index].confirmationSource = nil
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
      confirmedMutation.failure = nil
      confirmedMutation.confirmationSource = .localDrain
      confirmed.append(confirmedMutation)
      remaining.append(confirmedMutation)
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
        var mutation = nextMutations[index]
        mutation.status = .confirmed
        mutation.failureMessage = nil
        mutation.failure = nil
        mutation.confirmationSource = result.acceptance == .serverAccepted
          ? .serverTransport
          : .localTransport
        // Unlike WebSocket transact-ok, generic transport proof has no server transaction
        // watermark. Retain its reconciliation metadata until an authoritative refresh can strip
        // the optimistic layer before installing the server value.
        nextMutations[index] = mutation
        confirmed.append(mutation)

      case .failed:
        let message = result.message ?? "The Instant mutation transport rejected the mutation."
        nextMutations[index].status = .failed
        nextMutations[index].failureMessage = message
        nextMutations[index].failure = InstantMutationFailure(
          code: PendingMutation.failureCode(message: message),
          message: message
        )
        nextMutations[index].confirmationSource = nil
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
