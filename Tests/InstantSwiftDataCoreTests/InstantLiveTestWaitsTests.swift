// History
// 2026-10-23  #1020  Created. The shared live test sessions' count waits had no bound; each now fails once its count
//                    stands still for the bound, naming what it saw.

import CustomDump
import Foundation
@testable import InstantSwiftDataCore
import Testing

/// The live test support's count waits end by themselves (#1020). A wait that can never be satisfied used to park the
/// whole InstantSwiftDataCoreTests bundle at 0% CPU until someone killed it.
@Suite
struct InstantLiveTestWaitsTests {
  @Test
  func reactorParitySessionSentMessageWaitFailsWhenNothingMoreIsSent() async throws {
    let session = LiveReactorParitySession(messages: [])
    let socket = session.webSocketSession
    try await socket.send(InstantLiveMessage(op: "init", clientEventID: "init"))
    try await socket.send(InstantLiveMessage(op: "transact", clientEventID: "tx-01"))

    let error = try #require(
      try await stalledWait {
        try await session.waitForSentMessageCount(3, timeout: .milliseconds(200))
      }
    )

    expectNoDifference(error.wait, "3 sent messages")
    expectNoDifference(error.observed, ["init init", "transact tx-01"])
    await socket.close()
  }

  @Test
  func reactorParityTransportConnectionWaitFailsWhenNoOtherConnectionStarts() async throws {
    let transport = LiveReactorParityTransport(sessions: [LiveReactorParitySession(messages: [])])
    let socket = try await transport.transport.connect(
      InstantLiveSessionRequest(appID: "parity-connection-wait-bound")
    )

    let error = try #require(
      try await stalledWait {
        try await transport.waitForConnectionCount(2, timeout: .milliseconds(200))
      }
    )

    expectNoDifference(error.wait, "2 connections")
    expectNoDifference(error.observed, ["parity-connection-wait-bound"])
    await socket.close()
  }
}

/// Runs `wait` under a 5 s guard and returns the stall it reported, or `nil` if it was satisfied. The guard only
/// catches a wait that never ends by itself; it is not the bound under test.
func stalledWait(
  _ wait: @escaping @Sendable () async throws -> Void
) async throws -> InstantLiveTestWaitTimedOut? {
  try await instantLiveWithTimeout(
    operation: "the live test wait must end by itself (#1020)",
    timeoutMilliseconds: InstantTestWait.hangMilliseconds
  ) {
    do {
      try await wait()
      return nil
    } catch let error as InstantLiveTestWaitTimedOut {
      return error
    }
  }
}
