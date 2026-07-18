import CustomDump
import Dependencies
import Foundation
import InstantSwiftData
import Testing

#if canImport(SwiftUI)
  import SwiftUI

  @Suite
  struct V3RecordingsListFixtureTests {
    private let sourceReferences = [
      "upstream/instant/client/packages/vue/src/tests/InstantVueDatabase.test.ts:76-204",
      "upstream/sqlite-data/Sources/SQLiteData/Documentation.docc/Articles/DynamicQueries.md:46-91",
      "upstream/sqlite-data/Examples/CaseStudies/DynamicQuery.swift:17,82-99",
    ]

    @Test @MainActor
    func recordingsListModifierSyntaxCompilesWithDynamicQueryIdentity() {
      let screen = V3RecordingsListFixture()
      let view: any View = screen
      _ = view

      let mine = v3RecordingsQuery(scope: .mine, searchText: "walk")
      let shared = v3RecordingsQuery(scope: .shared, searchText: "walk")
      let searched = v3RecordingsQuery(scope: .mine, searchText: "meeting")

      #expect(mine.plan.id != shared.plan.id)
      #expect(mine.plan.id != searched.plan.id)
      expectNoDifference(
        mine.plan.filters,
        [
          .equals(field: "isShared", value: .bool(false)),
          .iLike(field: "title", pattern: "%walk%"),
        ]
      )
      expectNoDifference(
        sourceReferences,
        [
          "upstream/instant/client/packages/vue/src/tests/InstantVueDatabase.test.ts:76-204",
          "upstream/sqlite-data/Sources/SQLiteData/Documentation.docc/Articles/DynamicQueries.md:46-91",
          "upstream/sqlite-data/Examples/CaseStudies/DynamicQuery.swift:17,82-99",
        ]
      )
    }

    @Test
    func recordingsListDynamicFetchPreservesCacheAndReplacesStaleObservation() async throws {
      let recorder = V3RecordingsObservationRecorder()
      let client = v3RecordingsObservationClient(recorder)
      let cached = try V3RecordingListRow(
        snapshot: v3RecordingSnapshot(
          id: "recording-cached",
          title: "Cached walk",
          isShared: false
        )
      )
      let fetch = FetchAll<V3RecordingListRow>(wrappedValue: [cached])
      let mineQuery = v3RecordingsQuery(scope: .mine, searchText: "")
      let sharedQuery = v3RecordingsQuery(scope: .shared, searchText: "")

      let mineTask = Task {
        let fetch = fetch
        try await fetch.task(mineQuery, using: client)
      }
      try await waitForV3RecordingsCondition(
        operation: "wait for mine recordings observation"
      ) {
        await recorder.counts().observationCount == 1
      }
      expectNoDifference(fetch.wrappedValue.map(\.title), ["Cached walk"])
      expectNoDifference(fetch.loadError, nil)
      expectNoDifference(fetch.isLoading, true)

      await recorder.yield(
        .mine,
        values: [
          v3RecordingSnapshot(
            id: "recording-live-mine",
            title: "Live walk",
            isShared: false
          )
        ]
      )
      try await waitForV3RecordingsCondition(
        operation: "wait for mine recordings value"
      ) {
        fetch.wrappedValue.map(\.title) == ["Live walk"]
      }
      expectNoDifference(fetch.isLoading, false)

      let sharedTask = Task {
        let fetch = fetch
        try await fetch.task(sharedQuery, using: client)
      }
      try await waitForV3RecordingsCondition(
        operation: "wait for replacement recordings observation"
      ) {
        await recorder.counts().observationCount == 2
      }
      try await waitForV3RecordingsCondition(
        operation: "wait for stale recordings observation cancellation"
      ) {
        await recorder.counts().terminationCount == 1
      }
      expectNoDifference(fetch.wrappedValue.map(\.title), ["Live walk"])
      expectNoDifference(fetch.loadError, nil)
      expectNoDifference(fetch.isLoading, true)

      do {
        try await mineTask.value
        Issue.record("Expected the replaced recordings query task to cancel.")
      } catch is CancellationError {
      } catch {
        Issue.record("Expected CancellationError, got \(error).")
      }

      await recorder.yield(
        .mine,
        values: [
          v3RecordingSnapshot(
            id: "recording-stale-mine",
            title: "Stale walk",
            isShared: false
          )
        ],
        sequence: 1
      )
      try await Task.sleep(nanoseconds: 10_000_000)
      expectNoDifference(fetch.wrappedValue.map(\.title), ["Live walk"])
      expectNoDifference(fetch.isLoading, true)

      await recorder.yield(
        .shared,
        values: [
          v3RecordingSnapshot(
            id: "recording-live-shared",
            title: "Shared meeting",
            isShared: true
          )
        ]
      )
      try await waitForV3RecordingsCondition(
        operation: "wait for replacement recordings value"
      ) {
        fetch.wrappedValue.map(\.title) == ["Shared meeting"]
      }
      expectNoDifference(fetch.loadError, nil)
      expectNoDifference(fetch.isLoading, false)

      sharedTask.cancel()
      do {
        try await sharedTask.value
        Issue.record("Expected the active recordings query task to cancel.")
      } catch is CancellationError {
      } catch {
        Issue.record("Expected CancellationError, got \(error).")
      }
      try await waitForV3RecordingsCondition(
        operation: "wait for replacement recordings observation cleanup"
      ) {
        await recorder.counts().terminationCount == 2
      }

      let plans = await recorder.queryPlans()
      expectNoDifference(
        plans.map(\.filters),
        [
          [.equals(field: "isShared", value: .bool(false))],
          [.equals(field: "isShared", value: .bool(true))],
        ]
      )
    }

    @Test @MainActor
    func renameMessageFiresOptimisticAndAcceptedCallbacksOnce() async throws {
      let (client, runtime) = try await v3RecordingsMessageRuntime("accepted")
      let recorder = V3RenameCallbackRecorder()
      let task = client.send(
        RenameRecording(
          id: InstantID(rawValue: "recording-message-accepted"),
          title: "Edited walk title"
        ),
        onOptimisticCommit: { (change: borrowing RecordingRenamedChange) in
          recorder.optimistic.append(change.summary())
        },
        onServerAccepted: { (change: borrowing RecordingRenamedChange) in
          recorder.accepted.append(change.summary())
        },
        onFailure: { error in
          recorder.failures.append(error)
        }
      )

      let mutationID = try await waitForV3PendingMutation(runtime)
      let optimisticRows = try await client.query(V3RecordingListRow.query)
      expectNoDifference(optimisticRows.map(\.title), ["Edited walk title"])
      expectNoDifference(recorder.optimistic.map(\.newTitle), ["Edited walk title"])
      expectNoDifference(recorder.accepted, [])
      expectNoDifference(recorder.failures, [])

      _ = try await runtime.applyServerTransaction(
        InstantStoreTransaction(id: "passive-refresh", operations: []),
        processedTransactionID: "passive-refresh"
      )
      try await Task.sleep(nanoseconds: 10_000_000)
      expectNoDifference(recorder.accepted, [])

      _ = try await runtime.confirmMutation(id: mutationID)
      await task.value
      expectNoDifference(recorder.optimistic.count, 1)
      expectNoDifference(recorder.accepted.map(\.newTitle), ["Edited walk title"])
      expectNoDifference(recorder.failures, [])

      _ = try await runtime.applyServerTransaction(
        InstantStoreTransaction(id: "later-passive-refresh", operations: []),
        processedTransactionID: "later-passive-refresh"
      )
      try await Task.sleep(nanoseconds: 10_000_000)
      expectNoDifference(recorder.optimistic.count, 1)
      expectNoDifference(recorder.accepted.count, 1)
    }

    @Test @MainActor
    func renameMessageFailureDoesNotReplayCallbacksAfterRetry() async throws {
      let (client, runtime) = try await v3RecordingsMessageRuntime("failed")
      let recorder = V3RenameCallbackRecorder()
      let task = client.send(
        RenameRecording(
          id: InstantID(rawValue: "recording-message-failed"),
          title: "Rejected title"
        ),
        onOptimisticCommit: { change in
          recorder.optimistic.append(change.summary())
        },
        onServerAccepted: { change in
          recorder.accepted.append(change.summary())
        },
        onFailure: { error in
          recorder.failures.append(error)
        }
      )

      let mutationID = try await waitForV3PendingMutation(runtime)
      _ = try await runtime.failMutation(id: mutationID, message: "title update denied")
      await task.value

      expectNoDifference(recorder.optimistic.count, 1)
      expectNoDifference(recorder.accepted, [])
      expectNoDifference(recorder.failures.map(\.message), ["title update denied"])
      expectNoDifference(
        recorder.failures.map(\.recoveryMessage),
        ["Inspect the deployed schema and permissions, then retry the action."]
      )

      _ = try await runtime.retryMutation(id: mutationID)
      _ = try await runtime.confirmMutation(id: mutationID)
      try await Task.sleep(nanoseconds: 10_000_000)
      expectNoDifference(recorder.optimistic.count, 1)
      expectNoDifference(recorder.accepted, [])
      expectNoDifference(recorder.failures.count, 1)
    }
  }

  @MainActor
  private struct V3RecordingsListFixture: View {
    @FetchAll
    private var rows: [V3RecordingListRow]

    @State
    private var scope: V3RecordingListScope = .mine

    @State
    private var searchText = ""

    @Dependency(\.defaultInstantSwiftData)
    private var db

    var body: some View {
      List(rows) { row in
        Button(row.title) {
          renameButtonTapped(row)
        }
      }
      .searchable(text: $searchText)
      .instantFetch(
        $rows,
        rowsQuery
      )
    }

    private var rowsQuery: InstantQuery<V3RecordingListRow> {
      v3RecordingsQuery(scope: scope, searchText: searchText)
    }

    private func renameButtonTapped(_ row: V3RecordingListRow) {
      db.send(
        RenameRecording(id: row.id, title: "Edited walk title"),
        onOptimisticCommit: { (change: borrowing RecordingRenamedChange) in
          _ = change.summary()
        },
        onServerAccepted: { _ in },
        onFailure: { error in
          _ = error.recoveryMessage
        }
      )
    }
  }

  private enum V3RecordingListScope: String, Hashable, Sendable {
    case mine
    case shared
  }

  private func v3RecordingsQuery(
    scope: V3RecordingListScope,
    searchText: String
  ) -> InstantQuery<V3RecordingListRow> {
    let scoped = V3RecordingListRow.query
      .where(V3RecordingListRow.isShared == (scope == .shared))
      .order(V3RecordingListRow.title)
    guard !searchText.isEmpty else { return scoped }
    return scoped.where(V3RecordingListRow.title.iLike("%\(searchText)%"))
  }

  private struct V3RecordingListRow: Hashable, Codable, InstantEntityModel {
    var id: InstantID<V3RecordingListRow>
    var title: String
    var isShared: Bool

    static let instantNamespace = "v3_recording_list_rows"
    static let title = InstantAttributePath<V3RecordingListRow, String>("title")
    static let isShared = InstantAttributePath<V3RecordingListRow, Bool>("isShared")
    static let instantAttributes = [
      InstantAttribute(
        id: "v3_recording_list_rows/title",
        namespace: instantNamespace,
        name: "title",
        valueType: .string,
        isIndexed: true
      ),
      InstantAttribute(
        id: "v3_recording_list_rows/isShared",
        namespace: instantNamespace,
        name: "isShared",
        valueType: .boolean,
        isIndexed: true
      ),
    ]

    init(id: InstantID<Self>, title: String, isShared: Bool) {
      self.id = id
      self.title = title
      self.isShared = isShared
    }

    init(snapshot: InstantEntitySnapshot) throws {
      guard case let .string(title) = snapshot.values["title"]?.first,
        case let .bool(isShared) = snapshot.values["isShared"]?.first
      else {
        throw InstantError(
          code: .decodeFailed,
          operation: "decode V3 recording list row fixture",
          namespace: Self.instantNamespace,
          localID: snapshot.id,
          message: "Expected title and isShared values.",
          recovery: "Keep the compile fixture aligned with its declared attributes."
        )
      }
      self.id = InstantID(rawValue: snapshot.id)
      self.title = title
      self.isShared = isShared
    }
  }

  private struct RenameRecording: InstantMessage {
    var id: InstantID<V3RecordingListRow>
    var title: String

    func prepare(using client: InstantSwiftDataClient) async throws
      -> InstantPreparedMessage<RecordingRenamedChange>
    {
      guard let recording = try await client.query(V3RecordingListRow.query)
        .first(where: { $0.id == id })
      else {
        throw InstantError(
          code: .validationFailed,
          operation: "prepare recording rename",
          localID: id.rawValue,
          message: "The recording does not exist in the local snapshot.",
          recovery: "Reload the recordings query before retrying the rename."
        )
      }
      let change = RecordingRenamedChange(
        id: id,
        oldTitle: recording.title,
        newTitle: title
      )
      return InstantPreparedMessage(change: change) {
        V3RecordingListRow.update(id: id, V3RecordingListRow.title.set(title))
      }
    }
  }

  private struct RecordingRenamedChange: Sendable {
    var id: InstantID<V3RecordingListRow>
    var oldTitle: String
    var newTitle: String

    borrowing func summary() -> RecordingRenameSummary {
      RecordingRenameSummary(
        id: id,
        oldTitle: oldTitle,
        newTitle: newTitle
      )
    }
  }

  private struct RecordingRenameSummary: Equatable, Sendable {
    var id: InstantID<V3RecordingListRow>
    var oldTitle: String
    var newTitle: String
  }

  @MainActor
  private final class V3RenameCallbackRecorder {
    var optimistic: [RecordingRenameSummary] = []
    var accepted: [RecordingRenameSummary] = []
    var failures: [InstantError] = []
  }

  private actor V3RecordingsObservationRecorder {
    enum Request: Hashable, Sendable {
      case mine
      case shared
    }

    private var continuations: [Request: AsyncStream<InstantQueryEmission>.Continuation] = [:]
    private var observationCount = 0
    private var plans: [InstantQueryPlan] = []
    private var queryIDs: [Request: String] = [:]
    private var terminationCount = 0

    func observe(plan: InstantQueryPlan) -> AsyncStream<InstantQueryEmission> {
      observationCount += 1
      plans.append(plan)
      let request = Self.request(for: plan)
      queryIDs[request] = plan.id

      let stream = AsyncStream<InstantQueryEmission>.makeStream(
        bufferingPolicy: .bufferingNewest(1)
      )
      continuations[request] = stream.continuation
      stream.continuation.onTermination = { @Sendable _ in
        Task {
          await self.recordTermination()
        }
      }
      return stream.stream
    }

    func yield(
      _ request: Request,
      values: [InstantEntitySnapshot],
      sequence: Int64 = 0
    ) {
      guard
        let continuation = continuations[request],
        let queryID = queryIDs[request]
      else { return }

      continuation.yield(
        InstantQueryEmission(queryID: queryID, sequence: sequence, values: values)
      )
    }

    func counts() -> (observationCount: Int, terminationCount: Int) {
      (observationCount, terminationCount)
    }

    func queryPlans() -> [InstantQueryPlan] {
      plans
    }

    private func recordTermination() {
      terminationCount += 1
    }

    private static func request(for plan: InstantQueryPlan) -> Request {
      plan.filters.contains(.equals(field: "isShared", value: .bool(true)))
        ? .shared
        : .mine
    }
  }

  private func v3RecordingsObservationClient(
    _ recorder: V3RecordingsObservationRecorder
  ) -> InstantSwiftDataClient {
    InstantSwiftDataClient(
      transact: { transaction in
        InstantStoreMutationResult(
          transactionID: transaction.id,
          changedEntityIDs: [],
          tripleCount: transaction.operations.count,
          emissions: []
        )
      },
      query: { _ in [] },
      observe: { plan in
        await recorder.observe(plan: plan)
      },
      pendingMutations: { [] },
      localID: { name in "v3-recordings-\(name)" }
    )
  }

  private func v3RecordingsMessageRuntime(
    _ suffix: String
  ) async throws -> (InstantSwiftDataClient, InstantRuntime) {
    let cacheURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("v3-recordings-message-\(suffix)-\(UUID().uuidString).sqlite")
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "v3-recordings-message-\(suffix)",
        persistenceURL: cacheURL,
        initialAttributes: V3RecordingListRow.instantAttributes
      )
    )
    let client = InstantSwiftDataClient(runtime: runtime)
    try await client.transact(id: "seed-\(suffix)") {
      V3RecordingListRow.create(
        id: InstantID(rawValue: "recording-message-\(suffix)"),
        V3RecordingListRow.title.set("Morning walk"),
        V3RecordingListRow.isShared.set(false)
      )
    }
    _ = try await runtime.confirmMutation(id: "seed-\(suffix)")
    return (client, runtime)
  }

  private func waitForV3PendingMutation(_ runtime: InstantRuntime) async throws -> String {
    for _ in 0..<100 {
      if let id = await runtime.pendingMutations().first?.id {
        return id
      }
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    throw InstantError(
      code: .validationFailed,
      operation: "wait for V3 rename mutation",
      message: "Timed out waiting for the optimistic rename mutation.",
      recovery: "Inspect InstantMessage preparation and the durable outbox."
    )
  }

  private func waitForV3RecordingsCondition(
    operation: String,
    until condition: @escaping @Sendable () async -> Bool
  ) async throws {
    for _ in 0..<100 {
      if await condition() {
        return
      }
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    throw InstantError(
      code: .validationFailed,
      operation: operation,
      message: "Timed out waiting for the V3 recordings-list fixture condition.",
      recovery: "Inspect the controlled query client and FetchAll replacement lifecycle."
    )
  }

  private func v3RecordingSnapshot(
    id: String,
    title: String,
    isShared: Bool
  ) -> InstantEntitySnapshot {
    InstantEntitySnapshot(
      id: id,
      namespace: V3RecordingListRow.instantNamespace,
      values: [
        "title": .one(.string(title)),
        "isShared": .one(.bool(isShared)),
      ]
    )
  }
#endif
