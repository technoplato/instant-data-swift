import CustomDump
import Foundation
@testable import InstantSwiftDataCore
import Testing

/// Library-78, item 3: refused writes that are only duplicates.
///
/// Michael, verbatim (2026-10-01): "I want to know why rights are refused in the first place? I don't think they really
/// should be". A write offered again after its first offer was applied (a lost acknowledgment, a reconnect, a transient
/// error) is refused by Scribe's `validUpdate` rule (`newData.updatedAtMs >= data.updatedAtMs`) when a newer write of
/// the same row reached the server first. The server already holds a newer value for every slot it sets. The library
/// does not offer such a write again when later accepted writes cover it, holds it while later writes in flight cover
/// it, and resolves a refusal that later writes of this device cover as accepted instead of failed. Upstream
/// `Reactor.js` drops every refused mutation as an error (`_handleMutationError`) and never re-sends a mutation with a
/// tx-id; it has no supersession.
@Suite(.serialized)
struct InstantSupersededReplayTests {
  static let todoID = "todo-superseded"

  static func temporaryCacheURL() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("instant-superseded-replay-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("instant.sqlite")
  }

  static func refused(_ mutationID: String) -> InstantLiveMessage {
    InstantLiveMessage(
      op: "error",
      clientEventID: mutationID,
      fields: [
        "message": .string("Permission denied: not perms-pass?"),
        "status": .number(400),
        "type": .string("permission-denied"),
        "original-event": .object([
          "client-event-id": .string(mutationID),
          "op": .string("transact"),
        ]),
      ]
    )
  }

  static func accepted(_ mutationID: String, transactionID: Int) -> InstantLiveMessage {
    InstantLiveMessage(
      op: "transact-ok",
      clientEventID: mutationID,
      fields: ["tx-id": .string(String(transactionID))]
    )
  }

  static func transactIDs(sentTo session: LiveReactorParitySession) async -> [String?] {
    await session.sentMessages().filter { $0.op == "transact" }.map(\.clientEventID)
  }

  static func waitForTransacts(
    _ count: Int,
    on session: LiveReactorParitySession,
    within timeout: Duration = .seconds(10)
  ) async throws -> [String?] {
    let deadline = ContinuousClock.now + timeout
    while true {
      let ids = await transactIDs(sentTo: session)
      if ids.count >= count || ContinuousClock.now >= deadline { return ids }
      try await Task.sleep(for: .milliseconds(20))
    }
  }

  static func waitUntil(
    _ operation: String,
    within timeout: Duration = .seconds(10),
    _ condition: @Sendable () async throws -> Bool
  ) async throws {
    let deadline = ContinuousClock.now + timeout
    while try await !condition() {
      guard ContinuousClock.now < deadline else {
        Issue.record("Timed out: \(operation)")
        return
      }
      try await Task.sleep(for: .milliseconds(20))
    }
  }

  static func bootstrap(
    _ name: String,
    sessions: [LiveReactorParitySession]
  ) async throws -> (InstantRuntime, LiveReactorParityTransport) {
    let transport = LiveReactorParityTransport(sessions: sessions)
    var configuration = InstantRuntimeConfiguration(
      appID: "superseded-replay-\(name)",
      persistenceURL: try temporaryCacheURL(),
      initialAttributes: TodoExample.attributes,
      liveTransport: transport.transport
    )
    configuration.liveReconnectSleep = { _ in }
    return (try await InstantRuntime.bootstrap(configuration: configuration), transport)
  }

  /// Creates the todo and has the server accept it, so later updates are of an existing row.
  static func createAcceptedTodo(_ runtime: InstantRuntime, on session: LiveReactorParitySession) async throws {
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_078_000)
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-create",
        operations: TodoExample.createOperations(
          id: todoID,
          text: "created",
          createdAt: createdAt,
          transactionID: "tx-create"
        )
      ),
      createdAt: createdAt
    )
    _ = try await waitForTransacts(1, on: session)
    await session.enqueue(accepted("tx-create", transactionID: 1))
    try await waitUntil("the create is accepted") {
      await runtime.durableOutboxMutationsForTesting().first { $0.id == "tx-create" }?.status == .confirmed
    }
  }

  static func updateText(_ runtime: InstantRuntime, _ id: String, _ text: String, at offset: Int64) async throws {
    let updatedAt = InstantTimestamp(milliseconds: 1_700_000_078_100 + offset)
    try await runtime.transact(
      InstantStoreTransaction(
        id: id,
        operations: TodoExample.updateTextOperations(
          id: todoID,
          text: text,
          updatedAt: updatedAt,
          transactionID: id
        )
      ),
      createdAt: updatedAt
    )
  }

  static func mutation(_ id: String, in runtime: InstantRuntime) async -> PendingMutation? {
    await runtime.durableOutboxMutationsForTesting().first { $0.id == id }
  }

  @Test
  func aRefusalThatAnAcceptedLaterWriteCoversResolvesAsAcceptedNotFailed() async throws {
    let session = LiveReactorParitySession(messages: [liveReactorInitOK(attrs: liveReactorTodoServerAttrs)])
    let (runtime, transport) = try await Self.bootstrap("refusal-accepted-coverer", sessions: [session])
    _ = try await runtime.connect()
    try await Self.createAcceptedTodo(runtime, on: session)
    try await Self.updateText(runtime, "tx-first", "first", at: 1)
    try await Self.updateText(runtime, "tx-second", "second", at: 2)
    _ = try await Self.waitForTransacts(3, on: session)
    // The newer write lands first; the older one is refused as a replay of a row that is already newer.
    await session.enqueue(Self.accepted("tx-second", transactionID: 3))
    try await Self.waitUntil("the newer write is accepted") {
      await Self.mutation("tx-second", in: runtime)?.status == .confirmed
    }
    await session.enqueue(Self.refused("tx-first"))
    try await Self.waitUntil("the refused write is resolved") {
      await Self.mutation("tx-first", in: runtime)?.status != .pending
    }
    let first = await Self.mutation("tx-first", in: runtime)
    expectNoDifference(first?.status, .confirmed)
    expectNoDifference(first?.confirmationSource, .supersededByAcceptedWrite)
    expectNoDifference(first?.serverTransactionID, "3")
    let failed = await runtime.outboxMutations().filter { $0.status == .failed }.map(\.id)
    expectNoDifference(failed, [])
    let ids = await Self.transactIDs(sentTo: session)
    expectNoDifference(ids, ["tx-create", "tx-first", "tx-second"])
    let connections = await transport.connectionRequests()
    expectNoDifference(connections.count, 1)
    _ = try await runtime.closeConnection()
  }

  /// The large-store drop's shape: the socket dies before two writes of one row are answered, the server applied both,
  /// and the reconnect re-sends both. The server refuses the older one, because the newer one's first offer already
  /// set the row; the newer re-send is accepted. Swift used to record the refusal as a failure.
  @Test
  func aReplayRefusalThatALaterWriteInFlightCoversIsParkedAndResolvedWhenThatWriteIsAccepted() async throws {
    let first = LiveReactorParitySession(messages: [liveReactorInitOK(attrs: liveReactorTodoServerAttrs)])
    let second = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "after-drop")
    ])
    let (runtime, transport) = try await Self.bootstrap("replay-parked", sessions: [first, second])
    _ = try await runtime.connect()
    try await Self.createAcceptedTodo(runtime, on: first)
    try await Self.updateText(runtime, "tx-first", "first", at: 1)
    try await Self.updateText(runtime, "tx-second", "second", at: 2)
    _ = try await Self.waitForTransacts(3, on: first)
    await first.failReceive(
      InstantError(
        code: .networkFailed,
        operation: "receive superseded replay test event",
        message: "socket dropped before either answer",
        recovery: "Reconnect."
      )
    )
    let resent = try await Self.waitForTransacts(2, on: second)
    expectNoDifference(resent, ["tx-first", "tx-second"])
    // The older re-send is refused while the newer one is still in flight: parked, not failed.
    await second.enqueue(Self.refused("tx-first"))
    try await Task.sleep(for: .milliseconds(300))
    let parked = await Self.mutation("tx-first", in: runtime)?.status
    expectNoDifference(parked, .pending, "parked, not failed")
    await second.enqueue(Self.accepted("tx-second", transactionID: 3))
    try await Self.waitUntil("the parked refusal is superseded") {
      await Self.mutation("tx-first", in: runtime)?.status == .confirmed
    }
    let source = await Self.mutation("tx-first", in: runtime)?.confirmationSource
    expectNoDifference(source, .supersededByAcceptedWrite)
    let failed = await runtime.outboxMutations().filter { $0.status == .failed }.map(\.id)
    expectNoDifference(failed, [])
    let offered = await Self.transactIDs(sentTo: second)
    expectNoDifference(offered, ["tx-first", "tx-second"], "a parked write is not offered again")
    let connections = await transport.connectionRequests().count
    expectNoDifference(connections, 2)
    _ = try await runtime.closeConnection()
  }

  /// A refusal of a first offer is the server's verdict on the write itself: writes still in flight do not make it
  /// moot, so it fails as before.
  @Test
  func aFirstOfferRefusalThatOnlyWritesInFlightCoverStillFails() async throws {
    let session = LiveReactorParitySession(messages: [liveReactorInitOK(attrs: liveReactorTodoServerAttrs)])
    let (runtime, _) = try await Self.bootstrap("first-offer-pending-coverer", sessions: [session])
    _ = try await runtime.connect()
    try await Self.createAcceptedTodo(runtime, on: session)
    try await Self.updateText(runtime, "tx-first", "first", at: 1)
    try await Self.updateText(runtime, "tx-second", "second", at: 2)
    _ = try await Self.waitForTransacts(3, on: session)
    await session.enqueue(Self.refused("tx-first"))
    try await Self.waitUntil("the refusal is recorded") {
      await Self.mutation("tx-first", in: runtime)?.status == .failed
    }
    let status = await Self.mutation("tx-first", in: runtime)?.status
    expectNoDifference(status, .failed)
    _ = try await runtime.closeConnection()
  }

  @Test
  func aRefusalThatNoLaterWriteCoversStillFails() async throws {
    let session = LiveReactorParitySession(messages: [liveReactorInitOK(attrs: liveReactorTodoServerAttrs)])
    let (runtime, _) = try await Self.bootstrap("refusal-uncovered", sessions: [session])
    _ = try await runtime.connect()
    try await Self.createAcceptedTodo(runtime, on: session)
    try await Self.updateText(runtime, "tx-only", "only", at: 1)
    _ = try await Self.waitForTransacts(2, on: session)
    await session.enqueue(Self.refused("tx-only"))
    try await Self.waitUntil("the refusal is recorded") {
      await Self.mutation("tx-only", in: runtime)?.status == .failed
    }
    let observed5 = await Self.mutation("tx-only", in: runtime)?.status
    expectNoDifference(observed5, .failed)
    _ = try await runtime.closeConnection()
  }

  @Test
  func aReSendThatAnAcceptedLaterWriteCoversIsResolvedWithoutAnOffer() async throws {
    let first = LiveReactorParitySession(messages: [liveReactorInitOK(attrs: liveReactorTodoServerAttrs)])
    let second = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "after-lost-ack")
    ])
    let (runtime, _) = try await Self.bootstrap("resend-accepted-coverer", sessions: [first, second])
    _ = try await runtime.connect()
    try await Self.createAcceptedTodo(runtime, on: first)
    try await Self.updateText(runtime, "tx-first", "first", at: 1)
    try await Self.updateText(runtime, "tx-second", "second", at: 2)
    _ = try await Self.waitForTransacts(3, on: first)
    // Only the newer write's acknowledgment arrives before the socket dies.
    await first.enqueue(Self.accepted("tx-second", transactionID: 3))
    try await Self.waitUntil("the newer write is accepted") {
      await Self.mutation("tx-second", in: runtime)?.status == .confirmed
    }
    await first.failReceive(
      InstantError(
        code: .networkFailed,
        operation: "receive superseded replay test event",
        message: "socket dropped",
        recovery: "Reconnect."
      )
    )
    try await Self.waitUntil("the re-send is resolved without an offer") {
      await Self.mutation("tx-first", in: runtime)?.status == .confirmed
    }
    let observed9 = await Self.mutation("tx-first", in: runtime)?.confirmationSource
    expectNoDifference(observed9, .supersededByAcceptedWrite)
    try await Task.sleep(for: .milliseconds(200))
    let observed10 = await Self.transactIDs(sentTo: second)
    expectNoDifference(observed10, [])
    _ = try await runtime.closeConnection()
  }
}
