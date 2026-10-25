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
}
