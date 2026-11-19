// History:
// - 2026-11-19: added (#1497, #2551): an acknowledgement of a write saved in this process uses the body its save stored.

import CustomDump
import Foundation
import Testing

@testable import InstantSwiftDataCore

/// #1497 (#2551): the server's acknowledgement of a write decoded the write's whole stored body, though the save that
/// stored those exact bytes held the value: 262 of 485 acknowledgement samples (54%) in a 3.6-hour Power Profiler trace,
/// about half of the 1.97 ms an acknowledgement took on a phone. The save keeps the body it stored, found by the digest
/// of the stored bytes as the receipt fingerprint is (#1523), and an acknowledgement whose row holds those bytes uses it.
///
/// These tests pin that, that the acceptance is the one decoding the row gives, that a store that did not save the write
/// decodes as before, and the round trip the reuse rests on (the decoded body equals the body encoded) for every kind of
/// value and operation a body holds.
@Suite(.serialized)
struct InstantAcknowledgementBodyReuseTests {
  /// One write saved through the runtime, claimed and acknowledged on the same store: no body is decoded, and the
  /// acceptance equals what the acknowledged row decodes to.
  @Test
  func anAcknowledgementOfAWriteSavedInThisProcessDecodesNoBody() async throws {
    let url = try InstantStoredResultReloadTests.temporaryCacheURL()
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "acknowledgement-body-reuse",
        persistenceURL: url,
        initialAttributes: TodoExample.attributes
      )
    )
    let saved = try await runtime.transact(
      operations: TodoExample.createOperations(
        id: "todo-1",
        text: "A line with \"quotes\", a / and an \u{e9}",
        createdAt: InstantTimestamp(milliseconds: 1_000),
        transactionID: "write-1"
      )
    )
    let claim = try await runtime.persistence.claimAutomaticOutboxDeliveryWindow(
      InstantAutomaticOutboxClaimRequest(
        claimantID: "acknowledging-runtime",
        claimToken: "acknowledging-token",
        now: InstantTimestamp(milliseconds: 2_000),
        maximumMutationCount: 1
      )
    )
    expectNoDifference(claim.mutations.map(\.id), [saved.transactionID])
    let revision = try await runtime.persistence.currentOutboxRevision()
    await runtime.persistence.resetDecodedOutboxBodyCount()

    let acceptance = try await runtime.persistence.acceptOutboxMutation(
      id: saved.transactionID,
      serverTransactionID: "server-1",
      claimantID: "acknowledging-runtime",
      claimToken: "acknowledging-token",
      expectedOutboxRevision: revision
    )
    let decodedForTheAcknowledgement = await runtime.persistence.currentDecodedOutboxBodyCount()

    expectNoDifference(decodedForTheAcknowledgement, 0)
    expectNoDifference(acceptance?.didChange, true)
    let accepted = try #require(acceptance?.mutation)
    expectNoDifference(accepted.status, .confirmed)
    expectNoDifference(accepted.serverTransactionID, "server-1")
    let stored = try #require(
      try await runtime.persistence.loadOutboxMutations(
        statuses: [.pending, .confirmed, .failed],
        ids: [saved.transactionID],
        limit: 1,
        expectedOutboxRevision: try await runtime.persistence.currentOutboxRevision()
      )?.first
    )
    expectNoDifference(accepted, stored)
  }

  /// A store that did not save the write (another process, or this one before a relaunch) decodes the row's body, as
  /// before, and accepts it the same way.
  @Test
  func anAcknowledgementOnAStoreThatDidNotSaveTheWriteDecodesItsBody() async throws {
    let url = try InstantStoredResultReloadTests.temporaryCacheURL()
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "acknowledgement-body-decode",
        persistenceURL: url,
        initialAttributes: TodoExample.attributes
      )
    )
    let saved = try await runtime.transact(
      operations: TodoExample.createOperations(
        id: "todo-2",
        text: "Saved by the runtime",
        createdAt: InstantTimestamp(milliseconds: 1_000),
        transactionID: "write-2"
      )
    )
    let other = try SQLitePersistenceStore(fileURL: url)
    try await other.bootstrap()
    let claim = try await other.claimAutomaticOutboxDeliveryWindow(
      InstantAutomaticOutboxClaimRequest(
        claimantID: "other-store",
        claimToken: "other-token",
        now: InstantTimestamp(milliseconds: 2_000),
        maximumMutationCount: 1
      )
    )
    expectNoDifference(claim.mutations.map(\.id), [saved.transactionID])
    let revision = try await other.currentOutboxRevision()
    await other.resetDecodedOutboxBodyCount()

    let acceptance = try await other.acceptOutboxMutation(
      id: saved.transactionID,
      serverTransactionID: "server-2",
      claimantID: "other-store",
      claimToken: "other-token",
      expectedOutboxRevision: revision
    )
    let decodedForTheAcknowledgement = await other.currentDecodedOutboxBodyCount()

    expectNoDifference(decodedForTheAcknowledgement, 1)
    expectNoDifference(acceptance?.didChange, true)
    let accepted = try #require(acceptance?.mutation)
    let stored = try #require(
      try await other.loadOutboxMutations(
        statuses: [.pending, .confirmed, .failed],
        ids: [saved.transactionID],
        limit: 1,
        expectedOutboxRevision: try await other.currentOutboxRevision()
      )?.first
    )
    expectNoDifference(accepted, stored)
  }

  /// What an acknowledgement reuses equals what it would decode: a stored body, encoded as the store encodes it and
  /// decoded as it decodes it, is the same value, for every value kind, operation and optional field a body carries.
  @Test
  func aStoredBodyDecodesToTheValueThatWasEncoded() throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let decoder = JSONDecoder()
    for (index, mutation) in Self.corpus.enumerated() {
      let body = SQLitePersistenceStore.storedOutboxBody(mutation)
      let decoded = try decoder.decode(PendingMutation.self, from: encoder.encode(body))
      expectNoDifference(decoded, body, "mutation \(index)")
    }
  }

  static let values: [InstantValue] = [
    .null,
    .string(""),
    .string("plain"),
    .string("quote \" backslash \\ slash / newline \n tab \t \u{e9} \u{6c49}\u{5b57} \u{1f399}"),
    .number(0),
    .number(-0.0),
    .number(1),
    .number(-1.5),
    .number(0.1),
    .number(1e300),
    .number(Double.leastNonzeroMagnitude),
    .number(9_007_199_254_740_993),
    .number(1_795_000_000_123),
    .bool(true),
    .bool(false),
    .date(Date(timeIntervalSince1970: 1_795_000_000.123)),
    .date(Date(timeIntervalSinceReferenceDate: -1.5)),
    .json(
      .object([
        "list": .array([.number(1), .number(2.5), .string("x"), .null, .bool(true)]),
        "nested": .object(["empty": .object([:]), "none": .array([])]),
      ])
    ),
    .ref("entity-2"),
    .lookupRef(InstantLookupRef(attributeID: "todos/text", value: .string("by text"))),
    .lookupRef(InstantLookupRef(attributeID: "todos/createdAt", value: .number(12.5))),
  ]

  static func fact(_ index: Int, _ value: InstantValue) -> InstantTriple {
    InstantTriple(
      entityID: "entity-\(index)",
      attributeID: "todos/text",
      value: value,
      txID: "tx-\(index)",
      txTime: InstantTimestamp(milliseconds: 1_000 + Int64(index))
    )
  }

  static let corpus: [PendingMutation] = {
    let lookup = InstantLookupRef(attributeID: "todos/text", value: .string("by text"))
    let operations: [InstantTripleOperation] =
      values.enumerated().map { .insert(fact($0.offset, $0.element)) }
      + values.enumerated().map { .merge(fact($0.offset, $0.element)) }
      + values.enumerated().map { .retract(fact($0.offset, $0.element)) }
      + [
        .requireEntityMissing(entityID: "entity-1", namespace: "todos"),
        .requireEntityMissing(entityID: "entity-1", namespace: nil),
        .requireEntityMissingByLookup(lookup, namespace: "todos"),
        .requireEntityExists(entityID: "entity-1", namespace: "todos"),
        .requireEntityExistsByLookup(lookup, namespace: nil),
        .requireTripleExists(entityID: "entity-1", attributeID: "todos/text", value: .string("x")),
        .mergeByLookup(
          entity: lookup, attributeID: "todos/text", value: .number(3), txID: "tx",
          txTime: InstantTimestamp(milliseconds: 5)
        ),
        .insertByLookup(
          entity: lookup, attributeID: "todos/text", value: .bool(true), txID: "tx",
          txTime: InstantTimestamp(milliseconds: 6)
        ),
        .retractByLookup(
          entity: lookup, attributeID: "todos/text", value: .null, txID: "tx",
          txTime: InstantTimestamp(milliseconds: 7)
        ),
        .deleteEntity("entity-3"),
        .deleteEntityInNamespace(entityID: "entity-4", namespace: "todos"),
        .deleteEntityByLookup(lookup),
        .ruleParams(entityID: "entity-5", namespace: "todos", params: .object(["k": .number(1)])),
        .ruleParamsByLookup(entity: lookup, namespace: "todos", params: .array([.string("p")])),
      ]
    var plain = PendingMutation(
      id: "mutation-plain",
      createdAt: InstantTimestamp(milliseconds: 1_000),
      transaction: InstantStoreTransaction(id: "mutation-plain", operations: operations)
    )
    plain.optimisticOverlayState = .applied
    plain.optimisticEffectReceiptVersion = PendingMutation.currentOptimisticEffectReceiptVersion
    plain.rollbackTransaction = InstantStoreTransaction(
      id: "mutation-plain",
      operations: values.enumerated().map { .retract(fact($0.offset, $0.element)) }
    )
    var failed = plain
    failed.id = "mutation-failed"
    failed.transaction.id = "mutation-failed"
    failed.status = .failed
    failed.failureMessage = "The server refused it."
    failed.failure = InstantMutationFailure(
      code: .permissionRejected,
      message: "Refused",
      status: 400,
      type: "permission-denied",
      hint: .object(["count": .number(2), "fraction": .number(2.5), "items": .array([.string("a"), .null])]),
      traceID: "trace",
      originalEventTraceID: "original-trace"
    )
    var confirmed = plain
    confirmed.id = "mutation-confirmed"
    confirmed.transaction.id = "mutation-confirmed"
    confirmed.status = .confirmed
    confirmed.serverTransactionID = "server-tx"
    confirmed.confirmationSource = .webSocketTransactOK
    var removed = plain
    removed.id = "mutation-removed"
    removed.transaction.id = "mutation-removed"
    removed.optimisticOverlayState = .removed
    removed.rollbackTransaction = nil
    let bare = PendingMutation(
      id: "mutation-bare",
      createdAt: InstantTimestamp(milliseconds: 0),
      transaction: InstantStoreTransaction(id: "mutation-bare", operations: [])
    )
    return [plain, failed, confirmed, removed, bare]
  }()
}
