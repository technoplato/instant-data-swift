// History
// 2026-10-25  #1130  Created. Delivery took two pump passes per write, each starting with a background-priority retry
//                    turn under the operation gate: 176 claims and 176 retry turns for 88 writes in #1074's recording
//                    exercise, the largest holder after the prune.

import Foundation
import Testing

@testable import InstantSwiftDataCore

/// A write's delivery claims it once, and takes no retry turn while nothing failed (#1130).
///
/// Upstream `Reactor.js` flushes its pending mutations when it sends a new one and when the socket opens
/// (`_flushPendingMessages`); a `transact-ok` only settles the mutation it answers. Swift's pump also runs after an
/// acknowledgement, because a claim may have left writes behind for lack of room in flight; it now does only when a
/// write is waiting to be claimed.
@Suite(.serialized, .timeLimit(.minutes(2)))
struct InstantDeliveryPassTests {
  /// Eight writes, each sent and acknowledged before the next: eight claims, no retry turn.
  @Test
  func eachAcknowledgedWriteTakesOneClaimAndNoRetryTurn() async throws {
    let session = LiveReactorParitySession(messages: [liveReactorInitOK(attrs: liveReactorTodoServerAttrs)])
    let holds = InstantGateHoldCounter()
    let runtime = try await InstantObserverRegistrationGateTests.runtime(
      "delivery-passes",
      transport: session.transport
    ) {
      $0.operationGateTimeline = holds.record
    }
    _ = try await runtime.connect()
    try await InstantConnectionStateTruthTests.waitUntil("the connection's first pass to finish") {
      await runtime.automaticMutationPumpIsIdleForTesting()
    }
    holds.reset()

    let writes = 8
    for index in 0..<writes {
      try await InstantOfflineRuntimeFixture.createTodo("pass-\(index)", in: runtime)
      try await InstantConnectionStateTruthTests.waitUntil("write \(index) to reach the socket") {
        await session.sentMessages().contains { $0.op == "transact" && $0.clientEventID == "tx-pass-\(index)" }
      }
      await session.enqueue(
        InstantLiveMessage(op: "transact-ok", clientEventID: "tx-pass-\(index)", fields: ["tx-id": .string("server-\(index)")])
      )
      try await InstantConnectionStateTruthTests.waitUntil("the server to accept write \(index)") {
        await runtime.pendingMutations().isEmpty
      }
      try await InstantConnectionStateTruthTests.waitUntil("the pump to finish after write \(index)") {
        await runtime.automaticMutationPumpIsIdleForTesting()
      }
    }

    let claims = holds.count(of: "claim automatic outbox transport mutations for delivery")
    let retryTurns = holds.count(of: "retry one persisted transient mutation failure window")
    #expect(claims == writes, "#1130: \(claims) delivery claims for \(writes) writes")
    #expect(retryTurns == 0, "#1130: \(retryTurns) retry turns while nothing failed")
    let sent = await session.sentMessages().filter { $0.op == "transact" }.compactMap(\.clientEventID)
    #expect(sent == (0..<writes).map { "tx-pass-\($0)" }, "every write is sent once, in order: \(sent)")

    _ = try? await runtime.closeConnection()
  }
}
