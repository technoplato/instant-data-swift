// History
// 2026-10-25  #1132  Created. connectionStatus(), observeConnectionStatus() and observeAuthSession() queued on the
//                    operation gate for reads that need no exclusion: an auth observer's median wait was 1.7-10.7 s on
//                    builds 121-126, and #1074's recording exercise measured connectionStatus() at 1,815 ms p99.

import Foundation
import Testing

@testable import InstantSwiftDataCore

/// A connection status and an auth session are read, and observed, without the operation gate (#1132): the observer
/// registries keep the latest value they published, so a registration takes it in the same turn as any publish and can
/// neither miss one nor register late, which is what the gate guarded.
///
/// Upstream `Reactor.js` keeps the connection status and the auth user in memory and hands a new subscriber the current
/// value at once (`subscribeConnectionStatus`, `subscribeAuth`); nothing there waits for a write in progress.
@Suite(.serialized, .timeLimit(.minutes(2)))
struct InstantStatusReadsOffTheGateTests {
  /// While another caller holds the operation gate, a status read, a status observation and a session observation
  /// each answer.
  @Test
  func statusAndSessionReadsAnswerWhileAnotherCallerHoldsTheGate() async throws {
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "status-off-the-gate",
        persistenceURL: try InstantStoredResultReloadTests.temporaryCacheURL(),
        initialAttributes: TodoExample.attributes,
        liveTransport: .local
      )
    )
    let held = InstantPausePoint()
    let holder = Task {
      await runtime.holdingOperationGateForTesting {
        await held.pauseOnce()
      }
    }
    try await held.waitUntilEntered(within: .seconds(10))

    let status = await InstantObserverRegistrationGateTests.finishes(within: .seconds(2)) {
      _ = try await runtime.connectionStatus()
    }
    let statusObservation = await InstantObserverRegistrationGateTests.finishes(within: .seconds(2)) {
      _ = try await runtime.observeConnectionStatus()
    }
    let sessionObservation = await InstantObserverRegistrationGateTests.finishes(within: .seconds(2)) {
      _ = try await runtime.observeAuthSession()
    }
    held.release()
    await holder.value
    try await status.work.value
    try await statusObservation.work.value
    try await sessionObservation.work.value

    #expect(status.finished, "#1132: connectionStatus() waited for the operation gate")
    #expect(statusObservation.finished, "#1132: observeConnectionStatus() waited for the operation gate")
    #expect(sessionObservation.finished, "#1132: observeAuthSession() waited for the operation gate")

    _ = try? await runtime.closeConnection()
  }

  /// What a status read answers equals a read under the gate after each change the status shows (#1132): a
  /// connection, a local write, its acknowledgement, a write the server refused, and a close. Every writer of what the
  /// status reads computes a status under the gate, which is what the read answers from.
  @Test
  func aStatusReadAnswersWhatAReadUnderTheGateWould() async throws {
    let session = LiveReactorParitySession(messages: [liveReactorInitOK(attrs: liveReactorTodoServerAttrs)])
    var configuration = InstantRuntimeConfiguration(
      appID: "status-snapshot-coverage",
      persistenceURL: try InstantStoredResultReloadTests.temporaryCacheURL(),
      initialAttributes: TodoExample.attributes,
      liveTransport: session.transport
    )
    configuration.autoConnectLiveTransport = false
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    var differences: [String] = []
    func check(_ step: String) async throws {
      let answered = try await runtime.connectionStatus()
      let underTheGate = try await runtime.connectionStatusUnderTheGateForTesting()
      if answered != underTheGate {
        differences.append("\(step): answered \(answered), under the gate \(underTheGate)")
      }
    }

    try await check("bootstrap")
    _ = try await runtime.connect()
    try await check("a connection")
    try await InstantOfflineRuntimeFixture.createTodo("accepted", in: runtime)
    try await check("a local write")
    try await InstantConnectionStateTruthTests.waitUntil("the write to reach the socket") {
      await session.sentMessages().contains { $0.op == "transact" && $0.clientEventID == "tx-accepted" }
    }
    await session.enqueue(
      InstantLiveMessage(op: "transact-ok", clientEventID: "tx-accepted", fields: ["tx-id": .string("server-accepted")])
    )
    try await InstantConnectionStateTruthTests.waitUntil("the server to accept the write") {
      await runtime.pendingMutations().isEmpty
    }
    try await check("its acknowledgement")
    try await InstantOfflineRuntimeFixture.createTodo("refused", in: runtime)
    try await InstantConnectionStateTruthTests.waitUntil("the refused write to reach the socket") {
      await session.sentMessages().contains { $0.op == "transact" && $0.clientEventID == "tx-refused" }
    }
    await session.enqueue(
      InstantLiveMessage(
        op: "error",
        clientEventID: "tx-refused",
        fields: [
          "message": .string("permission denied"),
          "status": .number(403),
          "type": .string("permission-denied"),
        ]
      )
    )
    // Waits on the outbox, not a status read under the gate, which would refresh what the next read answers from.
    try await InstantConnectionStateTruthTests.waitUntil("the refusal to land") {
      await runtime.outboxMutations().contains { $0.id == "tx-refused" && $0.status == .failed }
    }
    try await check("a refused write")
    _ = try await runtime.closeConnection()
    try await check("a close")

    #expect(differences.isEmpty, "#1132: \(differences.joined(separator: "; "))")
  }
}
