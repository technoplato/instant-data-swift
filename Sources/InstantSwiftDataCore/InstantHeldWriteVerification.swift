import Foundation
import os

// History:
// - 2026-11-06: added for #696 (criteria from #134). A held write could be listed, exported and sent again, never
//   settled: nothing read the server to say whether it had landed. Verification reads the server's own rows, and
//   completing or discarding a held write records that evidence beside its kept row.

/// What the server holds of a held write, read from the server (#696).
///
/// A held write's effect on this device's cache is unknown, so this device cannot say whether the write landed; the
/// server can. A verification reads the server's own rows for every slot the write set (the answer the server sent, not
/// this device's view of it, which unsent later writes and the held write's own leftover effect can still color) and
/// settles the write only on that evidence:
///
/// ```swift
/// let verification = try await client.verifyQuarantinedMutation(id: mutation.id)
/// switch verification.verdict {
/// case .applied: try await client.completeQuarantinedMutation(id: mutation.id)
/// case .notApplied: try await client.discardQuarantinedMutation(id: mutation.id)
/// case .cannotTell: break  // It stays held; the verdict says why.
/// }
/// ```
public struct InstantQuarantinedMutationVerification: Hashable, Codable, Sendable {
  /// Whether the server holds the write.
  public enum Verdict: Hashable, Codable, Sendable {
    /// The server holds every value the write set, or a newer one that a later write of this device, which the server
    /// accepted, set: nothing of it is left to send, and completing it loses nothing.
    case applied
    /// The write is not on the server, and its record says why it will not get there as it stands.
    case notApplied(NotApplied)
    /// The server's rows cannot settle it, for the reason given. It stays held.
    case cannotTell(CannotTell)
  }

  /// Why a write is not on the server.
  public enum NotApplied: Hashable, Codable, Sendable {
    /// Its outbox row records no send: it never left this device. Send it again to deliver it, or discard it.
    case neverSent
    /// The server refused it with a client-error status, and its rows do not hold what it set.
    case refusedByServer(status: Int, type: String?, message: String)
  }

  /// Why the server's rows cannot settle a write.
  public enum CannotTell: Hashable, Codable, Sendable {
    /// It was sent, the server did not refuse it, and the server's rows do not hold some value it set. It may never
    /// have arrived, or it arrived and a later write this device does not know of replaced it; a value that differs
    /// cannot tell those apart.
    case serverDoesNotHoldIt
    /// It has an operation whose effect the server's rows cannot show, named here: a retraction, a deletion, a step
    /// addressed by a lookup, a deep merge that removes a key, or no write at all.
    case uncheckableOperation(String)
    /// The server could not be read: the error's message.
    case serverUnreadable(String)
    /// Its body no longer decodes, so what it set is unknown.
    case undecodable
  }

  /// The mutation's ID.
  public var id: String
  /// When the server's rows were read.
  public var verifiedAt: InstantTimestamp
  public var verdict: Verdict
  /// Every write operation of the mutation, with what covers it: the server's rows (``InstantSlotCoverage/Coverage/serverResult(receivedAt:)``,
  /// at ``verifiedAt``), a later write of this device, or nothing (with the values the server's rows hold). Empty when
  /// the body does not decode or the server could not be read.
  public var slots: [InstantSlotCoverage]

  public init(
    id: String,
    verifiedAt: InstantTimestamp,
    verdict: Verdict,
    slots: [InstantSlotCoverage]
  ) {
    self.id = id
    self.verifiedAt = verifiedAt
    self.verdict = verdict
    self.slots = slots
  }
}

// MARK: - The evidence and the verdict

/// One slot a held write set, as this device knows it before the server is read (#696).
package struct InstantHeldWriteSlot: Hashable, Sendable {
  package var entityID: String
  package var namespace: String?
  package var attributeName: String?
  package var attributeID: String
  package var operation: InstantSlotCoverage.Operation
  /// The value the write set; nil for a deletion.
  package var value: InstantValue?
  /// The namespace a link attribute points at; nil for any other attribute.
  package var linkNamespace: String?
  /// Why the server's rows cannot show this slot; nil when they can.
  package var uncheckable: String?
  /// The newest later write of this device that sets this slot: accepted by the server, or not yet.
  package var laterWrite: InstantSlotCoverage.Coverage?

  package init(
    entityID: String,
    namespace: String?,
    attributeName: String?,
    attributeID: String,
    operation: InstantSlotCoverage.Operation,
    value: InstantValue?,
    linkNamespace: String? = nil,
    uncheckable: String? = nil,
    laterWrite: InstantSlotCoverage.Coverage? = nil
  ) {
    self.entityID = entityID
    self.namespace = namespace
    self.attributeName = attributeName
    self.attributeID = attributeID
    self.operation = operation
    self.value = value
    self.linkNamespace = linkNamespace
    self.uncheckable = uncheckable
    self.laterWrite = laterWrite
  }
}

/// What this device knows of a held write: what it set, and what its kept outbox row says of its sends (#696).
package struct InstantHeldWriteEvidence: Hashable, Sendable {
  /// What the kept outbox row says of the write's sends.
  package enum Delivery: Hashable, Sendable {
    /// `delivery_started` is 0: no claim ever offered it to the server.
    case neverSent
    /// It was offered, and no refusal is recorded: whether the server applied it is unknown here.
    case sent
    /// The server answered it with a client-error status: that send changed nothing.
    case refused(status: Int, type: String?, message: String)
  }

  package var id: String
  /// Every write operation it has; nil when its body does not decode.
  package var slots: [InstantHeldWriteSlot]?
  package var delivery: Delivery

  package init(id: String, slots: [InstantHeldWriteSlot]?, delivery: Delivery) {
    self.id = id
    self.slots = slots
    self.delivery = delivery
  }

  /// The delivery a kept row records: `deliveryStarted` is its `delivery_started` column (nil for a row older than it,
  /// which counts as offered, as migration 0012 counts it), and `mutation` its decoded body.
  package static func delivery(deliveryStarted: Bool?, mutation: PendingMutation?) -> Delivery {
    if deliveryStarted == false { return .neverSent }
    // Only an answer from the server counts as a refusal: a status in 400..<500 says it refused that send, which then
    // changed nothing. A failure recorded without one (a local failure, or a body older than structured failures) does
    // not say the server saw the write.
    if let mutation, mutation.status == .failed, let failure = mutation.failure, let status = failure.status,
      (400..<500).contains(status)
    {
      return .refused(status: status, type: failure.type, message: failure.message)
    }
    return .sent
  }
}

/// What a one-shot read of the server's own rows came back with (#696).
package enum InstantServerRowsRead: Sendable {
  /// The rows the server's answers carried, in this device's attribute IDs.
  case rows([InstantTriple])
  /// The server could not be read: the error's message.
  case failed(String)
}

extension InstantQuarantinedMutationVerification {
  /// The verdict on what was read: pure, so every rule is tested without a socket (#696).
  ///
  /// Applied needs every slot covered: the server's rows hold the write's value, or a later write of this device that
  /// the server accepted set the slot. Otherwise only the delivery record can say it is not applied: it never left this
  /// device, or the server refused it. Anything else cannot be told, because a value that differs may be a later write
  /// over one that landed.
  package init(
    evidence: InstantHeldWriteEvidence,
    serverRead: InstantServerRowsRead,
    verifiedAt: InstantTimestamp
  ) {
    guard let heldSlots = evidence.slots else {
      self.init(id: evidence.id, verifiedAt: verifiedAt, verdict: .cannotTell(.undecodable), slots: [])
      return
    }
    let rows: [InstantTriple]
    switch serverRead {
    case let .failed(message):
      self.init(id: evidence.id, verifiedAt: verifiedAt, verdict: .cannotTell(.serverUnreadable(message)), slots: [])
      return
    case let .rows(read):
      rows = read
    }
    var serverValues: [InstantVisibleWriteKey: [InstantValue]] = [:]
    for row in rows {
      serverValues[InstantVisibleWriteKey(entityID: row.entityID, attributeID: row.attributeID), default: []]
        .append(row.value)
    }
    let slots = heldSlots.map { slot in
      let values = serverValues[InstantVisibleWriteKey(entityID: slot.entityID, attributeID: slot.attributeID)] ?? []
      let coverage: InstantSlotCoverage.Coverage
      if slot.uncheckable != nil {
        coverage = .notCheckable
      } else if let value = slot.value, Self.serverHolds(value, operation: slot.operation, among: values) {
        coverage = .serverResult(receivedAt: verifiedAt)
      } else if let laterWrite = slot.laterWrite {
        coverage = laterWrite
      } else {
        coverage = .notCovered(
          serverValues: values.sorted { $0.comparableKey < $1.comparableKey }
        )
      }
      return InstantSlotCoverage(
        entityID: slot.entityID,
        namespace: slot.namespace,
        attributeName: slot.attributeName,
        attributeID: slot.attributeID,
        operation: slot.operation,
        value: slot.value,
        coverage: coverage
      )
    }
    let firstUncheckable = heldSlots.first { $0.uncheckable != nil }?.uncheckable
    let everySlotCovered = slots.allSatisfy { slot in
      switch slot.coverage {
      case .serverResult, .laterAcceptedWrite: true
      case .laterPendingWrite, .notCovered, .notCheckable: false
      }
    }
    let verdict: Verdict
    if !slots.isEmpty, firstUncheckable == nil, everySlotCovered {
      verdict = .applied
    } else {
      switch evidence.delivery {
      case .neverSent:
        verdict = .notApplied(.neverSent)
      case let .refused(status, type, message):
        verdict = .notApplied(.refusedByServer(status: status, type: type, message: message))
      case .sent:
        if let firstUncheckable {
          verdict = .cannotTell(.uncheckableOperation(firstUncheckable))
        } else if slots.isEmpty {
          verdict = .cannotTell(.uncheckableOperation("no write operation"))
        } else {
          verdict = .cannotTell(.serverDoesNotHoldIt)
        }
      }
    }
    self.init(id: evidence.id, verifiedAt: verifiedAt, verdict: verdict, slots: slots)
  }

  /// Whether the server's values for a slot hold what the write set there. A set (`insert`) holds when one of them is
  /// its value; a deep merge holds when the server's object already contains its patch.
  package static func serverHolds(
    _ written: InstantValue,
    operation: InstantSlotCoverage.Operation,
    among serverValues: [InstantValue]
  ) -> Bool {
    switch operation {
    case .insert:
      return serverValues.contains { valuesMatch($0, written) }
    case .merge:
      guard case let .json(patch) = written else {
        return serverValues.contains { valuesMatch($0, written) }
      }
      return serverValues.contains { server in
        guard case let .json(current) = server else { return false }
        return jsonContains(current, patch)
      }
    case .other:
      return false
    }
  }

  /// Equal values, with a date compared at the millisecond the wire carries and a link's ID equal to the same ID as text.
  package static func valuesMatch(_ server: InstantValue, _ written: InstantValue) -> Bool {
    switch (server, written) {
    case let (.date(lhs), .date(rhs)):
      (lhs.timeIntervalSince1970 * 1_000).rounded() == (rhs.timeIntervalSince1970 * 1_000).rounded()
    case let (.ref(lhs), .string(rhs)), let (.string(lhs), .ref(rhs)):
      lhs == rhs
    default:
      server == written
    }
  }

  /// Whether `current` already holds `patch` as a deep merge leaves it: every key of an object patch holds its value,
  /// recursively; any other patch replaces the value. A patch with a null is never passed here: removing a key is a
  /// slot the server's rows cannot vouch for (see ``InstantHeldWriteSlot/uncheckable``).
  private static func jsonContains(_ current: JSONValue, _ patch: JSONValue) -> Bool {
    guard case let .object(patchObject) = patch else { return current == patch }
    guard case let .object(currentObject) = current else { return false }
    return patchObject.allSatisfy { key, value in
      guard let held = currentObject[key] else { return false }
      return jsonContains(held, value)
    }
  }

  /// One read of the server's own rows per entity a checkable slot names: the entity by ID, the attributes it set,
  /// and each link it set, limited to the linked IDs. A slot whose attribute this device does not know is uncheckable
  /// before this, so every slot here has a namespace and a name.
  package static func serverReadPlans(for slots: [InstantHeldWriteSlot]) -> [InstantQueryPlan] {
    var order: [String] = []
    var byEntity: [String: [InstantHeldWriteSlot]] = [:]
    for slot in slots where slot.uncheckable == nil {
      guard let namespace = slot.namespace, slot.attributeName != nil else { continue }
      let key = "\(namespace)\u{0}\(slot.entityID)"
      if byEntity[key] == nil { order.append(key) }
      byEntity[key, default: []].append(slot)
    }
    return order.compactMap { key -> InstantQueryPlan? in
      guard let entitySlots = byEntity[key], let first = entitySlots.first, let namespace = first.namespace else {
        return nil
      }
      var fields: [String] = ["id"]
      var links: [String: (namespace: String, targets: [InstantValue])] = [:]
      var linkOrder: [String] = []
      for slot in entitySlots {
        guard let name = slot.attributeName else { continue }
        if let linkNamespace = slot.linkNamespace {
          if links[name] == nil { linkOrder.append(name) }
          let target = slot.value.flatMap { value -> InstantValue? in
            switch value {
            case let .ref(id), let .string(id): .string(id)
            default: nil
            }
          }
          links[name, default: (namespace: linkNamespace, targets: [])].targets
            .append(contentsOf: target.map { [$0] } ?? [])
        } else if !fields.contains(name) {
          fields.append(name)
        }
      }
      let includes = linkOrder.compactMap { name -> InstantQueryInclude? in
        guard let link = links[name], !link.targets.isEmpty else { return nil }
        var plan = InstantQueryIncludePlan(
          id: "held-write-verification.\(first.entityID).\(name)",
          namespace: link.namespace,
          filters: [.in(field: "id", values: link.targets)],
          selectedFields: ["id"]
        )
        plan.limit = link.targets.count
        return InstantQueryInclude(name, direction: .forward, query: plan)
      }
      return InstantQueryPlan(
        id: "held-write-verification.\(first.entityID)",
        namespace: namespace,
        filters: [.equals(field: "id", value: .string(first.entityID))],
        selectedFields: fields,
        includes: includes
      )
    }
  }
}

extension InstantQuarantinedMutationVerification.Verdict {
  /// The verdict in a sentence, for an error or a log line.
  package var summary: String {
    switch self {
    case .applied:
      "the server holds what it set"
    case .notApplied(.neverSent):
      "it never left this device"
    case let .notApplied(.refusedByServer(status, _, message)):
      "the server refused it (\(status): \(message))"
    case .cannotTell(.serverDoesNotHoldIt):
      "it was sent and the server's rows do not hold what it set, so a later write may have replaced it"
    case let .cannotTell(.uncheckableOperation(kind)):
      "its \(kind) is an effect the server's rows cannot show"
    case let .cannotTell(.serverUnreadable(message)):
      "the server could not be read (\(message))"
    case .cannotTell(.undecodable):
      "its body no longer decodes"
    }
  }
}

// MARK: - The server's answers to reads of its own rows

/// The server's answers to one-shot reads of its own rows, kept for the reads that wait on them (#696).
///
/// A read registers its query's key before it sends `add-query`; the receive path offers each `add-query-ok` here
/// before the answer is applied to this device's store, and the read takes the answer's rows as the server sent them.
/// A key no read waits on is not kept, so every other answer costs one lookup.
final class InstantServerAnswerCaptures: Sendable {
  /// One `add-query-ok`, as it arrived.
  struct Answer: Sendable {
    var result: [InstantLiveJSONValue]
    var serverAttributes: [InstantLiveJSONValue]
    var processedTransactionID: String?
  }

  private struct State {
    var waiting: [String: Int] = [:]
    var answers: [String: Answer] = [:]
  }

  private let state = OSAllocatedUnfairLock(initialState: State())

  /// A read of `key` waits for its answer from now on.
  func expect(_ key: String) {
    state.withLock { $0.waiting[key, default: 0] += 1 }
  }

  /// Keeps the answer for `key` when a read waits on it.
  func offer(key: String, answer: @autoclosure () -> Answer) {
    guard state.withLock({ $0.waiting[key] != nil }) else { return }
    let answer = answer()
    state.withLock { state in
      guard state.waiting[key] != nil else { return }
      state.answers[key] = answer
    }
  }

  /// The newest answer for `key`, if one arrived since a read began waiting.
  func answer(for key: String) -> Answer? {
    state.withLock { $0.answers[key] }
  }

  /// A read of `key` stopped waiting; the last one to stop drops its answer.
  func forget(_ key: String) {
    state.withLock { state in
      guard let count = state.waiting[key] else { return }
      if count > 1 {
        state.waiting[key] = count - 1
      } else {
        state.waiting[key] = nil
        state.answers[key] = nil
      }
    }
  }
}

/// How a held write was settled (#696): the values `instant_outbox_quarantined.resolution` takes for it.
package enum InstantQuarantinedMutationSettlement: Sendable {
  case completed
  case discarded

  var resolution: String {
    switch self {
    case .completed: SQLitePersistenceStore.quarantineResolutionCompleted
    case .discarded: SQLitePersistenceStore.quarantineResolutionDiscarded
    }
  }

  var operation: String {
    switch self {
    case .completed: "complete a quarantined mutation"
    case .discarded: "discard a quarantined mutation"
    }
  }

  /// Whether a verification allows this settlement: completing needs applied, discarding needs not applied.
  func isAllowed(by verdict: InstantQuarantinedMutationVerification.Verdict) -> Bool {
    switch (self, verdict) {
    case (.completed, .applied), (.discarded, .notApplied): true
    default: false
    }
  }
}
