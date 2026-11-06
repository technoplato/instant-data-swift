import CustomDump
import Foundation
import SQLite3
import Testing
@testable import InstantSwiftDataCore

/// A held write ends known: the server's own rows say whether it landed, and only that evidence completes or discards
/// it (#696, criteria from #134).
///
/// A held write is one launch moved aside because its effect on the local cache is unknown: a row that predates durable
/// optimistic-overlay metadata (#134's shape) or one with no SQLite-owned preparation receipt (#696's). Each fixture here
/// is synthetic; no device store is committed. The fault cases are the ones a lost acknowledgement leaves: the server
/// applied it and the answer never came; the server refused it; it never left the device; it was sent and the server
/// does not hold it; a later write replaced it.
@Suite(.serialized)
struct InstantHeldWriteVerificationTests {
  /// The server applied the write and its acknowledgement was lost: the server's rows hold every value it set, so it
  /// verifies applied and completes. The completion is recorded beside the kept row, the body is byte for byte what it
  /// was, it is no longer listed as held, and its lifecycle observers see it accepted. Discarding it is refused.
  @Test
  func aWriteTheServerAppliedWhoseAcknowledgementWasLostCompletes() async throws {
    let held = heldWriteTestTodo("lost-ack", text: "applied, acknowledgement lost")
    let fixture = try await HeldWriteTestFixture.make(
      held: [held],
      offered: [held.id],
      serverRows: heldWriteTestTodoRows(id: heldWriteTestTodoID(held), text: "applied, acknowledgement lost", held: held)
    )
    let bodiesBefore = try fixture.quarantinedBodyDigests()

    let verification = try await fixture.runtime.verifyQuarantinedMutation(id: held.id)
    expectNoDifference(verification.verdict, .applied)
    expectNoDifference(verification.id, held.id)
    #expect(!verification.slots.isEmpty)
    #expect(verification.slots.allSatisfy { $0.coverage == .serverResult(receivedAt: verification.verifiedAt) })

    await #expect(throws: InstantError.self) {
      try await fixture.runtime.discardQuarantinedMutation(id: held.id)
    }
    let completed = try await fixture.runtime.completeQuarantinedMutation(id: held.id)
    expectNoDifference(completed.verdict, .applied)

    let stillHeld = try await fixture.runtime.quarantinedMutations(limit: 10)
    expectNoDifference(stillHeld, [])
    let rows = try fixture.quarantineRows()
    expectNoDifference(rows.map(\.id), [held.id])
    expectNoDifference(rows.map(\.resolution), ["completed"])
    #expect(rows[0].resolvedAtMilliseconds != nil)
    #expect(rows[0].resolutionJSON?.contains("applied") == true)
    expectNoDifference(try fixture.quarantinedBodyDigests(), bodiesBefore)

    let lifecycle = try await fixture.runtime.observeMutationLifecycle(id: held.id)
    var events = lifecycle.makeAsyncIterator()
    guard case let .serverAccepted(accepted)? = await events.next() else {
      Issue.record("A completed held write's lifecycle is accepted.")
      return
    }
    expectNoDifference(accepted.id, held.id)
  }

  /// The server refused the write with a client-error status, and its rows do not hold it: it verifies not applied,
  /// and discards. Completing it is refused. The discard is recorded beside the kept row, the body is unchanged, and
  /// its lifecycle observers see it failed.
  @Test
  func aWriteTheServerRefusedIsDiscarded() async throws {
    var held = heldWriteTestTodo("refused", text: "refused by the server", status: .failed)
    held.failureMessage = "Permission denied: not perms-pass?"
    held.failure = InstantMutationFailure(
      code: .permissionRejected,
      message: "Permission denied: not perms-pass?",
      status: 400,
      type: "permission-denied"
    )
    let fixture = try await HeldWriteTestFixture.make(held: [held], offered: [held.id], serverRows: [])
    let bodiesBefore = try fixture.quarantinedBodyDigests()

    let verification = try await fixture.runtime.verifyQuarantinedMutation(id: held.id)
    expectNoDifference(
      verification.verdict,
      .notApplied(
        .refusedByServer(status: 400, type: "permission-denied", message: "Permission denied: not perms-pass?")
      )
    )
    #expect(
      verification.slots.allSatisfy {
        if case .notCovered = $0.coverage { true } else { false }
      }
    )

    await #expect(throws: InstantError.self) {
      try await fixture.runtime.completeQuarantinedMutation(id: held.id)
    }
    let discarded = try await fixture.runtime.discardQuarantinedMutation(id: held.id)
    expectNoDifference(discarded.verdict, verification.verdict)

    let heldCount = try await fixture.runtime.quarantinedMutationCount()
    expectNoDifference(heldCount, 0)
    let rows = try fixture.quarantineRows()
    expectNoDifference(rows.map(\.resolution), ["discarded"])
    expectNoDifference(try fixture.quarantinedBodyDigests(), bodiesBefore)

    let lifecycle = try await fixture.runtime.observeMutationLifecycle(id: held.id)
    var events = lifecycle.makeAsyncIterator()
    guard case let .failed(failed)? = await events.next() else {
      Issue.record("A discarded held write's lifecycle is a failure.")
      return
    }
    expectNoDifference(failed.id, held.id)
    #expect(failed.failureMessage?.contains("Discarded") == true)
  }

  /// A write whose outbox row records no send never left this device: it verifies not applied, and discards.
  @Test
  func aWriteThatNeverLeftTheDeviceIsDiscarded() async throws {
    let held = heldWriteTestTodo("never-sent", text: "never left the device")
    let fixture = try await HeldWriteTestFixture.make(held: [held], offered: [], serverRows: [])

    let verification = try await fixture.runtime.verifyQuarantinedMutation(id: held.id)
    expectNoDifference(verification.verdict, .notApplied(.neverSent))
    let discarded = try await fixture.runtime.discardQuarantinedMutation(id: held.id)
    expectNoDifference(discarded.verdict, .notApplied(.neverSent))
    expectNoDifference(try fixture.quarantineRows().map(\.resolution), ["discarded"])
  }

  /// It was sent, no answer came, and the server's rows hold another value: it may never have arrived, or arrived and
  /// a later write replaced it, and a differing value cannot tell those apart. It stays held and says why; completing
  /// and discarding are both refused and write nothing.
  @Test
  func aSentWriteTheServerDoesNotHoldCannotBeTold() async throws {
    let held = heldWriteTestTodo("sent-unanswered", text: "sent, no answer")
    let fixture = try await HeldWriteTestFixture.make(
      held: [held],
      offered: [held.id],
      serverRows: heldWriteTestTodoRows(id: heldWriteTestTodoID(held), text: "written by someone else", held: held)
    )
    let bodiesBefore = try fixture.quarantinedBodyDigests()

    let verification = try await fixture.runtime.verifyQuarantinedMutation(id: held.id)
    expectNoDifference(verification.verdict, .cannotTell(.serverDoesNotHoldIt))
    let textSlot = verification.slots.first { $0.attributeID == "todos/text" }
    expectNoDifference(textSlot?.coverage, .notCovered(serverValues: [.string("written by someone else")]))

    await #expect(throws: InstantError.self) {
      try await fixture.runtime.completeQuarantinedMutation(id: held.id)
    }
    await #expect(throws: InstantError.self) {
      try await fixture.runtime.discardQuarantinedMutation(id: held.id)
    }
    let stillHeld = try await fixture.runtime.quarantinedMutations(limit: 10)
    expectNoDifference(stillHeld.map(\.id), [held.id])
    expectNoDifference(try fixture.quarantineRows().map(\.resolution), [nil])
    expectNoDifference(try fixture.quarantinedBodyDigests(), bodiesBefore)
  }

  /// The held write's own effect is still in this device's cache, and the server never got it: this device's view of
  /// the row shows the write's value, the server's rows do not. Verification reads the server's rows, so it never calls
  /// the write applied (#696's shape: an active optimistic effect with no preparation receipt).
  @Test
  func theHeldWritesOwnLeftoverEffectIsNotEvidence() async throws {
    let id = "leftover-\(heldWriteTestNow().milliseconds)"
    let fixture = try await HeldWriteTestFixture.make(
      heldWithLeftoverEffect: (id: id, text: "only on this device"),
      offered: [id],
      serverRows: []
    )
    let held = try await fixture.runtime.quarantinedMutations(limit: 10)
    expectNoDifference(held.map(\.id), [id])

    let local = try await fixture.runtime.queryLocally(TodoExample.query)
    #expect(
      try TodoExample.decode(local.values).map(\.text).contains("only on this device"),
      "This device's own view still shows the held write's effect."
    )

    let verification = try await fixture.runtime.verifyQuarantinedMutation(id: id)
    expectNoDifference(verification.verdict, .cannotTell(.serverDoesNotHoldIt))
  }

  /// A later write of this device that the server accepted set the same slot: the server holds a newer value of this
  /// device's own, so nothing of the held write is left to send. It verifies applied and completes.
  @Test
  func aWriteALaterAcceptedWriteOfThisDeviceReplacedCompletes() async throws {
    let held = heldWriteTestTodo("replaced", text: "replaced by a later write")
    let todoID = heldWriteTestTodoID(held)
    let fixture = try await HeldWriteTestFixture.make(
      held: [held],
      offered: [held.id],
      serverRows: heldWriteTestTodoRows(id: todoID, text: "the later write", held: held)
    )
    let laterID = "later-\(held.id)"
    try await fixture.runtime.transact(
      InstantStoreTransaction(
        id: laterID,
        operations: [
          .insert(
            InstantTriple(
              entityID: todoID,
              attributeID: "todos/text",
              value: .string("the later write"),
              txID: laterID,
              txTime: heldWriteTestNow()
            )
          )
        ]
      )
    )
    try await fixture.waitUntilDrained()

    let verification = try await fixture.runtime.verifyQuarantinedMutation(id: held.id)
    expectNoDifference(verification.verdict, .applied)
    let textSlot = verification.slots.first { $0.attributeID == "todos/text" }
    guard case let .laterAcceptedWrite(mutationID, _)? = textSlot?.coverage else {
      Issue.record("The text slot is covered by the later accepted write, not by the server's differing value.")
      return
    }
    expectNoDifference(mutationID, laterID)
    try await fixture.runtime.completeQuarantinedMutation(id: held.id)
    expectNoDifference(try fixture.quarantineRows().map(\.resolution), ["completed"])
  }

  /// A deletion's effect is an absence, which the server's rows cannot vouch for (a row the reader may not see is
  /// absent too): a sent deletion cannot be told.
  @Test
  func aSentDeletionCannotBeTold() async throws {
    let held = PendingMutation(
      id: "deletion-\(heldWriteTestNow().milliseconds)",
      createdAt: InstantTimestamp(milliseconds: 1_754_000_400_000),
      transaction: InstantStoreTransaction(
        id: "deletion-tx",
        operations: [.deleteEntityInNamespace(entityID: "todo-gone", namespace: TodoExample.namespace)]
      )
    )
    let fixture = try await HeldWriteTestFixture.make(held: [held], offered: [held.id], serverRows: [])
    let verification = try await fixture.runtime.verifyQuarantinedMutation(id: held.id)
    expectNoDifference(verification.verdict, .cannotTell(.uncheckableOperation("deleteEntityInNamespace")))
  }

  /// Without a server to read, nothing is settled: it cannot be told, and stays held.
  @Test
  func aServerThatCannotBeReadSettlesNothing() async throws {
    let held = heldWriteTestTodo("unreadable", text: "no server to ask")
    let fixture = try await HeldWriteTestFixture.make(
      held: [held],
      offered: [held.id],
      serverRows: [],
      connectsToServer: false
    )
    let verification = try await fixture.runtime.verifyQuarantinedMutation(id: held.id)
    guard case .cannotTell(.serverUnreadable) = verification.verdict else {
      Issue.record("Without a server to read, the verdict is that the server could not be read, not \(verification.verdict).")
      return
    }
    await #expect(throws: InstantError.self) {
      try await fixture.runtime.completeQuarantinedMutation(id: held.id)
    }
    expectNoDifference(try fixture.quarantineRows().map(\.resolution), [nil])
  }

  /// An application that kept 1.9.9's wall (`.blockSynchronization`) still has #134's shape in its outbox: a retained
  /// mutation whose local effect is unknown, which retry and discard refuse, and which refuses every connection. Asking
  /// to verify it holds it first, whole, the move launch makes by default: the connection then opens, and the server's
  /// rows settle it.
  @Test
  func aRetainedUnknownMutationStillInTheOutboxIsHeldThenVerified() async throws {
    let held = heldWriteTestTodo("blocked", text: "kept behind the wall")
    let fixture = try await HeldWriteTestFixture.make(
      held: [held],
      offered: [held.id],
      serverRows: heldWriteTestTodoRows(id: heldWriteTestTodoID(held), text: "kept behind the wall", held: held),
      recovery: .blockSynchronization
    )
    let heldCount = try await fixture.runtime.quarantinedMutationCount()
    expectNoDifference(heldCount, 0)

    // Not connected yet (the wall refused it), so this verification cannot read the server; it holds the row.
    let unconnected = try await fixture.runtime.verifyQuarantinedMutation(id: held.id)
    guard case .cannotTell(.serverUnreadable) = unconnected.verdict else {
      Issue.record("Not connected, the server cannot be read: \(unconnected.verdict).")
      return
    }
    let heldNow = try await fixture.runtime.quarantinedMutations(limit: 10)
    expectNoDifference(heldNow.map(\.id), [held.id])
    let outboxIDs = try await fixture.runtime.persistence.loadState().snapshot.outbox.map(\.id)
    #expect(!outboxIDs.contains(held.id))

    _ = try await fixture.runtime.connect()
    let verification = try await fixture.runtime.verifyQuarantinedMutation(id: held.id)
    expectNoDifference(verification.verdict, .applied)
  }

  /// No held mutation, no verification: an ID nothing holds throws.
  @Test
  func anIDNothingHoldsThrows() async throws {
    let fixture = try await HeldWriteTestFixture.make(held: [], offered: [], serverRows: [])
    await #expect(throws: InstantError.self) {
      try await fixture.runtime.verifyQuarantinedMutation(id: "nothing-holds-this")
    }
  }
}

// MARK: - Fixtures

private func heldWriteTestNow() -> InstantTimestamp {
  InstantTimestamp(milliseconds: Int64((Date().timeIntervalSince1970 * 1_000).rounded()))
}

/// A todo's creation, constructed publicly: no optimistic-overlay metadata and no preparation receipt (#134's shape).
private func heldWriteTestTodo(
  _ name: String,
  text: String,
  status: InstantMutationStatus = .pending
) -> PendingMutation {
  let id = "\(name)-\(UUID().uuidString.lowercased())"
  let createdAt = InstantTimestamp(milliseconds: 1_754_000_000_000)
  return PendingMutation(
    id: id,
    createdAt: createdAt,
    transaction: InstantStoreTransaction(
      id: id,
      operations: TodoExample.createOperations(
        id: "todo-\(id)",
        text: text,
        createdAt: createdAt,
        transactionID: id
      )
    ),
    status: status
  )
}

private func heldWriteTestTodoID(_ mutation: PendingMutation) -> String {
  "todo-\(mutation.id)"
}

/// The rows a server holds for a todo the held write created, with `text` for its text.
private func heldWriteTestTodoRows(id: String, text: String, held: PendingMutation) -> [InstantTriple] {
  held.transaction.operations.compactMap { operation -> InstantTriple? in
    guard case var .insert(triple) = operation, triple.entityID == id else { return nil }
    if triple.attributeID == "todos/text" {
      triple.value = .string(text)
    }
    return triple
  }
}

/// A store with held writes, a runtime launched on it, and a server that answers each read from `serverRows`.
private struct HeldWriteTestFixture {
  var runtime: InstantRuntime
  var cacheURL: URL
  var session: LiveReactorParitySession?

  static func make(
    held: [PendingMutation],
    offered: [String],
    serverRows: [InstantTriple],
    recovery: InstantRetainedMutationRecovery = .quarantine,
    connectsToServer: Bool = true
  ) async throws -> Self {
    let cacheURL = try heldWriteTestCacheURL()
    let persistence = try SQLitePersistenceStore(fileURL: cacheURL)
    try await persistence.bootstrap()
    if !held.isEmpty {
      try await persistence.saveOutbox(held)
    }
    await persistence.simulateUnexpectedConnectionCloseForTesting()
    try heldWriteTestMarkOffered(offered, in: cacheURL)
    return try await launch(
      cacheURL: cacheURL,
      serverRows: serverRows,
      recovery: recovery,
      connectsToServer: connectsToServer
    )
  }

  /// A write made through a runtime, so its effect is in the local cache, whose preparation receipt is then lost: an
  /// active optimistic effect with no receipt (#696's shape).
  static func make(
    heldWithLeftoverEffect write: (id: String, text: String),
    offered: [String],
    serverRows: [InstantTriple]
  ) async throws -> Self {
    let cacheURL = try heldWriteTestCacheURL()
    let seed = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "held-write-verification-seed",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    let createdAt = InstantTimestamp(milliseconds: 1_754_000_500_000)
    try await seed.transact(
      InstantStoreTransaction(
        id: write.id,
        operations: TodoExample.createOperations(
          id: "todo-\(write.id)",
          text: write.text,
          createdAt: createdAt,
          transactionID: write.id
        )
      ),
      createdAt: createdAt
    )
    _ = try? await seed.closeConnection()
    try heldWriteTestExecute(
      "UPDATE instant_outbox SET optimistic_effect_receipt_fingerprint = NULL WHERE mutation_id = ?",
      [write.id],
      in: cacheURL
    )
    try heldWriteTestMarkOffered(offered, in: cacheURL)
    return try await launch(
      cacheURL: cacheURL,
      serverRows: serverRows,
      recovery: .quarantine,
      connectsToServer: true
    )
  }

  private static func launch(
    cacheURL: URL,
    serverRows: [InstantTriple],
    recovery: InstantRetainedMutationRecovery,
    connectsToServer: Bool
  ) async throws -> Self {
    let session =
      connectsToServer
      ? LiveReactorParitySession(messages: [
        liveReactorInitOK(attrs: liveReactorServerAttrs(from: TodoExample.attributes))
      ])
      : nil
    var configuration = InstantRuntimeConfiguration(
      appID: "held-write-verification",
      persistenceURL: cacheURL,
      initialAttributes: TodoExample.attributes,
      liveTransport: session?.transport
    )
    configuration.autoConnectLiveTransport = false
    configuration.retainedMutationsWithoutPreparationReceipt = recovery
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    if let session {
      heldWriteTestServe(session, rows: serverRows)
      // With the 1.9.9 wall a held row refuses the connection; the test connects once it is held.
      if recovery == .quarantine {
        _ = try await runtime.connect()
      }
    }
    return Self(runtime: runtime, cacheURL: cacheURL, session: session)
  }

  func waitUntilDrained() async throws {
    try await instantLiveWithTimeout(operation: "wait for the outbox to drain", timeoutMilliseconds: 60_000) {
      while await runtime.pendingMutationCount() > 0 {
        try Task.checkCancellation()
        try await Task.sleep(nanoseconds: 5_000_000)
      }
    }
  }

  /// Every row of the quarantine table, in the order it was written.
  func quarantineRows() throws -> [HeldWriteTestQuarantineRow] {
    let database = try heldWriteTestOpen(cacheURL, flags: SQLITE_OPEN_READONLY)
    defer { sqlite3_close(database) }
    let columns = try heldWriteTestColumns(of: "instant_outbox_quarantined", in: database)
    let resolutionJSON = columns.contains("resolution_json") ? "resolution_json" : "NULL"
    var statement: OpaquePointer?
    guard
      sqlite3_prepare_v2(
        database,
        "SELECT mutation_id, resolution, resolved_at_ms, \(resolutionJSON) FROM instant_outbox_quarantined "
          + "ORDER BY quarantine_id",
        -1,
        &statement,
        nil
      ) == SQLITE_OK
    else { throw HeldWriteTestError(message: String(cString: sqlite3_errmsg(database))) }
    defer { sqlite3_finalize(statement) }
    var rows: [HeldWriteTestQuarantineRow] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      rows.append(
        HeldWriteTestQuarantineRow(
          id: String(cString: sqlite3_column_text(statement, 0)),
          resolution: sqlite3_column_text(statement, 1).map { String(cString: $0) },
          resolvedAtMilliseconds: sqlite3_column_type(statement, 2) == SQLITE_NULL
            ? nil : sqlite3_column_int64(statement, 2),
          resolutionJSON: sqlite3_column_text(statement, 3).map { String(cString: $0) }
        )
      )
    }
    return rows
  }

  /// Each held body's SHA-256, over the bytes the quarantine table stores: what "the body is kept" compares.
  func quarantinedBodyDigests() throws -> [String: String] {
    let database = try heldWriteTestOpen(cacheURL, flags: SQLITE_OPEN_READONLY)
    defer { sqlite3_close(database) }
    var statement: OpaquePointer?
    guard
      sqlite3_prepare_v2(
        database,
        "SELECT mutation_id, json FROM instant_outbox_quarantined ORDER BY quarantine_id",
        -1,
        &statement,
        nil
      ) == SQLITE_OK
    else { throw HeldWriteTestError(message: String(cString: sqlite3_errmsg(database))) }
    defer { sqlite3_finalize(statement) }
    var digests: [String: String] = [:]
    while sqlite3_step(statement) == SQLITE_ROW {
      let id = String(cString: sqlite3_column_text(statement, 0))
      let count = Int(sqlite3_column_bytes(statement, 1))
      let bytes = sqlite3_column_blob(statement, 1).map { Data(bytes: $0, count: count) } ?? Data()
      digests[id] = instantSHA256HexDigest(bytes)
    }
    return digests
  }
}

private struct HeldWriteTestQuarantineRow: Equatable {
  var id: String
  var resolution: String?
  var resolvedAtMilliseconds: Int64?
  var resolutionJSON: String?
}

/// Answers each `add-query` with the server's rows for the entities its `where` names, and each `transact` with
/// `transact-ok`, as a server that applied it.
private func heldWriteTestServe(_ session: LiveReactorParitySession, rows: [InstantTriple]) {
  Task {
    var handled = 0
    while !Task.isCancelled {
      do {
        try await session.waitForSentMessageCount(handled + 1, timeout: .seconds(600))
      } catch {
        return
      }
      let sent = await session.sentMessages()
      for message in sent[handled...] {
        switch message.op {
        case "add-query":
          if let answer = heldWriteTestAnswer(message, rows: rows) {
            await session.enqueue(answer)
          }
        case "transact":
          if let id = message.clientEventID {
            await session.enqueue(
              InstantLiveMessage(op: "transact-ok", clientEventID: id, fields: ["tx-id": .string("server-\(id)")])
            )
          }
        default:
          break
        }
      }
      handled = sent.count
    }
  }
}

private func heldWriteTestAnswer(_ message: InstantLiveMessage, rows: [InstantTriple]) -> InstantLiveMessage? {
  guard let query = message.fields["q"], case let .object(top) = query, let node = top.values.first else {
    return nil
  }
  var ids: [String] = []
  if case let .object(namespaceNode) = node,
    case let .object(options)? = namespaceNode["$"],
    case let .object(whereClause)? = options["where"]
  {
    switch whereClause["id"] {
    case let .string(id)?:
      ids = [id]
    case let .object(operators)?:
      if case let .array(values)? = operators["$in"] {
        ids = values.compactMap(\.stringValue)
      }
    default:
      break
    }
  }
  let joinRows: [InstantLiveJSONValue] = ids.compactMap { id in
    let triples = rows.filter { $0.entityID == id }
    guard !triples.isEmpty else { return nil }
    return .array(
      triples.map { triple in
        .array([
          .string(triple.entityID),
          .string(triple.attributeID),
          heldWriteTestJSON(triple.value),
          .number(1_700_000_000_000),
        ])
      }
    )
  }
  return InstantLiveMessage(
    op: "add-query-ok",
    clientEventID: message.clientEventID,
    fields: [
      "q": query,
      "processed-tx-id": .string("server-tx-1"),
      "result": .array([
        .object([
          "data": .object(["datalog-result": .object(["join-rows": .array(joinRows)])]),
          "child-nodes": .array([]),
        ])
      ]),
    ]
  )
}

private func heldWriteTestJSON(_ value: InstantValue) -> InstantLiveJSONValue {
  switch value {
  case .null: .null
  case let .string(string): .string(string)
  case let .number(number): .number(number)
  case let .bool(bool): .bool(bool)
  case let .date(date): .number((date.timeIntervalSince1970 * 1_000).rounded())
  case let .ref(id): .string(id)
  case .json, .lookupRef: .null
  }
}

// MARK: - Reading and writing the SQLite file directly

private struct HeldWriteTestError: Error, CustomStringConvertible {
  var message: String
  var description: String { message }
}

private func heldWriteTestCacheURL() throws -> URL {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("InstantHeldWriteVerificationTests-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  return directory.appendingPathComponent("state.sqlite")
}

private func heldWriteTestOpen(_ cacheURL: URL, flags: Int32) throws -> OpaquePointer {
  var database: OpaquePointer?
  guard sqlite3_open_v2(cacheURL.path, &database, flags, nil) == SQLITE_OK, let database else {
    sqlite3_close(database)
    throw HeldWriteTestError(message: "Could not open \(cacheURL.lastPathComponent).")
  }
  sqlite3_busy_timeout(database, 5_000)
  return database
}

private func heldWriteTestColumns(of table: String, in database: OpaquePointer) throws -> Set<String> {
  var statement: OpaquePointer?
  guard sqlite3_prepare_v2(database, "SELECT name FROM pragma_table_info('\(table)')", -1, &statement, nil) == SQLITE_OK
  else { throw HeldWriteTestError(message: String(cString: sqlite3_errmsg(database))) }
  defer { sqlite3_finalize(statement) }
  var columns: Set<String> = []
  while sqlite3_step(statement) == SQLITE_ROW {
    columns.insert(String(cString: sqlite3_column_text(statement, 0)))
  }
  return columns
}

private func heldWriteTestExecute(_ sql: String, _ bindings: [String], in cacheURL: URL) throws {
  let database = try heldWriteTestOpen(cacheURL, flags: SQLITE_OPEN_READWRITE)
  defer { sqlite3_close(database) }
  var statement: OpaquePointer?
  guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
    throw HeldWriteTestError(message: String(cString: sqlite3_errmsg(database)))
  }
  defer { sqlite3_finalize(statement) }
  for (offset, binding) in bindings.enumerated() {
    sqlite3_bind_text(statement, Int32(offset + 1), binding, -1, heldWriteTestSQLiteTransient)
  }
  guard sqlite3_step(statement) == SQLITE_DONE else {
    throw HeldWriteTestError(message: String(cString: sqlite3_errmsg(database)))
  }
}

/// Records that each write was offered to the server, as a claim does (`delivery_started`).
private func heldWriteTestMarkOffered(_ ids: [String], in cacheURL: URL) throws {
  for id in ids {
    try heldWriteTestExecute("UPDATE instant_outbox SET delivery_started = 1 WHERE mutation_id = ?", [id], in: cacheURL)
  }
}

private let heldWriteTestSQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
