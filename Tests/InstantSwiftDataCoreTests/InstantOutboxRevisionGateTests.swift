import CustomDump
import Foundation
@testable import InstantSwiftDataCore
import Testing

/// #303: recording a server refusal must not run out of attempts while this runtime keeps writing.
///
/// Each attempt of `failClaimedMutation` loads its state under the operation gate, releases the gate to load and
/// prepare the refused write's component, and takes the gate again to commit. In the experiment's large-store drop
/// (pair-large-drop-r1) dictation's own writes landed in that window five times in a row, so the attempts went stale
/// and "The local outbox changed repeatedly while updating mutation" ended the live receive loop: the reconnect
/// re-sent every write in flight, and the server refused them as replays. Upstream `Reactor.js` records a refusal
/// synchronously (`_handleMutationError`), so nothing can interleave; Swift gives the refusal one exclusive attempt.
@Suite(.serialized)
struct InstantOutboxRevisionGateTests {
  final class RuntimeReference: @unchecked Sendable {
    private let lock = NSLock()
    private var storedRuntime: InstantRuntime?
    private var storedWrites = 0
    private var storedExclusiveAttempts = 0

    var runtime: InstantRuntime? {
      get { lock.withLock { storedRuntime } }
      set { lock.withLock { storedRuntime = newValue } }
    }

    func nextWrite() -> Int {
      lock.withLock {
        storedWrites += 1
        return storedWrites
      }
    }

    var writes: Int { lock.withLock { storedWrites } }

    func recordExclusiveAttempt() {
      lock.withLock { storedExclusiveAttempts += 1 }
    }

    var exclusiveAttempts: Int { lock.withLock { storedExclusiveAttempts } }
  }

  static func temporaryCacheURL() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("instant-outbox-revision-gate-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("instant.sqlite")
  }

  static func todo(_ runtime: InstantRuntime, id: String, at milliseconds: Int64) async throws {
    let createdAt = InstantTimestamp(milliseconds: milliseconds)
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-\(id)",
        operations: TodoExample.createOperations(
          id: id,
          text: "dictation keeps writing",
          createdAt: createdAt,
          transactionID: "tx-\(id)"
        )
      ),
      createdAt: createdAt
    )
  }

  @Test
  func localWritesDuringEveryAttemptToRecordARefusalGetOneExclusiveAttempt() async throws {
    let session = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "refusal-under-writes")
    ])
    // One scripted session only: a receive-loop failure would reconnect, and that second connection would fail.
    let transport = LiveReactorParityTransport(sessions: [session])
    let reference = RuntimeReference()
    var configuration = InstantRuntimeConfiguration(
      appID: "refusal-under-local-writes",
      persistenceURL: try Self.temporaryCacheURL(),
      initialAttributes: TodoExample.attributes,
      liveTransport: transport.transport
    )
    configuration.liveReconnectSleep = { _ in }
    configuration.onClaimedTerminalFailureLoadedForTesting = { operationGateHeld in
      guard !operationGateHeld else {
        reference.recordExclusiveAttempt()
        return
      }
      // A local write lands between the attempt's load and its commit, as dictation's did.
      guard let runtime = reference.runtime, reference.writes < 10 else { return }
      let write = reference.nextWrite()
      try? await Self.todo(runtime, id: "dictation-\(write)", at: 1_700_000_303_100 + Int64(write))
    }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    reference.runtime = runtime
    _ = try await runtime.connect()

    try await Self.todo(runtime, id: "refused", at: 1_700_000_303_000)
    try await instantLiveWithTimeout(operation: "wait for the write to be offered", timeoutMilliseconds: 5_000) {
      await session.waitForSentMessageCount(2)
    }
    await session.enqueue(
      InstantLiveMessage(
        op: "error",
        clientEventID: "tx-refused",
        fields: [
          "message": .string("Permission denied: not perms-pass?"),
          "status": .number(400),
          "type": .string("permission-denied"),
          "original-event": .object([
            "client-event-id": .string("tx-refused"),
            "op": .string("transact"),
          ]),
        ]
      )
    )
    let deadline = ContinuousClock.now + .seconds(10)
    var failedIDs: [String] = []
    while !failedIDs.contains("tx-refused"), ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(20))
      failedIDs = await runtime.outboxMutations().filter { $0.status == .failed }.map(\.id)
    }
    expectNoDifference(failedIDs, ["tx-refused"], "the refusal is recorded")
    expectNoDifference(reference.writes, 5, "a local write landed during each of the five optimistic attempts")
    expectNoDifference(reference.exclusiveAttempts, 1, "then one attempt held local writes until it landed")
    let connections = await transport.connectionRequests()
    expectNoDifference(connections.count, 1, "recording the refusal must not end the receive loop")
    let pending = await runtime.pendingMutations().map(\.id).sorted()
    expectNoDifference(pending, (1...5).map { "tx-dictation-\($0)" }.sorted())
    _ = try await runtime.closeConnection()
  }
}
