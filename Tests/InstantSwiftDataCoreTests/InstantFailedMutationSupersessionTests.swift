import CustomDump
import Foundation
@testable import InstantSwiftDataCore
import Testing

/// #445: Michael's Sync view lists every pending and refused change and offers "Clear Superseded Refusals". It asks the
/// library, per failed mutation, whether it is superseded and by what: the rule the library applies to a refused re-send
/// itself (library-78 item 3, #441), reported slot by slot and read only. A slot is covered by the newest later write of
/// this device that the server accepted and that sets it, or by a live-query result the server sent since the write was
/// created that shows its value; a later write the server has not accepted yet is named but does not count.
@Suite(.serialized)
struct InstantFailedMutationSupersessionTests {
  typealias Fixture = InstantRefusalHeldByServerTests.Fixture
  static let todoID = InstantRefusalHeldByServerTests.todoID

  static func slot(
    _ attribute: String,
    _ value: InstantValue,
    _ coverage: InstantSlotCoverage.Coverage
  ) -> InstantSlotCoverage {
    InstantSlotCoverage(
      entityID: todoID,
      namespace: TodoExample.namespace,
      attributeName: attribute,
      attributeID: "\(TodoExample.namespace)/\(attribute)",
      operation: .insert,
      value: value,
      coverage: coverage
    )
  }

  /// Refuses `id`'s first offer on the first connection and waits until it is recorded as failed.
  static func refuseFirstOffer(_ id: String, in fixture: Fixture) async throws {
    await fixture.first.enqueue(InstantSupersededReplayTests.refused(id))
    try await InstantSupersededReplayTests.waitUntil("\(id) is refused") {
      await InstantSupersededReplayTests.mutation(id, in: fixture.runtime)?.status == .failed
    }
  }

  @Test
  func aFailedWriteThatALaterAcceptedWriteCoversIsSupersededByIt() async throws {
    let fixture = try await Fixture.make("supersession-accepted")
    try await InstantSupersededReplayTests.updateText(fixture.runtime, "tx-first", "first", at: 1)
    try await InstantSupersededReplayTests.updateText(fixture.runtime, "tx-second", "second", at: 2)
    _ = try await InstantSupersededReplayTests.waitForTransacts(3, on: fixture.first)
    try await Self.refuseFirstOffer("tx-first", in: fixture)
    await fixture.first.enqueue(InstantSupersededReplayTests.accepted("tx-second", transactionID: 3))
    try await InstantSupersededReplayTests.waitUntil("tx-second is accepted") {
      await InstantSupersededReplayTests.mutation("tx-second", in: fixture.runtime)?.status == .confirmed
    }

    let supersession = try await fixture.runtime.failedMutationSupersession(id: "tx-first")
    let covered = InstantSlotCoverage.Coverage.laterAcceptedWrite(mutationID: "tx-second", serverTransactionID: "3")
    expectNoDifference(
      supersession,
      .superseded(by: [
        Self.slot("id", .string(Self.todoID), covered),
        Self.slot("text", .string("first"), covered),
      ])
    )
    _ = try await fixture.runtime.closeConnection()
  }

  @Test
  func aFailedWriteWhoseValuesTheServersResultShowsIsSuperseded() async throws {
    let fixture = try await Fixture.make("supersession-server-result")
    try await InstantSupersededReplayTests.updateText(fixture.runtime, "tx-first", "first", at: 1)
    _ = try await InstantSupersededReplayTests.waitForTransacts(2, on: fixture.first)
    await fixture.first.enqueue(fixture.refresh(text: "first", processedTransactionID: 3))
    try await fixture.waitUntilTheStoredResultShows(text: "first")
    try await Self.refuseFirstOffer("tx-first", in: fixture)

    let supersession = try await fixture.runtime.failedMutationSupersession(id: "tx-first")
    #expect(supersession.isSuperseded)
    expectNoDifference(supersession.slots.map(\.attributeID), ["todos/id", "todos/text"])
    for slot in supersession.slots {
      guard case .serverResult = slot.coverage else {
        Issue.record("\(slot.attributeID) should be covered by the server's result, not \(slot.coverage)")
        continue
      }
    }
    _ = try await fixture.runtime.closeConnection()
  }

  @Test
  func aFailedWriteTheServerShowsAnotherValueForIsNotSuperseded() async throws {
    let fixture = try await Fixture.make("supersession-other-value")
    try await InstantSupersededReplayTests.updateText(fixture.runtime, "tx-first", "first", at: 1)
    _ = try await InstantSupersededReplayTests.waitForTransacts(2, on: fixture.first)
    await fixture.first.enqueue(fixture.refresh(text: "another device's text", processedTransactionID: 3))
    try await fixture.waitUntilTheStoredResultShows(text: "another device's text")
    try await Self.refuseFirstOffer("tx-first", in: fixture)

    let supersession = try await fixture.runtime.failedMutationSupersession(id: "tx-first")
    #expect(!supersession.isSuperseded)
    let text = supersession.slots.first { $0.attributeID == "todos/text" }
    expectNoDifference(text?.coverage, .notCovered(serverValues: [.string("another device's text")]))
    let identity = supersession.slots.first { $0.attributeID == "todos/id" }
    #expect(identity?.isCovered == true, "the server's result shows the entity")
    let all = try await fixture.runtime.failedMutationSupersessions()
    expectNoDifference(all, ["tx-first": supersession])
    _ = try await fixture.runtime.closeConnection()
  }

  @Test
  func aFailedWriteOnlyAWriteInFlightCoversIsNotSupersededYet() async throws {
    let fixture = try await Fixture.make("supersession-in-flight")
    try await InstantSupersededReplayTests.updateText(fixture.runtime, "tx-first", "first", at: 1)
    try await InstantSupersededReplayTests.updateText(fixture.runtime, "tx-second", "second", at: 2)
    _ = try await InstantSupersededReplayTests.waitForTransacts(3, on: fixture.first)
    try await Self.refuseFirstOffer("tx-first", in: fixture)

    let supersession = try await fixture.runtime.failedMutationSupersession(id: "tx-first")
    let inFlight = InstantSlotCoverage.Coverage.laterPendingWrite(mutationID: "tx-second")
    expectNoDifference(
      supersession,
      .notSuperseded(slots: [
        Self.slot("id", .string(Self.todoID), inFlight),
        Self.slot("text", .string("first"), inFlight),
      ])
    )
    _ = try await fixture.runtime.closeConnection()
  }

  @Test
  func onlyARetainedFailedMutationHasASupersession() async throws {
    let fixture = try await Fixture.make("supersession-not-failed")
    for id in ["tx-create", "no-such-mutation"] {
      do {
        _ = try await fixture.runtime.failedMutationSupersession(id: id)
        Issue.record("\(id) is not a failed mutation")
      } catch let error as InstantError {
        expectNoDifference(error.code, .validationFailed)
      }
    }
    let all = try await fixture.runtime.failedMutationSupersessions()
    expectNoDifference(all, [:])
    _ = try await fixture.runtime.closeConnection()
  }
}
