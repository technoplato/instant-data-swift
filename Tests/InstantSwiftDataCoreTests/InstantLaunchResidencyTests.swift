// History:
// - 2026-11-04: added (#1107, #1149): a relaunch holds the newest stored results' rows, as upstream preloads ten; an
//   older result loads from disk when its query subscribes again.
// - 2026-11-05: a relaunch finds the entities it loads in the loaded results' ownership rows, reading no stored result
//   whole (#1149).

import CustomDump
import Foundation
import Testing

@testable import InstantSwiftDataCore

/// A relaunch holds the newest stored results, not every one (#1107, #1149).
///
/// A launch loaded every stored result's entities into memory, open or not: on a phone (2026-11-04, the consuming app's
/// build 253) 46 results held 1,915 entities and 48,202 facts after each relaunch, where the newest ten hold 677 and
/// 31,070. Upstream `PersistedObject` preloads the `preloadEntryCount` most recently updated query results
/// (`Reactor.js` passes 10) and loads any other when its query subscribes (`waitForKeyToLoad`). Results are unloaded
/// where they are (#1500), so a launch unloads the older ones with one write, and each reloads from disk when its query
/// subscribes again, before the server answers.
@Suite(.serialized, .timeLimit(.minutes(2)))
struct InstantLaunchResidencyTests {
  @Test
  func aRelaunchHoldsTheNewestStoredResultsAndReadsAnOlderOneFromDisk() async throws {
    let url = try InstantStoredResultReloadTests.temporaryCacheURL()
    try await Self.showAndCloseTheKeptTodoThenTheList(at: url)

    // The relaunch preloads the newest result only: the list's rows are in memory, the kept todo stays on disk.
    let silent = LiveReactorParitySession(messages: [liveReactorInitOK(attrs: liveReactorTodoServerAttrs)])
    var relaunch = Self.configuration(url, transport: silent.transport)
    #expect(relaunch.preloadedLiveQueryResultCount == 10, "upstream's preloadEntryCount")
    relaunch.preloadedLiveQueryResultCount = 1
    let runtime = try await InstantRuntime.bootstrap(configuration: relaunch)
    let heldAtLaunch = await runtime.store.entityIDsWithFacts(among: Self.todoIDs)
    expectNoDifference(heldAtLaunch, ["todo-1", "todo-2"])

    // The kept todo's query subscribes again: its result loads back from disk and answers before the server does.
    let reopened = await runtime.observeQueryLease(InstantStoredResultReloadTests.keepAliveTodosQuery)
    let first = try await InstantStoredResultReloadTests.emission(of: reopened.stream, operation: "reopen the kept todo") {
      _ in true
    }
    expectNoDifference(first.values.map(\.id), ["todo-keep"])
    let heldAfterReopening = await runtime.store.entityIDsWithFacts(among: Self.todoIDs)
    expectNoDifference(heldAfterReopening, Self.todoIDs)
    await reopened.cancel()
    _ = try? await runtime.closeConnection()
  }

  /// A relaunch reads the entities its loaded results own from their ownership rows in one statement (#1149).
  ///
  /// It read each loaded result whole, every ownership row decoded into a fact, and ran the query's nested limits over
  /// those facts again, to find the same entities: a save stores ownership only of the facts the nested limits keep.
  /// Then it bound every one of them as a parameter of the facts' read. On the #1075 phone-sized store the launch
  /// allocated 370 MB to load 54,720 facts (E07, 2026-10-25).
  @Test
  func aRelaunchFindsTheEntitiesItLoadsInOwnershipRowsWithoutReadingAStoredResult() async throws {
    let url = try InstantStoredResultReloadTests.temporaryCacheURL()
    try await Self.showAndCloseTheKeptTodoThenTheList(at: url)

    let silent = LiveReactorParitySession(messages: [liveReactorInitOK(attrs: liveReactorTodoServerAttrs)])
    let runtime = try await InstantRuntime.bootstrap(configuration: Self.configuration(url, transport: silent.transport))
    let heldAtLaunch = await runtime.store.entityIDsWithFacts(among: Self.todoIDs)
    expectNoDifference(heldAtLaunch, Self.todoIDs)
    let metrics = await runtime.persistence.cacheResidencyMetricsForTesting()
    #expect(metrics.storedLiveQueryResultReadCount == 0, "stored results the launch read whole")
    _ = try? await runtime.closeConnection()
  }

  static let todoIDs: Set<String> = ["todo-keep", "todo-1", "todo-2"]

  /// A session that showed the kept todo, then the whole list, and closed both: two stored results, the list's newer.
  static func showAndCloseTheKeptTodoThenTheList(at url: URL) async throws {
    let session = LiveReactorParitySession(messages: [liveReactorInitOK(attrs: liveReactorTodoServerAttrs)])
    let runtime = try await InstantRuntime.bootstrap(configuration: Self.configuration(url, transport: session.transport))
    let kept = await runtime.observeQueryLease(InstantStoredResultReloadTests.keepAliveTodosQuery)
    _ = try await runtime.connect()
    await session.enqueue(
      liveReactorAddQueryOK(
        query: try await InstantStoredResultReloadTests.registeredQuery(number: 1, in: session),
        processedTransactionID: "tx-kept",
        result: InstantStoredResultReloadTests.todoResult([("todo-keep", "keep", 10)])
      )
    )
    _ = try await InstantStoredResultReloadTests.emission(of: kept.stream, operation: "show the kept todo") {
      $0.values.map(\.id) == ["todo-keep"]
    }
    // The list's result is saved after the kept todo's, so it is the newer of the two.
    try await Task.sleep(for: .milliseconds(20))
    let list = await runtime.observeQueryLease(TodoExample.query)
    await session.enqueue(
      liveReactorAddQueryOK(
        query: try await InstantStoredResultReloadTests.registeredQuery(number: 2, in: session),
        processedTransactionID: "tx-list",
        result: InstantStoredResultReloadTests.todoResult([("todo-1", "one", 1), ("todo-2", "two", 2)])
      )
    )
    _ = try await InstantStoredResultReloadTests.emission(of: list.stream, operation: "show the server's list") {
      Set(["todo-1", "todo-2"]).isSubset(of: $0.values.map(\.id))
    }
    await kept.cancel()
    await list.cancel()
    _ = try await runtime.closeConnection()
  }

  static func configuration(_ url: URL, transport: InstantLiveTransportClient) -> InstantRuntimeConfiguration {
    var configuration = InstantRuntimeConfiguration(
      appID: "launch-residency",
      persistenceURL: url,
      initialAttributes: TodoExample.attributes,
      liveTransport: transport
    )
    configuration.liveReconnectSleep = { _ in }
    return configuration
  }
}
