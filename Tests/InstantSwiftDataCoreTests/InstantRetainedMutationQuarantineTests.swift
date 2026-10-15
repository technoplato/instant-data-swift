import CustomDump
import Foundation
import SQLite3
import Testing
@testable import InstantSwiftDataCore

/// A retained mutation with no SQLite-owned preparation receipt is held aside at launch, not a wall in front of every
/// later write (#696).
///
/// The field failure: a store written by an earlier library version held five such mutations among older writes. The
/// first one refused every live connection ("Synchronization is blocked by 5 retained mutations"), reconnect paused,
/// and every write made after it, thousands of them while the application kept writing, waited unsent. The only way
/// out was to reset the local store, which set aside every unsent write with the five.
@Suite(.serialized)
struct InstantRetainedMutationQuarantineTests {
  /// Three receipt-less mutations, created first, then three writes made through the runtime with their receipts. The
  /// connection opens, the three later writes are sent in the order they were made and drain, and the three without a
  /// receipt are in the quarantine, each with its outbox row exactly as it was. A relaunch keeps them, once.
  @Test
  func retainedMutationsWithoutPreparationReceiptAreQuarantinedAndLaterWritesDrainInOrder() async throws {
    let cacheURL = try quarantineTestCacheURL()
    let testStartedAt = quarantineTestNow()
    let receiptless = quarantineTestReceiptlessMutations(
      startingAt: InstantTimestamp(milliseconds: 1_754_000_000_000)
    )
    let receiptlessIDs = Set(receiptless.map(\.id))

    // The shape a store from before preparation receipts holds: rows whose effect no receipt proves.
    let persistence = try SQLitePersistenceStore(fileURL: cacheURL)
    try await persistence.bootstrap()
    try await persistence.saveOutbox(receiptless)
    await persistence.simulateUnexpectedConnectionCloseForTesting()
    let seededBlocker = try await persistence.synchronizationBlocker()
    expectNoDifference(
      seededBlocker,
      InstantSynchronizationBlocker(
        reason: .unknownOptimisticEffectReceipt,
        firstMutationID: receiptless[0].id,
        blockedMutationCount: receiptless.count
      )
    )
    let rowsBefore = try quarantineTestOutboxRows(in: cacheURL, ids: receiptless.map(\.id))
    expectNoDifference(rowsBefore.map(\.id), receiptless.map(\.id))

    // Later writes made through the runtime, each with its receipt.
    let laterWrites = try await quarantineTestTransactLaterWrites(
      count: 3,
      startingAt: InstantTimestamp(milliseconds: 1_792_000_000_000),
      cacheURL: cacheURL
    )

    let liveSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs)
    ])
    var configuration = InstantRuntimeConfiguration(
      appID: "retained-mutation-quarantine",
      persistenceURL: cacheURL,
      initialAttributes: TodoExample.attributes,
      liveTransport: liveSession.transport
    )
    configuration.autoConnectLiveTransport = false
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)

    // Up to 1.9.9 this threw persistenceFailed: "Synchronization is blocked by 3 retained mutations."
    _ = try await runtime.connect()
    try await quarantineTestWaitForTransacts(count: laterWrites.count, in: liveSession)
    let sent = await liveSession.sentMessages()
    expectNoDifference(
      sent.filter { $0.op == "transact" }.compactMap(\.clientEventID),
      laterWrites,
      "The later writes are sent in the order they were made."
    )
    #expect(sent.compactMap(\.clientEventID).allSatisfy { !receiptlessIDs.contains($0) })

    for id in laterWrites {
      await liveSession.enqueue(
        InstantLiveMessage(
          op: "transact-ok",
          clientEventID: id,
          fields: ["tx-id": .string("server-\(id)")]
        )
      )
    }
    try await quarantineTestWaitUntilDrained(runtime)
    let pendingAfterDrain = await runtime.pendingMutationCount()
    expectNoDifference(pendingAfterDrain, 0)
    let status = try await runtime.connectionStatus()
    expectNoDifference(status.synchronizationBlocker, nil)
    let outboxIDs = try await runtime.persistence.loadState().snapshot.outbox.map(\.id)
    #expect(Set(outboxIDs).isDisjoint(with: receiptlessIDs))

    // Held aside, whole: the body byte for byte, every column of the outbox row, in the order they had.
    let quarantined = try await runtime.quarantinedMutations(limit: 10)
    expectNoDifference(quarantined.map(\.id), receiptless.map(\.id))
    expectNoDifference(
      quarantined.map(\.reason),
      Array(repeating: .noPreparationReceipt, count: receiptless.count)
    )
    expectNoDifference(quarantined.map(\.status), receiptless.map(\.status))
    expectNoDifference(quarantined.map(\.createdAt), receiptless.map(\.createdAt))
    expectNoDifference(quarantined.map(\.body), rowsBefore.map(\.json))
    expectNoDifference(
      try quarantined.map { try quarantineTestDecodeRowJSON($0.outboxRowJSON) },
      rowsBefore.map(\.columns)
    )
    expectNoDifference(quarantined.map { $0.mutation?.transaction }, receiptless.map(\.transaction))
    expectNoDifference(quarantined.map { $0.mutation?.failureMessage }, receiptless.map(\.failureMessage))
    #expect(
      quarantined.allSatisfy {
        $0.quarantinedAt >= testStartedAt && $0.quarantinedAt <= quarantineTestNow()
      }
    )
    let quarantinedCount = try await runtime.quarantinedMutationCount()
    expectNoDifference(quarantinedCount, receiptless.count)
    _ = try? await runtime.closeConnection()

    // A relaunch moves nothing again and deletes nothing.
    let relaunched = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "retained-mutation-quarantine",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    let quarantinedAfterRelaunch = try await relaunched.quarantinedMutations(limit: 10)
    expectNoDifference(quarantinedAfterRelaunch, quarantined)
    let quarantinedCountAfterRelaunch = try await relaunched.quarantinedMutationCount()
    expectNoDifference(quarantinedCountAfterRelaunch, receiptless.count)
    let statusAfterRelaunch = try await relaunched.connectionStatus()
    expectNoDifference(statusAfterRelaunch.synchronizationBlocker, nil)
  }

  /// A store with no receipt-less mutation is exactly as it was: the quarantine step finds nothing, writes nothing,
  /// and never creates its table, and a launch, a connection and a drain leave no trace of it either.
  @Test
  func aStoreWithoutReceiptlessMutationsIsLeftExactlyAsItWas() async throws {
    let cacheURL = try quarantineTestCacheURL()
    let laterWrites = try await quarantineTestTransactLaterWrites(
      count: 2,
      startingAt: InstantTimestamp(milliseconds: 1_792_000_100_000),
      cacheURL: cacheURL
    )

    let persistence = try SQLitePersistenceStore(fileURL: cacheURL)
    try await persistence.bootstrap()
    let before = try quarantineTestDatabaseDump(cacheURL)
    let quarantinedIDs = try await persistence.quarantineRetainedMutationsWithoutPreparationReceipt(
      now: quarantineTestNow()
    )
    expectNoDifference(quarantinedIDs, [])
    let after = try quarantineTestDatabaseDump(cacheURL)
    expectNoDifference(after, before)
    #expect(!after.schema.contains { $0.contains("instant_outbox_quarantined") })
    await persistence.simulateUnexpectedConnectionCloseForTesting()

    let liveSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs)
    ])
    var configuration = InstantRuntimeConfiguration(
      appID: "retained-mutation-quarantine-untouched",
      persistenceURL: cacheURL,
      initialAttributes: TodoExample.attributes,
      liveTransport: liveSession.transport
    )
    configuration.autoConnectLiveTransport = false
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    _ = try await runtime.connect()
    try await quarantineTestWaitForTransacts(count: laterWrites.count, in: liveSession)
    let sentTransacts = await liveSession.sentMessages().filter { $0.op == "transact" }
    expectNoDifference(sentTransacts.compactMap(\.clientEventID), laterWrites)
    for id in laterWrites {
      await liveSession.enqueue(
        InstantLiveMessage(
          op: "transact-ok",
          clientEventID: id,
          fields: ["tx-id": .string("server-\(id)")]
        )
      )
    }
    try await quarantineTestWaitUntilDrained(runtime)
    let quarantined = try await runtime.quarantinedMutations(limit: 10)
    expectNoDifference(quarantined, [])
    let quarantinedCount = try await runtime.quarantinedMutationCount()
    expectNoDifference(quarantinedCount, 0)
    _ = try? await runtime.closeConnection()
    #expect(
      !(try quarantineTestDatabaseDump(cacheURL)).schema.contains {
        $0.contains("instant_outbox_quarantined")
      }
    )
  }

  /// An application that wants the 1.9.9 wall keeps it: the receipt-less mutations stay in the outbox and refuse the
  /// connection, and nothing is quarantined.
  @Test
  func blockSynchronizationKeepsTheReceiptlessMutationsInTheOutbox() async throws {
    let cacheURL = try quarantineTestCacheURL()
    let receiptless = quarantineTestReceiptlessMutations(
      startingAt: InstantTimestamp(milliseconds: 1_754_000_200_000)
    )
    let persistence = try SQLitePersistenceStore(fileURL: cacheURL)
    try await persistence.bootstrap()
    try await persistence.saveOutbox(receiptless)
    await persistence.simulateUnexpectedConnectionCloseForTesting()

    let liveSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs)
    ])
    var configuration = InstantRuntimeConfiguration(
      appID: "retained-mutation-block",
      persistenceURL: cacheURL,
      initialAttributes: TodoExample.attributes,
      liveTransport: liveSession.transport
    )
    configuration.autoConnectLiveTransport = false
    configuration.retainedMutationsWithoutPreparationReceipt = .blockSynchronization
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    do {
      _ = try await runtime.connect()
      Issue.record("With blockSynchronization, a receipt-less retained mutation must refuse the connection.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .persistenceFailed)
      expectNoDifference(error.localID, receiptless[0].id)
    }
    let sent = await liveSession.sentMessages()
    expectNoDifference(sent, [])
    let quarantinedCount = try await runtime.quarantinedMutationCount()
    expectNoDifference(quarantinedCount, 0)
    let outboxIDs = try await runtime.persistence.loadState().snapshot.outbox.map(\.id)
    expectNoDifference(outboxIDs, receiptless.map(\.id))
  }
}

// MARK: - Fixtures

private func quarantineTestCacheURL() throws -> URL {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("InstantRetainedMutationQuarantineTests-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  return directory.appendingPathComponent("state.sqlite")
}

private func quarantineTestNow() -> InstantTimestamp {
  InstantTimestamp(milliseconds: Int64((Date().timeIntervalSince1970 * 1_000).rounded()))
}

/// Two pending writes and one the server refused, none with a preparation receipt: what `saveOutbox` stores for a
/// publicly constructed mutation, and the shape the field store held.
private func quarantineTestReceiptlessMutations(startingAt start: InstantTimestamp) -> [PendingMutation] {
  (0..<3).map { index in
    let id = "receiptless-\(start.milliseconds)-\(index)"
    let createdAt = InstantTimestamp(milliseconds: start.milliseconds + Int64(index))
    return PendingMutation(
      id: id,
      createdAt: createdAt,
      transaction: InstantStoreTransaction(
        id: id,
        operations: TodoExample.createOperations(
          id: "todo-\(id)",
          text: "written before preparation receipts \(index)",
          createdAt: createdAt,
          transactionID: id
        )
      ),
      status: index == 2 ? .failed : .pending,
      failureMessage: index == 2 ? "Permission denied: not perms-pass?" : nil
    )
  }
}

/// Makes `count` writes through a runtime with no live transport, as an application does while it cannot sync, and
/// returns their IDs in the order they were made.
private func quarantineTestTransactLaterWrites(
  count: Int,
  startingAt start: InstantTimestamp,
  cacheURL: URL
) async throws -> [String] {
  let runtime = try await InstantRuntime.bootstrap(
    configuration: InstantRuntimeConfiguration(
      appID: "retained-mutation-quarantine-seed",
      persistenceURL: cacheURL,
      initialAttributes: TodoExample.attributes
    )
  )
  var ids: [String] = []
  for index in 0..<count {
    let id = "later-write-\(start.milliseconds)-\(index)"
    let createdAt = InstantTimestamp(milliseconds: start.milliseconds + Int64(index))
    try await runtime.transact(
      InstantStoreTransaction(
        id: id,
        operations: TodoExample.createOperations(
          id: "todo-\(id)",
          text: "written while synchronization was blocked \(index)",
          createdAt: createdAt,
          transactionID: id
        )
      ),
      createdAt: createdAt
    )
    let receipt = try await runtime.persistence.optimisticEffectReceiptFingerprintForTesting(id: id)
    #expect(receipt != nil, "A write made through the runtime has its preparation receipt.")
    ids.append(id)
  }
  _ = try? await runtime.closeConnection()
  return ids
}

private func quarantineTestWaitForTransacts(count: Int, in session: LiveReactorParitySession) async throws {
  try await instantLiveWithTimeout(
    operation: "wait for the later writes to be sent",
    timeoutMilliseconds: 10_000
  ) {
    while await session.sentMessages().filter({ $0.op == "transact" }).count < count {
      try Task.checkCancellation()
      try await Task.sleep(nanoseconds: 5_000_000)
    }
  }
}

private func quarantineTestWaitUntilDrained(_ runtime: InstantRuntime) async throws {
  try await instantLiveWithTimeout(
    operation: "wait for the outbox to drain",
    timeoutMilliseconds: 10_000
  ) {
    while await runtime.pendingMutationCount() > 0 {
      try Task.checkCancellation()
      try await Task.sleep(nanoseconds: 5_000_000)
    }
  }
}

// MARK: - Reading the SQLite file directly

/// One SQLite value, as the file holds it.
private enum QuarantineTestSQLiteValue: Hashable {
  case null
  case integer(Int64)
  case real(Double)
  case text(String)
}

private struct QuarantineTestOutboxRow: Equatable {
  var id: String
  var json: String
  var columns: [String: QuarantineTestSQLiteValue]
}

/// Every table's schema and rows, read through a separate connection: what "exactly as it was" compares.
private struct QuarantineTestDatabaseDump: Equatable {
  var schema: [String]
  var rows: [String: [String]]
}

private func quarantineTestOpen(_ cacheURL: URL) throws -> OpaquePointer {
  var database: OpaquePointer?
  guard sqlite3_open_v2(cacheURL.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
    let database
  else {
    sqlite3_close(database)
    throw QuarantineTestSQLiteError(message: "Could not open \(cacheURL.lastPathComponent).")
  }
  return database
}

private struct QuarantineTestSQLiteError: Error, CustomStringConvertible {
  var message: String
  var description: String { message }
}

private func quarantineTestQuery(
  _ database: OpaquePointer,
  _ sql: String,
  bindings: [String] = []
) throws -> [[(name: String, value: QuarantineTestSQLiteValue)]] {
  var statement: OpaquePointer?
  guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
    throw QuarantineTestSQLiteError(message: String(cString: sqlite3_errmsg(database)))
  }
  defer { sqlite3_finalize(statement) }
  for (offset, binding) in bindings.enumerated() {
    sqlite3_bind_text(statement, Int32(offset + 1), binding, -1, quarantineTestSQLiteTransient)
  }
  var rows: [[(name: String, value: QuarantineTestSQLiteValue)]] = []
  while true {
    let code = sqlite3_step(statement)
    if code == SQLITE_DONE { return rows }
    guard code == SQLITE_ROW else {
      throw QuarantineTestSQLiteError(message: String(cString: sqlite3_errmsg(database)))
    }
    var row: [(name: String, value: QuarantineTestSQLiteValue)] = []
    for column in 0..<sqlite3_column_count(statement) {
      let name = String(cString: sqlite3_column_name(statement, column))
      let value: QuarantineTestSQLiteValue
      switch sqlite3_column_type(statement, column) {
      case SQLITE_NULL: value = .null
      case SQLITE_INTEGER: value = .integer(sqlite3_column_int64(statement, column))
      case SQLITE_FLOAT: value = .real(sqlite3_column_double(statement, column))
      default: value = .text(String(cString: sqlite3_column_text(statement, column)))
      }
      row.append((name, value))
    }
    rows.append(row)
  }
}

private func quarantineTestOutboxRows(in cacheURL: URL, ids: [String]) throws -> [QuarantineTestOutboxRow] {
  let database = try quarantineTestOpen(cacheURL)
  defer { sqlite3_close(database) }
  return try ids.map { id in
    guard
      let row = try quarantineTestQuery(
        database,
        "SELECT * FROM instant_outbox WHERE mutation_id = ?",
        bindings: [id]
      ).first,
      case .text(let json)? = row.first(where: { $0.name == "json" })?.value
    else {
      throw QuarantineTestSQLiteError(message: "No outbox row \(id).")
    }
    return QuarantineTestOutboxRow(
      id: id,
      json: json,
      columns: Dictionary(uniqueKeysWithValues: row.map { ($0.name, $0.value) })
    )
  }
}

private func quarantineTestDatabaseDump(_ cacheURL: URL) throws -> QuarantineTestDatabaseDump {
  let database = try quarantineTestOpen(cacheURL)
  defer { sqlite3_close(database) }
  let schemaRows = try quarantineTestQuery(
    database,
    "SELECT type, name, COALESCE(sql, '') FROM sqlite_master ORDER BY type, name"
  )
  let schema = schemaRows.map { row in row.map { "\($0.value)" }.joined(separator: " | ") }
  var rows: [String: [String]] = [:]
  for row in schemaRows {
    guard case .text("table") = row[0].value, case .text(let table) = row[1].value else { continue }
    rows[table] = try quarantineTestQuery(database, "SELECT * FROM \"\(table)\"")
      .map { row in row.map { "\($0.name)=\($0.value)" }.joined(separator: ", ") }
      .sorted()
  }
  return QuarantineTestDatabaseDump(schema: schema, rows: rows)
}

/// The quarantine's JSON object for a row, read back as SQLite values.
private func quarantineTestDecodeRowJSON(_ json: String) throws -> [String: QuarantineTestSQLiteValue] {
  guard let object = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else {
    throw QuarantineTestSQLiteError(message: "The quarantined row is not a JSON object.")
  }
  return try object.mapValues { value in
    switch value {
    case is NSNull: return .null
    case let string as String: return .text(string)
    case let number as NSNumber:
      return CFNumberIsFloatType(number) ? .real(number.doubleValue) : .integer(number.int64Value)
    default:
      throw QuarantineTestSQLiteError(message: "Unexpected JSON value \(value) in a quarantined row.")
    }
  }
}

private let quarantineTestSQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
