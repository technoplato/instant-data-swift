import CustomDump
import Foundation
import Testing

@testable import InstantSwiftDataCore

/// A mutation the server has already accepted must never be offered for delivery again.
///
/// `confirmationSource` was added after `serverTransactionID`, so every mutation accepted by an
/// earlier build carries a server-assigned transaction ID and no source. Asking only
/// `confirmationSource?.provesServerAcceptance != true` answers "not proven" for all of them, and
/// they are re-sent on every inbound server event, forever.
///
/// Measured on a Mac Scribe diagnostics store on 2026-08-04: 7,928 outbox rows, of which 6,887 were
/// confirmed, carried a `serverTransactionID`, and had no `confirmationSource`. All 6,887 were
/// re-offered on every server event. The process held ~200% CPU indefinitely while the store stayed
/// byte-for-byte identical — it was re-sending already-accepted work, not making progress.
@Suite(.serialized)
struct InstantServerAcceptanceProofTests {

  /// `Outbox.accepting(id:serverTransactionID:)` is the only writer of `serverTransactionID`, and
  /// it is reached only from a server `transact-ok` carrying a server-assigned `tx-id`. The two
  /// rollback paths clear it. So a non-nil value is proof, independent of `confirmationSource`.
  @Test
  func aServerAssignedTransactionIDIsProofOfAcceptance() {
    var legacy = PendingMutation(
      id: "legacy-accepted",
      createdAt: InstantTimestamp(milliseconds: 1),
      transaction: InstantStoreTransaction(id: "legacy-accepted", operations: []),
      status: .confirmed
    )
    legacy.serverTransactionID = "2608566264"
    legacy.confirmationSource = nil
    #expect(legacy.provesServerAcceptance)

    var current = PendingMutation(
      id: "current-accepted",
      createdAt: InstantTimestamp(milliseconds: 2),
      transaction: InstantStoreTransaction(id: "current-accepted", operations: []),
      status: .confirmed
    )
    current.serverTransactionID = "2608566265"
    current.confirmationSource = .webSocketTransactOK
    #expect(current.provesServerAcceptance)
  }

  /// A local receipt is not the server's word. These must still be delivered.
  @Test
  func localReceiptsAreNotProofOfAcceptance() {
    for source in [
      InstantMutationConfirmationSource.manual,
      .localDrain,
      .localTransport,
    ] {
      var mutation = PendingMutation(
        id: "local-\(source.rawValue)",
        createdAt: InstantTimestamp(milliseconds: 3),
        transaction: InstantStoreTransaction(id: "local-\(source.rawValue)", operations: []),
        status: .confirmed
      )
      mutation.confirmationSource = source
      #expect(
        !mutation.provesServerAcceptance,
        "\(source.rawValue) is a local receipt and must not suppress delivery"
      )
    }

    let pending = PendingMutation(
      id: "still-pending",
      createdAt: InstantTimestamp(milliseconds: 4),
      transaction: InstantStoreTransaction(id: "still-pending", operations: []),
      status: .pending
    )
    #expect(!pending.provesServerAcceptance)
  }

  /// The end-to-end consequence: a legacy-shaped accepted mutation is not offered to the transport.
  /// Before the fix this returned the legacy mutation on every call, which is what turned a large
  /// outbox into a permanent resend loop.
  @Test
  func acceptedLegacyMutationsAreNotOfferedToTheTransport() async throws {
    let cacheURL = try temporaryServerAcceptanceCacheURL()
    let persistence = try SQLitePersistenceStore(fileURL: cacheURL)
    try await persistence.bootstrap()

    var legacyAccepted = PendingMutation(
      id: "legacy-accepted",
      createdAt: InstantTimestamp(milliseconds: 1),
      transaction: InstantStoreTransaction(
        id: "legacy-accepted",
        operations: TodoExample.createOperations(
          id: "todo-legacy-accepted",
          text: "already accepted by the server",
          createdAt: InstantTimestamp(milliseconds: 1),
          transactionID: "legacy-accepted"
        )
      ),
      status: .confirmed
    )
    legacyAccepted.serverTransactionID = "2608566264"
    legacyAccepted.confirmationSource = nil
    legacyAccepted.optimisticOverlayState = .applied

    var stillUnsent = PendingMutation(
      id: "still-unsent",
      createdAt: InstantTimestamp(milliseconds: 2),
      transaction: InstantStoreTransaction(
        id: "still-unsent",
        operations: TodoExample.createOperations(
          id: "todo-still-unsent",
          text: "never reached the server",
          createdAt: InstantTimestamp(milliseconds: 2),
          transactionID: "still-unsent"
        )
      ),
      status: .pending
    )
    stillUnsent.optimisticOverlayState = .applied
    stillUnsent.optimisticEffectReceiptVersion =
      PendingMutation.currentOptimisticEffectReceiptVersion
    stillUnsent.rollbackTransaction = InstantStoreTransaction(
      id: "rollback-still-unsent",
      operations: [.deleteEntity("todo-still-unsent")]
    )

    let materializedTriples: [InstantTriple] = [legacyAccepted, stillUnsent].flatMap {
      mutation in
      mutation.transaction.operations.compactMap { operation -> InstantTriple? in
        guard case let .insert(triple) = operation else { return nil }
        return triple
      }
    }

    let didSave = try await persistence.saveLiveRefresh(
      InstantPersistenceSnapshot(
        store: InstantStoreSnapshot(
          attributes: TodoExample.attributes,
          triples: materializedTriples
        ),
        outbox: [legacyAccepted]
      ),
      queryResults: [],
      storeChanged: true,
      outboxChanged: true,
      metadataKey: "test.server-acceptance-proof",
      metadataValue: "seeded",
      metadataUpdatedAt: InstantTimestamp(milliseconds: 2),
      expectedStoreRevision: 0,
      expectedOutboxRevision: 0,
      expectedAttributeRevision: 0
    )
    expectNoDifference(didSave, true)
    let publicSeed = try await persistence.loadCompactState()
    let didSeedPreparedPendingTail = try await persistence.saveOutbox(
      [legacyAccepted, stillUnsent],
      replacing: [legacyAccepted],
      metadataEntries: [],
      expectedStoreRevision: publicSeed.storeRevision,
      expectedOutboxRevision: publicSeed.outboxRevision
    )
    expectNoDifference(didSeedPreparedPendingTail, true)
    let acceptedFingerprint = try await persistence
      .optimisticEffectReceiptFingerprintForTesting(id: legacyAccepted.id)
    expectNoDifference(
      acceptedFingerprint,
      nil
    )
    #expect(
      try await persistence.optimisticEffectReceiptFingerprintForTesting(
        id: stillUnsent.id
      ) != nil
    )

    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "server-acceptance-proof",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )

    let offered = await runtime.outboxTransportMutations()

    expectNoDifference(
      offered.map(\.id),
      ["still-unsent"],
      """
      Only the mutation the server has never seen may be offered for delivery.

      Offering an already-accepted mutation is not merely wasteful: the outbox is rebuilt on every \
      inbound server event, so re-offering accepted work makes each server response produce another \
      send, which produces another response. That loop is what pinned a Mac at ~200% CPU with a \
      byte-for-byte unchanging store.
      """
    )
  }
}

private func temporaryServerAcceptanceCacheURL() throws -> URL {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("InstantServerAcceptanceProofTests-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  return directory.appendingPathComponent("state.sqlite")
}
