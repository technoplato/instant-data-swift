import CustomDump
import Foundation
import InstantSwiftData
import Testing
import os

/// #1648: a write's place in the outbox is decided when it enters the runtime's operation gate, after every write that
/// entered before it, on every transact path.
///
/// Delivery orders the outbox by `(created_at_ms, mutation_id)` and a mutation id is random. The typed transact read the
/// clock before the gate and handed that time to the runtime, which steps a new write past the outbox tail only when it
/// is given none, so two typed writes made in the same millisecond tied and went out in id order: on a phone the newer
/// of two revisions of one row went first, and a rule requiring a newer `updatedAtMs` refused the older. Upstream
/// Reactor.js `pushOps` gives each mutation `order = max(order) + 1` when it is made and sends in that order
/// (`sortedMutationEntries`).
///
/// Each test freezes the configuration's clock and gives the second write an id that sorts before the first's, so a
/// tie broken by id puts the second write first.
@Suite(.serialized)
struct InstantWriteCreationOrderTests {
  static let sameMillisecond = InstantTimestamp(milliseconds: 1_790_000_000_000)
  static let songID = InstantID<CreationOrderSong>(rawValue: "song-1")

  static func create() -> InstantMutation {
    CreationOrderSong.create(
      id: songID,
      CreationOrderSong.title.set("Draft"),
      CreationOrderSong.updatedAtMs.set(1),
      CreationOrderSong.isFinal.set(false)
    )
  }

  static func revise(_ title: String, updatedAtMs: Double) -> InstantMutation {
    CreationOrderSong.update(
      id: songID,
      CreationOrderSong.title.set(title),
      CreationOrderSong.updatedAtMs.set(updatedAtMs)
    )
  }

  /// A revision with one more field than ``revise(_:updatedAtMs:)``, so it never replaces an unsent revision in the
  /// outbox and both go on the wire.
  static func finish(_ title: String, updatedAtMs: Double) -> InstantMutation {
    CreationOrderSong.update(
      id: songID,
      CreationOrderSong.title.set(title),
      CreationOrderSong.updatedAtMs.set(updatedAtMs),
      CreationOrderSong.isFinal.set(true)
    )
  }

  @Test
  func twoTypedWritesInOneMillisecondReachTheOutboxAndTheWireInTheOrderTheyWereMade() async throws {
    let server = CreationOrderServer()
    let fixture = try await CreationOrderFixture.make(
      "typed-same-millisecond",
      now: { Self.sameMillisecond },
      liveTransport: server.transport
    )
    defer { fixture.remove() }

    try await fixture.client.transact([Self.create()], id: "m-create")
    try await fixture.client.transact([Self.revise("First", updatedAtMs: 2)], id: "z-first")
    try await fixture.client.transact([Self.finish("Second", updatedAtMs: 3)], id: "a-second")

    let outbox = await fixture.runtime.pendingMutations(limit: 10)
    expectNoDifference(outbox.map(\.id), ["m-create", "z-first", "a-second"])
    let start = Self.sameMillisecond.milliseconds
    expectNoDifference(outbox.map(\.createdAt.milliseconds), [start, start + 1, start + 2])
    // Every fact a typed write asserts carries the write's creation time, so the visible-write filter and the
    // same-entity supersession compare the order delivery uses.
    for mutation in outbox {
      expectNoDifference(mutation.writeTimes, [mutation.createdAt], "\(mutation.id)'s facts")
    }

    _ = try await fixture.runtime.connect()
    try await waitUntil("three transacts are sent") { await server.transactIDs().count == 3 }
    let sent = await server.transactIDs()
    expectNoDifference(sent, ["m-create", "z-first", "a-second"])
    _ = try? await fixture.runtime.closeConnection()
  }

  /// The clock may step back between two writes (a time sync). The second write is still made after the first.
  @Test
  func aTypedWriteMadeAfterTheClockStepsBackStillGoesAfterTheWriteBeforeIt() async throws {
    let clock = OSAllocatedUnfairLock(initialState: Self.sameMillisecond.milliseconds + 500)
    let fixture = try await CreationOrderFixture.make(
      "typed-clock-steps-back",
      now: { InstantTimestamp(milliseconds: clock.withLock { $0 }) }
    )
    defer { fixture.remove() }

    try await fixture.client.transact([Self.create()], id: "z-before")
    clock.withLock { $0 = Self.sameMillisecond.milliseconds }
    try await fixture.client.transact([Self.revise("After the step back", updatedAtMs: 2)], id: "a-after")

    let outbox = await fixture.runtime.pendingMutations(limit: 10)
    expectNoDifference(outbox.map(\.id), ["z-before", "a-after"])
    let before = Self.sameMillisecond.milliseconds + 500
    expectNoDifference(outbox.map(\.createdAt.milliseconds), [before, before + 1])
  }

  /// The immediate-tail supersession lets a new write replace the unsent write of the same row just before it, and only
  /// a write that sorts after it. With one stamp for both, the replacement depended on the ids: the newer revision
  /// either queued ahead of the older one, or, when the writes entered the gate in the other order, the older replaced
  /// the newer and the newer was never sent.
  @Test
  func aTypedWriteReplacesTheUnsentRevisionOfTheSameRowMadeInTheSameMillisecond() async throws {
    let fixture = try await CreationOrderFixture.make(
      "typed-same-millisecond-supersession",
      now: { Self.sameMillisecond }
    )
    defer { fixture.remove() }

    try await fixture.client.transact([Self.create()], id: "m-create")
    try await fixture.client.transact([Self.revise("First", updatedAtMs: 2)], id: "z-first")
    try await fixture.client.transact([Self.revise("Second", updatedAtMs: 3)], id: "a-second")

    let outbox = await fixture.runtime.pendingMutations(limit: 10)
    expectNoDifference(outbox.map(\.id), ["m-create", "a-second"])
    let start = Self.sameMillisecond.milliseconds
    expectNoDifference(outbox.map(\.createdAt.milliseconds), [start, start + 2])
    expectNoDifference(outbox.last?.insertedValue(of: "title"), InstantValue.string("Second"))
    let songs = try await fixture.client.query(CreationOrderSong.query)
    expectNoDifference(songs.map(\.title), ["Second"])
  }

  /// `failedMutationSupersessions()` calls a write later by its place in the outbox. A refused write whose covering
  /// write was made after it, in the same millisecond, but sorted first by id, was never superseded and stayed listed.
  @Test
  func aRefusedTypedWriteIsSupersededByTheWriteMadeAfterItInTheSameMillisecond() async throws {
    let server = CreationOrderServer()
    let fixture = try await CreationOrderFixture.make(
      "typed-refused-superseded",
      now: { Self.sameMillisecond },
      liveTransport: server.transport
    )
    defer { fixture.remove() }

    try await fixture.client.transact([Self.create()], id: "m-create")
    try await fixture.client.transact([Self.revise("First", updatedAtMs: 2)], id: "z-first")
    try await fixture.client.transact([Self.finish("Second", updatedAtMs: 3)], id: "a-second")
    _ = try await fixture.runtime.connect()
    try await waitUntil("three transacts are sent") { await server.transactIDs().count == 3 }

    await server.accept("m-create", transactionID: 1)
    try await waitUntil("m-create is accepted") { await fixture.status(of: "m-create") == .confirmed }
    await server.refuse("z-first")
    try await waitUntil("z-first is refused") { await fixture.status(of: "z-first") == .failed }
    await server.accept("a-second", transactionID: 2)
    try await waitUntil("a-second is accepted") { await fixture.status(of: "a-second") == .confirmed }

    let supersession = try await fixture.client.supersession(ofFailedMutation: "z-first")
    let covered = InstantSlotCoverage.Coverage.laterAcceptedWrite(mutationID: "a-second", serverTransactionID: "2")
    expectNoDifference(supersession.slots.map(\.attributeName), ["id", "title", "updatedAtMs"])
    expectNoDifference(supersession.slots.map(\.coverage), [covered, covered, covered])
    #expect(supersession.isSuperseded)
    _ = try? await fixture.runtime.closeConnection()
  }

  /// The device's case: the newer revision is accepted first and the older one is refused. A refusal that a later
  /// accepted write covers is resolved as accepted (library-78 item 3), when "later" is the order the writes were made.
  @Test
  func aRefusalCoveredByTheAcceptedWriteMadeAfterItInTheSameMillisecondResolvesAsAccepted() async throws {
    let server = CreationOrderServer()
    let fixture = try await CreationOrderFixture.make(
      "typed-refusal-resolved",
      now: { Self.sameMillisecond },
      liveTransport: server.transport
    )
    defer { fixture.remove() }

    try await fixture.client.transact([Self.create()], id: "m-create")
    try await fixture.client.transact([Self.revise("First", updatedAtMs: 2)], id: "z-first")
    try await fixture.client.transact([Self.finish("Second", updatedAtMs: 3)], id: "a-second")
    _ = try await fixture.runtime.connect()
    try await waitUntil("three transacts are sent") { await server.transactIDs().count == 3 }

    await server.accept("m-create", transactionID: 1)
    await server.accept("a-second", transactionID: 2)
    try await waitUntil("a-second is accepted") { await fixture.status(of: "a-second") == .confirmed }
    await server.refuse("z-first")
    try await waitUntil("z-first's refusal is resolved") { await fixture.status(of: "z-first") != .pending }

    let resolved = await fixture.status(of: "z-first")
    #expect(resolved != .failed, "a refusal the later accepted write covers is no failure")
    let failed = try await fixture.client.failedMutationSupersessions()
    expectNoDifference(failed, [:])
    _ = try? await fixture.runtime.closeConnection()
  }

  /// `InstantRuntime.transact(operations:)` read the clock before the gate too.
  @Test
  func runtimeOperationWritesInOneMillisecondKeepTheOrderTheyWereMade() async throws {
    let ids = OSAllocatedUnfairLock(initialState: [String]())
    let fixture = try await CreationOrderFixture.make(
      "operations-same-millisecond",
      now: { Self.sameMillisecond },
      makeID: { ids.withLock { $0.isEmpty ? UUID().uuidString.lowercased() : $0.removeFirst() } }
    )
    defer { fixture.remove() }
    ids.withLock { $0 = ["z-first", "a-second"] }

    // Different fields, so the second never replaces the first in the outbox.
    try await fixture.runtime.transact(
      operations: [
        .insert(Self.triple("id", .string(Self.songID.rawValue))),
        .insert(Self.triple("title", .string("First"))),
        .insert(Self.triple("updatedAtMs", .number(2))),
        .insert(Self.triple("isFinal", .bool(false))),
      ]
    )
    try await fixture.runtime.transact(
      operations: [
        .insert(Self.triple("id", .string(Self.songID.rawValue))),
        .insert(Self.triple("title", .string("Second"))),
        .insert(Self.triple("updatedAtMs", .number(3))),
      ]
    )

    let outbox = await fixture.runtime.pendingMutations(limit: 10)
    expectNoDifference(outbox.map(\.id), ["z-first", "a-second"])
    let start = Self.sameMillisecond.milliseconds
    expectNoDifference(outbox.map(\.createdAt.milliseconds), [start, start + 1])
  }

  static func triple(_ attribute: String, _ value: InstantValue) -> InstantTriple {
    InstantTriple(
      entityID: songID.rawValue,
      attributeID: "\(CreationOrderSong.instantNamespace)/\(attribute)",
      value: value,
      txID: "operations",
      txTime: sameMillisecond
    )
  }
}

// MARK: - Fixtures

@InstantEntity("creation_order_songs")
struct CreationOrderSong: Hashable, Codable, InstantEntityModel {
  var id: InstantID<CreationOrderSong>
  var title: String
  var updatedAtMs: Double
  var isFinal: Bool

  init(snapshot: InstantEntitySnapshot) throws {
    id = InstantID(rawValue: snapshot.id)
    title = try snapshot.value(Self.title, operation: "decode a creation order song")
    updatedAtMs = try snapshot.value(Self.updatedAtMs, operation: "decode a creation order song")
    isFinal = try snapshot.value(Self.isFinal, operation: "decode a creation order song")
  }
}

private struct CreationOrderFixture {
  var directory: URL
  var runtime: InstantRuntime
  var client: InstantSwiftDataClient

  static func make(
    _ name: String,
    now: @escaping @Sendable () -> InstantTimestamp,
    makeID: (@Sendable () -> String)? = nil,
    liveTransport: InstantLiveTransportClient? = nil
  ) async throws -> Self {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("write-creation-order-\(name)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    var configuration = InstantRuntimeConfiguration(
      appID: "write-creation-order-\(name)",
      persistenceURL: directory.appendingPathComponent("state.sqlite"),
      initialAttributes: CreationOrderSong.instantAttributes,
      now: now,
      liveTransport: liveTransport
    )
    if let makeID {
      configuration.makeID = makeID
    }
    configuration.autoConnectLiveTransport = false
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    return Self(directory: directory, runtime: runtime, client: InstantSwiftDataClient(runtime: runtime))
  }

  func status(of id: String) async -> InstantMutationStatus? {
    await runtime.durableOutboxMutationsForTesting().first { $0.id == id }?.status
  }

  func remove() {
    try? FileManager.default.removeItem(at: directory)
  }
}

extension PendingMutation {
  /// The times on every fact this write asserts or retracts.
  fileprivate var writeTimes: Set<InstantTimestamp> {
    Set(
      transaction.operations.compactMap { operation -> InstantTimestamp? in
        switch operation {
        case let .insert(triple), let .merge(triple), let .retract(triple):
          return triple.txTime
        default:
          return nil
        }
      }
    )
  }

  fileprivate func insertedValue(of attribute: String) -> InstantValue? {
    transaction.operations.lazy.compactMap { operation -> InstantValue? in
      guard case let .insert(triple) = operation, triple.attributeID.hasSuffix("/\(attribute)") else { return nil }
      return triple.value
    }.first
  }
}

private func waitUntil(
  _ step: String,
  within timeout: Duration = .seconds(60),
  _ condition: @Sendable () async throws -> Bool
) async throws {
  let deadline = ContinuousClock.now + timeout
  while try await !condition() {
    guard ContinuousClock.now < deadline else {
      Issue.record("Timed out: \(step)")
      return
    }
    try await Task.sleep(for: .milliseconds(5))
  }
}

/// A live server that answers `init` and records every frame the runtime sends; each test answers the transacts.
private actor CreationOrderServer {
  nonisolated private let abortState = InstantLiveTestWireAbortState()
  private var inbox: [InstantLiveMessage] = []
  private var receiver: InstantLiveTestPendingOperation<InstantLiveMessage>?
  private var sent: [InstantLiveMessage] = []

  nonisolated var transport: InstantLiveTransportClient {
    .immediate { _ in
      InstantLiveWebSocketSession(
        send: { message in try await self.send(message) },
        receive: {
          try self.abortState.check()
          return try await self.receive()
        },
        close: { await self.close() },
        abort: { self.abortState.abort() }
      )
    }
  }

  func transactIDs() -> [String?] {
    sent.filter { $0.op == "transact" }.map(\.clientEventID)
  }

  func accept(_ id: String, transactionID: Int) {
    deliver(
      InstantLiveMessage(op: "transact-ok", clientEventID: id, fields: ["tx-id": .string(String(transactionID))])
    )
  }

  /// The refusal a permission rule sends.
  func refuse(_ id: String) {
    deliver(
      InstantLiveMessage(
        op: "error",
        clientEventID: id,
        fields: [
          "message": .string("Permission denied: not perms-pass?"),
          "status": .number(400),
          "type": .string("permission-denied"),
          "original-event": .object(["client-event-id": .string(id), "op": .string("transact")]),
        ]
      )
    )
  }

  private func send(_ message: InstantLiveMessage) throws {
    try abortState.check()
    sent.append(message)
    guard message.op == "init" else { return }
    deliver(
      InstantLiveMessage(
        op: "init-ok",
        clientEventID: message.clientEventID,
        fields: [
          "attrs": .array([]),
          "auth": .null,
          "session-id": .string("write-creation-order"),
        ]
      )
    )
  }

  private func deliver(_ message: InstantLiveMessage) {
    guard !abortState.isAborted else { return }
    if let receiver {
      self.receiver = nil
      abortState.unregister(receiver.abortToken)
      receiver.continuation.resume(returning: message)
    } else {
      inbox.append(message)
    }
  }

  private func receive() async throws -> InstantLiveMessage {
    if !inbox.isEmpty { return inbox.removeFirst() }
    let id = UUID()
    defer { clearReceiver(id: id) }
    return try await withCheckedThrowingContinuation { continuation in
      let continuation = InstantLiveTestThrowingContinuationBox(continuation)
      guard let abortToken = abortState.register({ continuation.resume(throwing: CancellationError()) }) else {
        continuation.resume(throwing: CancellationError())
        return
      }
      receiver = InstantLiveTestPendingOperation(id: id, abortToken: abortToken, continuation: continuation)
    }
  }

  private func close() {
    abortState.abort()
    receiver = nil
  }

  private func clearReceiver(id: UUID) {
    guard let receiver, receiver.id == id else { return }
    abortState.unregister(receiver.abortToken)
    self.receiver = nil
  }
}
