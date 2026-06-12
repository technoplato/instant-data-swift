import CustomDump
import Dependencies
import Foundation
import InstantSwiftData
import Testing

@Suite(.serialized)
struct TypedAPITests {
  @Test
  func queryBuilderProducesInstantPlan() {
    let query = TypedTodo.query
      .where(TypedTodo.isCompleted == false)
      .order(TypedTodo.createdAt, .descending)
      .offset(5)
      .limit(10)

    expectNoDifference(query.plan.namespace, "todos")
    expectNoDifference(query.plan.filters, [.equals(field: "isCompleted", value: .bool(false))])
    expectNoDifference(query.plan.order, InstantQueryOrder("createdAt", .descending))
    expectNoDifference(query.plan.offset, 5)
    expectNoDifference(query.plan.limit, 10)

    let initializedWithLimit = InstantEntityQuery<TypedTodo>(offset: 1, limit: 2)
    expectNoDifference(initializedWithLimit.plan.offset, 1)
    expectNoDifference(initializedWithLimit.plan.limit, 2)

    let comparisonQuery = TypedTodo.query
      .where(TypedTodo.createdAt >= Date(timeIntervalSince1970: 1_700_000_000))
      .where(TypedTodo.text != "Archived")
      .where(TypedTodo.text.isIn(["Open", "Queued"]))
      .where(TypedTodo.text.isNotNull)
      .where(
        .any(
          TypedTodo.text.iLike("%instant%"),
          .all(
            TypedTodo.text.like("README%"),
            TypedTodo.isCompleted == false
          )
        )
      )

    expectNoDifference(
      comparisonQuery.plan.filters,
      [
        .greaterThanOrEqual(
          field: "createdAt",
          value: .date(Date(timeIntervalSince1970: 1_700_000_000))
        ),
        .notEquals(field: "text", value: .string("Archived")),
        .in(field: "text", values: [.string("Open"), .string("Queued")]),
        .isNotNull(field: "text"),
        .or([
          .iLike(field: "text", pattern: "%instant%"),
          .and([
            .like(field: "text", pattern: "README%"),
            .equals(field: "isCompleted", value: .bool(false)),
          ]),
        ]),
      ]
    )

    let delimiterHeavyQuery = TypedTodo.query
      .where(TypedTodo.text.isIn(["a", "b"]))
    let singleValueQuery = TypedTodo.query
      .where(TypedTodo.text.isIn(["a,string:b"]))
    #expect(delimiterHeavyQuery.plan.id != singleValueQuery.plan.id)

    let nonFiniteQuery = InstantEntityQuery<TypedTodo>(
      filters: [.equals(field: "score", value: .number(.infinity))]
    )
    #expect(nonFiniteQuery.plan.id.hasPrefix("instant-query:"))
  }

  @Test
  func typedMutationAndQueryRoundTripThroughDependencyClient() async throws {
    let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
    let fixedUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000321")!
    let todoID = InstantID<TypedTodo>(rawValue: "todo-public")

    try await withDependencies {
      $0.date.now = fixedDate
      $0.uuid = .constant(fixedUUID)
      try await $0.bootstrapInstantSwiftData(
        appID: "typed-api-\(UUID().uuidString)",
        context: .test,
        initialAttributes: TypedTodo.instantAttributes
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var db

      try await db.transact {
        TypedTodo.create(
          id: todoID,
          TypedTodo.text.set("Use the typed API"),
          TypedTodo.isCompleted.set(false),
          TypedTodo.createdAt.set(fixedDate)
        )
      }

      let todos = try await db.query(
        TypedTodo.query
          .where(TypedTodo.isCompleted == false)
          .order(TypedTodo.createdAt)
      )
      expectNoDifference(
        todos,
        [
          TypedTodo(
            id: todoID,
            text: "Use the typed API",
            isCompleted: false,
            createdAt: fixedDate
          )
        ]
      )

      let pending = await db.pendingMutations()
      expectNoDifference(pending.map(\.id), [fixedUUID.uuidString.lowercased()])
    }
  }

  @Test
  func fetchAllLoadsTypedDynamicQuery() async throws {
    let baseDate = Date(timeIntervalSince1970: 1_700_000_100)
    let fixedUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000654")!

    try await withDependencies {
      $0.date.now = baseDate
      $0.uuid = .constant(fixedUUID)
      try await $0.bootstrapInstantSwiftData(
        appID: "fetch-all-\(UUID().uuidString)",
        context: .test,
        initialAttributes: TypedTodo.instantAttributes
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var db

      try await db.transact {
        TypedTodo.create(
          id: InstantID(rawValue: "todo-open"),
          TypedTodo.text.set("Open"),
          TypedTodo.isCompleted.set(false),
          TypedTodo.createdAt.set(baseDate)
        )
        TypedTodo.create(
          id: InstantID(rawValue: "todo-done"),
          TypedTodo.text.set("Done"),
          TypedTodo.isCompleted.set(true),
          TypedTodo.createdAt.set(baseDate.addingTimeInterval(1))
        )
      }

      var fetch = FetchAll<TypedTodo>(
        TypedTodo.query
          .where(TypedTodo.isCompleted == false)
          .order(TypedTodo.createdAt)
      )
      try await fetch.load()

      expectNoDifference(fetch.wrappedValue.map(\.text), ["Open"])
      expectNoDifference(fetch.isLoading, false)
      expectNoDifference(fetch.loadError, nil)
    }
  }

  @Test
  func typedTransactionBuilderUsesDependencyClockForMockClient() async throws {
    let fixedDate = Date(timeIntervalSince1970: 1_700_000_200)
    let fixedUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000987")!
    let recorder = TransactionRecorder()
    let mock = InstantSwiftDataClient(
      transact: { transaction in
        await recorder.record(transaction)
        return InstantStoreMutationResult(
          transactionID: transaction.id,
          changedEntityIDs: ["todo-mock"],
          tripleCount: transaction.operations.count,
          emissions: []
        )
      },
      query: { _ in [] },
      observe: { _ in AsyncStream { continuation in continuation.finish() } },
      pendingMutations: { [] },
      localID: { name in "mock-\(name)" }
    )

    try await withDependencies {
      $0.date.now = fixedDate
      $0.uuid = .constant(fixedUUID)
      $0.defaultInstantSwiftData = mock
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var db
      let result = try await db.transact {
        TypedTodo.create(
          id: InstantID(rawValue: "todo-mock"),
          TypedTodo.text.set("Mock transact")
        )
      }

      expectNoDifference(result.transactionID, fixedUUID.uuidString.lowercased())
      expectNoDifference(result.tripleCount, 1)
    }

    let transactions = await recorder.transactions
    let expectedTime = InstantTimestamp(milliseconds: 1_700_000_200_000)
    expectNoDifference(
      transactions,
      [
        InstantStoreTransaction(
          id: fixedUUID.uuidString.lowercased(),
          operations: [
            .insert(
              InstantTriple(
                entityID: "todo-mock",
                attributeID: "todos/text",
                value: .string("Mock transact"),
                txID: fixedUUID.uuidString.lowercased(),
                txTime: expectedTime
              )
            )
          ]
        )
      ]
    )
  }

  @Test
  func fetchAllPropertyWrapperProjectionLoadsTypedQuery() async throws {
    let baseDate = Date(timeIntervalSince1970: 1_700_000_300)
    let fixedUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000abc")!

    try await withDependencies {
      $0.date.now = baseDate
      $0.uuid = .constant(fixedUUID)
      try await $0.bootstrapInstantSwiftData(
        appID: "fetch-wrapper-\(UUID().uuidString)",
        context: .test,
        initialAttributes: TypedTodo.instantAttributes
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var db
      try await db.transact {
        TypedTodo.create(
          id: InstantID(rawValue: "todo-wrapper"),
          TypedTodo.text.set("Wrapped"),
          TypedTodo.isCompleted.set(false),
          TypedTodo.createdAt.set(baseDate)
        )
      }

      var model = TypedTodoFetchModel()
      try await model.load()

      expectNoDifference(model.todos.map(\.text), ["Wrapped"])
      expectNoDifference(model.$todos.loadError, nil)
      expectNoDifference(model.$todos.isLoading, false)
    }
  }
}

private actor TransactionRecorder {
  private(set) var transactions: [InstantStoreTransaction] = []

  func record(_ transaction: InstantStoreTransaction) {
    transactions.append(transaction)
  }
}

private struct TypedTodoFetchModel {
  @FetchAll(TypedTodo.query.where(TypedTodo.isCompleted == false).order(TypedTodo.createdAt))
  var todos: [TypedTodo]

  mutating func load() async throws {
    try await $todos.load()
  }
}

private struct TypedTodo: Hashable, Codable, InstantEntityModel {
  var id: InstantID<TypedTodo>
  var text: String
  var isCompleted: Bool
  var createdAt: Date

  static let instantNamespace = "todos"
  static let text = InstantAttributePath<TypedTodo, String>("text")
  static let isCompleted = InstantAttributePath<TypedTodo, Bool>("isCompleted")
  static let createdAt = InstantAttributePath<TypedTodo, Date>("createdAt")

  static let instantAttributes = [
    InstantAttribute(
      id: "todos/text",
      namespace: instantNamespace,
      name: "text",
      valueType: .string,
      isIndexed: true
    ),
    InstantAttribute(
      id: "todos/isCompleted",
      namespace: instantNamespace,
      name: "isCompleted",
      valueType: .boolean,
      isIndexed: true
    ),
    InstantAttribute(
      id: "todos/createdAt",
      namespace: instantNamespace,
      name: "createdAt",
      valueType: .date,
      isIndexed: true
    ),
  ]

  init(id: InstantID<TypedTodo>, text: String, isCompleted: Bool, createdAt: Date) {
    self.id = id
    self.text = text
    self.isCompleted = isCompleted
    self.createdAt = createdAt
  }

  init(snapshot: InstantEntitySnapshot) throws {
    guard case let .string(text) = snapshot.values["text"]?.first else {
      throw Self.decodeError(snapshot: snapshot, field: "text", expected: "string")
    }
    guard case let .bool(isCompleted) = snapshot.values["isCompleted"]?.first else {
      throw Self.decodeError(snapshot: snapshot, field: "isCompleted", expected: "boolean")
    }
    guard case let .date(createdAt) = snapshot.values["createdAt"]?.first else {
      throw Self.decodeError(snapshot: snapshot, field: "createdAt", expected: "date")
    }

    self.id = InstantID(rawValue: snapshot.id)
    self.text = text
    self.isCompleted = isCompleted
    self.createdAt = createdAt
  }

  private static func decodeError(
    snapshot: InstantEntitySnapshot,
    field: String,
    expected: String
  ) -> InstantError {
    InstantError(
      code: .decodeFailed,
      operation: "decode typed todo",
      namespace: instantNamespace,
      path: field,
      localID: snapshot.id,
      message: "Expected \(expected) for todo field '\(field)'.",
      recovery: "Check the Instant entity schema and server values for the todos namespace."
    )
  }
}
