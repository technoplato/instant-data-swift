import CustomDump
import Dependencies
import Foundation
import InstantSwiftData
import Testing

/// Library batch `transact` / `delete(ids:)` / `InstantMutationBatch` send API.
///
/// Instant JS: `db.transact(goals.map((g) => db.tx.goals[g.id].delete()))`
/// and optional chunking for large N.
@Suite(.serialized)
struct InstantMutationBatchAPITests {
  @Test
  func deleteIdsSugarProducesOneMutationPerId() {
    let a = InstantID<BatchTodo>(rawValue: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")
    let b = InstantID<BatchTodo>(rawValue: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")
    let mutations = BatchTodo.delete(ids: [a, b])
    expectNoDifference(mutations.count, 2)
  }

  @Test
  func deleteEntitiesSugarUsesEntityIds() {
    let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
    let entities = [
      BatchTodo(
        id: InstantID(rawValue: "cccccccc-cccc-4ccc-8ccc-cccccccccccc"),
        text: "one",
        isCompleted: false,
        createdAt: createdAt
      ),
      BatchTodo(
        id: InstantID(rawValue: "dddddddd-dddd-4ddd-8ddd-dddddddddddd"),
        text: "two",
        isCompleted: false,
        createdAt: createdAt
      ),
    ]
    let mutations = BatchTodo.delete(entities)
    expectNoDifference(mutations.count, 2)
  }

  @Test
  func arrayTransactWithoutBatchSizeIsOneAtomicOutboxMutation() async throws {
    let createdAt = Date(timeIntervalSince1970: 1_700_000_100)
    let ids = (0..<3).map { index in
      InstantID<BatchTodo>(
        rawValue: "00000000-0000-4000-8000-00000000000\(index)"
      )
    }

    try await withDependencies {
      try await $0.bootstrapInstantSwiftData(
        appID: "batch-api-atomic-\(UUID().uuidString)",
        context: .test,
        initialAttributes: BatchTodo.instantAttributes
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var db

      try await db.transact(id: "tx-seed-three") {
        for id in ids {
          BatchTodo.create(
            id: id,
            BatchTodo.text.set("todo-\(id.rawValue.suffix(1))"),
            BatchTodo.isCompleted.set(false),
            BatchTodo.createdAt.set(createdAt)
          )
        }
      }
      var seeded = try await db.query(BatchTodo.query)
      expectNoDifference(seeded.count, 3)

      // Instant-shaped array delete — one transaction when batchSize is nil.
      let results = try await db.transact(
        BatchTodo.delete(ids: ids),
        id: "tx-delete-all-atomic"
      )
      expectNoDifference(results.count, 1)
      expectNoDifference(results[0].transactionID, "tx-delete-all-atomic")

      let remaining = try await db.query(BatchTodo.query)
      expectNoDifference(remaining, [])

      let pending = await db.pendingMutations()
      // seed + one bulk delete
      #expect(pending.map(\.id).contains("tx-delete-all-atomic"))
      let deleteMutation = try #require(pending.first { $0.id == "tx-delete-all-atomic" })
      #expect(deleteMutation.transaction.operations.count >= 3)
    }
  }

  @Test
  func arrayTransactWithBatchSizeSplitsIntoMultipleOutboxMutations() async throws {
    let createdAt = Date(timeIntervalSince1970: 1_700_000_200)
    let ids = (0..<5).map { index in
      InstantID<BatchTodo>(
        rawValue: "11111111-1111-4111-8111-11111111111\(index)"
      )
    }

    try await withDependencies {
      try await $0.bootstrapInstantSwiftData(
        appID: "batch-api-chunked-\(UUID().uuidString)",
        context: .test,
        initialAttributes: BatchTodo.instantAttributes
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var db

      try await db.transact(id: "tx-seed-five") {
        for id in ids {
          BatchTodo.create(
            id: id,
            BatchTodo.text.set("t"),
            BatchTodo.isCompleted.set(false),
            BatchTodo.createdAt.set(createdAt)
          )
        }
      }

      let results = try await db.transact(
        BatchTodo.delete(ids: ids),
        batchSize: 2,
        idPrefix: "tx-delete-chunk"
      )
      // 5 deletes → batches of 2 → 3 transactions
      expectNoDifference(results.count, 3)
      expectNoDifference(
        results.map(\.transactionID),
        ["tx-delete-chunk-0", "tx-delete-chunk-1", "tx-delete-chunk-2"]
      )

      let remaining = try await db.query(BatchTodo.query)
      expectNoDifference(remaining, [])

      let pending = await db.pendingMutations()
      let chunkIDs = pending.map(\.id).filter { $0.hasPrefix("tx-delete-chunk") }
      expectNoDifference(Set(chunkIDs).count, 3)
    }
  }

  @Test
  func mutationBatchSendFiresOptimisticAndDoesNotRequireAppMessageType() async throws {
    let createdAt = Date(timeIntervalSince1970: 1_700_000_300)
    let ids = [
      InstantID<BatchTodo>(rawValue: "22222222-2222-4222-8222-222222222220"),
      InstantID<BatchTodo>(rawValue: "22222222-2222-4222-8222-222222222221"),
    ]

    try await withDependencies {
      try await $0.bootstrapInstantSwiftData(
        appID: "batch-api-send-\(UUID().uuidString)",
        context: .test,
        initialAttributes: BatchTodo.instantAttributes
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var db

      try await db.transact(id: "tx-seed-send") {
        for id in ids {
          BatchTodo.create(
            id: id,
            BatchTodo.text.set("x"),
            BatchTodo.isCompleted.set(false),
            BatchTodo.createdAt.set(createdAt)
          )
        }
      }

      let probe = BatchSendProbe()
      let task = db.send(
        InstantMutationBatch(BatchTodo.delete(ids: ids)),
        onOptimisticCommit: { change in
          probe.optimisticCount = change.mutationCount
        },
        onServerAccepted: { _ in
          probe.accepted = true
        },
        onFailure: { error in
          probe.failure = error.message
        }
      )

      // Local test runtime: optimistic commit should run; server acceptance may not.
      try await Task.sleep(for: .milliseconds(50))
      expectNoDifference(probe.optimisticCount, 2)
      let remaining = try await db.query(BatchTodo.query)
      expectNoDifference(remaining, [])
      _ = task
    }
  }

  @Test
  func sendMutationsConvenienceMatchesMutationBatch() async throws {
    let createdAt = Date(timeIntervalSince1970: 1_700_000_400)
    let id = InstantID<BatchTodo>(rawValue: "33333333-3333-4333-8333-333333333333")

    try await withDependencies {
      try await $0.bootstrapInstantSwiftData(
        appID: "batch-api-send-mutations-\(UUID().uuidString)",
        context: .test,
        initialAttributes: BatchTodo.instantAttributes
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var db

      try await db.transact(id: "tx-seed-one") {
        BatchTodo.create(
          id: id,
          BatchTodo.text.set("only"),
          BatchTodo.isCompleted.set(false),
          BatchTodo.createdAt.set(createdAt)
        )
      }

      let probe = BatchSendProbe()
      _ = db.send(
        mutations: BatchTodo.delete(ids: [id]),
        onOptimisticCommit: { change in
          probe.optimisticCount = change.mutationCount
        },
        onFailure: { _ in probe.failure = "fail" }
      )
      try await Task.sleep(for: .milliseconds(50))
      expectNoDifference(probe.optimisticCount, 1)
      let remaining = try await db.query(BatchTodo.query)
      expectNoDifference(remaining, [])
    }
  }
}

// MARK: - Fixtures

@InstantEntity("batch_api_todos")
private struct BatchTodo: Hashable, Codable, InstantEntityModel {
  var id: InstantID<BatchTodo>
  var text: String
  var isCompleted: Bool
  var createdAt: Date

  init(
    id: InstantID<BatchTodo>,
    text: String,
    isCompleted: Bool,
    createdAt: Date
  ) {
    self.id = id
    self.text = text
    self.isCompleted = isCompleted
    self.createdAt = createdAt
  }

  init(snapshot: InstantEntitySnapshot) throws {
    guard case let .string(text) = snapshot.values["text"]?.first,
      case let .bool(isCompleted) = snapshot.values["isCompleted"]?.first,
      case let .date(createdAt) = snapshot.values["createdAt"]?.first
    else {
      throw InstantError(
        code: .decodeFailed,
        operation: "decode BatchTodo",
        namespace: Self.instantNamespace,
        localID: snapshot.id,
        message: "Expected text, isCompleted, createdAt.",
        recovery: "Align BatchTodo with schema."
      )
    }
    self.id = InstantID(rawValue: snapshot.id)
    self.text = text
    self.isCompleted = isCompleted
    self.createdAt = createdAt
  }
}

/// MainActor callbacks mutate this from `send`; test body reads after a short wait.
private final class BatchSendProbe: @unchecked Sendable {
  var optimisticCount: Int?
  var accepted = false
  var failure: String?
}
