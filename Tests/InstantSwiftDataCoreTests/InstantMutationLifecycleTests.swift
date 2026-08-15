import CustomDump
import Foundation
import SQLite3
@testable import InstantSwiftDataCore
import Testing

@Suite(.serialized)
struct InstantMutationLifecycleTests {
  @Test
  func explicitServerTransportPublishesTransactionSpecificAcceptance() async throws {
    let runtime = try await mutationLifecycleRuntime(
      "accepted",
      mutationTransport: InstantMutationTransportClient { request in
        InstantMutationTransportResponse(
          results: request.mutations.map {
            InstantMutationTransportResult(
              mutationID: $0.mutationID,
              outcome: .confirmed,
              acceptance: .serverAccepted
            )
          }
        )
      }
    )
    let lifecycle = try await runtime.observeMutationLifecycle(id: "tx-accepted")
    var iterator = lifecycle.makeAsyncIterator()
    let initial = await iterator.next()
    expectNoDifference(initial, .waiting)

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-accepted",
        operations: TodoExample.createOperations(
          id: "todo-accepted",
          text: "Optimistic",
          createdAt: InstantTimestamp(milliseconds: 1_700_000_500_000),
          transactionID: "tx-accepted"
        )
      )
    )
    _ = try await runtime.flushPendingMutations()

    guard case let .serverAccepted(mutation) = await iterator.next() else {
      Issue.record("Expected transaction-specific server acceptance.")
      return
    }
    expectNoDifference(mutation.id, "tx-accepted")
    expectNoDifference(mutation.status, .confirmed)
  }

  @Test
  func durableFailurePublishesTransactionSpecificFailure() async throws {
    let runtime = try await mutationLifecycleRuntime("failed")
    let lifecycle = try await runtime.observeMutationLifecycle(id: "tx-failed")
    var iterator = lifecycle.makeAsyncIterator()
    let initial = await iterator.next()
    expectNoDifference(initial, .waiting)

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-failed",
        operations: TodoExample.createOperations(
          id: "todo-failed",
          text: "Rejected",
          createdAt: InstantTimestamp(milliseconds: 1_700_000_500_001),
          transactionID: "tx-failed"
        )
      )
    )
    _ = try await runtime.failMutation(id: "tx-failed", message: "permission denied")

    guard case let .failed(mutation) = await iterator.next() else {
      Issue.record("Expected transaction-specific failure.")
      return
    }
    expectNoDifference(mutation.id, "tx-failed")
    expectNoDifference(mutation.status, .failed)
    expectNoDifference(mutation.failureMessage, "permission denied")
  }

  @Test
  func publicAcceptedShapedBodyWithoutSQLiteAuthorityRemainsWaiting() async throws {
    let cacheURL = mutationLifecycleCacheURL("untrusted-accepted")
    let persistence = try SQLitePersistenceStore(fileURL: cacheURL)
    try await persistence.bootstrap()

    var mutation = PendingMutation(
      id: "tx-untrusted-accepted",
      createdAt: InstantTimestamp(milliseconds: 1_700_000_500_002),
      transaction: InstantStoreTransaction(
        id: "tx-untrusted-accepted",
        operations: TodoExample.createOperations(
          id: "todo-untrusted-accepted",
          text: "Caller-shaped acceptance",
          createdAt: InstantTimestamp(milliseconds: 1_700_000_500_002),
          transactionID: "tx-untrusted-accepted"
        )
      )
    )
    mutation.status = .confirmed
    mutation.serverTransactionID = "forged-server-transaction"
    mutation.confirmationSource = .webSocketTransactOK
    try await persistence.saveOutbox([mutation])

    let runtime = try await mutationLifecycleRuntime(
      "untrusted-accepted",
      cacheURL: cacheURL
    )
    let lifecycle = try await runtime.observeMutationLifecycle(id: mutation.id)
    var iterator = lifecycle.makeAsyncIterator()
    let initial = await iterator.next()
    expectNoDifference(initial, .waiting)
  }

  @Test
  func publicFailedBodyWithoutSQLiteReceiptReportsUnknownLocalEffect() async throws {
    let cacheURL = mutationLifecycleCacheURL("untrusted-failed")
    let persistence = try SQLitePersistenceStore(fileURL: cacheURL)
    try await persistence.bootstrap()

    let transaction = InstantStoreTransaction(
      id: "tx-untrusted-failed",
      operations: TodoExample.createOperations(
        id: "todo-untrusted-failed",
        text: "Caller-shaped rollback",
        createdAt: InstantTimestamp(milliseconds: 1_700_000_500_003),
        transactionID: "tx-untrusted-failed"
      )
    )
    var mutation = PendingMutation(
      id: transaction.id,
      createdAt: InstantTimestamp(milliseconds: 1_700_000_500_003),
      transaction: transaction
    )
    mutation.status = .failed
    mutation.failureMessage = "permission denied"
    mutation.optimisticOverlayState = .applied
    mutation.optimisticEffectReceiptVersion =
      PendingMutation.currentOptimisticEffectReceiptVersion
    mutation.rollbackTransaction = InstantStoreTransaction(
      id: "rollback-\(transaction.id)",
      operations: [.deleteEntity("todo-untrusted-failed")]
    )
    try await persistence.saveOutbox([mutation])

    let runtime = try await mutationLifecycleRuntime(
      "untrusted-failed",
      cacheURL: cacheURL
    )
    let lifecycle = try await runtime.observeMutationLifecycle(id: mutation.id)
    var iterator = lifecycle.makeAsyncIterator()
    guard case let .failed(failed) = await iterator.next() else {
      Issue.record("Expected the untrusted failed row to remain a failed lifecycle event.")
      return
    }
    expectNoDifference(failed.id, mutation.id)
    expectNoDifference(failed.optimisticOverlayState, nil)
    expectNoDifference(failed.rollbackTransaction, nil)
    #expect(failed.isLegacyUnknownOverlayCandidate)
  }

  @Test
  func preReceiptAuthorityTerminalAcceptanceRemainsWaitingAfterRelaunch() async throws {
    let cacheURL = mutationLifecycleCacheURL("pre-receipt-terminal-acceptance")
    var terminal = PendingMutation(
      id: "tx-pre-receipt-terminal-accepted-current",
      createdAt: InstantTimestamp(milliseconds: 1_700_000_500_004),
      transaction: InstantStoreTransaction(
        id: "tx-pre-receipt-terminal-accepted-current",
        operations: TodoExample.createOperations(
          id: "todo-pre-receipt-terminal-accepted",
          text: "Body-only acceptance",
          createdAt: InstantTimestamp(milliseconds: 1_700_000_500_004),
          transactionID: "tx-pre-receipt-terminal-accepted-current"
        )
      )
    )
    terminal.status = .confirmed
    terminal.serverTransactionID = "forged-server-transaction"
    terminal.confirmationSource = .webSocketTransactOK
    terminal.optimisticOverlayState = .applied
    terminal.optimisticEffectReceiptVersion =
      PendingMutation.currentOptimisticEffectReceiptVersion
    terminal.rollbackTransaction = InstantStoreTransaction(
      id: "rollback-\(terminal.id)",
      operations: [.deleteEntity("todo-pre-receipt-terminal-accepted")]
    )
    try await seedPreReceiptAuthorityTerminalLifecycle(
      cacheURL: cacheURL,
      lifecycleID: "tx-pre-receipt-terminal-accepted-original",
      terminalMutation: terminal
    )

    let relaunched = try await mutationLifecycleRuntime(
      "pre-receipt-terminal-acceptance",
      cacheURL: cacheURL
    )
    let lifecycle = try await relaunched.observeMutationLifecycle(
      id: "tx-pre-receipt-terminal-accepted-original"
    )
    var iterator = lifecycle.makeAsyncIterator()
    let initial = await iterator.next()
    expectNoDifference(
      initial,
      .waiting,
      "A pre-0021 terminal body cannot authenticate its own server-acceptance claim."
    )
  }

  @Test
  func preReceiptAuthorityTerminalFailureReportsUnknownLocalEffectAfterRelaunch()
    async throws
  {
    let cacheURL = mutationLifecycleCacheURL("pre-receipt-terminal-failure")
    var terminal = PendingMutation(
      id: "tx-pre-receipt-terminal-failed-current",
      createdAt: InstantTimestamp(milliseconds: 1_700_000_500_005),
      transaction: InstantStoreTransaction(
        id: "tx-pre-receipt-terminal-failed-current",
        operations: TodoExample.createOperations(
          id: "todo-pre-receipt-terminal-failed",
          text: "Body-only rollback",
          createdAt: InstantTimestamp(milliseconds: 1_700_000_500_005),
          transactionID: "tx-pre-receipt-terminal-failed-current"
        )
      )
    )
    terminal.status = .failed
    terminal.failureMessage = "permission denied"
    terminal.optimisticOverlayState = .applied
    terminal.optimisticEffectReceiptVersion =
      PendingMutation.currentOptimisticEffectReceiptVersion
    terminal.rollbackTransaction = InstantStoreTransaction(
      id: "rollback-\(terminal.id)",
      operations: [.deleteEntity("todo-pre-receipt-terminal-failed")]
    )
    try await seedPreReceiptAuthorityTerminalLifecycle(
      cacheURL: cacheURL,
      lifecycleID: "tx-pre-receipt-terminal-failed-original",
      terminalMutation: terminal
    )

    let relaunched = try await mutationLifecycleRuntime(
      "pre-receipt-terminal-failure",
      cacheURL: cacheURL
    )
    let lifecycle = try await relaunched.observeMutationLifecycle(
      id: "tx-pre-receipt-terminal-failed-original"
    )
    var iterator = lifecycle.makeAsyncIterator()
    guard case let .failed(failed) = await iterator.next() else {
      Issue.record("Expected the pre-0021 terminal failure to remain observable.")
      return
    }
    expectNoDifference(failed.id, terminal.id)
    expectNoDifference(failed.optimisticOverlayState, nil)
    expectNoDifference(failed.rollbackTransaction, nil)
    #expect(failed.isLegacyUnknownOverlayCandidate)
  }

  @Test
  func SQLiteAuthorizedAcceptanceSurvivesRelaunch() async throws {
    let cacheURL = mutationLifecycleCacheURL("accepted-relaunch")
    let runtime = try await mutationLifecycleRuntime(
      "accepted-relaunch",
      cacheURL: cacheURL,
      mutationTransport: InstantMutationTransportClient { request in
        InstantMutationTransportResponse(
          results: request.mutations.map {
            InstantMutationTransportResult(
              mutationID: $0.mutationID,
              outcome: .confirmed,
              acceptance: .serverAccepted
            )
          }
        )
      }
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-accepted-relaunch",
        operations: TodoExample.createOperations(
          id: "todo-accepted-relaunch",
          text: "Durable authority",
          createdAt: InstantTimestamp(milliseconds: 1_700_000_500_004),
          transactionID: "tx-accepted-relaunch"
        )
      )
    )
    _ = try await runtime.flushPendingMutations()

    let relaunched = try await mutationLifecycleRuntime(
      "accepted-relaunch",
      cacheURL: cacheURL
    )
    let lifecycle = try await relaunched.observeMutationLifecycle(id: "tx-accepted-relaunch")
    var iterator = lifecycle.makeAsyncIterator()
    guard case let .serverAccepted(accepted) = await iterator.next() else {
      Issue.record("Expected SQLite-authorized acceptance after relaunch.")
      return
    }
    expectNoDifference(accepted.id, "tx-accepted-relaunch")
    expectNoDifference(accepted.status, .confirmed)
  }
}

private func mutationLifecycleRuntime(
  _ suffix: String,
  cacheURL: URL? = nil,
  mutationTransport: InstantMutationTransportClient = .local
) async throws -> InstantRuntime {
  let cacheURL = cacheURL ?? mutationLifecycleCacheURL(suffix)
  return try await InstantRuntime.bootstrap(
    configuration: InstantRuntimeConfiguration(
      appID: "mutation-lifecycle-\(suffix)",
      persistenceURL: cacheURL,
      initialAttributes: TodoExample.attributes,
      mutationTransport: mutationTransport
    )
  )
}

private func mutationLifecycleCacheURL(_ suffix: String) -> URL {
  FileManager.default.temporaryDirectory
    .appendingPathComponent("instant-mutation-lifecycle-\(suffix)-\(UUID().uuidString).sqlite")
}

private func seedPreReceiptAuthorityTerminalLifecycle(
  cacheURL: URL,
  lifecycleID: String,
  terminalMutation: PendingMutation
) async throws {
  let persistence = try SQLitePersistenceStore(fileURL: cacheURL)
  try await persistence.bootstrap()
  await persistence.simulateUnexpectedConnectionCloseForTesting()

  let encoder = JSONEncoder()
  encoder.outputFormatting = [.sortedKeys]
  let terminalJSON = String(
    decoding: try encoder.encode(terminalMutation.compactedForMemory),
    as: UTF8.self
  )
  try executeMutationLifecycleSQL(
    """
    BEGIN IMMEDIATE;
    INSERT INTO instant_outbox_lifecycles
      (lifecycle_id, current_mutation_id, terminal_json)
    VALUES (
      \(mutationLifecycleSQLLiteral(lifecycleID)),
      \(mutationLifecycleSQLLiteral(terminalMutation.id)),
      \(mutationLifecycleSQLLiteral(terminalJSON))
    );
    INSERT INTO instant_outbox_lifecycle_aliases (mutation_id, lifecycle_id)
    VALUES (
      \(mutationLifecycleSQLLiteral(lifecycleID)),
      \(mutationLifecycleSQLLiteral(lifecycleID))
    );
    ALTER TABLE instant_outbox_lifecycles
      DROP COLUMN terminal_optimistic_effect_receipt_fingerprint;
    ALTER TABLE instant_outbox_lifecycles
      DROP COLUMN terminal_server_acceptance_payload_fingerprint;
    DELETE FROM instant_schema_migrations
    WHERE name = '0021_outbox_lifecycle_receipt_authority';
    COMMIT;
    """,
    cacheURL: cacheURL
  )
}

private func mutationLifecycleSQLLiteral(_ value: String) -> String {
  "'\(value.replacingOccurrences(of: "'", with: "''"))'"
}

private func executeMutationLifecycleSQL(
  _ sql: String,
  cacheURL: URL
) throws {
  var database: OpaquePointer?
  guard
    sqlite3_open_v2(
      cacheURL.path,
      &database,
      SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
      nil
    ) == SQLITE_OK,
    let database
  else {
    defer { sqlite3_close(database) }
    throw mutationLifecycleSQLiteError(database, operation: "open pre-0021 fixture")
  }
  defer { sqlite3_close(database) }
  sqlite3_busy_timeout(database, 10_000)
  var errorMessage: UnsafeMutablePointer<CChar>?
  guard sqlite3_exec(database, sql, nil, nil, &errorMessage) == SQLITE_OK else {
    let message = errorMessage.map { String(cString: $0) }
    sqlite3_free(errorMessage)
    throw NSError(
      domain: "InstantMutationLifecycleTests",
      code: 2,
      userInfo: [
        NSLocalizedDescriptionKey: message
          ?? String(cString: sqlite3_errmsg(database))
      ]
    )
  }
}

private func mutationLifecycleSQLiteError(
  _ database: OpaquePointer?,
  operation: String
) -> NSError {
  NSError(
    domain: "InstantMutationLifecycleTests",
    code: 1,
    userInfo: [
      NSLocalizedDescriptionKey:
        "Could not \(operation): "
        + (database.map { String(cString: sqlite3_errmsg($0)) }
          ?? "SQLite did not provide an error message.")
    ]
  )
}
