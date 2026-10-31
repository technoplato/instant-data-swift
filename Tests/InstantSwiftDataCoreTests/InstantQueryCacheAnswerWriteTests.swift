// History:
// - 2026-10-31: created (#1498). A one-shot read JSON-encoded its whole answer into the query cache on every read, on
//   the persistence actor, whether or not the answer had changed: 431 of queryOnce's 795 ms of CPU a minute in the
//   #1482 audit's sample of the recording exercise (60 reads of one unchanged page, Mac mini, release).

import CustomDump
import Foundation
import Testing

@testable import InstantSwiftDataCore

/// A one-shot read leaves its answer as the query's cached row, and a reader of that row sees the last read's answer,
/// time, revisions and sequence (#1498). An answer the row already holds is not encoded again: only what changed since
/// the last read is written.
@Suite(.serialized, .timeLimit(.minutes(2)))
struct InstantQueryCacheAnswerWriteTests {
  /// The open todos, so a completed todo moves the store without changing the answer.
  static let openPlan = InstantQueryPlan(
    id: "examples.todos.open",
    namespace: TodoExample.namespace,
    filters: [.equals(field: "isCompleted", value: .bool(false))],
    order: InstantQueryOrder("createdAt", .ascending)
  )

  /// A repeated read whose answer did not change encodes nothing, and leaves the row a whole write would have: its
  /// answer, the read's time, the store's revisions and the read's sequence, in this process and after a relaunch.
  @Test
  func anUnchangedRepeatedReadEncodesNoAnswer() async throws {
    let cacheURL = try InstantStoredResultReloadTests.temporaryCacheURL()
    let clock = InstantLiveQueryResultWriteTests.TestClock(1_700_000_000_100)
    let runtime = try await Self.runtime(cacheURL, clock: clock)
    try await Self.createTodo("open", completed: false, in: runtime)
    let first = try await runtime.queryOnce(Self.openPlan)

    try await Self.createTodo("done", completed: true, in: runtime)
    clock.advance(by: 1_000)
    let encodesBefore = runtime.persistence.queryCacheAnswerEncodeCountForTesting()
    let second = try await runtime.queryOnce(Self.openPlan)
    let encodes = runtime.persistence.queryCacheAnswerEncodeCountForTesting() - encodesBefore
    let state = try await runtime.persistence.loadState()

    expectNoDifference(second.values, first.values, "a completed todo is not open")
    #expect(second.sequence > first.sequence, "the completed todo moved the store's sequence")
    #expect(encodes == 0, "#1498: an unchanged answer was encoded again (\(encodes))")
    let expected = InstantCachedQuery(
      queryID: Self.openPlan.id,
      plan: Self.openPlan,
      emission: second,
      updatedAt: clock.now(),
      storeRevision: state.storeRevision,
      attributeRevision: state.attributeRevision
    )
    let cached = try await runtime.cachedQuery(Self.openPlan)
    expectNoDifference(cached, expected)

    let relaunched = try await Self.runtime(cacheURL, clock: clock)
    let relaunchedCached = try await relaunched.cachedQuery(Self.openPlan)
    let relaunchedCachedQueries = try await relaunched.cachedQueries()
    expectNoDifference(relaunchedCached, expected)
    expectNoDifference(relaunchedCachedQueries, [expected])
  }

  /// A changed answer is written whole, once.
  @Test
  func aChangedAnswerIsWrittenWhole() async throws {
    let clock = InstantLiveQueryResultWriteTests.TestClock(1_700_000_000_100)
    let runtime = try await Self.runtime(try InstantStoredResultReloadTests.temporaryCacheURL(), clock: clock)
    try await Self.createTodo("first", completed: false, in: runtime)
    _ = try await runtime.queryOnce(Self.openPlan)

    try await Self.createTodo("second", completed: false, in: runtime)
    clock.advance(by: 1_000)
    let encodesBefore = runtime.persistence.queryCacheAnswerEncodeCountForTesting()
    let answer = try await runtime.queryOnce(Self.openPlan)
    let encodes = runtime.persistence.queryCacheAnswerEncodeCountForTesting() - encodesBefore
    let state = try await runtime.persistence.loadState()

    expectNoDifference(answer.values.map(\.id), ["todo-first", "todo-second"])
    #expect(encodes == 1, "a changed answer is encoded once, not \(encodes) times")
    let cached = try await runtime.cachedQuery(Self.openPlan)
    expectNoDifference(
      cached,
      InstantCachedQuery(
        queryID: Self.openPlan.id,
        plan: Self.openPlan,
        emission: answer,
        updatedAt: clock.now(),
        storeRevision: state.storeRevision,
        attributeRevision: state.attributeRevision
      )
    )
  }

  /// When another connection replaced the row, a read whose answer is the one it cached before writes it again: the
  /// row is compared, not this process's memory of it.
  @Test
  func aReadRewritesARowAnotherConnectionReplaced() async throws {
    let cacheURL = try InstantStoredResultReloadTests.temporaryCacheURL()
    let clock = InstantLiveQueryResultWriteTests.TestClock(1_700_000_000_100)
    let runtime = try await Self.runtime(cacheURL, clock: clock)
    try await Self.createTodo("open", completed: false, in: runtime)
    let first = try await runtime.queryOnce(Self.openPlan)

    let other = try SQLitePersistenceStore(fileURL: cacheURL)
    try await other.bootstrap()
    let otherState = try await other.loadState()
    let replaced = try await other.saveQueryCache(
      InstantCachedQuery(
        queryID: Self.openPlan.id,
        plan: Self.openPlan,
        emission: InstantQueryEmission(queryID: Self.openPlan.id, sequence: 0, values: []),
        updatedAt: InstantTimestamp(milliseconds: 1),
        storeRevision: otherState.storeRevision,
        attributeRevision: otherState.attributeRevision
      ),
      expectedStoreRevision: otherState.storeRevision,
      expectedAttributeRevision: otherState.attributeRevision
    )
    #expect(replaced)

    clock.advance(by: 1_000)
    let second = try await runtime.queryOnce(Self.openPlan)
    let state = try await runtime.persistence.loadState()

    expectNoDifference(second.values, first.values)
    let cached = try await runtime.cachedQuery(Self.openPlan)
    expectNoDifference(
      cached,
      InstantCachedQuery(
        queryID: Self.openPlan.id,
        plan: Self.openPlan,
        emission: second,
        updatedAt: clock.now(),
        storeRevision: state.storeRevision,
        attributeRevision: state.attributeRevision
      )
    )
  }

  /// A read that adopts another connection's write under the operation gate, and finds its answer unchanged, encodes
  /// nothing either.
  @Test
  func anUnchangedReadUnderTheGateEncodesNoAnswer() async throws {
    let cacheURL = try InstantStoredResultReloadTests.temporaryCacheURL()
    let clock = InstantLiveQueryResultWriteTests.TestClock(1_700_000_000_100)
    let holds = InstantGateHoldCounter()
    let runtime = try await Self.runtime(cacheURL, clock: clock) { $0.operationGateTimeline = holds.record }
    try await Self.createTodo("open", completed: false, in: runtime)
    let first = try await runtime.queryOnce(Self.openPlan)

    let writer = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "query-cache-answer-write",
        persistenceURL: cacheURL,
        now: { clock.now() }
      )
    )
    try await Self.createTodo("done", completed: true, in: writer)
    clock.advance(by: 1_000)
    holds.reset()
    let encodesBefore = runtime.persistence.queryCacheAnswerEncodeCountForTesting()
    let second = try await runtime.queryOnce(Self.openPlan)
    let encodes = runtime.persistence.queryCacheAnswerEncodeCountForTesting() - encodesBefore
    let state = try await runtime.persistence.loadState()

    expectNoDifference(
      holds.count(of: "materializeLocalQueryOnceUnderTheGate(_:enforcesConnectionFreshness:remotePageInfo:)"),
      1,
      "the read adopted the other connection's write under the gate"
    )
    expectNoDifference(second.values, first.values)
    #expect(encodes == 0, "#1498: an unchanged answer was encoded again under the gate (\(encodes))")
    let cached = try await runtime.cachedQuery(Self.openPlan)
    expectNoDifference(
      cached,
      InstantCachedQuery(
        queryID: Self.openPlan.id,
        plan: Self.openPlan,
        emission: second,
        updatedAt: clock.now(),
        storeRevision: state.storeRevision,
        attributeRevision: state.attributeRevision
      )
    )
  }

  /// A closed connection's error still carries the row an unchanged read left, as it is.
  @Test
  func aClosedConnectionsErrorCarriesTheRowAnUnchangedReadLeft() async throws {
    let clock = InstantLiveQueryResultWriteTests.TestClock(1_700_000_000_100)
    let runtime = try await Self.runtime(try InstantStoredResultReloadTests.temporaryCacheURL(), clock: clock)
    try await Self.createTodo("open", completed: false, in: runtime)
    _ = try await runtime.queryOnce(Self.openPlan)
    try await Self.createTodo("done", completed: true, in: runtime)
    clock.advance(by: 1_000)
    let second = try await runtime.queryOnce(Self.openPlan)
    let cached = try #require(try await runtime.cachedQuery(Self.openPlan))

    try await runtime.closeConnection()
    do {
      _ = try await runtime.queryOnce(Self.openPlan)
      Issue.record("Expected queryOnce to fail while the connection is closed.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .networkFailed)
      expectNoDifference(error.cachedQuery, cached)
      expectNoDifference(error.cachedQuery?.emission.values, second.values)
    }
  }

  private static func runtime(
    _ cacheURL: URL,
    clock: InstantLiveQueryResultWriteTests.TestClock,
    configure: (inout InstantRuntimeConfiguration) -> Void = { _ in }
  ) async throws -> InstantRuntime {
    var configuration = InstantRuntimeConfiguration(
      appID: "query-cache-answer-write",
      persistenceURL: cacheURL,
      initialAttributes: TodoExample.attributes,
      now: { clock.now() }
    )
    configure(&configuration)
    return try await InstantRuntime.bootstrap(configuration: configuration)
  }

  /// Creates `todo-<name>`, completed or open.
  private static func createTodo(_ name: String, completed: Bool, in runtime: InstantRuntime) async throws {
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_000_000)
    var operations = TodoExample.createOperations(
      id: "todo-\(name)",
      text: name,
      createdAt: createdAt,
      transactionID: "tx-\(name)"
    )
    if completed {
      operations += TodoExample.completeOperations(id: "todo-\(name)", updatedAt: createdAt, transactionID: "tx-\(name)")
    }
    _ = try await runtime.transact(InstantStoreTransaction(id: "tx-\(name)", operations: operations), createdAt: createdAt)
  }
}
