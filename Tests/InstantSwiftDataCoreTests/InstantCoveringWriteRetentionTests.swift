import CustomDump
import Foundation
@testable import InstantSwiftDataCore
import Testing

/// #2028: an accepted write stays the evidence that an older write of the same slots is moot.
///
/// A write's first offer goes unanswered when its socket drops. A later write of the same row is accepted, and the
/// server's next result passes its transaction, so the watermark prunes it from the outbox. The older write is offered
/// again, and a rule that keeps a row's `updatedAtMs` from going back refuses it: the server holds a newer value for
/// every slot it sets. Library-78 (item 3) resolves such a write as accepted when later accepted writes of this device
/// cover all of it, but it reads those writes from the outbox, and the prune had removed them, so the refusal stood
/// and the app reported a write as refused that the server holds a newer value for. Instant's server applies every
/// transact it receives without deduplicating a client-event-id (`session.clj`), so a re-send can arrive after a newer
/// write of its row; `Reactor.js` drops its refusal as an error (`_handleMutationError`).
@Suite(.serialized)
struct InstantCoveringWriteRetentionTests {
  typealias Fixture = InstantRefusalHeldByServerTests.Fixture

  /// The answers of the newer write and of the server's result arrive before the older re-send's refusal.
  @Test
  func aReSendRefusalThatALaterWriteThePrunePassedCoversResolvesAsAccepted() async throws {
    let fixture = try await Fixture.make("retained-coverer-refusal")
    try await fixture.transact("tx-first", at: 1, text: "first", isCompleted: false)
    try await fixture.transact("tx-second", at: 2, text: "second", isCompleted: true)
    _ = try await InstantSupersededReplayTests.waitForTransacts(3, on: fixture.first)
    await fixture.dropTheFirstConnection()
    let resent = try await InstantSupersededReplayTests.waitForTransacts(2, on: fixture.second)
    expectNoDifference(resent, ["tx-first", "tx-second"])
    await fixture.second.enqueue(InstantSupersededReplayTests.accepted("tx-second", transactionID: 4))
    await fixture.second.enqueue(fixture.addQueryOK(text: "second", isCompleted: true, processedTransactionID: 4))
    try await fixture.waitUntilTheStoredResultShows(text: "second")
    await fixture.second.enqueue(InstantSupersededReplayTests.refused("tx-first"))
    try await InstantSupersededReplayTests.waitUntil("the refusal is resolved") {
      await InstantSupersededReplayTests.mutation("tx-first", in: fixture.runtime)?.status != .pending
    }

    let first = await InstantSupersededReplayTests.mutation("tx-first", in: fixture.runtime)
    expectNoDifference(first?.status, .confirmed)
    expectNoDifference(first?.confirmationSource, .supersededByAcceptedWrite)
    expectNoDifference(first?.serverTransactionID, "4")
    let failed = await fixture.failedMutationIDs()
    expectNoDifference(failed, [])
    _ = try await fixture.runtime.closeConnection()
  }

  /// Before any replay: the newer write's answer and the server's result arrive, then the socket drops. The next
  /// connection resolves the older write without offering it.
  @Test
  func aReSendThatALaterWriteThePrunePassedCoversIsResolvedWithoutAnOffer() async throws {
    let fixture = try await Fixture.make("retained-coverer-resend")
    try await fixture.transact("tx-first", at: 1, text: "first", isCompleted: false)
    try await fixture.transact("tx-second", at: 2, text: "second", isCompleted: true)
    _ = try await InstantSupersededReplayTests.waitForTransacts(3, on: fixture.first)
    await fixture.first.enqueue(InstantSupersededReplayTests.accepted("tx-second", transactionID: 4))
    await fixture.first.enqueue(fixture.refresh(text: "second", isCompleted: true, processedTransactionID: 4))
    try await fixture.waitUntilTheStoredResultShows(text: "second")
    await fixture.dropTheFirstConnection()
    try await InstantSupersededReplayTests.waitUntil("the re-send is resolved") {
      await InstantSupersededReplayTests.mutation("tx-first", in: fixture.runtime)?.status != .pending
    }

    let first = await InstantSupersededReplayTests.mutation("tx-first", in: fixture.runtime)
    expectNoDifference(first?.status, .confirmed)
    expectNoDifference(first?.confirmationSource, .supersededByAcceptedWrite)
    let failed = await fixture.failedMutationIDs()
    expectNoDifference(failed, [])
    try await Task.sleep(for: .milliseconds(200))
    let offered = await InstantSupersededReplayTests.transactIDs(sentTo: fixture.second)
    expectNoDifference(offered, [], "a write the server holds a newer value for is not offered again")
    _ = try await fixture.runtime.closeConnection()
  }

  /// A true refusal still stands: the newer write sets only some of the refused write's slots, and the server's result
  /// shows another value for the rest.
  @Test
  func aReSendRefusalThatALaterWriteCoversOnlyInPartStillFails() async throws {
    let fixture = try await Fixture.make("retained-partial-coverer")
    try await fixture.transact("tx-first", at: 1, text: "first", isCompleted: false)
    try await fixture.transact("tx-second", at: 2, text: nil, isCompleted: true)
    _ = try await InstantSupersededReplayTests.waitForTransacts(3, on: fixture.first)
    await fixture.dropTheFirstConnection()
    let resent = try await InstantSupersededReplayTests.waitForTransacts(2, on: fixture.second)
    expectNoDifference(resent, ["tx-first", "tx-second"])
    await fixture.second.enqueue(InstantSupersededReplayTests.accepted("tx-second", transactionID: 4))
    await fixture.second.enqueue(fixture.addQueryOK(text: "created", isCompleted: true, processedTransactionID: 4))
    try await fixture.waitUntilTheStoredResultShows(text: "created")
    await fixture.second.enqueue(InstantSupersededReplayTests.refused("tx-first"))
    try await InstantSupersededReplayTests.waitUntil("the refusal is recorded") {
      await InstantSupersededReplayTests.mutation("tx-first", in: fixture.runtime)?.status == .failed
    }

    let failed = await fixture.failedMutationIDs()
    expectNoDifference(failed, ["tx-first"])
    _ = try await fixture.runtime.closeConnection()
  }
}
