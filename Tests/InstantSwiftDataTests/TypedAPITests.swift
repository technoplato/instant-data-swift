import CustomDump
import Dependencies
import Foundation
import InstantSwiftData
import Testing

@Suite(.serialized)
struct TypedAPITests {
  @Test
  func queryBuilderProducesInstantPlan() {
    let cursorDate = Date(timeIntervalSince1970: 1_700_000_000)
    let cursor = InstantQueryCursor(
      entityID: "todo-cursor",
      sortValue: .date(cursorDate),
      inclusive: true
    )
    let query = TypedTodo.query
      .where(TypedTodo.isCompleted == false)
      .order(TypedTodo.createdAt, .descending)
      .offset(5)
      .limit(10)
      .first(3)
      .after(cursor)

    expectNoDifference(query.plan.namespace, "todos")
    expectNoDifference(query.plan.filters, [.equals(field: "isCompleted", value: .bool(false))])
    expectNoDifference(query.plan.order, InstantQueryOrder("createdAt", .descending))
    expectNoDifference(query.plan.offset, 5)
    expectNoDifference(query.plan.limit, 10)
    expectNoDifference(query.plan.first, 3)
    expectNoDifference(query.plan.after, cursor)
    expectNoDifference(query.plan.last, nil)
    expectNoDifference(query.plan.before, nil)
    expectNoDifference(query.plan.selectedFields, nil)

    let initializedWithLimit = InstantEntityQuery<TypedTodo>(offset: 1, limit: 2, first: 1, after: cursor)
    expectNoDifference(initializedWithLimit.plan.offset, 1)
    expectNoDifference(initializedWithLimit.plan.limit, 2)
    expectNoDifference(initializedWithLimit.plan.first, 1)
    expectNoDifference(initializedWithLimit.plan.after, cursor)

    let previousPageQuery = query
      .last(2)
      .before(InstantQueryCursor(entityID: "todo-before"))
    expectNoDifference(previousPageQuery.plan.first, nil)
    expectNoDifference(previousPageQuery.plan.last, 2)
    expectNoDifference(previousPageQuery.plan.before, InstantQueryCursor(entityID: "todo-before"))
    #expect(previousPageQuery.plan.id != query.plan.id)

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

    let defaultServerCreatedAtQuery = TypedTodo.query.order(.serverCreatedAt)
    expectNoDifference(defaultServerCreatedAtQuery.plan.order, .serverCreatedAt)
    #expect(defaultServerCreatedAtQuery.plan.id != TypedTodo.query.plan.id)
    #expect(defaultServerCreatedAtQuery.plan.cacheKey != TypedTodo.query.plan.cacheKey)

    let createdAtDescendingQuery = TypedTodo.query.order(TypedTodo.createdAt, .descending)
    let serverCreatedAtQuery = TypedTodo.query.order(.serverCreatedAt, .descending)
    expectNoDifference(serverCreatedAtQuery.plan.order, .serverCreatedAtDescending)
    #expect(serverCreatedAtQuery.plan.id != createdAtDescendingQuery.plan.id)
    #expect(serverCreatedAtQuery.plan.cacheKey != createdAtDescendingQuery.plan.cacheKey)
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
  func typedQueryOrdersByServerCreatedAt() async throws {
    let cacheURL = try typedTestCacheURL("typed-server-created-at")
    let fixedDate = Date(timeIntervalSince1970: 1_700_000_500)
    let fixedUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000500")!

    try await withDependencies {
      $0.date.now = fixedDate
      $0.uuid = .constant(fixedUUID)
      try await $0.bootstrapInstantSwiftData(
        appID: "typed-server-created-at",
        persistenceURL: cacheURL,
        context: .test,
        initialAttributes: TypedTodo.instantAttributes
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var db

      try await db.transact(
        id: "tx-typed-server-created-at-first",
        createdAt: InstantTimestamp(milliseconds: 1_700_000_500_010)
      ) {
        TypedTodo.create(
          id: InstantID(rawValue: "todo-a"),
          TypedTodo.text.set("First"),
          TypedTodo.isCompleted.set(false),
          TypedTodo.createdAt.set(fixedDate)
        )
      }
      try await db.transact(
        id: "tx-typed-server-created-at-second",
        createdAt: InstantTimestamp(milliseconds: 1_700_000_500_020)
      ) {
        TypedTodo.create(
          id: InstantID(rawValue: "todo-b"),
          TypedTodo.text.set("Second"),
          TypedTodo.isCompleted.set(false),
          TypedTodo.createdAt.set(fixedDate.addingTimeInterval(1))
        )
      }

      let todos = try await db.query(TypedTodo.query.order(.serverCreatedAt, .descending))
      expectNoDifference(todos.map(\.text), ["Second", "First"])

      let ascendingTodos = try await db.query(TypedTodo.query.order(.serverCreatedAt))
      expectNoDifference(ascendingTodos.map(\.text), ["First", "Second"])
    }
  }

  @Test
  func bootstrapRejectsServerCreatedAtSchemaAttribute() async throws {
    let fixedUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000501")!

    do {
      try await withDependencies {
        $0.uuid = .constant(fixedUUID)
        try await $0.bootstrapInstantSwiftData(
          appID: "typed-reserved-server-created-at",
          context: .test,
          initialAttributes: TypedReservedServerCreatedAtEntity.instantAttributes
        )
      } operation: {}
      #expect(Bool(false), "Expected bootstrap to reject a serverCreatedAt schema field.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed)
      expectNoDifference(error.operation, "bootstrap attributes")
      expectNoDifference(error.namespace, "reservedServerCreatedAtEntities")
      expectNoDifference(error.path, "serverCreatedAt")
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }
  }

  @Test
  func typedReservedServerCreatedAtAttributeRejectsWritesBeforeMockClientReceivesTransaction()
    async throws
  {
    let recorder = TransactionRecorder()
    let mock = InstantSwiftDataClient(
      transact: { transaction in
        await recorder.record(transaction)
        return InstantStoreMutationResult(
          transactionID: transaction.id,
          changedEntityIDs: [],
          tripleCount: transaction.operations.count,
          emissions: []
        )
      },
      query: { _ in [] },
      observe: { _ in AsyncStream { continuation in continuation.finish() } },
      pendingMutations: { [] },
      localID: { name in "mock-\(name)" }
    )

    await withDependencies {
      $0.date.now = Date(timeIntervalSince1970: 1_700_000_501)
      $0.uuid = .constant(UUID(uuidString: "00000000-0000-0000-0000-000000000502")!)
      $0.defaultInstantSwiftData = mock
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var db

      do {
        try await db.transact(id: "tx-mock-reserved-server-created-at") {
          TypedReservedServerCreatedAtEntity.update(
            id: InstantID(rawValue: "reserved-1"),
            TypedReservedServerCreatedAtEntity.serverCreatedAt.set(
              Date(timeIntervalSince1970: 1_700_000_501)
            )
          )
        }
        #expect(Bool(false), "Expected serverCreatedAt assignment validation to run first.")
      } catch let error as InstantError {
        expectNoDifference(error.code, .validationFailed)
        expectNoDifference(error.operation, "write entity attribute")
        expectNoDifference(error.namespace, "reservedServerCreatedAtEntities")
        expectNoDifference(error.path, "serverCreatedAt")
      } catch {
        #expect(Bool(false), "Unexpected error: \(error)")
      }
    }

    let transactions = await recorder.transactions
    expectNoDifference(transactions, [])
  }

  @Test
  func typedCreateIsStrictAndTypedUpdateUpserts() async throws {
    let createdAt = Date(timeIntervalSince1970: 1_700_000_025)
    let todoID = InstantID<TypedTodo>(rawValue: "todo-strict-create")
    let upsertedID = InstantID<TypedTodo>(rawValue: "todo-upserted")
    let idOnlyID = InstantID<TypedTodo>(rawValue: "todo-id-only")

    try await withDependencies {
      $0.date.now = createdAt
      try await $0.bootstrapInstantSwiftData(
        appID: "typed-strict-create-\(UUID().uuidString)",
        context: .test,
        initialAttributes: TypedTodo.instantAttributes
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var db

      try await db.transact(id: "tx-typed-create") {
        TypedTodo.create(
          id: todoID,
          TypedTodo.text.set("Created strictly"),
          TypedTodo.isCompleted.set(false),
          TypedTodo.createdAt.set(createdAt)
        )
      }

      do {
        try await db.transact(id: "tx-typed-duplicate-create") {
          TypedTodo.create(
            id: todoID,
            TypedTodo.text.set("Duplicate")
          )
        }
        #expect(Bool(false), "Expected typed create to reject an existing entity.")
      } catch let error as InstantError {
        expectNoDifference(error.code, .validationFailed)
        expectNoDifference(error.operation, "strict create entity")
        expectNoDifference(error.namespace, "todos")
        expectNoDifference(error.localID, todoID.rawValue)
      } catch {
        #expect(Bool(false), "Unexpected error: \(error)")
      }

      try await db.transact(id: "tx-typed-update-upsert") {
        TypedTodo.update(
          id: upsertedID,
          TypedTodo.text.set("Upserted by update"),
          TypedTodo.isCompleted.set(false),
          TypedTodo.createdAt.set(createdAt.addingTimeInterval(1))
        )
      }

      let todos = try await db.query(TypedTodo.query.order(TypedTodo.createdAt))
      expectNoDifference(
        todos,
        [
          TypedTodo(
            id: todoID,
            text: "Created strictly",
            isCompleted: false,
            createdAt: createdAt
          ),
          TypedTodo(
            id: upsertedID,
            text: "Upserted by update",
            isCompleted: false,
            createdAt: createdAt.addingTimeInterval(1)
          ),
        ]
      )

      try await db.transact(id: "tx-typed-id-only-create") {
        TypedTodo.create(id: idOnlyID)
      }

      let idOnlySnapshots = try await db.query(
        InstantQueryPlan(id: "typed.id-only", namespace: TypedTodo.instantNamespace)
      )
      expectNoDifference(
        idOnlySnapshots.map(\.id),
        [idOnlyID.rawValue, todoID.rawValue, upsertedID.rawValue]
      )
      expectNoDifference(idOnlySnapshots.first?.values["id"]?.first, .string(idOnlyID.rawValue))

      do {
        try await db.transact(id: "tx-typed-id-only-duplicate") {
          TypedTodo.create(id: idOnlyID)
        }
        #expect(Bool(false), "Expected id-only typed create to reject an existing entity.")
      } catch let error as InstantError {
        expectNoDifference(error.code, .validationFailed)
        expectNoDifference(error.operation, "strict create entity")
        expectNoDifference(error.namespace, "todos")
        expectNoDifference(error.localID, idOnlyID.rawValue)
      } catch {
        #expect(Bool(false), "Unexpected error: \(error)")
      }

      let pending = await db.pendingMutations()
      #expect(
        pending.map(\.id)
          == ["tx-typed-create", "tx-typed-id-only-create", "tx-typed-update-upsert"]
      )
      let idOnlyMutation = pending.first { $0.id == "tx-typed-id-only-create" }
      expectNoDifference(
        idOnlyMutation?.transaction.operations,
        [
          .requireEntityMissing(entityID: idOnlyID.rawValue, namespace: "todos"),
          .insert(
            InstantTriple(
              entityID: idOnlyID.rawValue,
              attributeID: "todos/id",
              value: .string(idOnlyID.rawValue),
              txID: "tx-typed-id-only-create",
              txTime: InstantTimestamp(milliseconds: 1_700_000_025_000)
            )
          ),
        ]
      )
    }
  }

  @Test
  func typedMergeAndStrictUpdateRoundTripThroughDependencyClient() async throws {
    let createdAt = Date(timeIntervalSince1970: 1_700_000_050)
    let todoID = InstantID<TypedTodo>(rawValue: "todo-merge")
    let missingID = InstantID<TypedTodo>(rawValue: "todo-missing")

    try await withDependencies {
      try await $0.bootstrapInstantSwiftData(
        appID: "typed-strict-update-\(UUID().uuidString)",
        context: .test,
        initialAttributes: TypedTodo.instantAttributes
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var db

      do {
        try await db.transact(id: "tx-missing-empty-strict-update") {
          TypedTodo.updateExisting(id: missingID)
        }
        #expect(Bool(false), "Expected empty strict update to reject a missing entity.")
      } catch let error as InstantError {
        expectNoDifference(error.code, .validationFailed)
        expectNoDifference(error.operation, "strict update entity")
        expectNoDifference(error.namespace, "todos")
        expectNoDifference(error.localID, missingID.rawValue)
      } catch {
        #expect(Bool(false), "Unexpected error: \(error)")
      }

      do {
        try await db.transact(id: "tx-missing-strict-update") {
          TypedTodo.updateExisting(
            id: missingID,
            TypedTodo.text.set("Should not upsert")
          )
        }
        #expect(Bool(false), "Expected strict update to reject a missing entity.")
      } catch let error as InstantError {
        expectNoDifference(error.code, .validationFailed)
        expectNoDifference(error.operation, "strict update entity")
        expectNoDifference(error.namespace, "todos")
        expectNoDifference(error.localID, missingID.rawValue)
      } catch {
        #expect(Bool(false), "Unexpected error: \(error)")
      }

      let initialPending = await db.pendingMutations()
      expectNoDifference(initialPending, [])

      try await db.transact(id: "tx-merge-todo") {
        TypedTodo.merge(
          id: todoID,
          TypedTodo.text.set("Merged"),
          TypedTodo.isCompleted.set(false),
          TypedTodo.createdAt.set(createdAt)
        )
      }
      try await db.transact(id: "tx-strict-update-todo") {
        TypedTodo.updateExisting(
          id: todoID,
          TypedTodo.text.set("Updated strictly")
        )
      }

      let todos = try await db.query(TypedTodo.query)
      expectNoDifference(
        todos,
        [
          TypedTodo(
            id: todoID,
            text: "Updated strictly",
            isCompleted: false,
            createdAt: createdAt
          )
        ]
      )
      let pending = await db.pendingMutations()
      expectNoDifference(pending.map(\.id), ["tx-merge-todo", "tx-strict-update-todo"])
    }
  }

  @Test
  func typedMergeDeepMergesJSONValues() async throws {
    let profileID = InstantID<TypedProfile>(rawValue: "profile-merge")

    try await withDependencies {
      try await $0.bootstrapInstantSwiftData(
        appID: "typed-json-merge-\(UUID().uuidString)",
        context: .test,
        initialAttributes: TypedProfile.instantAttributes
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var db

      try await db.transact(id: "tx-profile-create") {
        TypedProfile.create(
          id: profileID,
          TypedProfile.metadata.set(
            .object([
              "nested": .object([
                "keep": .bool(true),
                "size": .number(1),
              ]),
              "theme": .string("light"),
            ])
          )
        )
      }
      try await db.transact(id: "tx-profile-merge") {
        TypedProfile.merge(
          id: profileID,
          TypedProfile.metadata.set(
            .object([
              "nested": .object([
                "size": .number(2)
              ]),
              "theme": .string("dark"),
              "timezone": .string("UTC"),
            ])
          )
        )
      }

      let profiles = try await db.query(TypedProfile.query)
      expectNoDifference(
        profiles,
        [
          TypedProfile(
            id: profileID,
            metadata: .object([
              "nested": .object([
                "keep": .bool(true),
                "size": .number(2),
              ]),
              "theme": .string("dark"),
              "timezone": .string("UTC"),
            ])
          )
        ]
      )
    }
  }

  @Test
  func typedLinkAndUnlinkMutationsRoundTripThroughDependencyClient() async throws {
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_100_000)
    let userID = InstantID<TypedUser>(rawValue: "user-1")
    let postID = InstantID<TypedPost>(rawValue: "post-1")

    try await withDependencies {
      try await $0.bootstrapInstantSwiftData(
        appID: "typed-links-\(UUID().uuidString)",
        context: .test,
        initialAttributes: TypedUser.instantAttributes + TypedPost.instantAttributes
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var db

      try await db.transact(id: "tx-link", createdAt: createdAt) {
        TypedUser.create(
          id: userID,
          TypedUser.name.set("Blob")
        )
        TypedPost.create(
          id: postID,
          TypedPost.title.set("Hello links")
        )
        TypedPost.author.link(from: postID, to: userID)
      }

      let linkedPosts = try await db.query(TypedPost.query)
      expectNoDifference(
        linkedPosts,
        [TypedPost(id: postID, title: "Hello links", authorID: userID)]
      )

      try await db.transact(
        id: "tx-unlink",
        createdAt: InstantTimestamp(milliseconds: createdAt.milliseconds + 1)
      ) {
        TypedPost.author.unlink(from: postID, to: userID)
      }

      let unlinkedPosts = try await db.query(TypedPost.query)
      expectNoDifference(
        unlinkedPosts,
        [TypedPost(id: postID, title: "Hello links", authorID: nil)]
      )

      let pending = await db.pendingMutations()
      expectNoDifference(pending.map(\.id), ["tx-link", "tx-unlink"])
    }
  }

  @Test
  func typedLookupMutationsResolveUniqueAttributesAndPreservePendingLookups() async throws {
    let createdAt = Date(timeIntervalSince1970: 1_700_000_300)
    let timestamp = InstantTimestamp(milliseconds: 1_700_000_300_000)
    let userID = InstantID<TypedUser>(rawValue: "lookup-user")
    let postID = InstantID<TypedPost>(rawValue: "lookup-post")
    let userLookup = TypedUser.email.lookup("blob@example.com")
    let renamedUserLookup = TypedUser.email.lookup("blob@instantdb.com")
    let postLookup = TypedPost.slug.lookup("hello-lookup")

    try await withDependencies {
      $0.date.now = createdAt
      try await $0.bootstrapInstantSwiftData(
        appID: "typed-lookup-\(UUID().uuidString)",
        context: .test,
        initialAttributes: TypedUser.instantAttributes + TypedPost.instantAttributes
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var db

      try await db.transact(id: "tx-seed-lookup") {
        TypedUser.create(
          id: userID,
          TypedUser.name.set("Blob"),
          TypedUser.email.set("blob@example.com")
        )
        TypedPost.create(
          id: postID,
          TypedPost.title.set("Hello lookups"),
          TypedPost.slug.set("hello-lookup")
        )
      }

      try await db.transact(id: "tx-lookup-update") {
        TypedUser.update(
          lookup: userLookup,
          TypedUser.name.set("Blob Jr."),
          TypedUser.email.set("blob@instantdb.com")
        )
      }

      let userSnapshots = try await db.query(
        InstantQueryPlan(id: "typed.lookup.users", namespace: TypedUser.instantNamespace)
      )
      expectNoDifference(userSnapshots.map(\.id), [userID.rawValue])
      expectNoDifference(userSnapshots.first?.values["name"]?.first, .string("Blob Jr."))
      expectNoDifference(
        userSnapshots.first?.values["email"]?.first,
        .string("blob@instantdb.com")
      )

      try await db.transact(id: "tx-lookup-link") {
        TypedPost.author.link(from: postLookup, to: renamedUserLookup)
      }

      let linkedPosts = try await db.query(TypedPost.query)
      expectNoDifference(
        linkedPosts,
        [TypedPost(id: postID, title: "Hello lookups", authorID: userID)]
      )

      try await db.transact(id: "tx-lookup-unlink") {
        TypedPost.author.unlink(from: postLookup, to: renamedUserLookup)
      }

      let unlinkedPosts = try await db.query(TypedPost.query)
      expectNoDifference(
        unlinkedPosts,
        [TypedPost(id: postID, title: "Hello lookups", authorID: nil)]
      )

      let pending = await db.pendingMutations()
      let lookupUpdate = pending.first { $0.id == "tx-lookup-update" }
      expectNoDifference(
        lookupUpdate?.transaction.operations,
        [
          .insertByLookup(
            entity: userLookup.lookupRef,
            attributeID: "users/id",
            value: .lookupRef(userLookup.lookupRef),
            txID: "tx-lookup-update",
            txTime: timestamp
          ),
          .insertByLookup(
            entity: userLookup.lookupRef,
            attributeID: "users/name",
            value: .string("Blob Jr."),
            txID: "tx-lookup-update",
            txTime: timestamp
          ),
          .insertByLookup(
            entity: userLookup.lookupRef,
            attributeID: "users/email",
            value: .string("blob@instantdb.com"),
            txID: "tx-lookup-update",
            txTime: timestamp
          ),
        ]
      )

      let lookupLink = pending.first { $0.id == "tx-lookup-link" }
      expectNoDifference(
        lookupLink?.transaction.operations,
        [
          .insertByLookup(
            entity: postLookup.lookupRef,
            attributeID: "posts/id",
            value: .lookupRef(postLookup.lookupRef),
            txID: "tx-lookup-link",
            txTime: timestamp
          ),
          .insertByLookup(
            entity: postLookup.lookupRef,
            attributeID: "posts/author",
            value: .lookupRef(renamedUserLookup.lookupRef),
            txID: "tx-lookup-link",
            txTime: timestamp
          ),
        ]
      )
    }
  }

  @Test
  func typedLookupUpdateCanResolveEntityCreatedEarlierInSameTransaction() async throws {
    let createdAt = Date(timeIntervalSince1970: 1_700_000_325)
    let userID = InstantID<TypedUser>(rawValue: "lookup-same-tx-user")

    try await withDependencies {
      $0.date.now = createdAt
      try await $0.bootstrapInstantSwiftData(
        appID: "typed-lookup-same-tx-\(UUID().uuidString)",
        context: .test,
        initialAttributes: TypedUser.instantAttributes
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var db

      try await db.transact(id: "tx-lookup-same-transaction") {
        TypedUser.create(
          id: userID,
          TypedUser.name.set("Draft"),
          TypedUser.email.set("same-tx@example.com")
        )
        TypedUser.update(
          lookup: TypedUser.email.lookup("same-tx@example.com"),
          TypedUser.name.set("Resolved in order")
        )
      }

      let users = try await db.query(
        InstantQueryPlan(id: "typed.lookup.same-tx", namespace: TypedUser.instantNamespace)
      )
      expectNoDifference(users.map(\.id), [userID.rawValue])
      expectNoDifference(users.first?.values["name"]?.first, .string("Resolved in order"))
    }
  }

  @Test
  func unresolvedLookupUpdateNoOpsLocallyButPersistsPendingMutation() async throws {
    let createdAt = Date(timeIntervalSince1970: 1_700_000_350)

    try await withDependencies {
      $0.date.now = createdAt
      try await $0.bootstrapInstantSwiftData(
        appID: "typed-unresolved-lookup-\(UUID().uuidString)",
        context: .test,
        initialAttributes: TypedUser.instantAttributes
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var db

      try await db.transact(id: "tx-unresolved-lookup-update") {
        TypedUser.update(
          lookup: TypedUser.email.lookup("missing@example.com"),
          TypedUser.name.set("Server may resolve later")
        )
      }

      let users = try await db.query(
        InstantQueryPlan(id: "typed.unresolved.lookup.users", namespace: TypedUser.instantNamespace)
      )
      expectNoDifference(users, [])

      let pending = await db.pendingMutations()
      expectNoDifference(pending.map(\.id), ["tx-unresolved-lookup-update"])
      #expect(
        pending.first?.transaction.operations.contains {
          if case .insertByLookup = $0 { return true }
          return false
        } == true
      )
    }
  }

  @Test
  func strictLookupUpdateRejectsMissingAndAmbiguousLocalMatches() async throws {
    let createdAt = Date(timeIntervalSince1970: 1_700_000_375)
    let duplicateLookup = TypedUser.email.lookup("duplicate@example.com")

    try await withDependencies {
      $0.date.now = createdAt
      try await $0.bootstrapInstantSwiftData(
        appID: "typed-strict-lookup-\(UUID().uuidString)",
        context: .test,
        initialAttributes: TypedUser.instantAttributes
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var db

      do {
        try await db.transact(id: "tx-missing-strict-lookup") {
          TypedUser.updateExisting(
            lookup: TypedUser.email.lookup("missing@example.com"),
            TypedUser.name.set("Missing")
          )
        }
        #expect(Bool(false), "Expected missing strict lookup update to fail.")
      } catch let error as InstantError {
        expectNoDifference(error.code, .validationFailed)
        expectNoDifference(error.operation, "strict update entity")
        expectNoDifference(error.namespace, "users")
        expectNoDifference(error.path, "email")
      } catch {
        #expect(Bool(false), "Unexpected error: \(error)")
      }

      try await db.transact(id: "tx-duplicate-lookup-seed") {
        TypedUser.create(
          id: InstantID(rawValue: "duplicate-user-1"),
          TypedUser.name.set("One"),
          TypedUser.email.set("duplicate@example.com")
        )
        TypedUser.create(
          id: InstantID(rawValue: "duplicate-user-2"),
          TypedUser.name.set("Two"),
          TypedUser.email.set("duplicate@example.com")
        )
      }

      do {
        try await db.transact(id: "tx-ambiguous-strict-lookup") {
          TypedUser.updateExisting(
            lookup: duplicateLookup,
            TypedUser.name.set("Ambiguous")
          )
        }
        #expect(Bool(false), "Expected duplicate local lookup values to fail deterministically.")
      } catch let error as InstantError {
        expectNoDifference(error.code, .validationFailed)
        expectNoDifference(error.operation, "lookup entity")
        expectNoDifference(error.namespace, "users")
        expectNoDifference(error.path, "email")
      } catch {
        #expect(Bool(false), "Unexpected error: \(error)")
      }

      let pending = await db.pendingMutations()
      expectNoDifference(pending.map(\.id), ["tx-duplicate-lookup-seed"])
    }
  }

  @Test
  func typedLookupMergeAndDeleteRoundTripThroughDependencyClient() async throws {
    let profileID = InstantID<TypedProfile>(rawValue: "lookup-profile")
    let profileLookup = TypedProfile.handle.lookup("blob")

    try await withDependencies {
      try await $0.bootstrapInstantSwiftData(
        appID: "typed-lookup-merge-delete-\(UUID().uuidString)",
        context: .test,
        initialAttributes: TypedProfile.instantAttributes
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var db

      try await db.transact(id: "tx-profile-lookup-create") {
        TypedProfile.create(
          id: profileID,
          TypedProfile.handle.set("blob"),
          TypedProfile.metadata.set(
            .object([
              "nested": .object([
                "keep": .bool(true),
                "size": .number(1),
              ]),
              "theme": .string("light"),
            ])
          )
        )
      }
      try await db.transact(id: "tx-profile-lookup-merge") {
        TypedProfile.merge(
          lookup: profileLookup,
          TypedProfile.metadata.set(
            .object([
              "nested": .object([
                "size": .number(2)
              ]),
              "theme": .string("dark"),
            ])
          )
        )
      }

      let profiles = try await db.query(TypedProfile.query)
      expectNoDifference(
        profiles,
        [
          TypedProfile(
            id: profileID,
            metadata: .object([
              "nested": .object([
                "keep": .bool(true),
                "size": .number(2),
              ]),
              "theme": .string("dark"),
            ])
          )
        ]
      )

      try await db.transact(id: "tx-profile-lookup-delete") {
        TypedProfile.delete(lookup: profileLookup)
      }

      let deletedProfiles = try await db.query(TypedProfile.query)
      expectNoDifference(deletedProfiles, [])

      let pending = await db.pendingMutations()
      expectNoDifference(
        Set(pending.map(\.id)),
        Set(["tx-profile-lookup-create", "tx-profile-lookup-delete", "tx-profile-lookup-merge"])
      )
    }
  }

  @Test
  func typedLookupLinkOverloadsResolveSourceAndTargetIndependently() async throws {
    let userID = InstantID<TypedUser>(rawValue: "lookup-link-user")
    let secondUserID = InstantID<TypedUser>(rawValue: "lookup-link-user-2")
    let postID = InstantID<TypedPost>(rawValue: "lookup-link-post")
    let secondPostID = InstantID<TypedPost>(rawValue: "lookup-link-post-2")

    try await withDependencies {
      try await $0.bootstrapInstantSwiftData(
        appID: "typed-lookup-link-overloads-\(UUID().uuidString)",
        context: .test,
        initialAttributes: TypedUser.instantAttributes + TypedPost.instantAttributes
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var db

      try await db.transact(id: "tx-lookup-link-overload-seed") {
        TypedUser.create(
          id: userID,
          TypedUser.name.set("Blob"),
          TypedUser.email.set("blob@example.com")
        )
        TypedUser.create(
          id: secondUserID,
          TypedUser.name.set("Nub"),
          TypedUser.email.set("nub@example.com")
        )
        TypedPost.create(
          id: postID,
          TypedPost.title.set("Source lookup"),
          TypedPost.slug.set("source-lookup")
        )
        TypedPost.create(
          id: secondPostID,
          TypedPost.title.set("Target lookup"),
          TypedPost.slug.set("target-lookup")
        )
      }

      try await db.transact(id: "tx-link-source-lookup") {
        TypedPost.author.link(
          from: TypedPost.slug.lookup("source-lookup"),
          to: userID
        )
      }
      try await db.transact(id: "tx-link-target-lookup") {
        TypedPost.author.link(
          from: secondPostID,
          to: TypedUser.email.lookup("nub@example.com")
        )
      }

      let sourceLookupPost = try await db.query(
        TypedPost.query.where(TypedPost.slug == "source-lookup")
      )
      expectNoDifference(
        sourceLookupPost,
        [TypedPost(id: postID, title: "Source lookup", authorID: userID)]
      )

      let targetLookupPost = try await db.query(
        TypedPost.query.where(TypedPost.slug == "target-lookup")
      )
      expectNoDifference(
        targetLookupPost,
        [TypedPost(id: secondPostID, title: "Target lookup", authorID: secondUserID)]
      )

      try await db.transact(id: "tx-unlink-source-lookup") {
        TypedPost.author.unlink(
          from: TypedPost.slug.lookup("source-lookup"),
          to: userID
        )
      }
      try await db.transact(id: "tx-unlink-target-lookup") {
        TypedPost.author.unlink(
          from: secondPostID,
          to: TypedUser.email.lookup("nub@example.com")
        )
      }

      let unlinkedSourceLookupPost = try await db.query(
        TypedPost.query.where(TypedPost.slug == "source-lookup")
      )
      expectNoDifference(
        unlinkedSourceLookupPost,
        [TypedPost(id: postID, title: "Source lookup", authorID: nil)]
      )

      let unlinkedTargetLookupPost = try await db.query(
        TypedPost.query.where(TypedPost.slug == "target-lookup")
      )
      expectNoDifference(
        unlinkedTargetLookupPost,
        [TypedPost(id: secondPostID, title: "Target lookup", authorID: nil)]
      )
    }
  }

  @Test
  func typedRuleParamsPersistForIDsAndLookupsWithoutLocalMutation() async throws {
    let userID = InstantID<TypedUser>(rawValue: "rule-params-user")
    let userLookup = TypedUser.email.lookup("rule@example.com")

    try await withDependencies {
      try await $0.bootstrapInstantSwiftData(
        appID: "typed-rule-params-\(UUID().uuidString)",
        context: .test,
        initialAttributes: TypedUser.instantAttributes
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var db

      try await db.transact(id: "tx-rule-params-id") {
        TypedUser.ruleParams(
          id: userID,
          .object(["role": .string("owner")])
        )
      }
      try await db.transact(id: "tx-rule-params-lookup") {
        TypedUser.ruleParams(
          lookup: userLookup,
          .object(["role": .string("editor")])
        )
      }

      let users = try await db.query(
        InstantQueryPlan(id: "typed.rule-params.users", namespace: TypedUser.instantNamespace)
      )
      expectNoDifference(users, [])

      let pending = await db.pendingMutations()
      expectNoDifference(
        pending.map(\.transaction),
        [
          InstantStoreTransaction(
            id: "tx-rule-params-id",
            operations: [
              .ruleParams(
                entityID: userID.rawValue,
                namespace: TypedUser.instantNamespace,
                params: .object(["role": .string("owner")])
              )
            ]
          ),
          InstantStoreTransaction(
            id: "tx-rule-params-lookup",
            operations: [
              .ruleParamsByLookup(
                entity: userLookup.lookupRef,
                namespace: TypedUser.instantNamespace,
                params: .object(["role": .string("editor")])
              )
            ]
          ),
        ]
      )
    }
  }

  @Test
  func typedRuleParamsRejectsInvalidLookupsBeforeMockClientReceivesTransaction() async throws {
    let recorder = TransactionRecorder()
    let mock = InstantSwiftDataClient(
      transact: { transaction in
        await recorder.record(transaction)
        return InstantStoreMutationResult(
          transactionID: transaction.id,
          changedEntityIDs: [],
          tripleCount: transaction.operations.count,
          emissions: []
        )
      },
      query: { _ in [] },
      observe: { _ in AsyncStream { continuation in continuation.finish() } },
      pendingMutations: { [] },
      localID: { name in "mock-\(name)" }
    )

    await withDependencies {
      $0.date.now = Date(timeIntervalSince1970: 1_700_000_425)
      $0.uuid = .constant(UUID(uuidString: "00000000-0000-0000-0000-000000000779")!)
      $0.defaultInstantSwiftData = mock
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var db

      do {
        try await db.transact(id: "tx-rule-params-non-unique") {
          TypedUser.ruleParams(
            lookup: TypedUser.name.lookup("Blob"),
            .object(["role": .string("owner")])
          )
        }
        #expect(Bool(false), "Expected non-unique rule params lookup to fail before the mock client.")
      } catch let error as InstantError {
        expectNoDifference(error.code, .validationFailed)
        expectNoDifference(error.operation, "lookup entity")
        expectNoDifference(error.namespace, "users")
        expectNoDifference(error.path, "name")
      } catch {
        #expect(Bool(false), "Unexpected error: \(error)")
      }

      do {
        try await db.transact(id: "tx-rule-params-wrong-type") {
          TypedUser.ruleParams(
            lookup: InstantEntityLookup<TypedUser>(
              name: "email",
              attributeID: "users/email",
              value: .number(1)
            ),
            .object(["role": .string("owner")])
          )
        }
        #expect(Bool(false), "Expected wrong-value rule params lookup to fail before the mock client.")
      } catch let error as InstantError {
        expectNoDifference(error.code, .validationFailed)
        expectNoDifference(error.operation, "lookup entity")
        expectNoDifference(error.namespace, "users")
        expectNoDifference(error.path, "email")
      } catch {
        #expect(Bool(false), "Unexpected error: \(error)")
      }

      do {
        try await db.transact(id: "tx-rule-params-wrong-namespace") {
          TypedWrongNamespaceLookupEntity.ruleParams(
            lookup: TypedWrongNamespaceLookupEntity.email.lookup("blob@example.com"),
            .object(["role": .string("owner")])
          )
        }
        #expect(Bool(false), "Expected wrong-namespace rule params lookup to fail before the mock client.")
      } catch let error as InstantError {
        expectNoDifference(error.code, .validationFailed)
        expectNoDifference(error.operation, "lookup entity")
        expectNoDifference(error.namespace, "wrongUsers")
        expectNoDifference(error.path, "email")
      } catch {
        #expect(Bool(false), "Unexpected error: \(error)")
      }
    }

    let transactions = await recorder.transactions
    expectNoDifference(transactions, [])
  }

  @Test
  func typedLinkRejectsMismatchedTargetNamespaceBeforePersistence() async throws {
    let postID = InstantID<TypedPost>(rawValue: "post-1")
    let wrongTargetID = InstantID<TypedTodo>(rawValue: "todo-1")
    let wrongAuthorPath = InstantAttributePath<TypedPost, InstantID<TypedTodo>>(
      "author",
      attributeID: "posts/author"
    )

    try await withDependencies {
      try await $0.bootstrapInstantSwiftData(
        appID: "typed-link-validation-\(UUID().uuidString)",
        context: .test,
        initialAttributes: TypedUser.instantAttributes + TypedPost.instantAttributes
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var db

      do {
        try await db.transact(id: "tx-invalid-link") {
          wrongAuthorPath.link(from: postID, to: wrongTargetID)
        }
        #expect(Bool(false), "Expected mismatched link namespace to fail.")
      } catch let error as InstantError {
        expectNoDifference(error.code, .validationFailed)
        expectNoDifference(error.operation, "build link mutation")
        expectNoDifference(error.namespace, "posts")
        expectNoDifference(error.path, "author")
      } catch {
        #expect(Bool(false), "Unexpected error: \(error)")
      }

      do {
        try await db.transact(id: "tx-invalid-merge-ref") {
          TypedPost.merge(
            id: postID,
            TypedPost.author.set(InstantID<TypedUser>(rawValue: "user-1"))
          )
        }
        #expect(Bool(false), "Expected merge on a ref attribute to fail.")
      } catch let error as InstantError {
        expectNoDifference(error.code, .validationFailed)
        expectNoDifference(error.operation, "merge entity attribute")
        expectNoDifference(error.namespace, "posts")
        expectNoDifference(error.path, "author")
      } catch {
        #expect(Bool(false), "Unexpected error: \(error)")
      }

      let pending = await db.pendingMutations()
      expectNoDifference(pending, [])
    }
  }

  @Test
  func typedMergeRejectsRefAttributesBeforeMockClientReceivesTransaction() async throws {
    let recorder = TransactionRecorder()
    let mock = InstantSwiftDataClient(
      transact: { transaction in
        await recorder.record(transaction)
        return InstantStoreMutationResult(
          transactionID: transaction.id,
          changedEntityIDs: [],
          tripleCount: transaction.operations.count,
          emissions: []
        )
      },
      query: { _ in [] },
      observe: { _ in AsyncStream { continuation in continuation.finish() } },
      pendingMutations: { [] },
      localID: { name in "mock-\(name)" }
    )

    await withDependencies {
      $0.date.now = Date(timeIntervalSince1970: 1_700_000_250)
      $0.uuid = .constant(UUID(uuidString: "00000000-0000-0000-0000-000000000999")!)
      $0.defaultInstantSwiftData = mock
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var db

      do {
        try await db.transact(id: "tx-mock-invalid-merge") {
          TypedPost.merge(
            id: InstantID(rawValue: "post-1"),
            TypedPost.author.set(InstantID<TypedUser>(rawValue: "user-1"))
          )
        }
        #expect(Bool(false), "Expected typed merge validation to run before the mock client.")
      } catch let error as InstantError {
        expectNoDifference(error.code, .validationFailed)
        expectNoDifference(error.operation, "merge entity attribute")
        expectNoDifference(error.namespace, "posts")
        expectNoDifference(error.path, "author")
      } catch {
        #expect(Bool(false), "Unexpected error: \(error)")
      }

      let mismatchedEmail = InstantAttributePath<TypedUser, String>(
        "email",
        attributeID: "users/notEmail"
      )
      do {
        try await db.transact(id: "tx-mock-mismatched-lookup") {
          TypedUser.update(
            lookup: mismatchedEmail.lookup("blob@example.com"),
            TypedUser.name.set("Blob")
          )
        }
        #expect(Bool(false), "Expected mismatched lookup path validation to run before the mock client.")
      } catch let error as InstantError {
        expectNoDifference(error.code, .validationFailed)
        expectNoDifference(error.operation, "lookup entity")
        expectNoDifference(error.namespace, "users")
        expectNoDifference(error.path, "email")
      } catch {
        #expect(Bool(false), "Unexpected error: \(error)")
      }
    }

    let transactions = await recorder.transactions
    expectNoDifference(transactions, [])
  }

  @Test
  func typedMutationsRejectReservedIDAssignmentsBeforeMockClientReceivesTransaction() async throws {
    let recorder = TransactionRecorder()
    let mock = InstantSwiftDataClient(
      transact: { transaction in
        await recorder.record(transaction)
        return InstantStoreMutationResult(
          transactionID: transaction.id,
          changedEntityIDs: [],
          tripleCount: transaction.operations.count,
          emissions: []
        )
      },
      query: { _ in [] },
      observe: { _ in AsyncStream { continuation in continuation.finish() } },
      pendingMutations: { [] },
      localID: { name in "mock-\(name)" }
    )

    await withDependencies {
      $0.date.now = Date(timeIntervalSince1970: 1_700_000_275)
      $0.uuid = .constant(UUID(uuidString: "00000000-0000-0000-0000-000000000777")!)
      $0.defaultInstantSwiftData = mock
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var db
      let idPath = InstantAttributePath<TypedTodo, String>("id")

      do {
        try await db.transact(id: "tx-mock-invalid-id") {
          TypedTodo.update(
            id: InstantID(rawValue: "todo-1"),
            idPath.set("other-id")
          )
        }
        #expect(Bool(false), "Expected id assignment validation to run before the mock client.")
      } catch let error as InstantError {
        expectNoDifference(error.code, .validationFailed)
        expectNoDifference(error.operation, "write entity attribute")
        expectNoDifference(error.namespace, "todos")
        expectNoDifference(error.path, "id")
      } catch {
        #expect(Bool(false), "Unexpected error: \(error)")
      }

      do {
        try await db.transact(id: "tx-mock-invalid-declared-id") {
          TypedBadIDEntity.update(
            id: InstantID(rawValue: "bad-1"),
            TypedBadIDEntity.idAttribute.set("other-id")
          )
        }
        #expect(Bool(false), "Expected declared id attribute validation to run before the mock client.")
      } catch let error as InstantError {
        expectNoDifference(error.code, .validationFailed)
        expectNoDifference(error.operation, "write entity attribute")
        expectNoDifference(error.namespace, "badIDEntities")
        expectNoDifference(error.path, "id")
      } catch {
        #expect(Bool(false), "Unexpected error: \(error)")
      }
    }

    let transactions = await recorder.transactions
    expectNoDifference(transactions, [])
  }

  @Test
  func typedLookupRejectsNonUniqueAttributeBeforeMockClientReceivesTransaction() async throws {
    let recorder = TransactionRecorder()
    let mock = InstantSwiftDataClient(
      transact: { transaction in
        await recorder.record(transaction)
        return InstantStoreMutationResult(
          transactionID: transaction.id,
          changedEntityIDs: [],
          tripleCount: transaction.operations.count,
          emissions: []
        )
      },
      query: { _ in [] },
      observe: { _ in AsyncStream { continuation in continuation.finish() } },
      pendingMutations: { [] },
      localID: { name in "mock-\(name)" }
    )

    await withDependencies {
      $0.date.now = Date(timeIntervalSince1970: 1_700_000_400)
      $0.uuid = .constant(UUID(uuidString: "00000000-0000-0000-0000-000000000778")!)
      $0.defaultInstantSwiftData = mock
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var db

      do {
        try await db.transact(id: "tx-mock-invalid-lookup") {
          TypedUser.update(
            lookup: TypedUser.name.lookup("Blob"),
            TypedUser.email.set("blob@example.com")
          )
        }
        #expect(Bool(false), "Expected lookup validation to run before the mock client.")
      } catch let error as InstantError {
        expectNoDifference(error.code, .validationFailed)
        expectNoDifference(error.operation, "lookup entity")
        expectNoDifference(error.namespace, "users")
        expectNoDifference(error.path, "name")
      } catch {
        #expect(Bool(false), "Unexpected error: \(error)")
      }
    }

    let transactions = await recorder.transactions
    expectNoDifference(transactions, [])
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
  func fetchAllSubscriptionEmitsInitialAndOptimisticUpdates() async throws {
    let baseDate = Date(timeIntervalSince1970: 1_700_000_125)
    let fixedUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000657")!

    try await withDependencies {
      $0.date.now = baseDate
      $0.uuid = .constant(fixedUUID)
      try await $0.bootstrapInstantSwiftData(
        appID: "fetch-all-subscription-\(UUID().uuidString)",
        context: .test,
        initialAttributes: TypedTodo.instantAttributes
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var db

      var fetch = FetchAll<TypedTodo>(
        TypedTodo.query
          .where(TypedTodo.isCompleted == false)
          .order(TypedTodo.createdAt)
      )
      let subscription = try await fetch.subscribe()
      var iterator = subscription.makeAsyncIterator()

      let initial = try await iterator.next()
      expectNoDifference(initial, [])

      try await db.transact {
        TypedTodo.create(
          id: InstantID(rawValue: "todo-live"),
          TypedTodo.text.set("Live"),
          TypedTodo.isCompleted.set(false),
          TypedTodo.createdAt.set(baseDate)
        )
      }

      let updated = try await iterator.next()
      expectNoDifference(updated?.map(\.text), ["Live"])
      expectNoDifference(fetch.loadError, nil)
      subscription.cancel()
    }
  }

  @Test
  func fetchOneLoadsFirstTypedQueryAndDynamicQuery() async throws {
    let baseDate = Date(timeIntervalSince1970: 1_700_000_150)
    let fixedUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000655")!

    try await withDependencies {
      $0.date.now = baseDate
      $0.uuid = .constant(fixedUUID)
      try await $0.bootstrapInstantSwiftData(
        appID: "fetch-one-\(UUID().uuidString)",
        context: .test,
        initialAttributes: TypedTodo.instantAttributes
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var db

      try await db.transact {
        TypedTodo.create(
          id: InstantID(rawValue: "todo-first"),
          TypedTodo.text.set("First"),
          TypedTodo.isCompleted.set(false),
          TypedTodo.createdAt.set(baseDate)
        )
        TypedTodo.create(
          id: InstantID(rawValue: "todo-second"),
          TypedTodo.text.set("Second"),
          TypedTodo.isCompleted.set(false),
          TypedTodo.createdAt.set(baseDate.addingTimeInterval(1))
        )
      }

      var fetch = FetchOne<TypedTodo>(TypedTodo.query.order(TypedTodo.createdAt))
      try await fetch.load()

      expectNoDifference(fetch.wrappedValue?.text, "First")
      expectNoDifference(fetch.isLoading, false)
      expectNoDifference(fetch.loadError, nil)

      try await fetch.load(TypedTodo.query.where(TypedTodo.text == "Missing"))

      expectNoDifference(fetch.wrappedValue, nil)
      expectNoDifference(fetch.isLoading, false)
      expectNoDifference(fetch.loadError, nil)
    }
  }

  @Test
  func fetchOneSubscriptionMapsLiveValuesToFirstEntity() async throws {
    let baseDate = Date(timeIntervalSince1970: 1_700_000_160)
    let fixedUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000658")!

    try await withDependencies {
      $0.date.now = baseDate
      $0.uuid = .constant(fixedUUID)
      try await $0.bootstrapInstantSwiftData(
        appID: "fetch-one-subscription-\(UUID().uuidString)",
        context: .test,
        initialAttributes: TypedTodo.instantAttributes
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var db

      var fetch = FetchOne<TypedTodo>(TypedTodo.query.order(TypedTodo.createdAt))
      let subscription = try await fetch.subscribe()
      var iterator = subscription.makeAsyncIterator()

      let initial = try await iterator.next()
      guard case .some(nil) = initial else {
        Issue.record("Expected initial FetchOne subscription emission to be nil.")
        return
      }

      try await db.transact {
        TypedTodo.create(
          id: InstantID(rawValue: "todo-second-live"),
          TypedTodo.text.set("Second live"),
          TypedTodo.isCompleted.set(false),
          TypedTodo.createdAt.set(baseDate.addingTimeInterval(1))
        )
        TypedTodo.create(
          id: InstantID(rawValue: "todo-first-live"),
          TypedTodo.text.set("First live"),
          TypedTodo.isCompleted.set(false),
          TypedTodo.createdAt.set(baseDate)
        )
      }

      let updated = try await iterator.next()
      let todo = try #require(updated ?? nil)
      expectNoDifference(todo.text, "First live")
      expectNoDifference(fetch.loadError, nil)
      subscription.cancel()
    }
  }

  @Test
  func fetchSubscriptionCancelTerminatesObservedStream() async throws {
    let termination = ObservationTermination()
    let mock = mockClient(recording: termination)

    var fetch = FetchAll<TypedTodo>(TypedTodo.query)
    let subscription = try await fetch.subscribe(using: mock)
    var iterator = subscription.makeAsyncIterator()

    let initial = try await iterator.next()
    expectNoDifference(initial?.count, 0)

    subscription.cancel()
    if let value = try await iterator.next() {
      Issue.record("Expected subscription cancellation to finish the stream; got \(value.count) values.")
    }
    await termination.wait()
  }

  @Test
  func fetchSubscriptionCancelBeforeFirstReadTerminatesObservedStream() async throws {
    let termination = ObservationTermination()
    let mock = mockClient(recording: termination)

    var fetch = FetchAll<TypedTodo>(TypedTodo.query)
    let subscription = try await fetch.subscribe(using: mock)
    subscription.cancel()

    var iterator = subscription.makeAsyncIterator()
    _ = try await iterator.next()
    if let value = try await iterator.next() {
      Issue.record("Expected cancelled subscription to finish after draining; got \(value.count) values.")
    }
    await termination.wait()
  }

  @Test
  func fetchOneSubscriptionCancelTerminatesMappedObservedStream() async throws {
    let termination = ObservationTermination()
    let mock = mockClient(recording: termination)

    var fetch = FetchOne<TypedTodo>(TypedTodo.query)
    let subscription = try await fetch.subscribe(using: mock)
    subscription.cancel()

    var iterator = subscription.makeAsyncIterator()
    _ = try await iterator.next()
    if let value = try await iterator.next() {
      Issue.record("Expected mapped subscription to finish after draining; got \(String(describing: value)).")
    }
    await termination.wait()
  }

  @Test
  func unusedFetchSubscriptionCleansUpWhenReleased() async throws {
    let termination = ObservationTermination()
    let mock = mockClient(recording: termination)

    try await makeUnusedFetchSubscription(using: mock)
    await termination.wait()
  }

  @Test
  func fetchLoadsCustomDerivedValues() async throws {
    let baseDate = Date(timeIntervalSince1970: 1_700_000_175)
    let fixedUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000656")!

    try await withDependencies {
      $0.date.now = baseDate
      $0.uuid = .constant(fixedUUID)
      try await $0.bootstrapInstantSwiftData(
        appID: "fetch-custom-\(UUID().uuidString)",
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

      var fetch = Fetch<Int>(wrappedValue: 0) { client in
        try await client.query(TypedTodo.query).count
      }
      try await fetch.load()

      expectNoDifference(fetch.wrappedValue, 2)
      expectNoDifference(fetch.isLoading, false)
      expectNoDifference(fetch.loadError, nil)

      try await fetch.load { client in
        try await client.query(TypedTodo.query.where(TypedTodo.isCompleted == false)).count
      }

      expectNoDifference(fetch.wrappedValue, 1)
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
      expectNoDifference(result.tripleCount, 3)
    }

    let transactions = await recorder.transactions
    let expectedTime = InstantTimestamp(milliseconds: 1_700_000_200_000)
    expectNoDifference(
      transactions,
      [
        InstantStoreTransaction(
          id: fixedUUID.uuidString.lowercased(),
          operations: [
            .requireEntityMissing(entityID: "todo-mock", namespace: "todos"),
            .insert(
              InstantTriple(
                entityID: "todo-mock",
                attributeID: "todos/id",
                value: .string("todo-mock"),
                txID: fixedUUID.uuidString.lowercased(),
                txTime: expectedTime
              )
            ),
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

  @Test
  func fetchAllPropertyWrapperSupportsServerCreatedAtOrder() async throws {
    let cacheURL = try typedTestCacheURL("fetch-wrapper-server-created-at")
    let baseDate = Date(timeIntervalSince1970: 1_700_000_301)
    let fixedUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000abe")!

    try await withDependencies {
      $0.date.now = baseDate
      $0.uuid = .constant(fixedUUID)
      try await $0.bootstrapInstantSwiftData(
        appID: "fetch-wrapper-server-created-at",
        persistenceURL: cacheURL,
        context: .test,
        initialAttributes: TypedTodo.instantAttributes
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var db

      try await db.transact(
        id: "tx-fetch-wrapper-server-created-at-first",
        createdAt: InstantTimestamp(milliseconds: 1_700_000_301_010)
      ) {
        TypedTodo.create(
          id: InstantID(rawValue: "todo-wrapper-first"),
          TypedTodo.text.set("First"),
          TypedTodo.isCompleted.set(false),
          TypedTodo.createdAt.set(baseDate)
        )
      }
      try await db.transact(
        id: "tx-fetch-wrapper-server-created-at-second",
        createdAt: InstantTimestamp(milliseconds: 1_700_000_301_020)
      ) {
        TypedTodo.create(
          id: InstantID(rawValue: "todo-wrapper-second"),
          TypedTodo.text.set("Second"),
          TypedTodo.isCompleted.set(false),
          TypedTodo.createdAt.set(baseDate.addingTimeInterval(1))
        )
      }

      var model = TypedTodoServerCreatedAtFetchModel()
      try await model.load()

      expectNoDifference(model.todos.map(\.text), ["Second", "First"])
      expectNoDifference(model.$todos.loadError, nil)
      expectNoDifference(model.$todos.isLoading, false)
    }
  }

  @Test
  func fetchOnePropertyWrapperProjectionLoadsTypedQuery() async throws {
    let baseDate = Date(timeIntervalSince1970: 1_700_000_325)
    let fixedUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000def")!

    try await withDependencies {
      $0.date.now = baseDate
      $0.uuid = .constant(fixedUUID)
      try await $0.bootstrapInstantSwiftData(
        appID: "fetch-one-wrapper-\(UUID().uuidString)",
        context: .test,
        initialAttributes: TypedTodo.instantAttributes
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var db
      try await db.transact {
        TypedTodo.create(
          id: InstantID(rawValue: "todo-later"),
          TypedTodo.text.set("Later"),
          TypedTodo.isCompleted.set(false),
          TypedTodo.createdAt.set(baseDate.addingTimeInterval(1))
        )
        TypedTodo.create(
          id: InstantID(rawValue: "todo-earlier"),
          TypedTodo.text.set("Earlier"),
          TypedTodo.isCompleted.set(false),
          TypedTodo.createdAt.set(baseDate)
        )
      }

      var model = TypedTodoFetchOneModel()
      try await model.load()

      expectNoDifference(model.todo?.text, "Earlier")
      expectNoDifference(model.$todo.loadError, nil)
      expectNoDifference(model.$todo.isLoading, false)
    }
  }
}

private actor TransactionRecorder {
  private(set) var transactions: [InstantStoreTransaction] = []

  func record(_ transaction: InstantStoreTransaction) {
    transactions.append(transaction)
  }
}

private func mockClient(recording termination: ObservationTermination) -> InstantSwiftDataClient {
  InstantSwiftDataClient(
    transact: { _ in
      InstantStoreMutationResult(
        transactionID: "tx",
        changedEntityIDs: [],
        tripleCount: 0,
        emissions: []
      )
    },
    query: { _ in [] },
    observe: { plan in
      AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
        continuation.yield(
          InstantQueryEmission(queryID: plan.id, sequence: 0, values: [])
        )
        continuation.onTermination = { @Sendable _ in
          Task {
            await termination.record()
          }
        }
      }
    },
    pendingMutations: { [] },
    localID: { name in "mock-\(name)" }
  )
}

private func makeUnusedFetchSubscription(using client: InstantSwiftDataClient) async throws {
  var fetch = FetchAll<TypedTodo>(TypedTodo.query)
  let subscription = try await fetch.subscribe(using: client)
  withExtendedLifetime(subscription) {}
}

private func typedTestCacheURL(_ name: String) throws -> URL {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("InstantSwiftDataTypedAPITests", isDirectory: true)
    .appendingPathComponent(name, isDirectory: true)
  try? FileManager.default.removeItem(at: directory)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  return directory.appendingPathComponent("state.sqlite")
}

private actor ObservationTermination {
  private var didTerminate = false
  private var continuations: [CheckedContinuation<Void, Never>] = []

  func record() {
    didTerminate = true
    for continuation in continuations {
      continuation.resume()
    }
    continuations.removeAll()
  }

  func wait() async {
    if didTerminate { return }
    await withCheckedContinuation { continuation in
      continuations.append(continuation)
    }
  }
}

private struct TypedTodoFetchModel {
  @FetchAll(TypedTodo.query.where(TypedTodo.isCompleted == false).order(TypedTodo.createdAt))
  var todos: [TypedTodo]

  mutating func load() async throws {
    try await $todos.load()
  }
}

private struct TypedTodoServerCreatedAtFetchModel {
  @FetchAll(TypedTodo.query.order(.serverCreatedAt, .descending))
  var todos: [TypedTodo]

  mutating func load() async throws {
    try await $todos.load()
  }
}

private struct TypedTodoFetchOneModel {
  @FetchOne(TypedTodo.query.where(TypedTodo.isCompleted == false).order(TypedTodo.createdAt))
  var todo: TypedTodo?

  mutating func load() async throws {
    try await $todo.load()
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

private struct TypedBadIDEntity: Hashable, Codable, InstantEntityModel {
  var id: InstantID<TypedBadIDEntity>

  static let instantNamespace = "badIDEntities"
  static let idAttribute = InstantAttributePath<TypedBadIDEntity, String>(
    "id",
    attributeID: "badIDEntities/id"
  )

  static let instantAttributes = [
    InstantAttribute(
      id: "badIDEntities/id",
      namespace: instantNamespace,
      name: "id",
      valueType: .string,
      isIndexed: true
    )
  ]

  init(snapshot: InstantEntitySnapshot) throws {
    self.id = InstantID(rawValue: snapshot.id)
  }
}

private struct TypedReservedServerCreatedAtEntity: Hashable, Codable, InstantEntityModel {
  var id: InstantID<TypedReservedServerCreatedAtEntity>

  static let instantNamespace = "reservedServerCreatedAtEntities"
  static let serverCreatedAt =
    InstantAttributePath<TypedReservedServerCreatedAtEntity, Date>("serverCreatedAt")

  static let instantAttributes = [
    InstantAttribute(
      id: "reservedServerCreatedAtEntities/serverCreatedAt",
      namespace: instantNamespace,
      name: "serverCreatedAt",
      valueType: .date,
      isIndexed: true
    )
  ]

  init(snapshot: InstantEntitySnapshot) throws {
    self.id = InstantID(rawValue: snapshot.id)
  }
}

private struct TypedWrongNamespaceLookupEntity: Hashable, Codable, InstantEntityModel {
  var id: InstantID<TypedWrongNamespaceLookupEntity>

  static let instantNamespace = "wrongUsers"
  static let email = InstantAttributePath<TypedWrongNamespaceLookupEntity, String>(
    "email",
    attributeID: "users/email"
  )

  static let instantAttributes = [
    InstantAttribute(
      id: "users/email",
      namespace: "users",
      name: "email",
      valueType: .string,
      isIndexed: true,
      isUnique: true
    )
  ]

  init(snapshot: InstantEntitySnapshot) throws {
    self.id = InstantID(rawValue: snapshot.id)
  }
}

private struct TypedUser: Hashable, Codable, InstantEntityModel {
  var id: InstantID<TypedUser>
  var name: String

  static let instantNamespace = "users"
  static let name = InstantAttributePath<TypedUser, String>("name")
  static let email = InstantAttributePath<TypedUser, String>("email")

  static let instantAttributes = [
    InstantAttribute(
      id: "users/name",
      namespace: instantNamespace,
      name: "name",
      valueType: .string,
      isIndexed: true
    ),
    InstantAttribute(
      id: "users/email",
      namespace: instantNamespace,
      name: "email",
      valueType: .string,
      isIndexed: true,
      isUnique: true
    )
  ]

  init(id: InstantID<TypedUser>, name: String) {
    self.id = id
    self.name = name
  }

  init(snapshot: InstantEntitySnapshot) throws {
    guard case let .string(name) = snapshot.values["name"]?.first else {
      throw InstantError(
        code: .decodeFailed,
        operation: "decode typed user",
        namespace: Self.instantNamespace,
        path: "name",
        localID: snapshot.id,
        message: "Expected string for user field 'name'.",
        recovery: "Check the Instant entity schema and server values for the users namespace."
      )
    }
    self.id = InstantID(rawValue: snapshot.id)
    self.name = name
  }
}

private struct TypedProfile: Hashable, Codable, InstantEntityModel {
  var id: InstantID<TypedProfile>
  var metadata: JSONValue

  static let instantNamespace = "profiles"
  static let handle = InstantAttributePath<TypedProfile, String>("handle")
  static let metadata = InstantAttributePath<TypedProfile, JSONValue>("metadata")

  static let instantAttributes = [
    InstantAttribute(
      id: "profiles/handle",
      namespace: instantNamespace,
      name: "handle",
      valueType: .string,
      isIndexed: true,
      isUnique: true
    ),
    InstantAttribute(
      id: "profiles/metadata",
      namespace: instantNamespace,
      name: "metadata",
      valueType: .json
    )
  ]

  init(id: InstantID<TypedProfile>, metadata: JSONValue) {
    self.id = id
    self.metadata = metadata
  }

  init(snapshot: InstantEntitySnapshot) throws {
    guard case let .json(metadata) = snapshot.values["metadata"]?.first else {
      throw InstantError(
        code: .decodeFailed,
        operation: "decode typed profile",
        namespace: Self.instantNamespace,
        path: "metadata",
        localID: snapshot.id,
        message: "Expected json for profile field 'metadata'.",
        recovery: "Check the Instant entity schema and server values for the profiles namespace."
      )
    }
    self.id = InstantID(rawValue: snapshot.id)
    self.metadata = metadata
  }
}

private struct TypedPost: Hashable, Codable, InstantEntityModel {
  var id: InstantID<TypedPost>
  var title: String
  var authorID: InstantID<TypedUser>?

  static let instantNamespace = "posts"
  static let title = InstantAttributePath<TypedPost, String>("title")
  static let slug = InstantAttributePath<TypedPost, String>("slug")
  static let author = InstantAttributePath<TypedPost, InstantID<TypedUser>>("author")

  static let instantAttributes = [
    InstantAttribute(
      id: "posts/title",
      namespace: instantNamespace,
      name: "title",
      valueType: .string,
      isIndexed: true
    ),
    InstantAttribute(
      id: "posts/slug",
      namespace: instantNamespace,
      name: "slug",
      valueType: .string,
      isIndexed: true,
      isUnique: true
    ),
    InstantAttribute(
      id: "posts/author",
      namespace: instantNamespace,
      name: "author",
      valueType: .ref,
      isIndexed: true,
      forwardIdentity: "posts/author",
      reverseIdentity: "users/posts",
      linkNamespace: TypedUser.instantNamespace
    ),
  ]

  init(id: InstantID<TypedPost>, title: String, authorID: InstantID<TypedUser>?) {
    self.id = id
    self.title = title
    self.authorID = authorID
  }

  init(snapshot: InstantEntitySnapshot) throws {
    guard case let .string(title) = snapshot.values["title"]?.first else {
      throw InstantError(
        code: .decodeFailed,
        operation: "decode typed post",
        namespace: Self.instantNamespace,
        path: "title",
        localID: snapshot.id,
        message: "Expected string for post field 'title'.",
        recovery: "Check the Instant entity schema and server values for the posts namespace."
      )
    }

    let authorID: InstantID<TypedUser>?
    if let author = snapshot.values["author"]?.first {
      guard case let .ref(rawValue) = author else {
        throw InstantError(
          code: .decodeFailed,
          operation: "decode typed post",
          namespace: Self.instantNamespace,
          path: "author",
          localID: snapshot.id,
          message: "Expected ref for post field 'author'.",
          recovery: "Check the Instant entity schema and server values for the posts namespace."
        )
      }
      authorID = InstantID<TypedUser>(rawValue: rawValue)
    } else {
      authorID = nil
    }

    self.id = InstantID(rawValue: snapshot.id)
    self.title = title
    self.authorID = authorID
  }
}
