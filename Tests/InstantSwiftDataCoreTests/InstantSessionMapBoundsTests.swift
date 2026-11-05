// History:
// - 2026-11-04: added (#541): the live-query acknowledgement maps hold only the keys a registration holds. Ported from
//   the 1.9.9 branch's red test (60770190), which never reached main.

import CustomDump
import Foundation
import Testing

@testable import InstantSwiftDataCore

/// #541: a map that grew for a session's whole life is bounded by what is live.
///
/// The live-query acknowledgement state kept a revision and an outcome for every live-query key a session ever
/// registered: a one-shot read waits on them, and nothing let them go. A phone's agent replies restarted about 380 times
/// in 16 minutes on 2026-10-04, each with a new key; the memory audit measured 3,151 B kept per closed lease (E06).
@Suite(.serialized, .timeLimit(.minutes(2)))
struct InstantSessionMapBoundsTests {
  static func temporaryCacheURL() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("instant-session-map-bounds-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("instant.sqlite")
  }

  static func waitForMessages(
    _ op: String,
    count: Int,
    in session: LiveReactorParitySession
  ) async throws -> [InstantLiveMessage] {
    let deadline = ContinuousClock.now + .seconds(10)
    while true {
      let sent = await session.sentMessages().filter { $0.op == op }
      if sent.count >= count || ContinuousClock.now >= deadline { return sent }
      try await Task.sleep(for: .milliseconds(10))
    }
  }

  /// Twelve distinct live queries, each answered by the server and then given up, leave no acknowledgement entry.
  @Test
  func liveQueriesThatUnregisterLeaveNoAcknowledgementEntries() async throws {
    let session = LiveReactorParitySession(messages: [liveReactorInitOK(attrs: liveReactorTodoServerAttrs)])
    var configuration = InstantRuntimeConfiguration(
      appID: "session-map-bounds-acknowledgements",
      persistenceURL: try Self.temporaryCacheURL(),
      initialAttributes: TodoExample.attributes,
      liveTransport: session.transport
    )
    configuration.liveReconnectSleep = { _ in }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    _ = try await runtime.connect()

    for index in 0..<12 {
      let plan = InstantQueryPlan(
        id: "todos.restart.\(index)",
        namespace: TodoExample.namespace,
        order: InstantQueryOrder("createdAt", .ascending),
        limit: index + 1
      )
      let observation = await runtime.observeQueryLease(plan)
      var iterator = observation.stream.makeAsyncIterator()
      _ = await iterator.next()
      let added = try await Self.waitForMessages("add-query", count: index + 1, in: session)
      try #require(added.count == index + 1, "add-query \(index) was sent")
      await session.enqueue(
        liveReactorAddQueryOK(
          query: try InstantLiveQueryEncoder.encode(plan),
          processedTransactionID: "server-tx-\(index)",
          result: liveReactorTodoQueryResult(
            id: "todo-\(index)",
            text: "row \(index)",
            createdAt: InstantTimestamp(milliseconds: 1_700_000_541_000 + Int64(index))
          )
        )
      )
      let deadline = ContinuousClock.now + .seconds(10)
      while try await !runtime.isAnsweredOnCurrentSocketForTesting(plan) {
        guard ContinuousClock.now < deadline else {
          Issue.record("The server's answer to query \(index) was never recorded.")
          break
        }
        try await Task.sleep(for: .milliseconds(5))
      }
      await observation.cancel()
      let removed = try await Self.waitForMessages("remove-query", count: index + 1, in: session)
      try #require(removed.count == index + 1, "remove-query \(index) was sent")
    }

    let remembered = await runtime.liveQueryAcknowledgementKeyCountForTesting()
    #expect(remembered == 0, "keys remembered after every query unregistered: \(remembered)")
    _ = try await runtime.closeConnection()
  }
}
