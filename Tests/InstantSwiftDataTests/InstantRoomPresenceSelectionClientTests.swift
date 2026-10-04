import CustomDump
import Foundation
import InstantSwiftData
import Testing

/// The client's presence selection (#461): only the selected part of a room's presence, and only when it changed, as
/// `Reactor.js`'s `subscribePresence` options and `hasPresenceResponseChanged` (presence.ts) give a handler.
@Suite
struct InstantRoomPresenceSelectionClientTests {
  @Test
  func aClientPresenceSelectionForwardsOnlyChangesToItsPart() async throws {
    let room = InstantRoomHandle(type: "recording", id: "room-client-selection")
    let (source, feed) = AsyncStream.makeStream(of: [InstantRoomPresenceMember].self, bufferingPolicy: .unbounded)
    let client = InstantSwiftDataClient(
      transact: { transaction in
        InstantStoreMutationResult(
          transactionID: transaction.id,
          changedEntityIDs: [],
          tripleCount: transaction.operations.count,
          emissions: []
        )
      },
      query: { _ in [] },
      observe: { _ in AsyncStream { continuation in continuation.finish() } },
      pendingMutations: { [] },
      localID: { name in "mock-\(name)" },
      observeRoomPresence: { _ in source }
    )
    let stream = try await client.observeRoomPresence(
      room: room,
      selection: InstantRoomPresenceSelection(keys: ["status"], includesLocal: false)
    )
    let received = ClientSelectionRecorder()
    let reader = Task {
      for await slice in stream { await received.record(slice) }
    }
    defer { reader.cancel() }
    func member(peerID: String?, status: String, cursor: Double) -> InstantRoomPresenceMember {
      InstantRoomPresenceMember(
        appID: "mock-app",
        room: room,
        userID: "user-michael",
        peerID: peerID,
        values: ["status": .string(status), "cursor": .number(cursor)],
        updatedAt: InstantTimestamp(milliseconds: Int64(cursor))
      )
    }

    feed.yield([member(peerID: nil, status: "here", cursor: 1), member(peerID: "session-agent", status: "online", cursor: 1)])
    try await waitForClientSelection("the first selected part") { await received.count == 1 }

    feed.yield([member(peerID: nil, status: "here", cursor: 2), member(peerID: "session-agent", status: "online", cursor: 2)])
    try await Task.sleep(nanoseconds: 200_000_000)
    let afterUnselectedChange = await received.count
    expectNoDifference(afterUnselectedChange, 1, "A change to an unselected key was forwarded.")

    feed.yield([member(peerID: nil, status: "here", cursor: 2), member(peerID: "session-agent", status: "away", cursor: 2)])
    try await waitForClientSelection("the selected key's change") { await received.count == 2 }
    let slices = await received.slices
    expectNoDifference(slices.map { $0.map(\.peerID) }, [["session-agent"], ["session-agent"]])
    expectNoDifference(
      slices.map { $0.map(\.values) },
      [[["status": .string("online")]], [["status": .string("away")]]]
    )
    feed.finish()
  }
}

private actor ClientSelectionRecorder {
  private(set) var slices: [[InstantRoomPresenceMember]] = []

  var count: Int { slices.count }

  func record(_ slice: [InstantRoomPresenceMember]) {
    slices.append(slice)
  }
}

private struct ClientSelectionWaitTimedOut: Error, CustomStringConvertible {
  var description: String
}

/// Polls `condition` every 2 ms for at most 5 s (the codebase's timeout rule).
private func waitForClientSelection(
  _ description: String,
  _ condition: @Sendable () async -> Bool
) async throws {
  let deadline = ContinuousClock.now + .seconds(5)
  while !(await condition()) {
    guard ContinuousClock.now < deadline else {
      throw ClientSelectionWaitTimedOut(description: "Timed out after 5 s waiting for \(description).")
    }
    try await Task.sleep(nanoseconds: 2_000_000)
  }
}
