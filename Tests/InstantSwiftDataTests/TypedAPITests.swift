import CustomDump
import Dependencies
import Foundation
import InstantSwiftData
import Testing

#if canImport(SwiftUI)
  import SwiftUI
#endif

#if canImport(Observation)
  import Observation
#endif

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

    let selectedQuery = TypedTodo.query
      .where(TypedTodo.isCompleted == false)
      .select(TypedTodo.text, TypedTodo.isCompleted, TypedTodo.text)
    let unselectedFilteredQuery = TypedTodo.query.where(TypedTodo.isCompleted == false)
    expectNoDifference(selectedQuery.plan.selectedFields, ["isCompleted", "text"])
    #expect(selectedQuery.plan.id != unselectedFilteredQuery.plan.id)
    #expect(selectedQuery.plan.cacheKey != unselectedFilteredQuery.plan.cacheKey)

    let dynamicSelectedQuery = TypedTodo.query.select([TypedTodo.text])
    expectNoDifference(dynamicSelectedQuery.plan.selectedFields, ["text"])

    let selectedThenOrderedQuery = TypedTodo.query
      .select(TypedTodo.text)
      .order(.serverCreatedAt, .descending)
    expectNoDifference(selectedThenOrderedQuery.plan.order, .serverCreatedAtDescending)
    expectNoDifference(selectedThenOrderedQuery.plan.selectedFields, ["text"])
    #expect(selectedThenOrderedQuery.plan.cacheKey != serverCreatedAtQuery.plan.cacheKey)

    let includedQuery = TypedPost.query
      .include(
        TypedPost.author,
        TypedUser.query
          .select(TypedUser.name)
          .order(TypedUser.name)
      )
    expectNoDifference(
      includedQuery.plan.includes,
      [
        InstantQueryInclude(
          "author",
          query: InstantQueryIncludePlan(
            id: TypedUser.query.select(TypedUser.name).order(TypedUser.name).plan.id,
            namespace: TypedUser.instantNamespace,
            order: InstantQueryOrder("name"),
            selectedFields: ["name"]
          )
        )
      ]
    )
    #expect(includedQuery.plan.id != TypedPost.query.plan.id)
    #expect(includedQuery.plan.cacheKey != TypedPost.query.plan.cacheKey)

    let filteredIncludedQuery = includedQuery.where(TypedPost.title == "Hello links")
    #expect(filteredIncludedQuery.plan.id != includedQuery.plan.id)
    expectNoDifference(filteredIncludedQuery.plan.includes, includedQuery.plan.includes)

    let filteredChildIncludeQuery = TypedPost.query.include(
      TypedPost.author,
      TypedUser.query.where(TypedUser.name == "Blob").select(TypedUser.name)
    )
    #expect(filteredChildIncludeQuery.plan.id != includedQuery.plan.id)
    #expect(filteredChildIncludeQuery.plan.cacheKey != includedQuery.plan.cacheKey)
    expectNoDifference(
      filteredChildIncludeQuery.plan.includes?.first?.query?.filters,
      [.equals(field: "name", value: .string("Blob"))]
    )

    let replacedIncludeQuery = TypedPost.query
      .include(TypedPost.author, TypedUser.query.select(TypedUser.name))
      .include(TypedPost.author, TypedUser.query.select(TypedUser.email))
    expectNoDifference(replacedIncludeQuery.plan.includes?.count, 1)
    expectNoDifference(replacedIncludeQuery.plan.includes?.first?.query?.selectedFields, ["email"])

    let reverseIncludedQuery = TypedUser.query
      .include(
        TypedUser.posts,
        TypedPost.query
          .select(TypedPost.title)
          .order(TypedPost.title)
      )
    expectNoDifference(TypedUser.posts.name, "posts")
    expectNoDifference(TypedUser.posts.attributeID, "posts/author")
    expectNoDifference(
      reverseIncludedQuery.plan.includes,
      [
        InstantQueryInclude(
          "posts",
          direction: .reverse,
          query: InstantQueryIncludePlan(
            id: TypedPost.query.select(TypedPost.title).order(TypedPost.title).plan.id,
            namespace: TypedPost.instantNamespace,
            order: InstantQueryOrder("title"),
            selectedFields: ["title"]
          )
        )
      ]
    )
    #expect(reverseIncludedQuery.plan.id != TypedUser.query.plan.id)
    #expect(reverseIncludedQuery.plan.cacheKey != TypedUser.query.plan.cacheKey)
  }

  @Test
  func instantEntityMacroGeneratedSchemaHelpersDriveTypedAPI() async throws {
    let dueAt = Date(timeIntervalSince1970: 1_700_000_123)
    let todoID = InstantID<MacroGeneratedTodo>(rawValue: "macro-generated-todo")

    expectNoDifference(
      MacroGeneratedTodo.instantAttributes,
      [
        InstantAttribute(
          id: "macroGeneratedTodos/title",
          namespace: MacroGeneratedTodo.instantNamespace,
          name: "title",
          valueType: .string,
          isIndexed: true
        ),
        InstantAttribute(
          id: "macroGeneratedTodos/score",
          namespace: MacroGeneratedTodo.instantNamespace,
          name: "score",
          valueType: .number,
          isIndexed: true
        ),
        InstantAttribute(
          id: "macroGeneratedTodos/dueAt",
          namespace: MacroGeneratedTodo.instantNamespace,
          name: "dueAt",
          valueType: .date,
          isRequired: false,
          isIndexed: true
        ),
        InstantAttribute(
          id: "macroGeneratedTodos/metadata",
          namespace: MacroGeneratedTodo.instantNamespace,
          name: "metadata",
          valueType: .json,
          isIndexed: true
        ),
        InstantAttribute(
          id: "macroGeneratedTodos/isCompleted",
          namespace: MacroGeneratedTodo.instantNamespace,
          name: "isCompleted",
          valueType: .boolean,
          isIndexed: true
        ),
      ]
    )

    try await withDependencies {
      try await $0.bootstrapInstantSwiftData(
        appID: "macro-generated-helpers-\(UUID().uuidString)",
        context: .test,
        initialAttributes: MacroGeneratedTodo.instantAttributes
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var db

      try await db.transact(id: "tx-macro-generated-todo") {
        MacroGeneratedTodo.create(
          id: todoID,
          MacroGeneratedTodo.title.set("Generated helpers"),
          MacroGeneratedTodo.score.set(42),
          MacroGeneratedTodo.dueAt.set(dueAt),
          MacroGeneratedTodo.metadata.set(.object(["source": .string("macro")])),
          MacroGeneratedTodo.isCompleted.set(false)
        )
      }

      let todos = try await db.query(
        MacroGeneratedTodo.query
          .where(MacroGeneratedTodo.isCompleted == false)
          .order(MacroGeneratedTodo.score)
      )
      expectNoDifference(
        todos,
        [
          MacroGeneratedTodo(
            id: todoID,
            title: "Generated helpers",
            score: 42,
            dueAt: dueAt,
            metadata: .object(["source": .string("macro")]),
            isCompleted: false
          )
        ]
      )
    }
  }

  @Test
  func instantEntityMacroGeneratedRelationMetadataDrivesReverseIncludes() throws {
    expectNoDifference(
      MacroGeneratedPost.instantAttributes,
      [
        InstantAttribute(
          id: "macroGeneratedPosts/title",
          namespace: MacroGeneratedPost.instantNamespace,
          name: "title",
          valueType: .string,
          isIndexed: true
        ),
        InstantAttribute(
          id: "macroGeneratedPosts/author",
          namespace: MacroGeneratedPost.instantNamespace,
          name: "author",
          valueType: .ref,
          isIndexed: true,
          forwardIdentity: "macroGeneratedPosts/author",
          reverseIdentity: "macroGeneratedUsers/posts",
          linkNamespace: MacroGeneratedUser.instantNamespace
        ),
      ]
    )

    let posts = MacroGeneratedPost.posts
    expectNoDifference(
      posts,
      try InstantReverseRelation<MacroGeneratedUser, MacroGeneratedPost>(
        validating: MacroGeneratedPost.author
      )
    )
    expectNoDifference(posts.name, "posts")
    expectNoDifference(posts.attributeID, "macroGeneratedPosts/author")

    let query = MacroGeneratedUser.query.include(
      posts,
      MacroGeneratedPost.query.select(MacroGeneratedPost.title)
    )
    expectNoDifference(
      query.plan.includes,
      [
        InstantQueryInclude(
          "posts",
          direction: .reverse,
          query: InstantQueryIncludePlan(
            id: MacroGeneratedPost.query.select(MacroGeneratedPost.title).plan.id,
            namespace: MacroGeneratedPost.instantNamespace,
            selectedFields: ["title"]
          )
        )
      ]
    )
  }

  @Test
  func instantEntityMacroGeneratedReverseRelationTokensSupportOptionalRefs() {
    expectNoDifference(MacroGeneratedOptionalPost.posts.name, "posts")
    expectNoDifference(
      MacroGeneratedOptionalPost.posts.attributeID,
      "macroGeneratedOptionalPosts/author"
    )

    let query = MacroGeneratedOptionalUser.query.include(
      MacroGeneratedOptionalPost.posts,
      MacroGeneratedOptionalPost.query.select(MacroGeneratedOptionalPost.title)
    )
    expectNoDifference(
      query.plan.includes,
      [
        InstantQueryInclude(
          "posts",
          direction: .reverse,
          query: InstantQueryIncludePlan(
            id: MacroGeneratedOptionalPost.query.select(MacroGeneratedOptionalPost.title).plan.id,
            namespace: MacroGeneratedOptionalPost.instantNamespace,
            selectedFields: ["title"]
          )
        )
      ]
    )
  }

  @Test
  func reverseRelationDerivesNameFromRefAttributeMetadata() throws {
    let posts = try InstantReverseRelation<TypedUser, TypedPost>(validating: TypedPost.author)
    expectNoDifference(posts, TypedUser.posts)

    let editedPosts = try InstantReverseRelation<TypedUser, TypedPost>(validating: TypedPost.editor)
    expectNoDifference(editedPosts, TypedUser.editedPosts)
    expectNoDifference(editedPosts.name, "editedPosts")
    expectNoDifference(editedPosts.attributeID, "posts/editor")

    let editedPostsQuery = TypedUser.query.include(
      editedPosts,
      TypedPost.query.select(TypedPost.title)
    )
    expectNoDifference(
      editedPostsQuery.plan.includes,
      [
        InstantQueryInclude(
          "editedPosts",
          direction: .reverse,
          query: InstantQueryIncludePlan(
            id: TypedPost.query.select(TypedPost.title).plan.id,
            namespace: TypedPost.instantNamespace,
            selectedFields: ["title"]
          )
        )
      ]
    )

    do {
      _ = try InstantReverseRelation<TypedUser, TypedPost>(
        validating: InstantAttributePath<TypedPost, InstantID<TypedUser>>(
          "author",
          attributeID: "posts/editor"
        )
      )
      Issue.record("Expected reverse relation derivation to reject an id/name mismatch.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed)
      expectNoDifference(error.operation, "derive reverse include")
      expectNoDifference(error.namespace, "users")
      expectNoDifference(error.path, "author")
      #expect(error.message.contains("schema declares that id as 'editor'"))
    } catch {
      Issue.record("Unexpected error: \(error).")
    }

    do {
      _ = try InstantReverseRelation<TypedUser, TypedPost>(
        validating: InstantAttributePath<TypedPost, InstantID<TypedUser>>(
          "author",
          attributeID: "posts/missing"
        )
      )
      Issue.record("Expected reverse relation derivation to reject a missing explicit id.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed)
      expectNoDifference(error.operation, "derive reverse include")
      expectNoDifference(error.namespace, "users")
      expectNoDifference(error.path, "author")
      #expect(error.message.contains("schema declares 'author' as attribute id 'posts/author'"))
    } catch {
      Issue.record("Unexpected error: \(error).")
    }

    do {
      _ = try InstantReverseRelation<TypedMalformedReverseUser, TypedMalformedReversePost>(
        validating: TypedMalformedReversePost.author
      )
      Issue.record("Expected reverse relation derivation to reject an empty relation name.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed)
      expectNoDifference(error.operation, "derive reverse include")
      expectNoDifference(error.namespace, "malformedUsers")
      expectNoDifference(error.path, "author")
      #expect(error.message.contains("does not contain a relation name"))
    } catch {
      Issue.record("Unexpected error: \(error).")
    }
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
  func typedQueryOnceDecodedReturnsPageInfo() async throws {
    let cacheURL = try typedTestCacheURL("typed-query-once-decoded")
    let fixedDate = Date(timeIntervalSince1970: 1_700_000_410)
    let fixedUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000410")!

    try await withDependencies {
      $0.date.now = fixedDate
      $0.uuid = .constant(fixedUUID)
      try await $0.bootstrapInstantSwiftData(
        appID: "typed-query-once-decoded",
        persistenceURL: cacheURL,
        context: .test,
        initialAttributes: TypedTodo.instantAttributes
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var db

      try await db.transact(
        id: "tx-typed-query-once-first",
        createdAt: InstantTimestamp(milliseconds: 1_700_000_410_010)
      ) {
        TypedTodo.create(
          id: InstantID(rawValue: "todo-query-once-first"),
          TypedTodo.text.set("First page"),
          TypedTodo.isCompleted.set(false),
          TypedTodo.createdAt.set(fixedDate)
        )
      }
      try await db.transact(
        id: "tx-typed-query-once-second",
        createdAt: InstantTimestamp(milliseconds: 1_700_000_410_020)
      ) {
        TypedTodo.create(
          id: InstantID(rawValue: "todo-query-once-second"),
          TypedTodo.text.set("Second page"),
          TypedTodo.isCompleted.set(false),
          TypedTodo.createdAt.set(fixedDate.addingTimeInterval(1))
        )
      }

      let page = try await db.queryOnceDecoded(
        TypedTodo.query
          .order(TypedTodo.createdAt)
          .first(1)
      )

      expectNoDifference(page.values.map(\.text), ["First page"])
      expectNoDifference(page.pageInfo?.hasNextPage, true)
      expectNoDifference(
        page.pageInfo?.endCursor,
        InstantQueryCursor(
          entityID: "todo-query-once-first",
          sortValue: .date(fixedDate),
          inclusive: false
        )
      )
    }
  }

  @Test
  func typedInfiniteQuerySubscriptionDecodesAndLoadsNextPage() async throws {
    let cacheURL = try typedTestCacheURL("typed-infinite-query")
    let fixedDate = Date(timeIntervalSince1970: 1_700_000_411)
    let fixedUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000411")!
    let query = TypedTodo.query
      .order(TypedTodo.createdAt)
      .limit(1)

    try await withDependencies {
      $0.date.now = fixedDate
      $0.uuid = .constant(fixedUUID)
      try await $0.bootstrapInstantSwiftData(
        appID: "typed-infinite-query",
        persistenceURL: cacheURL,
        context: .test,
        initialAttributes: TypedTodo.instantAttributes
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var db

      let subscription = await db.subscribeInfiniteQuery(query)
      defer { subscription.cancel() }
      var iterator = subscription.makeAsyncIterator()

      let empty = try #require(await iterator.next())
      expectNoDifference(empty.values, [])
      expectNoDifference(empty.canLoadNextPage, false)
      expectNoDifference(empty.error, nil)

      try await db.transact(
        id: "tx-typed-infinite-create",
        createdAt: InstantTimestamp(milliseconds: 1_700_000_411_010)
      ) {
        TypedTodo.create(
          id: InstantID(rawValue: "todo-infinite-first"),
          TypedTodo.text.set("First infinite page"),
          TypedTodo.isCompleted.set(false),
          TypedTodo.createdAt.set(fixedDate)
        )
        TypedTodo.create(
          id: InstantID(rawValue: "todo-infinite-second"),
          TypedTodo.text.set("Second infinite page"),
          TypedTodo.isCompleted.set(false),
          TypedTodo.createdAt.set(fixedDate.addingTimeInterval(1))
        )
      }

      let firstPage = try #require(await iterator.next())
      expectNoDifference(firstPage.values.map(\.text), ["First infinite page"])
      expectNoDifference(firstPage.canLoadNextPage, true)
      expectNoDifference(firstPage.error, nil)
      expectNoDifference(firstPage.pageInfo?.endCursor?.entityID, "todo-infinite-first")

      let initialSnapshot = try await db.infiniteQueryInitialSnapshot(query)
      expectNoDifference(initialSnapshot.values.map(\.text), ["First infinite page"])
      expectNoDifference(initialSnapshot.canLoadNextPage, false)
      expectNoDifference(initialSnapshot.error, nil)
      expectNoDifference(initialSnapshot.pageInfo?.hasNextPage, true)

      subscription.loadNextPage()
      let secondPage = try #require(await iterator.next())
      expectNoDifference(
        secondPage.values.map(\.text),
        ["First infinite page", "Second infinite page"]
      )
      expectNoDifference(secondPage.canLoadNextPage, false)
      expectNoDifference(secondPage.error, nil)
      expectNoDifference(secondPage.pageInfo?.endCursor?.entityID, "todo-infinite-second")
    }
  }

  @Test
  func typedInfiniteQuerySubscriptionPreservesErrorSnapshotsAndRecovers() async throws {
    let error = InstantError(
      code: .validationFailed,
      operation: "validate infinite query",
      namespace: TypedTodo.instantNamespace,
      path: "createdAt",
      message: "Cannot page an invalid typed query.",
      recovery: "Use a schema-valid typed query before subscribing."
    )
    let rawStream = AsyncStream<InstantInfiniteQuerySnapshot>.makeStream(
      bufferingPolicy: .bufferingNewest(1)
    )
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
      observe: { _ in finiteStream([] as [InstantQueryEmission]) },
      subscribeInfiniteQuery: { _ in
        InstantInfiniteQuerySubscription(
          snapshots: rawStream.stream,
          loadNextPage: {},
          unsubscribe: {}
        )
      },
      pendingMutations: { [] },
      localID: { name in "typed-infinite-\(name)" }
    )

    let subscription = await client.subscribeInfiniteQuery(
      TypedTodo.query.order(TypedTodo.createdAt).limit(1)
    )
    defer { subscription.cancel() }
    var iterator = subscription.makeAsyncIterator()

    rawStream.continuation.yield(
      InstantInfiniteQuerySnapshot(
        queryID: TypedTodo.query.plan.id,
        sequence: 0,
        values: [],
        canLoadNextPage: false,
        error: error
      )
    )
    let errorSnapshot = try #require(await iterator.next())
    expectNoDifference(errorSnapshot.values, [])
    expectNoDifference(errorSnapshot.canLoadNextPage, false)
    expectNoDifference(errorSnapshot.error?.operation, "validate infinite query")
    expectNoDifference(errorSnapshot.error?.namespace, TypedTodo.instantNamespace)
    expectNoDifference(errorSnapshot.error?.path, "createdAt")

    rawStream.continuation.yield(
      InstantInfiniteQuerySnapshot(
        queryID: TypedTodo.query.plan.id,
        sequence: 1,
        values: [
          typedTodoSnapshot(
            id: "todo-infinite-recovery",
            text: "Recovered infinite page",
            isCompleted: false,
            createdAt: Date(timeIntervalSince1970: 1_700_000_412)
          )
        ],
        canLoadNextPage: false
      )
    )
    let recovered = try #require(await iterator.next())
    expectNoDifference(recovered.values.map(\.text), ["Recovered infinite page"])
    expectNoDifference(recovered.error, nil)
    rawStream.continuation.finish()
  }

  @Test
  func typedInfiniteQuerySubscriptionCancellationIsIdempotentAndStopsLoading() async throws {
    let recorder = InfiniteQuerySubscriptionRecorder()
    let rawStream = AsyncStream<InstantInfiniteQuerySnapshot>.makeStream(
      bufferingPolicy: .bufferingNewest(1)
    )
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
      observe: { _ in finiteStream([] as [InstantQueryEmission]) },
      subscribeInfiniteQuery: { _ in
        InstantInfiniteQuerySubscription(
          snapshots: rawStream.stream,
          loadNextPage: {
            Task {
              await recorder.recordLoadNextPage()
            }
          },
          unsubscribe: {
            Task {
              await recorder.recordUnsubscribe()
            }
          }
        )
      },
      pendingMutations: { [] },
      localID: { name in "typed-infinite-cancel-\(name)" }
    )

    let subscription = await client.subscribeInfiniteQuery(
      TypedTodo.query.order(TypedTodo.createdAt).limit(1)
    )

    subscription.loadNextPage()
    try await waitForTypedCondition(operation: "record initial infinite loadNextPage") {
      await recorder.counts().loadNextPageCount == 1
    }

    subscription.cancel()
    subscription.cancel()
    try await waitForTypedCondition(operation: "record single infinite unsubscribe") {
      await recorder.counts().unsubscribeCount == 1
    }

    subscription.loadNextPage()
    try await Task.sleep(nanoseconds: 20_000_000)
    let counts = await recorder.counts()
    expectNoDifference(counts.loadNextPageCount, 1)
    expectNoDifference(counts.unsubscribeCount, 1)
  }

  @Test
  func infiniteQueryWrapperTasksAndLoadsNextPageThroughProjectedState() async throws {
    let cacheURL = try typedTestCacheURL("infinite-query-wrapper")
    let fixedDate = Date(timeIntervalSince1970: 1_700_000_413)
    let fixedUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000413")!
    let query = TypedTodo.query
      .order(TypedTodo.createdAt)
      .limit(1)

    try await withDependencies {
      $0.date.now = fixedDate
      $0.uuid = .constant(fixedUUID)
      try await $0.bootstrapInstantSwiftData(
        appID: "infinite-query-wrapper",
        persistenceURL: cacheURL,
        context: .test,
        initialAttributes: TypedTodo.instantAttributes
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var db
      let client = db
      let infinite = InfiniteQuery<TypedTodo>(query)

      let task = Task {
        let infinite = infinite
        let client = client
        try await infinite.task(using: client)
      }
      defer {
        task.cancel()
      }

      try await client.transact(
        id: "tx-infinite-wrapper-create",
        createdAt: InstantTimestamp(milliseconds: 1_700_000_413_010)
      ) {
        TypedTodo.create(
          id: InstantID(rawValue: "todo-infinite-wrapper-first"),
          TypedTodo.text.set("First wrapper page"),
          TypedTodo.isCompleted.set(false),
          TypedTodo.createdAt.set(fixedDate)
        )
        TypedTodo.create(
          id: InstantID(rawValue: "todo-infinite-wrapper-second"),
          TypedTodo.text.set("Second wrapper page"),
          TypedTodo.isCompleted.set(false),
          TypedTodo.createdAt.set(fixedDate.addingTimeInterval(1))
        )
      }

      try await waitForTypedCondition(operation: "wait for first infinite wrapper page") {
        infinite.wrappedValue.map(\.text) == ["First wrapper page"]
      }
      expectNoDifference(infinite.canLoadNextPage, true)
      expectNoDifference(infinite.pageInfo?.endCursor?.entityID, "todo-infinite-wrapper-first")
      expectNoDifference(infinite.loadError, nil)
      expectNoDifference(infinite.isLoading, false)

      infinite.loadNextPage()
      try await waitForTypedCondition(operation: "wait for second infinite wrapper page") {
        infinite.wrappedValue.map(\.text) == ["First wrapper page", "Second wrapper page"]
      }
      expectNoDifference(infinite.canLoadNextPage, false)
      expectNoDifference(infinite.pageInfo?.endCursor?.entityID, "todo-infinite-wrapper-second")
      expectNoDifference(infinite.loadError, nil)
    }
  }

  @Test
  func infiniteQueryWrapperPreservesErrorSnapshotsAndRecovers() async throws {
    let error = InstantError(
      code: .validationFailed,
      operation: "validate infinite query",
      namespace: TypedTodo.instantNamespace,
      path: "createdAt",
      message: "Cannot page an invalid wrapper query.",
      recovery: "Use a schema-valid typed query before subscribing."
    )
    let rawStream = AsyncStream<InstantInfiniteQuerySnapshot>.makeStream(
      bufferingPolicy: .bufferingNewest(1)
    )
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
      observe: { _ in finiteStream([] as [InstantQueryEmission]) },
      subscribeInfiniteQuery: { _ in
        InstantInfiniteQuerySubscription(
          snapshots: rawStream.stream,
          loadNextPage: {},
          unsubscribe: {}
        )
      },
      pendingMutations: { [] },
      localID: { name in "infinite-wrapper-\(name)" }
    )
    let infinite = InfiniteQuery<TypedTodo>(TypedTodo.query.order(TypedTodo.createdAt).limit(1))

    let task = Task {
      let infinite = infinite
      let client = client
      try await infinite.task(using: client)
    }
    defer {
      task.cancel()
    }

    rawStream.continuation.yield(
      InstantInfiniteQuerySnapshot(
        queryID: TypedTodo.query.plan.id,
        sequence: 0,
        values: [],
        canLoadNextPage: false,
        error: error
      )
    )
    try await waitForTypedCondition(operation: "wait for infinite wrapper error state") {
      infinite.loadError?.operation == "validate infinite query"
    }
    expectNoDifference(infinite.wrappedValue, [])
    expectNoDifference(infinite.canLoadNextPage, false)

    rawStream.continuation.yield(
      InstantInfiniteQuerySnapshot(
        queryID: TypedTodo.query.plan.id,
        sequence: 1,
        values: [
          typedTodoSnapshot(
            id: "todo-infinite-wrapper-recovered",
            text: "Recovered wrapper page",
            isCompleted: false,
            createdAt: Date(timeIntervalSince1970: 1_700_000_414)
          )
        ],
        canLoadNextPage: false
      )
    )
    try await waitForTypedCondition(operation: "wait for infinite wrapper recovery") {
      infinite.wrappedValue.map(\.text) == ["Recovered wrapper page"]
    }
    expectNoDifference(infinite.loadError, nil)
    expectNoDifference(infinite.isLoading, false)
    rawStream.continuation.finish()
  }

  @Test
  func infiniteQueryWrapperCancelIsIdempotentAndStopsLoading() async throws {
    let recorder = InfiniteQuerySubscriptionRecorder()
    let rawStream = AsyncStream<InstantInfiniteQuerySnapshot>.makeStream(
      bufferingPolicy: .bufferingNewest(1)
    )
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
      observe: { _ in finiteStream([] as [InstantQueryEmission]) },
      subscribeInfiniteQuery: { _ in
        InstantInfiniteQuerySubscription(
          snapshots: rawStream.stream,
          loadNextPage: {
            Task {
              await recorder.recordLoadNextPage()
            }
          },
          unsubscribe: {
            Task {
              await recorder.recordUnsubscribe()
            }
          }
        )
      },
      pendingMutations: { [] },
      localID: { name in "infinite-wrapper-cancel-\(name)" }
    )
    let infinite = InfiniteQuery<TypedTodo>(TypedTodo.query.order(TypedTodo.createdAt).limit(1))

    let task = Task {
      let infinite = infinite
      let client = client
      try await infinite.task(using: client)
    }
    defer {
      task.cancel()
      rawStream.continuation.finish()
    }

    rawStream.continuation.yield(
      InstantInfiniteQuerySnapshot(
        queryID: TypedTodo.query.plan.id,
        sequence: 0,
        values: [],
        canLoadNextPage: true
      )
    )
    try await waitForTypedCondition(operation: "wait for active infinite wrapper subscription") {
      infinite.canLoadNextPage
    }

    infinite.loadNextPage()
    try await waitForTypedCondition(operation: "record wrapper infinite loadNextPage") {
      await recorder.counts().loadNextPageCount == 1
    }

    infinite.cancel()
    infinite.cancel()
    try await waitForTypedCondition(operation: "record single wrapper infinite unsubscribe") {
      await recorder.counts().unsubscribeCount == 1
    }
    expectNoDifference(infinite.isLoading, false)

    infinite.loadNextPage()
    try await Task.sleep(nanoseconds: 20_000_000)
    let counts = await recorder.counts()
    expectNoDifference(counts.loadNextPageCount, 1)
    expectNoDifference(counts.unsubscribeCount, 1)
  }

  @Test
  func typedQuerySelectsFieldsForSnapshotsAndCompleteDecoding() async throws {
    let cacheURL = try typedTestCacheURL("typed-field-selection")
    let fixedDate = Date(timeIntervalSince1970: 1_700_000_450)
    let fixedUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000450")!
    let todoID = InstantID<TypedTodo>(rawValue: "todo-selected")

    try await withDependencies {
      $0.date.now = fixedDate
      $0.uuid = .constant(fixedUUID)
      try await $0.bootstrapInstantSwiftData(
        appID: "typed-field-selection",
        persistenceURL: cacheURL,
        context: .test,
        initialAttributes: TypedTodo.instantAttributes
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var db

      try await db.transact {
        TypedTodo.create(
          id: todoID,
          TypedTodo.text.set("Project only what you need"),
          TypedTodo.isCompleted.set(false),
          TypedTodo.createdAt.set(fixedDate)
        )
      }

      let selectedSnapshots = try await db.query(
        TypedTodo.query
          .where(TypedTodo.isCompleted == false)
          .select(TypedTodo.text, TypedTodo.isCompleted)
          .plan
      )
      expectNoDifference(selectedSnapshots.map { $0.values.keys.sorted() }, [["isCompleted", "text"]])
      expectNoDifference(selectedSnapshots.first?.values["createdAt"], nil)

      let decodedTodos = try await db.query(
        TypedTodo.query
          .select(TypedTodo.text, TypedTodo.isCompleted, TypedTodo.createdAt)
      )
      expectNoDifference(
        decodedTodos,
        [
          TypedTodo(
            id: todoID,
            text: "Project only what you need",
            isCompleted: false,
            createdAt: fixedDate
          )
        ]
      )
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
  func generatedDraftSaveCreatesAndEditsEntities() async throws {
    let createdAt = Date(timeIntervalSince1970: 1_700_000_026)
    let fixedUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000526")!

    try await withDependencies {
      $0.date.now = createdAt
      $0.uuid = .constant(fixedUUID)
      try await $0.bootstrapInstantSwiftData(
        appID: "typed-draft-save-\(UUID().uuidString)",
        context: .test,
        initialAttributes: DraftBackedTodo.instantAttributes
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var db

      let draft = DraftBackedTodo.Draft(
        title: "Create from draft",
        isCompleted: false,
        createdAt: createdAt
      )
      expectNoDifference(draft.id, nil)
      expectNoDifference(draft.instantAssignments.map(\.attributeID), [
        "draftBackedTodos/body",
        "draftBackedTodos/isCompleted",
        "draftBackedTodos/createdAt",
        "draftBackedTodos/notes",
      ])
      expectNoDifference(
        draft.instantAssignments.map(\.attributeID).contains("draftBackedTodos/id"),
        false
      )
      let createdID = try await db.save(
        draft,
        localIDName: "typed.drafts.todo",
        transactionID: "tx-draft-create"
      )
      expectNoDifference(createdID.rawValue, fixedUUID.uuidString.lowercased())

      let createdTodos = try await db.query(DraftBackedTodo.query.order(DraftBackedTodo.createdAt))
      expectNoDifference(createdTodos, [
        DraftBackedTodo(
          id: createdID,
          title: "Create from draft",
          isCompleted: false,
          createdAt: createdAt,
          notes: nil
        )
      ])

      var editDraft = DraftBackedTodo.Draft(try #require(createdTodos.first))
      editDraft.title = "Update from draft"
      editDraft.isCompleted = true
      editDraft.notes = "Edited from a draft"
      let editedID = try await db.save(editDraft, transactionID: "tx-draft-edit")
      expectNoDifference(editedID, createdID)

      let upsertedID = InstantID<DraftBackedTodo>(rawValue: "draft-upserted")
      let upsertedDraft = DraftBackedTodo.Draft(
        id: upsertedID,
        title: "Upsert from draft",
        isCompleted: false,
        createdAt: createdAt.addingTimeInterval(1),
        notes: nil
      )
      let savedUpsertID = try await db.save(upsertedDraft, transactionID: "tx-draft-upsert")
      expectNoDifference(savedUpsertID, upsertedID)

      do {
        try await db.save(
          DraftBackedTodo.Draft(
            title: "Duplicate local id draft",
            isCompleted: false,
            createdAt: createdAt.addingTimeInterval(2),
            notes: nil
          ),
          localIDName: "typed.drafts.todo",
          transactionID: "tx-draft-duplicate-local-id"
        )
        #expect(Bool(false), "Expected strict create to reject a duplicate draft local id.")
      } catch let error as InstantError {
        expectNoDifference(error.code, .validationFailed)
        expectNoDifference(error.operation, "strict create entity")
        expectNoDifference(error.namespace, "draftBackedTodos")
        expectNoDifference(error.localID, createdID.rawValue)
      } catch {
        #expect(Bool(false), "Unexpected error: \(error)")
      }

      let editedTodos = try await db.query(DraftBackedTodo.query.order(DraftBackedTodo.createdAt))
      expectNoDifference(editedTodos, [
        DraftBackedTodo(
          id: createdID,
          title: "Update from draft",
          isCompleted: true,
          createdAt: createdAt,
          notes: "Edited from a draft"
        ),
        DraftBackedTodo(
          id: upsertedID,
          title: "Upsert from draft",
          isCompleted: false,
          createdAt: createdAt.addingTimeInterval(1),
          notes: nil
        )
      ])

      let pending = await db.pendingMutations()
      expectNoDifference(
        pending.map(\.id),
        ["tx-draft-create", "tx-draft-edit", "tx-draft-upsert"]
      )
    }
  }

  @Test
  func generatedDraftExcludesUndeclaredStoredFieldsFromAssignments()
    async throws
  {
    let recorder = TransactionRecorder()
    let fixedUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000527")!
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

    try await withDependencies {
      $0.date.now = Date(timeIntervalSince1970: 1_700_000_027)
      $0.uuid = .constant(fixedUUID)
      $0.defaultInstantSwiftData = mock
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var db

      let draft = DraftWithUndeclaredFieldTodo.Draft(title: "Draft with managed field")
      expectNoDifference(draft.instantAssignments.map(\.name), ["title"])
      expectNoDifference(draft.instantAssignments.map(\.attributeID), [
        "draftWithUndeclaredFieldTodos/title"
      ])

      let savedID = try await db.save(
        draft,
        transactionID: "tx-draft-managed-field-excluded"
      )
      expectNoDifference(savedID.rawValue, fixedUUID.uuidString.lowercased())

      do {
        try await db.transact(id: "tx-typed-undeclared-field") {
          TypedTodo.update(
            id: InstantID(rawValue: "todo-1"),
            InstantAttributeAssignment<TypedTodo>(
              name: "serverManaged",
              attributeID: "todos/serverManaged",
              value: .string("hidden")
            )
          )
        }
        #expect(Bool(false), "Expected undeclared typed assignment validation to fail.")
      } catch let error as InstantError {
        expectNoDifference(error.code, .validationFailed)
        expectNoDifference(error.operation, "write entity attribute")
        expectNoDifference(error.namespace, "todos")
        expectNoDifference(error.path, "serverManaged")
      } catch {
        #expect(Bool(false), "Unexpected error: \(error)")
      }
    }

    let transactions = await recorder.transactions
    expectNoDifference(transactions.map(\.id), ["tx-draft-managed-field-excluded"])
    expectNoDifference(
      transactions.first?.operations,
      [
        .requireEntityMissing(
          entityID: fixedUUID.uuidString.lowercased(),
          namespace: "draftWithUndeclaredFieldTodos"
        ),
        .insert(
          InstantTriple(
            entityID: fixedUUID.uuidString.lowercased(),
            attributeID: "draftWithUndeclaredFieldTodos/id",
            value: .string(fixedUUID.uuidString.lowercased()),
            txID: "tx-draft-managed-field-excluded",
            txTime: InstantTimestamp(milliseconds: 1_700_000_027_000)
          )
        ),
        .insert(
          InstantTriple(
            entityID: fixedUUID.uuidString.lowercased(),
            attributeID: "draftWithUndeclaredFieldTodos/title",
            value: .string("Draft with managed field"),
            txID: "tx-draft-managed-field-excluded",
            txTime: InstantTimestamp(milliseconds: 1_700_000_027_000)
          )
        ),
      ]
    )
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

      try await db.transact(id: "tx-create-todo") {
        TypedTodo.create(
          id: todoID,
          TypedTodo.text.set("Created"),
          TypedTodo.isCompleted.set(false),
          TypedTodo.createdAt.set(createdAt)
        )
      }
      try await db.transact(id: "tx-merge-todo") {
        TypedTodo.merge(
          id: todoID,
          TypedTodo.text.set("Merged")
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
      expectNoDifference(pending.map(\.id), ["tx-create-todo", "tx-merge-todo", "tx-strict-update-todo"])
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
  func typedQueryIncludesForwardAndReverseLinkedSnapshots() async throws {
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_105_000)
    let userID = InstantID<TypedUser>(rawValue: "included-user")
    let postID = InstantID<TypedPost>(rawValue: "included-post")

    try await withDependencies {
      try await $0.bootstrapInstantSwiftData(
        appID: "typed-includes-\(UUID().uuidString)",
        context: .test,
        initialAttributes: TypedUser.instantAttributes + TypedPost.instantAttributes
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var db

      try await db.transact(id: "tx-typed-include", createdAt: createdAt) {
        TypedUser.create(
          id: userID,
          TypedUser.name.set("Blob")
        )
        TypedPost.create(
          id: postID,
          TypedPost.title.set("Hello includes")
        )
        TypedPost.author.link(from: postID, to: userID)
      }

      let query = TypedPost.query.include(
        TypedPost.author,
        TypedUser.query.select(TypedUser.name)
      )
      let snapshots = try await db.query(query.plan)
      expectNoDifference(snapshots.map(\.id), [postID.rawValue])
      expectNoDifference(snapshots.first?.links?["author"]?.map(\.id), [userID.rawValue])
      expectNoDifference(
        snapshots.first?.links?["author"]?.first?.values,
        ["name": .one(.string("Blob"))]
      )

      let decodedPosts = try await db.query(query)
      expectNoDifference(
        decodedPosts,
        [TypedPost(id: postID, title: "Hello includes", authorID: userID)]
      )

      let hiddenByChildFilter = try await db.query(
        TypedPost.query
          .include(
            TypedPost.author,
            TypedUser.query.where(TypedUser.name == "Someone else").select(TypedUser.name)
          )
          .plan
      )
      expectNoDifference(hiddenByChildFilter.first?.links?["author"], [])

      let reverseQuery = TypedUser.query.include(
        TypedUser.posts,
        TypedPost.query.select(TypedPost.title)
      )
      let userSnapshots = try await db.query(reverseQuery.plan)
      expectNoDifference(userSnapshots.map(\.id), [userID.rawValue])
      expectNoDifference(userSnapshots.first?.links?["posts"]?.map(\.id), [postID.rawValue])
      expectNoDifference(
        userSnapshots.first?.links?["posts"]?.first?.values,
        ["title": .one(.string("Hello includes"))]
      )

      let decodedUsers = try await db.query(reverseQuery)
      expectNoDifference(decodedUsers, [TypedUser(id: userID, name: "Blob")])

      let hiddenReverseByChildFilter = try await db.query(
        TypedUser.query
          .include(
            TypedUser.posts,
            TypedPost.query.where(TypedPost.title == "Someone else").select(TypedPost.title)
          )
          .plan
      )
      expectNoDifference(hiddenReverseByChildFilter.first?.links?["posts"], [])
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
  func typedLookupDeleteScopesResolvedEntityToLookupNamespace() async throws {
    let sharedID = "typed-lookup-shared-raw-id"

    try await withDependencies {
      try await $0.bootstrapInstantSwiftData(
        appID: "typed-lookup-delete-scoped-\(UUID().uuidString)",
        context: .test,
        initialAttributes: TypedProfile.instantAttributes + TypedUser.instantAttributes
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var db

      try await db.transact(id: "tx-lookup-delete-shared-seed") {
        TypedProfile.create(
          id: InstantID(rawValue: sharedID),
          TypedProfile.handle.set("shared"),
          TypedProfile.metadata.set(.object(["kind": .string("profile")]))
        )
        TypedUser.create(
          id: InstantID(rawValue: sharedID),
          TypedUser.name.set("Shared User"),
          TypedUser.email.set("shared@example.com")
        )
      }

      try await db.transact(id: "tx-lookup-delete-profile") {
        TypedProfile.delete(lookup: TypedProfile.handle.lookup("shared"))
      }

      let profiles = try await db.query(TypedProfile.query)
      let users = try await db.query(TypedUser.query)
      expectNoDifference(profiles, [])
      expectNoDifference(users.map(\.id.rawValue), [sharedID])
      expectNoDifference(users.map(\.name), ["Shared User"])

      let pending = await db.pendingMutations()
      expectNoDifference(
        pending.first { $0.id == "tx-lookup-delete-profile" }?.transaction.operations,
        [
          .requireEntityExistsByLookup(
            TypedProfile.handle.lookup("shared").lookupRef,
            namespace: TypedProfile.instantNamespace
          ),
          .deleteEntityByLookup(TypedProfile.handle.lookup("shared").lookupRef),
        ]
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
        try await db.transact(id: "tx-mock-required-null") {
          TypedTodo.update(
            id: InstantID(rawValue: "todo-1"),
            InstantAttributeAssignment<TypedTodo>(
              name: "text",
              attributeID: "todos/text",
              value: .null
            )
          )
        }
        #expect(Bool(false), "Expected required null validation to run before the mock client.")
      } catch let error as InstantError {
        expectNoDifference(error.code, .validationFailed)
        expectNoDifference(error.operation, "write entity attribute")
        expectNoDifference(error.namespace, "todos")
        expectNoDifference(error.path, "text")
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

      let fetch = FetchAll<TypedTodo>(
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
  func bareFetchAllDefaultsToEntityQuery() async throws {
    let baseDate = Date(timeIntervalSince1970: 1_700_000_110)
    let fixedUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000674")!

    try await withDependencies {
      $0.date.now = baseDate
      $0.uuid = .constant(fixedUUID)
      try await $0.bootstrapInstantSwiftData(
        appID: "bare-fetch-all-\(UUID().uuidString)",
        context: .test,
        initialAttributes: TypedTodo.instantAttributes
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var db

      let firstID = InstantID<TypedTodo>(rawValue: "todo-bare-first")
      let secondID = InstantID<TypedTodo>(rawValue: "todo-bare-second")
      try await db.transact {
        TypedTodo.create(
          id: firstID,
          TypedTodo.text.set("Bare first"),
          TypedTodo.isCompleted.set(false),
          TypedTodo.createdAt.set(baseDate)
        )
        TypedTodo.create(
          id: secondID,
          TypedTodo.text.set("Bare second"),
          TypedTodo.isCompleted.set(true),
          TypedTodo.createdAt.set(baseDate.addingTimeInterval(1))
        )
      }

      @FetchAll var todos: [TypedTodo]
      expectNoDifference(todos, [])

      try await $todos.load()
      expectNoDifference(
        todos.map(\.id.rawValue).sorted(),
        ["todo-bare-first", "todo-bare-second"]
      )
      expectNoDifference($todos.loadError, nil)
      expectNoDifference($todos.isLoading, false)

      try await db.transact(id: "tx-bare-fetch-all-delete") {
        TypedTodo.delete(id: firstID)
        TypedTodo.delete(id: secondID)
      }
      try await $todos.load()
      expectNoDifference(todos, [])
      expectNoDifference($todos.loadError, nil)
    }
  }

  @Test
  func fetchAllReloadsAfterConcurrentCreatesAndDeletes() async throws {
    let baseDate = Date(timeIntervalSince1970: 1_700_000_120)
    let fixedUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000680")!
    let count = 100

    try await withDependencies {
      $0.date.now = baseDate
      $0.uuid = .constant(fixedUUID)
      try await $0.bootstrapInstantSwiftData(
        appID: "fetch-all-concurrency-\(UUID().uuidString)",
        context: .test,
        initialAttributes: TypedTodo.instantAttributes
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var db
      let client = db

      @FetchAll(TypedTodo.query.order(TypedTodo.createdAt)) var todos: [TypedTodo]
      expectNoDifference(todos, [])

      try await withThrowingTaskGroup(of: Void.self) { group in
        for index in 1...count {
          group.addTask {
            try await client.transact(id: "tx-fetch-all-concurrency-create-\(index)") {
              TypedTodo.create(
                id: InstantID(rawValue: "todo-concurrency-\(index)"),
                TypedTodo.text.set("Concurrent \(index)"),
                TypedTodo.isCompleted.set(false),
                TypedTodo.createdAt.set(baseDate.addingTimeInterval(Double(index)))
              )
            }
          }
        }
        try await group.waitForAll()
      }

      try await $todos.load()
      expectNoDifference(
        todos.map(\.id.rawValue),
        (1...count).map { "todo-concurrency-\($0)" }
      )
      expectNoDifference($todos.loadError, nil)
      expectNoDifference($todos.isLoading, false)

      try await withThrowingTaskGroup(of: Void.self) { group in
        for index in 1...(count / 2) {
          let evenIndex = index * 2
          group.addTask {
            try await client.transact(id: "tx-fetch-all-concurrency-delete-\(evenIndex)") {
              TypedTodo.delete(id: InstantID(rawValue: "todo-concurrency-\(evenIndex)"))
            }
          }
        }
        try await group.waitForAll()
      }

      try await $todos.load()
      expectNoDifference(
        todos.map(\.id.rawValue),
        (1...count).filter { !$0.isMultiple(of: 2) }.map { "todo-concurrency-\($0)" }
      )
      expectNoDifference($todos.loadError, nil)
      expectNoDifference($todos.isLoading, false)
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

      let fetch = FetchAll<TypedTodo>(
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
  func bareFetchAllSubscribeDefaultsToEntityQuery() async throws {
    let baseDate = Date(timeIntervalSince1970: 1_700_000_135)
    let fixedUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000675")!

    try await withDependencies {
      $0.date.now = baseDate
      $0.uuid = .constant(fixedUUID)
      try await $0.bootstrapInstantSwiftData(
        appID: "bare-fetch-all-subscription-\(UUID().uuidString)",
        context: .test,
        initialAttributes: TypedTodo.instantAttributes
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var db

      let fetch = FetchAll<TypedTodo>()
      let subscription = try await fetch.subscribe()
      var iterator = subscription.makeAsyncIterator()

      let initial = try await iterator.next()
      expectNoDifference(initial, [])

      try await db.transact {
        TypedTodo.create(
          id: InstantID(rawValue: "todo-bare-live"),
          TypedTodo.text.set("Bare live"),
          TypedTodo.isCompleted.set(false),
          TypedTodo.createdAt.set(baseDate)
        )
      }

      let updated = try await iterator.next()
      expectNoDifference(updated?.map(\.text), ["Bare live"])
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

      let fetch = FetchOne<TypedTodo?>(TypedTodo.query.order(TypedTodo.createdAt))
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
  func bareOptionalFetchOneDefaultsToEntityQuery() async throws {
    let baseDate = Date(timeIntervalSince1970: 1_700_000_155)
    let fixedUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000676")!

    try await withDependencies {
      $0.date.now = baseDate
      $0.uuid = .constant(fixedUUID)
      try await $0.bootstrapInstantSwiftData(
        appID: "bare-fetch-one-\(UUID().uuidString)",
        context: .test,
        initialAttributes: TypedTodo.instantAttributes
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var db

      let id = InstantID<TypedTodo>(rawValue: "todo-bare-one")
      try await db.transact {
        TypedTodo.create(
          id: id,
          TypedTodo.text.set("Bare one"),
          TypedTodo.isCompleted.set(false),
          TypedTodo.createdAt.set(baseDate)
        )
      }

      @FetchOne var todo: TypedTodo?
      expectNoDifference(todo, nil)

      try await $todo.load()
      expectNoDifference(todo?.text, "Bare one")
      expectNoDifference($todo.loadError, nil)
      expectNoDifference($todo.isLoading, false)

      try await db.transact(id: "tx-bare-fetch-one-delete") {
        TypedTodo.delete(id: id)
      }
      try await $todo.load()
      expectNoDifference(todo, nil)
      expectNoDifference($todo.loadError, nil)
    }
  }

  @Test
  func fetchOneInitializersPreserveDefaultsAndDelayedAssignment() async throws {
    @FetchOne var scalar = 42
    expectNoDifference(scalar, 42)
    expectNoDifference($scalar.loadError, nil)
    expectNoDifference($scalar.isLoading, false)

    let recorder = ClientCallRecorder()
    do {
      try await $scalar.load(using: recordingClient(recorder))
      #expect(Bool(false), "Expected a value-only FetchOne to require a configured query.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .implementationFailed)
      expectNoDifference(error.operation, "load FetchOne")
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }
    expectNoDifference(scalar, 42)
    expectNoDifference($scalar.loadError?.operation, "load FetchOne")
    let counts = await recorder.counts()
    expectNoDifference(counts.queryCount, 0)
    expectNoDifference(counts.observationCount, 0)

    let baseDate = Date(timeIntervalSince1970: 1_700_000_155.5)
    let fixedUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000682")!
    let defaultTodo = TypedTodo(
      id: InstantID(rawValue: "todo-default-optional"),
      text: "Default optional",
      isCompleted: false,
      createdAt: baseDate.addingTimeInterval(-1)
    )
    let delayedDefaultTodo = TypedTodo(
      id: InstantID(rawValue: "todo-delayed-default"),
      text: "Delayed default",
      isCompleted: false,
      createdAt: baseDate.addingTimeInterval(-2)
    )

    try await withDependencies {
      $0.date.now = baseDate
      $0.uuid = .constant(fixedUUID)
      try await $0.bootstrapInstantSwiftData(
        appID: "fetch-one-initializers-\(UUID().uuidString)",
        context: .test,
        initialAttributes: TypedTodo.instantAttributes
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var db

      let firstID = InstantID<TypedTodo>(rawValue: "todo-fetch-one-initializer-first")
      try await db.transact {
        TypedTodo.create(
          id: firstID,
          TypedTodo.text.set("Loaded optional"),
          TypedTodo.isCompleted.set(false),
          TypedTodo.createdAt.set(baseDate)
        )
      }

      @FetchOne var optionalTodo: TypedTodo? = defaultTodo
      expectNoDifference(optionalTodo?.text, "Default optional")
      try await $optionalTodo.load()
      expectNoDifference(optionalTodo?.text, "Loaded optional")
      expectNoDifference($optionalTodo.loadError, nil)

      try await db.transact(id: "tx-fetch-one-initializers-delete") {
        TypedTodo.delete(id: firstID)
      }
      try await $optionalTodo.load()
      expectNoDifference(optionalTodo, nil)
      expectNoDifference($optionalTodo.loadError, nil)

      var delayed = RequiredTypedTodoFetchOneModel(defaultTodo: delayedDefaultTodo)
      expectNoDifference(delayed.todo.text, "Delayed default")

      let secondID = InstantID<TypedTodo>(rawValue: "todo-fetch-one-initializer-second")
      try await db.transact(id: "tx-fetch-one-initializers-recreate") {
        TypedTodo.create(
          id: secondID,
          TypedTodo.text.set("Loaded delayed"),
          TypedTodo.isCompleted.set(false),
          TypedTodo.createdAt.set(baseDate.addingTimeInterval(1))
        )
      }
      try await delayed.load()
      expectNoDifference(delayed.todo.text, "Loaded delayed")
      expectNoDifference(delayed.$todo.loadError, nil)
    }
  }

  @Test
  func fetchOneScalarSelectionsPreserveSQLiteDataStatementSemantics() async throws {
    let baseDate = Date(timeIntervalSince1970: 1_700_000_155.75)
    let fixedUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000683")!

    try await withDependencies {
      $0.date.now = baseDate
      $0.uuid = .constant(fixedUUID)
      try await $0.bootstrapInstantSwiftData(
        appID: "fetch-one-scalar-selection-\(UUID().uuidString)",
        context: .test,
        initialAttributes: MacroGeneratedTodo.instantAttributes
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var db

      try await db.transact {
        MacroGeneratedTodo.create(
          id: InstantID(rawValue: "todo-scalar-first"),
          MacroGeneratedTodo.title.set("First scalar"),
          MacroGeneratedTodo.score.set(1),
          MacroGeneratedTodo.dueAt.set(baseDate),
          MacroGeneratedTodo.metadata.set(.object(["row": .string("first")])),
          MacroGeneratedTodo.isCompleted.set(false)
        )
        MacroGeneratedTodo.create(
          id: InstantID(rawValue: "todo-scalar-second"),
          MacroGeneratedTodo.title.set("Second scalar"),
          MacroGeneratedTodo.score.set(2),
          MacroGeneratedTodo.dueAt.set(nil),
          MacroGeneratedTodo.metadata.set(.object(["row": .string("second")])),
          MacroGeneratedTodo.isCompleted.set(true)
        )
      }

      let title = FetchOne(
        wrappedValue: "Default scalar",
        MacroGeneratedTodo.query.order(MacroGeneratedTodo.score),
        selecting: MacroGeneratedTodo.title
      )
      try await title.load()
      expectNoDifference(title.wrappedValue, "First scalar")
      expectNoDifference(title.loadError, nil)

      try await title.load(
        MacroGeneratedTodo.query.where(MacroGeneratedTodo.title == "Second scalar"),
        selecting: MacroGeneratedTodo.title
      )
      expectNoDifference(title.wrappedValue, "Second scalar")
      expectNoDifference(title.loadError, nil)

      do {
        try await title.load(
          MacroGeneratedTodo.query.where(MacroGeneratedTodo.title == "Missing scalar"),
          selecting: MacroGeneratedTodo.title
        )
        #expect(Bool(false), "Expected required scalar FetchOne selection to throw.")
      } catch let error as InstantError {
        expectNoDifference(error.code, .implementationFailed)
        expectNoDifference(error.operation, "load FetchOne")
        expectNoDifference(error.namespace, "macroGeneratedTodos")
      } catch {
        #expect(Bool(false), "Unexpected error: \(error)")
      }
      expectNoDifference(title.wrappedValue, "Second scalar")
      expectNoDifference(title.loadError?.operation, "load FetchOne")

      @FetchOne(
        MacroGeneratedTodo.query.order(MacroGeneratedTodo.score),
        selecting: MacroGeneratedTodo.dueAt
      )
      var dueAt: Date?
      try await $dueAt.load()
      expectNoDifference(dueAt, baseDate)
      expectNoDifference($dueAt.loadError, nil)

      @FetchOne(
        MacroGeneratedTodo.query.order(MacroGeneratedTodo.score),
        selecting: MacroGeneratedTodo.title
      )
      var optionalTitle: String?
      try await $optionalTitle.load()
      expectNoDifference(optionalTitle, "First scalar")
      expectNoDifference($optionalTitle.loadError, nil)

      try await $optionalTitle.load(
        MacroGeneratedTodo.query.where(MacroGeneratedTodo.title == "Missing scalar"),
        selecting: MacroGeneratedTodo.title
      )
      expectNoDifference(optionalTitle, nil)
      expectNoDifference($optionalTitle.loadError, nil)

      let missingTitleRecorder = ClientCallRecorder(queryResults: [
        [
          InstantEntitySnapshot(
            id: "todo-scalar-missing-title",
            namespace: MacroGeneratedTodo.instantNamespace,
            values: [
              "score": .one(.number(3))
            ]
          )
        ]
      ])
      try await $optionalTitle.load(
        MacroGeneratedTodo.query,
        selecting: MacroGeneratedTodo.title,
        using: recordingClient(missingTitleRecorder)
      )
      expectNoDifference(optionalTitle, nil)
      expectNoDifference($optionalTitle.loadError, nil)
      let missingTitlePlans = await missingTitleRecorder.queryPlans()
      expectNoDifference(missingTitlePlans.map(\.selectedFields), [["title"]])

      try await $dueAt.load(
        MacroGeneratedTodo.query.where(MacroGeneratedTodo.title == "Second scalar"),
        selecting: MacroGeneratedTodo.dueAt
      )
      expectNoDifference(dueAt, nil)
      expectNoDifference($dueAt.loadError, nil)

      try await $dueAt.load(
        MacroGeneratedTodo.query.where(MacroGeneratedTodo.title == "Missing scalar"),
        selecting: MacroGeneratedTodo.dueAt
      )
      expectNoDifference(dueAt, nil)
      expectNoDifference($dueAt.loadError, nil)
    }
  }

  @Test
  func fetchOneScalarSelectionsSubscribeAndTaskDecodePartialSnapshots() async throws {
    let titleSnapshot = InstantEntitySnapshot(
      id: "todo-scalar-subscribe",
      namespace: MacroGeneratedTodo.instantNamespace,
      values: [
        "title": .one(.string("Subscribed scalar"))
      ]
    )
    let fetch = FetchOne(
      wrappedValue: "Default subscription scalar",
      MacroGeneratedTodo.query,
      selecting: MacroGeneratedTodo.title
    )
    let subscription = try await fetch.subscribe(
      using: finiteObservationClient([[titleSnapshot]])
    )
    var iterator = subscription.makeAsyncIterator()
    let subscribedValue = try await iterator.next()
    let finishedValue = try await iterator.next()
    expectNoDifference(subscribedValue, "Subscribed scalar")
    expectNoDifference(finishedValue, nil)
    subscription.cancel()

    let taskSnapshot = InstantEntitySnapshot(
      id: "todo-scalar-task",
      namespace: MacroGeneratedTodo.instantNamespace,
      values: [
        "title": .one(.string("Task scalar"))
      ]
    )
    let taskFetch = FetchOne(
      wrappedValue: "Default task scalar",
      MacroGeneratedTodo.query,
      selecting: MacroGeneratedTodo.title
    )
    try await taskFetch.task(using: finiteObservationClient([[taskSnapshot]]))
    expectNoDifference(taskFetch.wrappedValue, "Task scalar")
    expectNoDifference(taskFetch.loadError, nil)
    expectNoDifference(taskFetch.isLoading, false)
  }

  @Test
  func fetchAllScalarSelectionsPreserveSQLiteDataSelectionSemantics() async throws {
    let baseDate = Date(timeIntervalSince1970: 1_700_000_205)
    let fixedUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000704")!

    try await withDependencies {
      $0.date.now = baseDate
      $0.uuid = .constant(fixedUUID)
      try await $0.bootstrapInstantSwiftData(
        appID: "fetch-all-scalar-selection-\(UUID().uuidString)",
        context: .test,
        initialAttributes: MacroGeneratedTodo.instantAttributes
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var db

      try await db.transact {
        MacroGeneratedTodo.create(
          id: InstantID(rawValue: "todo-scalar-all-first"),
          MacroGeneratedTodo.title.set("First scalar all"),
          MacroGeneratedTodo.score.set(1),
          MacroGeneratedTodo.dueAt.set(baseDate),
          MacroGeneratedTodo.metadata.set(.object(["row": .string("first")])),
          MacroGeneratedTodo.isCompleted.set(false)
        )
        MacroGeneratedTodo.create(
          id: InstantID(rawValue: "todo-scalar-all-second"),
          MacroGeneratedTodo.title.set("Second scalar all"),
          MacroGeneratedTodo.score.set(2),
          MacroGeneratedTodo.dueAt.set(nil),
          MacroGeneratedTodo.metadata.set(.object(["row": .string("second")])),
          MacroGeneratedTodo.isCompleted.set(true)
        )
        MacroGeneratedTodo.create(
          id: InstantID(rawValue: "todo-scalar-all-third"),
          MacroGeneratedTodo.title.set("Third scalar all"),
          MacroGeneratedTodo.score.set(3),
          MacroGeneratedTodo.dueAt.set(baseDate.addingTimeInterval(2)),
          MacroGeneratedTodo.metadata.set(.object(["row": .string("third")])),
          MacroGeneratedTodo.isCompleted.set(false)
        )
      }

      @FetchAll(
        MacroGeneratedTodo.query.order(MacroGeneratedTodo.score),
        selecting: MacroGeneratedTodo.title
      )
      var titles: [String]
      try await $titles.load()
      expectNoDifference(titles, ["First scalar all", "Second scalar all", "Third scalar all"])
      expectNoDifference($titles.loadError, nil)

      try await $titles.load(
        MacroGeneratedTodo.query
          .where(MacroGeneratedTodo.isCompleted == true)
          .order(MacroGeneratedTodo.score),
        selecting: MacroGeneratedTodo.title
      )
      expectNoDifference(titles, ["Second scalar all"])
      expectNoDifference($titles.loadError, nil)

      @FetchAll(
        MacroGeneratedTodo.query.order(MacroGeneratedTodo.score),
        selecting: MacroGeneratedTodo.dueAt
      )
      var dueDates: [Date?]
      try await $dueDates.load()
      expectNoDifference(dueDates, [baseDate, nil, baseDate.addingTimeInterval(2)])
      expectNoDifference($dueDates.loadError, nil)

      let requiredMissingRecorder = ClientCallRecorder(queryResults: [
        [
          InstantEntitySnapshot(
            id: "todo-scalar-all-missing-title",
            namespace: MacroGeneratedTodo.instantNamespace,
            values: [
              "score": .one(.number(4))
            ]
          )
        ]
      ])
      let requiredTitles = FetchAll<String>(
        wrappedValue: ["Cached scalar all"],
        MacroGeneratedTodo.query,
        selecting: MacroGeneratedTodo.title
      )
      do {
        try await requiredTitles.load(using: recordingClient(requiredMissingRecorder))
        Issue.record("Expected malformed selected FetchAll row to fail decoding.")
      } catch let error as InstantError {
        expectNoDifference(error.code, .decodeFailed)
        expectNoDifference(error.operation, "load FetchAll")
      }
      expectNoDifference(requiredTitles.wrappedValue, ["Cached scalar all"])
      expectNoDifference(requiredTitles.loadError?.operation, "load FetchAll")
      let requiredPlans = await requiredMissingRecorder.queryPlans()
      expectNoDifference(requiredPlans.map(\.selectedFields), [["title"]])

      let optionalMissingRecorder = ClientCallRecorder(queryResults: [
        [
          InstantEntitySnapshot(
            id: "todo-scalar-all-optional-missing",
            namespace: MacroGeneratedTodo.instantNamespace,
            values: [:]
          ),
          InstantEntitySnapshot(
            id: "todo-scalar-all-optional-present",
            namespace: MacroGeneratedTodo.instantNamespace,
            values: [
              "title": .one(.string("Present optional scalar all"))
            ]
          ),
        ]
      ])
      let optionalTitles = FetchAll<String?>(
        MacroGeneratedTodo.query,
        selecting: MacroGeneratedTodo.title
      )
      try await optionalTitles.load(using: recordingClient(optionalMissingRecorder))
      expectNoDifference(optionalTitles.wrappedValue, [nil, "Present optional scalar all"])
      expectNoDifference(optionalTitles.loadError, nil)
      let optionalPlans = await optionalMissingRecorder.queryPlans()
      expectNoDifference(optionalPlans.map(\.selectedFields), [["title"]])
    }
  }

  @Test
  func fetchAllScalarSelectionsSubscribeAndTaskDecodePartialSnapshots() async throws {
    let firstEmission = [
      InstantEntitySnapshot(
        id: "todo-scalar-all-subscribe-first",
        namespace: MacroGeneratedTodo.instantNamespace,
        values: [
          "title": .one(.string("Subscribed first scalar all"))
        ]
      ),
      InstantEntitySnapshot(
        id: "todo-scalar-all-subscribe-second",
        namespace: MacroGeneratedTodo.instantNamespace,
        values: [
          "title": .one(.string("Subscribed second scalar all"))
        ]
      ),
    ]
    let secondEmission = [
      InstantEntitySnapshot(
        id: "todo-scalar-all-subscribe-third",
        namespace: MacroGeneratedTodo.instantNamespace,
        values: [
          "title": .one(.string("Subscribed third scalar all"))
        ]
      )
    ]
    let fetch = FetchAll<String>(
      MacroGeneratedTodo.query,
      selecting: MacroGeneratedTodo.title
    )
    let subscription = try await fetch.subscribe(
      using: stagedObservationClient([firstEmission, secondEmission])
    )
    var iterator = subscription.makeAsyncIterator()
    let firstValue = try await iterator.next()
    let secondValue = try await iterator.next()
    let finishedValue = try await iterator.next()
    expectNoDifference(firstValue, [
      "Subscribed first scalar all",
      "Subscribed second scalar all",
    ])
    expectNoDifference(secondValue, ["Subscribed third scalar all"])
    expectNoDifference(finishedValue, nil)
    subscription.cancel()

    let taskFetch = FetchAll<String>(
      MacroGeneratedTodo.query,
      selecting: MacroGeneratedTodo.title
    )
    try await taskFetch.task(using: finiteObservationClient([firstEmission, secondEmission]))
    expectNoDifference(taskFetch.wrappedValue, ["Subscribed third scalar all"])
    expectNoDifference(taskFetch.loadError, nil)
    expectNoDifference(taskFetch.isLoading, false)
  }

  @Test
  func nonOptionalFetchOnePreservesLastValueWhenQueryIsEmpty() async throws {
    let baseDate = Date(timeIntervalSince1970: 1_700_000_156)
    let fixedUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000679")!
    let defaultTodo = TypedTodo(
      id: InstantID(rawValue: "todo-default"),
      text: "Default",
      isCompleted: false,
      createdAt: baseDate.addingTimeInterval(-1)
    )

    try await withDependencies {
      $0.date.now = baseDate
      $0.uuid = .constant(fixedUUID)
      try await $0.bootstrapInstantSwiftData(
        appID: "required-fetch-one-\(UUID().uuidString)",
        context: .test,
        initialAttributes: TypedTodo.instantAttributes
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var db

      let firstID = InstantID<TypedTodo>(rawValue: "todo-required-first")
      let secondID = InstantID<TypedTodo>(rawValue: "todo-required-second")
      try await db.transact {
        TypedTodo.create(
          id: firstID,
          TypedTodo.text.set("First required"),
          TypedTodo.isCompleted.set(false),
          TypedTodo.createdAt.set(baseDate)
        )
        TypedTodo.create(
          id: secondID,
          TypedTodo.text.set("Second required"),
          TypedTodo.isCompleted.set(false),
          TypedTodo.createdAt.set(baseDate.addingTimeInterval(1))
        )
      }

      let fetch = FetchOne(wrappedValue: defaultTodo, TypedTodo.query.order(TypedTodo.createdAt))
      try await fetch.load()
      expectNoDifference(fetch.wrappedValue.text, "First required")
      expectNoDifference(fetch.loadError, nil)

      do {
        try await fetch.load(TypedTodo.query.where(TypedTodo.text == "Missing"))
        #expect(Bool(false), "Expected non-optional FetchOne to throw when no entity matches.")
      } catch let error as InstantError {
        expectNoDifference(error.code, .implementationFailed)
        expectNoDifference(error.operation, "load FetchOne")
        expectNoDifference(error.namespace, "todos")
      } catch {
        #expect(Bool(false), "Unexpected error: \(error)")
      }
      expectNoDifference(fetch.wrappedValue.text, "First required")
      expectNoDifference(fetch.loadError?.operation, "load FetchOne")

      var model = RequiredTypedTodoFetchOneModel(defaultTodo: defaultTodo)
      try await model.load()
      expectNoDifference(model.todo.text, "First required")

      try await db.transact(id: "tx-required-fetch-one-delete") {
        TypedTodo.delete(id: firstID)
        TypedTodo.delete(id: secondID)
      }

      do {
        try await model.load()
        #expect(Bool(false), "Expected non-optional @FetchOne to throw after deleting all rows.")
      } catch let error as InstantError {
        expectNoDifference(error.code, .implementationFailed)
        expectNoDifference(error.operation, "load FetchOne")
        expectNoDifference(error.namespace, "todos")
      } catch {
        #expect(Bool(false), "Unexpected error: \(error)")
      }
      expectNoDifference(model.todo.text, "First required")
      expectNoDifference(model.$todo.loadError?.operation, "load FetchOne")
    }
  }

  @Test
  func nonOptionalFetchOneSubscriptionFailsWhenLiveQueryBecomesEmpty() async throws {
    let stream = AsyncStream<InstantQueryEmission>.makeStream()
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
      observe: { _ in stream.stream },
      pendingMutations: { [] },
      localID: { name in "mock-\(name)" }
    )
    let baseDate = Date(timeIntervalSince1970: 1_700_000_157)
    let fetch = FetchOne(
      wrappedValue: TypedTodo(
        id: InstantID(rawValue: "todo-live-required-default"),
        text: "Default",
        isCompleted: false,
        createdAt: baseDate.addingTimeInterval(-1)
      ),
      TypedTodo.query.order(TypedTodo.createdAt)
    )
    let subscription = try await fetch.subscribe(using: client)
    var iterator = subscription.makeAsyncIterator()

    stream.continuation.yield(
      InstantQueryEmission(
        queryID: "required-fetch-one-live",
        sequence: 0,
        values: [
          typedTodoSnapshot(
            id: "todo-live-required",
            text: "Live required",
            isCompleted: false,
            createdAt: baseDate
          )
        ],
        pageInfo: nil
      )
    )
    let first = try await iterator.next()
    expectNoDifference(first?.text, "Live required")

    stream.continuation.yield(
      InstantQueryEmission(
        queryID: "required-fetch-one-live",
        sequence: 1,
        values: [],
        pageInfo: nil
      )
    )
    do {
      _ = try await iterator.next()
      #expect(Bool(false), "Expected required FetchOne subscription to fail on an empty emission.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .implementationFailed)
      expectNoDifference(error.operation, "subscribe FetchOne")
      expectNoDifference(error.namespace, "todos")
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }
    expectNoDifference(fetch.wrappedValue.text, "Default")
    subscription.cancel()
    stream.continuation.finish()
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

      let fetch = FetchOne<TypedTodo?>(TypedTodo.query.order(TypedTodo.createdAt))
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

    let fetch = FetchAll<TypedTodo>(TypedTodo.query)
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

    let fetch = FetchAll<TypedTodo>(TypedTodo.query)
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

    let fetch = FetchOne<TypedTodo?>(TypedTodo.query)
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

      let fetch = Fetch<Int>(wrappedValue: 0) { client in
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
  func fetchKeyRequestLoadsTransactionStyleCompositeValues() async throws {
    let baseDate = Date(timeIntervalSince1970: 1_700_000_175.25)
    let fixedUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000705")!

    try await withDependencies {
      $0.date.now = baseDate
      $0.uuid = .constant(fixedUUID)
      try await $0.bootstrapInstantSwiftData(
        appID: "fetch-request-\(UUID().uuidString)",
        context: .test,
        initialAttributes: TypedTodo.instantAttributes
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var db
      let request = TypedTodoFactsRequest(
        rowsQuery: TypedTodo.query.order(TypedTodo.createdAt),
        countQuery: TypedTodo.query
      )

      @Fetch(request) var facts = TypedTodoFacts()
      expectNoDifference(facts, TypedTodoFacts())

      let firstID = InstantID<TypedTodo>(rawValue: "todo-fetch-request-first")
      let secondID = InstantID<TypedTodo>(rawValue: "todo-fetch-request-second")
      try await db.transact(id: "tx-fetch-request-create") {
        TypedTodo.create(
          id: firstID,
          TypedTodo.text.set("Transaction first"),
          TypedTodo.isCompleted.set(false),
          TypedTodo.createdAt.set(baseDate)
        )
        TypedTodo.create(
          id: secondID,
          TypedTodo.text.set("Transaction second"),
          TypedTodo.isCompleted.set(false),
          TypedTodo.createdAt.set(baseDate.addingTimeInterval(1))
        )
      }

      try await $facts.load()
      expectNoDifference(facts.todos.map(\.text), ["Transaction first", "Transaction second"])
      expectNoDifference(facts.count, 2)
      expectNoDifference($facts.loadError, nil)
      expectNoDifference($facts.isLoading, false)

      try await db.transact(id: "tx-fetch-request-delete") {
        TypedTodo.delete(id: firstID)
      }

      try await $facts.load(request)
      expectNoDifference(facts.todos.map(\.text), ["Transaction second"])
      expectNoDifference(facts.count, 1)
      expectNoDifference($facts.loadError, nil)
      expectNoDifference($facts.isLoading, false)

      let recorder = ClientCallRecorder(queryResults: [
        [
          typedTodoSnapshot(
            id: "todo-fetch-request-visible",
            text: "Visible row",
            isCompleted: false,
            createdAt: baseDate
          )
        ],
        [
          typedTodoSnapshot(
            id: "todo-fetch-request-counted-first",
            text: "Counted first",
            isCompleted: false,
            createdAt: baseDate
          ),
          typedTodoSnapshot(
            id: "todo-fetch-request-counted-second",
            text: "Counted second",
            isCompleted: false,
            createdAt: baseDate.addingTimeInterval(1)
          ),
        ],
      ])
      let visibleOpenRows = TypedTodoFactsRequest(
        rowsQuery: TypedTodo.query.where(TypedTodo.text == "Visible row"),
        countQuery: TypedTodo.query
      )
      let recordedFetch = Fetch(wrappedValue: TypedTodoFacts(), visibleOpenRows)
      try await recordedFetch.load(using: recordingClient(recorder))
      expectNoDifference(recordedFetch.wrappedValue.todos.map(\.text), ["Visible row"])
      expectNoDifference(recordedFetch.wrappedValue.count, 2)
      let plans = await recorder.queryPlans()
      expectNoDifference(plans.map(\.namespace), ["todos", "todos"])
      expectNoDifference(plans.count, 2)
    }
  }

  @Test
  func fetchKeyRequestTaskBindsCompositeSubscriptionValues() async throws {
    let baseDate = Date(timeIntervalSince1970: 1_700_000_175.35)
    let firstEmission = [
      typedTodoSnapshot(
        id: "todo-fetch-request-live-first",
        text: "Live transaction first",
        isCompleted: false,
        createdAt: baseDate
      )
    ]
    let secondEmission = [
      typedTodoSnapshot(
        id: "todo-fetch-request-live-first",
        text: "Live transaction first",
        isCompleted: false,
        createdAt: baseDate
      ),
      typedTodoSnapshot(
        id: "todo-fetch-request-live-second",
        text: "Live transaction second",
        isCompleted: false,
        createdAt: baseDate.addingTimeInterval(1)
      ),
    ]
    let fetch = Fetch(
      wrappedValue: TypedTodoFacts(),
      TypedTodoFactsRequest(
        rowsQuery: TypedTodo.query.order(TypedTodo.createdAt),
        countQuery: TypedTodo.query
      )
    )

    try await fetch.task(using: finiteObservationClient([firstEmission, secondEmission]))

    expectNoDifference(fetch.wrappedValue.todos.map(\.text), [
      "Live transaction first",
      "Live transaction second",
    ])
    expectNoDifference(fetch.wrappedValue.count, 2)
    expectNoDifference(fetch.loadError, nil)
    expectNoDifference(fetch.isLoading, false)
  }

  @Test
  func fetchKeyRequestLoadsDynamicRequestsAndRecordsPlans() async throws {
    let baseDate = Date(timeIntervalSince1970: 1_700_000_175.375)
    let open = typedTodoSnapshot(
      id: "todo-fetch-request-dynamic-open",
      text: "Dynamic open",
      isCompleted: false,
      createdAt: baseDate
    )
    let done = typedTodoSnapshot(
      id: "todo-fetch-request-dynamic-done",
      text: "Dynamic done",
      isCompleted: true,
      createdAt: baseDate.addingTimeInterval(1)
    )
    let recorder = ClientCallRecorder(queryResults: [
      [open],
      [open, done],
      [done],
      [open, done],
    ])
    let client = recordingClient(recorder)
    let fetch = Fetch(wrappedValue: TypedTodoFacts())

    try await fetch.load(
      TypedTodoFactsRequest(
        rowsQuery: TypedTodo.query
          .where(TypedTodo.isCompleted == false)
          .order(TypedTodo.createdAt),
        countQuery: TypedTodo.query
      ),
      using: client
    )
    expectNoDifference(fetch.wrappedValue.todos.map(\.text), ["Dynamic open"])
    expectNoDifference(fetch.wrappedValue.count, 2)

    try await fetch.load(
      TypedTodoFactsRequest(
        rowsQuery: TypedTodo.query
          .where(TypedTodo.isCompleted == true)
          .order(TypedTodo.createdAt),
        countQuery: TypedTodo.query
      ),
      using: client
    )

    expectNoDifference(fetch.wrappedValue.todos.map(\.text), ["Dynamic done"])
    expectNoDifference(fetch.wrappedValue.count, 2)
    expectNoDifference(fetch.loadError, nil)
    expectNoDifference(fetch.isLoading, false)
    let plans = await recorder.queryPlans()
    expectNoDifference(
      plans.map(\.filters),
      [
        [.equals(field: "isCompleted", value: .bool(false))],
        [],
        [.equals(field: "isCompleted", value: .bool(true))],
        [],
      ]
    )
    expectNoDifference(
      plans.map(\.order),
      [
        InstantQueryOrder("createdAt"),
        nil,
        InstantQueryOrder("createdAt"),
        nil,
      ]
    )
    let counts = await recorder.counts()
    expectNoDifference(counts.queryCount, 4)
    expectNoDifference(counts.observationCount, 0)
  }

  @Test
  func fetchKeyRequestLoadNilRequestResetsDefaultValueWithoutCallingClient() async throws {
    let fetch = Fetch(wrappedValue: TypedTodoFacts())
    fetch.wrappedValue = TypedTodoFacts(
      todos: [
        TypedTodo(
          id: InstantID(rawValue: "todo-fetch-request-cached"),
          text: "Cached request value",
          isCompleted: false,
          createdAt: Date(timeIntervalSince1970: 1_700_000_175.385)
        )
      ],
      count: 1
    )
    fetch.loadError = InstantError(
      code: .implementationFailed,
      operation: "previous Fetch request load",
      message: "previous failure",
      recovery: "Retry with a request."
    )
    fetch.isLoading = true
    let recorder = ClientCallRecorder()

    try await fetch.load(nil as TypedTodoFactsRequest?, using: recordingClient(recorder))

    expectNoDifference(fetch.wrappedValue, TypedTodoFacts())
    expectNoDifference(fetch.loadError, nil)
    expectNoDifference(fetch.isLoading, false)
    let counts = await recorder.counts()
    expectNoDifference(counts.queryCount, 0)
    expectNoDifference(counts.observationCount, 0)
  }

  @Test
  func fetchKeyRequestSubscribeNilRequestReturnsFinishedSubscriptionWithoutCallingClient()
    async throws
  {
    let fetch = Fetch(wrappedValue: TypedTodoFacts())
    fetch.wrappedValue = TypedTodoFacts(
      todos: [
        TypedTodo(
          id: InstantID(rawValue: "todo-fetch-request-subscribe-cached"),
          text: "Cached subscribed request value",
          isCompleted: false,
          createdAt: Date(timeIntervalSince1970: 1_700_000_175.395)
        )
      ],
      count: 1
    )
    let recorder = ClientCallRecorder()

    let subscription = try await fetch.subscribe(
      nil as TypedTodoFactsRequest?,
      using: recordingClient(recorder)
    )
    var iterator = subscription.makeAsyncIterator()
    let first = try await iterator.next()

    #expect(first == nil)
    try await subscription.task
    expectNoDifference(fetch.wrappedValue, TypedTodoFacts())
    expectNoDifference(fetch.loadError, nil)
    expectNoDifference(fetch.isLoading, false)
    let counts = await recorder.counts()
    expectNoDifference(counts.queryCount, 0)
    expectNoDifference(counts.observationCount, 0)
  }

  @Test
  func fetchKeyRequestTaskNilRequestDoesNotStartObservationAndClearsLoading() async throws {
    let fetch = Fetch(wrappedValue: TypedTodoFacts())
    fetch.wrappedValue = TypedTodoFacts(
      todos: [
        TypedTodo(
          id: InstantID(rawValue: "todo-fetch-request-task-cached"),
          text: "Cached task request value",
          isCompleted: false,
          createdAt: Date(timeIntervalSince1970: 1_700_000_175.405)
        )
      ],
      count: 1
    )
    fetch.isLoading = true
    let recorder = ClientCallRecorder()

    try await fetch.task(nil as TypedTodoFactsRequest?, using: recordingClient(recorder))

    expectNoDifference(fetch.wrappedValue, TypedTodoFacts())
    expectNoDifference(fetch.loadError, nil)
    expectNoDifference(fetch.isLoading, false)
    let counts = await recorder.counts()
    expectNoDifference(counts.queryCount, 0)
    expectNoDifference(counts.observationCount, 0)
  }

  @Test
  func fetchKeyRequestDynamicTaskCancellationStopsStaleEmissions() async throws {
    let baseDate = Date(timeIntervalSince1970: 1_700_000_175.415)
    let recorder = DynamicRequestObservationRecorder()
    let client = dynamicRequestObservationClient(recorder)
    let fetch = Fetch(wrappedValue: TypedTodoFacts())
    let openRequest = TypedTodoFactsRequest(
      rowsQuery: TypedTodo.query
        .where(TypedTodo.isCompleted == false)
        .order(TypedTodo.createdAt),
      countQuery: TypedTodo.query
    )
    let doneRequest = TypedTodoFactsRequest(
      rowsQuery: TypedTodo.query
        .where(TypedTodo.isCompleted == true)
        .order(TypedTodo.createdAt),
      countQuery: TypedTodo.query
    )

    let openTask = Task {
      let fetch = fetch
      try await fetch.task(openRequest, using: client)
    }
    try await waitForTypedCondition(
      operation: "wait for first dynamic Fetch request observation"
    ) {
      await recorder.counts().observationCount == 1
    }
    await recorder.yield(
      .open,
      values: [
        typedTodoSnapshot(
          id: "todo-fetch-request-live-open",
          text: "Live open",
          isCompleted: false,
          createdAt: baseDate
        )
      ]
    )
    try await waitForTypedCondition(
      operation: "wait for first dynamic Fetch request value"
    ) {
      fetch.wrappedValue.todos.map(\.text) == ["Live open"]
    }

    openTask.cancel()
    do {
      try await openTask.value
      Issue.record("Expected first dynamic Fetch request task cancellation to throw.")
    } catch is CancellationError {
    } catch {
      Issue.record("Expected CancellationError, got \(error).")
    }
    try await waitForTypedCondition(
      operation: "wait for first dynamic Fetch request termination"
    ) {
      await recorder.counts().terminationCount == 1
    }

    let doneTask = Task {
      let fetch = fetch
      try await fetch.task(doneRequest, using: client)
    }
    try await waitForTypedCondition(
      operation: "wait for second dynamic Fetch request observation"
    ) {
      await recorder.counts().observationCount == 2
    }
    await recorder.yield(
      .done,
      values: [
        typedTodoSnapshot(
          id: "todo-fetch-request-live-done",
          text: "Live done",
          isCompleted: true,
          createdAt: baseDate.addingTimeInterval(1)
        )
      ]
    )
    try await waitForTypedCondition(
      operation: "wait for second dynamic Fetch request value"
    ) {
      fetch.wrappedValue.todos.map(\.text) == ["Live done"]
    }

    await recorder.yield(
      .open,
      values: [
        typedTodoSnapshot(
          id: "todo-fetch-request-live-stale",
          text: "Stale open",
          isCompleted: false,
          createdAt: baseDate.addingTimeInterval(2)
        )
      ],
      sequence: 1
    )
    try await Task.sleep(nanoseconds: 10_000_000)

    expectNoDifference(fetch.wrappedValue.todos.map(\.text), ["Live done"])
    expectNoDifference(fetch.wrappedValue.count, 1)
    expectNoDifference(fetch.loadError, nil)
    expectNoDifference(fetch.isLoading, false)

    doneTask.cancel()
    do {
      try await doneTask.value
      Issue.record("Expected second dynamic Fetch request task cancellation to throw.")
    } catch is CancellationError {
    } catch {
      Issue.record("Expected CancellationError, got \(error).")
    }
    try await waitForTypedCondition(
      operation: "wait for second dynamic Fetch request termination"
    ) {
      await recorder.counts().terminationCount == 2
    }
    let plans = await recorder.queryPlans()
    expectNoDifference(
      plans.map(\.filters),
      [
        [.equals(field: "isCompleted", value: .bool(false))],
        [.equals(field: "isCompleted", value: .bool(true))],
      ]
    )
  }

  @Test
  func fetchKeyRequestNilResetCancelsLiveTaskAndIgnoresStaleEmissions() async throws {
    let baseDate = Date(timeIntervalSince1970: 1_700_000_175.425)
    let recorder = DynamicRequestObservationRecorder()
    let client = dynamicRequestObservationClient(recorder)
    let fetch = Fetch(wrappedValue: TypedTodoFacts())
    let request = TypedTodoFactsRequest(
      rowsQuery: TypedTodo.query
        .where(TypedTodo.isCompleted == false)
        .order(TypedTodo.createdAt),
      countQuery: TypedTodo.query
    )

    let liveTask = Task {
      let fetch = fetch
      try await fetch.task(request, using: client)
    }
    try await waitForTypedCondition(
      operation: "wait for live Fetch request observation before nil reset"
    ) {
      await recorder.counts().observationCount == 1
    }
    await recorder.yield(
      .open,
      values: [
        typedTodoSnapshot(
          id: "todo-fetch-request-live-before-reset",
          text: "Live before reset",
          isCompleted: false,
          createdAt: baseDate
        )
      ]
    )
    try await waitForTypedCondition(
      operation: "wait for live Fetch request value before nil reset"
    ) {
      fetch.wrappedValue.todos.map(\.text) == ["Live before reset"]
    }

    try await fetch.task(nil as TypedTodoFactsRequest?, using: client)

    expectNoDifference(fetch.wrappedValue, TypedTodoFacts())
    expectNoDifference(fetch.loadError, nil)
    expectNoDifference(fetch.isLoading, false)
    do {
      try await liveTask.value
      Issue.record("Expected nil request reset to cancel the live Fetch request task.")
    } catch is CancellationError {
    } catch {
      Issue.record("Expected CancellationError, got \(error).")
    }
    try await waitForTypedCondition(
      operation: "wait for live Fetch request termination after nil reset"
    ) {
      await recorder.counts().terminationCount == 1
    }

    await recorder.yield(
      .open,
      values: [
        typedTodoSnapshot(
          id: "todo-fetch-request-stale-after-reset",
          text: "Stale after reset",
          isCompleted: false,
          createdAt: baseDate.addingTimeInterval(1)
        )
      ],
      sequence: 1
    )
    try await Task.sleep(nanoseconds: 10_000_000)

    expectNoDifference(fetch.wrappedValue, TypedTodoFacts())
    expectNoDifference(fetch.loadError, nil)
    expectNoDifference(fetch.isLoading, false)
    let counts = await recorder.counts()
    expectNoDifference(counts.observationCount, 1)
    expectNoDifference(counts.terminationCount, 1)
  }

  @Test
  func fetchKeyRequestWithoutSubscriptionReportsTaskError() async throws {
    let fetch = Fetch(wrappedValue: 0, FetchOnlyCountRequest())

    do {
      try await fetch.task(using: recordingClient(ClientCallRecorder()))
      Issue.record("Expected fetch-only request task to fail without a subscription implementation.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .implementationFailed)
      expectNoDifference(error.operation, "subscribe Fetch")
    }

    expectNoDifference(fetch.wrappedValue, 0)
    expectNoDifference(fetch.loadError?.operation, "subscribe Fetch")
    expectNoDifference(fetch.isLoading, false)
  }

  @Test
  func fetchAllAndFetchReloadFilteredActiveRows() async throws {
    let baseDate = Date(timeIntervalSince1970: 1_700_000_175.5)
    let fixedUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000681")!

    try await withDependencies {
      $0.date.now = baseDate
      $0.uuid = .constant(fixedUUID)
      try await $0.bootstrapInstantSwiftData(
        appID: "fetch-filtered-reload-\(UUID().uuidString)",
        context: .test,
        initialAttributes: TypedTodo.instantAttributes
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var db
      let activeQuery = TypedTodo.query
        .where(TypedTodo.text == "Engineering")
        .where(TypedTodo.isCompleted == false)
        .order(TypedTodo.createdAt)

      @FetchAll(activeQuery) var activeTodos: [TypedTodo]
      @Fetch(
        wrappedValue: [],
        load: { client in
          try await client.query(activeQuery)
        }
      ) var fetchedActiveTodos: [TypedTodo]

      expectNoDifference(activeTodos, [])
      expectNoDifference(fetchedActiveTodos, [])

      let todoID = InstantID<TypedTodo>(rawValue: "todo-filtered-reload")
      try await db.transact(id: "tx-filtered-reload-create-active") {
        TypedTodo.create(
          id: todoID,
          TypedTodo.text.set("Engineering"),
          TypedTodo.isCompleted.set(false),
          TypedTodo.createdAt.set(baseDate)
        )
      }
      try await $activeTodos.load()
      try await $fetchedActiveTodos.load()
      expectNoDifference(activeTodos.map(\.text), ["Engineering"])
      expectNoDifference(fetchedActiveTodos.map(\.text), ["Engineering"])

      try await db.transact(id: "tx-filtered-reload-update-inactive") {
        TypedTodo.update(
          id: todoID,
          TypedTodo.isCompleted.set(true)
        )
      }
      try await $activeTodos.load()
      try await $fetchedActiveTodos.load()
      expectNoDifference(activeTodos, [])
      expectNoDifference(fetchedActiveTodos, [])

      try await db.transact(id: "tx-filtered-reload-update-active") {
        TypedTodo.update(
          id: todoID,
          TypedTodo.isCompleted.set(false)
        )
      }
      try await $activeTodos.load()
      try await $fetchedActiveTodos.load()
      expectNoDifference(activeTodos.map(\.text), ["Engineering"])
      expectNoDifference(fetchedActiveTodos.map(\.text), ["Engineering"])
      expectNoDifference($activeTodos.loadError, nil)
      expectNoDifference($fetchedActiveTodos.loadError, nil)
      expectNoDifference($activeTodos.isLoading, false)
      expectNoDifference($fetchedActiveTodos.isLoading, false)
    }
  }

  @Test
  func fetchWrappersLoadBasicSQLiteDataMatrix() async throws {
    let baseDate = Date(timeIntervalSince1970: 1_700_000_175.75)
    let fixedUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000683")!
    let recordIDs = [
      InstantID<TypedTodo>(rawValue: "todo-fetch-matrix-1"),
      InstantID<TypedTodo>(rawValue: "todo-fetch-matrix-2"),
      InstantID<TypedTodo>(rawValue: "todo-fetch-matrix-3"),
    ]
    let defaultTodo = TypedTodo(
      id: InstantID(rawValue: "todo-fetch-matrix-default"),
      text: "Default",
      isCompleted: false,
      createdAt: baseDate.addingTimeInterval(-1)
    )

    try await withDependencies {
      $0.date.now = baseDate
      $0.uuid = .constant(fixedUUID)
      try await $0.bootstrapInstantSwiftData(
        appID: "fetch-basic-matrix-\(UUID().uuidString)",
        context: .test,
        initialAttributes: TypedTodo.instantAttributes
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var db
      let orderedQuery = TypedTodo.query.order(TypedTodo.createdAt)
      let openQuery = TypedTodo.query
        .where(TypedTodo.isCompleted == false)
        .order(TypedTodo.createdAt)

      try await db.transact(id: "tx-fetch-basic-matrix-seed") {
        TypedTodo.create(
          id: recordIDs[0],
          TypedTodo.text.set("Record 1"),
          TypedTodo.isCompleted.set(true),
          TypedTodo.createdAt.set(baseDate)
        )
        TypedTodo.create(
          id: recordIDs[1],
          TypedTodo.text.set("Record 2"),
          TypedTodo.isCompleted.set(false),
          TypedTodo.createdAt.set(baseDate.addingTimeInterval(1))
        )
        TypedTodo.create(
          id: recordIDs[2],
          TypedTodo.text.set("Record 3"),
          TypedTodo.isCompleted.set(false),
          TypedTodo.createdAt.set(baseDate.addingTimeInterval(2))
        )
      }

      @FetchAll var allTodos: [TypedTodo]
      @FetchAll(openQuery) var openTodos: [TypedTodo]
      @FetchOne var optionalTodo: TypedTodo?
      @FetchOne var requiredTodo = defaultTodo
      @FetchOne(orderedQuery) var typedQueryTodo: TypedTodo?
      @Fetch(
        wrappedValue: 0,
        load: { client in
          try await client.query(openQuery).count
        }
      ) var openCount

      expectNoDifference(allTodos, [])
      expectNoDifference(openTodos, [])
      expectNoDifference(optionalTodo, nil)
      expectNoDifference(requiredTodo.text, "Default")
      expectNoDifference(typedQueryTodo, nil)
      expectNoDifference(openCount, 0)

      try await $allTodos.load()
      try await $openTodos.load()
      try await $optionalTodo.load()
      try await $requiredTodo.load()
      try await $typedQueryTodo.load()
      try await $openCount.load()

      expectNoDifference(allTodos.map(\.text).sorted(), ["Record 1", "Record 2", "Record 3"])
      expectNoDifference(openTodos.map(\.text), ["Record 2", "Record 3"])
      #expect(["Record 1", "Record 2", "Record 3"].contains(optionalTodo?.text))
      #expect(["Record 1", "Record 2", "Record 3"].contains(requiredTodo.text))
      expectNoDifference(typedQueryTodo?.text, "Record 1")
      expectNoDifference(openCount, 2)
      expectNoDifference($allTodos.loadError, nil)
      expectNoDifference($openTodos.loadError, nil)
      expectNoDifference($optionalTodo.loadError, nil)
      expectNoDifference($requiredTodo.loadError, nil)
      expectNoDifference($typedQueryTodo.loadError, nil)
      expectNoDifference($openCount.loadError, nil)

      let loadedRequiredText = requiredTodo.text
      try await db.transact(id: "tx-fetch-basic-matrix-delete") {
        for id in recordIDs {
          TypedTodo.delete(id: id)
        }
      }

      try await $allTodos.load()
      try await $openTodos.load()
      try await $optionalTodo.load()
      try await $typedQueryTodo.load()
      try await $openCount.load()
      do {
        try await $requiredTodo.load()
        #expect(Bool(false), "Expected required FetchOne to throw after deleting all records.")
      } catch let error as InstantError {
        expectNoDifference(error.code, .implementationFailed)
        expectNoDifference(error.operation, "load FetchOne")
        expectNoDifference(error.namespace, "todos")
      } catch {
        #expect(Bool(false), "Unexpected error: \(error)")
      }

      expectNoDifference(allTodos, [])
      expectNoDifference(openTodos, [])
      expectNoDifference(optionalTodo, nil)
      expectNoDifference(typedQueryTodo, nil)
      expectNoDifference(openCount, 0)
      expectNoDifference(requiredTodo.text, loadedRequiredText)
      expectNoDifference($requiredTodo.loadError?.operation, "load FetchOne")
    }
  }

  @Test
  func fetchWrappersDriveCaseStudiesListCountAndImperativeSnapshots() async throws {
    let baseDate = Date(timeIntervalSince1970: 1_700_000_175.875)
    let fixedUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000684")!

    try await withDependencies {
      $0.date.now = baseDate
      $0.uuid = .constant(fixedUUID)
      try await $0.bootstrapInstantSwiftData(
        appID: "fetch-case-studies-\(UUID().uuidString)",
        context: .test,
        initialAttributes: TypedTodo.instantAttributes
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var db
      @FetchAll(TypedTodo.query.order(TypedTodo.createdAt, .descending))
      var facts: [TypedTodo]
      @Fetch(
        wrappedValue: 0,
        load: { client in
          try await client.query(TypedTodo.query).count
        }
      )
      var factsCount

      try await db.transact(id: "tx-case-studies-facts-seed") {
        TypedTodo.create(
          id: InstantID(rawValue: "fact-1"),
          TypedTodo.text.set("Fact 1"),
          TypedTodo.isCompleted.set(false),
          TypedTodo.createdAt.set(baseDate)
        )
        TypedTodo.create(
          id: InstantID(rawValue: "fact-2"),
          TypedTodo.text.set("Fact 2"),
          TypedTodo.isCompleted.set(false),
          TypedTodo.createdAt.set(baseDate.addingTimeInterval(1))
        )
        TypedTodo.create(
          id: InstantID(rawValue: "fact-3"),
          TypedTodo.text.set("Fact 3"),
          TypedTodo.isCompleted.set(false),
          TypedTodo.createdAt.set(baseDate.addingTimeInterval(2))
        )
      }

      var reloadedSnapshots: [[String]] = []
      try await $facts.load()
      try await $factsCount.load()
      reloadedSnapshots.append(facts.map(\.text))

      expectNoDifference(facts.map(\.text), ["Fact 3", "Fact 2", "Fact 1"])
      expectNoDifference(factsCount, 3)
      expectNoDifference($facts.loadError, nil)
      expectNoDifference($factsCount.loadError, nil)
      expectNoDifference($facts.isLoading, false)
      expectNoDifference($factsCount.isLoading, false)

      let deletedID = try #require(facts.dropFirst().first?.id)
      try await db.transact(id: "tx-case-studies-facts-delete") {
        TypedTodo.delete(id: deletedID)
      }
      try await $facts.load()
      try await $factsCount.load()
      reloadedSnapshots.append(facts.map(\.text))

      expectNoDifference(facts.map(\.text), ["Fact 3", "Fact 1"])
      expectNoDifference(factsCount, 2)
      expectNoDifference(reloadedSnapshots, [
        ["Fact 3", "Fact 2", "Fact 1"],
        ["Fact 3", "Fact 1"],
      ])

      let liveFacts = FetchAll<TypedTodo>(
        TypedTodo.query.order(TypedTodo.createdAt, .descending)
      )
      let subscription = try await liveFacts.subscribe()
      var iterator = subscription.makeAsyncIterator()
      var appliedSnapshots: [[String]] = []

      let initialLiveFacts = try #require(try await iterator.next())
      appliedSnapshots.append(initialLiveFacts.map(\.text))

      try await db.transact(id: "tx-case-studies-facts-live-insert") {
        TypedTodo.create(
          id: InstantID(rawValue: "fact-4"),
          TypedTodo.text.set("Fact 4"),
          TypedTodo.isCompleted.set(false),
          TypedTodo.createdAt.set(baseDate.addingTimeInterval(3))
        )
      }
      let insertedLiveFacts = try #require(try await iterator.next())
      appliedSnapshots.append(insertedLiveFacts.map(\.text))

      try await db.transact(id: "tx-case-studies-facts-live-delete") {
        TypedTodo.delete(id: InstantID(rawValue: "fact-4"))
      }
      let deletedLiveFacts = try #require(try await iterator.next())
      appliedSnapshots.append(deletedLiveFacts.map(\.text))
      subscription.cancel()

      expectNoDifference(appliedSnapshots, [
        ["Fact 3", "Fact 1"],
        ["Fact 4", "Fact 3", "Fact 1"],
        ["Fact 3", "Fact 1"],
      ])
    }
  }

  @Test
  func fetchSubscribesToCustomDerivedValues() async throws {
    let baseDate = Date(timeIntervalSince1970: 1_700_000_176)
    let fixedUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000677")!

    try await withDependencies {
      $0.date.now = baseDate
      $0.uuid = .constant(fixedUUID)
      try await $0.bootstrapInstantSwiftData(
        appID: "fetch-custom-subscription-\(UUID().uuidString)",
        context: .test,
        initialAttributes: TypedTodo.instantAttributes
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var db

      let fetch = Fetch<Int>(
        wrappedValue: -1,
        load: { client in
          try await client.query(TypedTodo.query).count
        },
        subscribe: { client in
          await client.subscribe(TypedTodo.query.order(TypedTodo.createdAt)).map(\.count)
        }
      )
      let subscription = try await fetch.subscribe()
      var iterator = subscription.makeAsyncIterator()

      let initial = try await iterator.next()
      expectNoDifference(initial, 0)

      try await db.transact {
        TypedTodo.create(
          id: InstantID(rawValue: "todo-derived-count"),
          TypedTodo.text.set("Derived count"),
          TypedTodo.isCompleted.set(false),
          TypedTodo.createdAt.set(baseDate)
        )
      }

      let updated = try await iterator.next()
      expectNoDifference(updated, 1)
      expectNoDifference(fetch.loadError, nil)
      subscription.cancel()
    }
  }

  @Test
  func fetchTaskBindsCustomSubscriptionEmissionsIntoWrappedValue() async throws {
    let baseDate = Date(timeIntervalSince1970: 1_700_000_177)
    let client = finiteObservationClient([
      [],
      [
        typedTodoSnapshot(
          id: "todo-derived-first",
          text: "Derived first",
          isCompleted: false,
          createdAt: baseDate
        ),
        typedTodoSnapshot(
          id: "todo-derived-second",
          text: "Derived second",
          isCompleted: false,
          createdAt: baseDate.addingTimeInterval(1)
        ),
      ],
    ])

    let fetch = Fetch<Int>(
      wrappedValue: 0,
      load: { client in
        try await client.query(TypedTodo.query).count
      },
      subscribe: { client in
        await client.subscribe(TypedTodo.query).map(\.count)
      }
    )
    try await fetch.task(using: client)

    expectNoDifference(fetch.wrappedValue, 2)
    expectNoDifference(fetch.loadError, nil)
    expectNoDifference(fetch.isLoading, false)
  }

  @Test
  func fetchTaskPreservesLastValueAndRecordsDerivedError() async throws {
    let fetch = Fetch<Int>(
      wrappedValue: 0,
      load: { _ in 0 },
      subscribe: { _ in
        let stream = AsyncThrowingStream<Int, Error>.makeStream(
          bufferingPolicy: .bufferingNewest(1)
        )
        stream.continuation.yield(1)
        stream.continuation.finish(throwing: DerivedFetchFailure())
        return FetchSubscription(stream: stream.stream) {
          stream.continuation.finish()
        }
      }
    )

    do {
      try await fetch.task(using: mockClient(recording: ObservationTermination()))
      Issue.record("Expected derived subscription failure.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .implementationFailed)
      expectNoDifference(error.operation, "observe Fetch")
      expectNoDifference(fetch.loadError?.operation, "observe Fetch")
    } catch {
      Issue.record("Unexpected error: \(error).")
    }

    expectNoDifference(fetch.wrappedValue, 1)
    expectNoDifference(fetch.isLoading, false)
  }

  @Test
  func fetchTaskCancellationTerminatesUnderlyingObservation() async throws {
    let termination = ObservationTermination()
    let mock = mockClient(recording: termination)
    let fetch = Fetch<Int>(
      wrappedValue: 0,
      load: { client in
        try await client.query(TypedTodo.query).count
      },
      subscribe: { client in
        await client.subscribe(TypedTodo.query).map(\.count)
      }
    )
    let task = Task {
      let fetch = fetch
      try await fetch.task(using: mock)
    }

    try await Task.sleep(nanoseconds: 10_000_000)
    task.cancel()
    do {
      try await task.value
      Issue.record("Expected wrapper task cancellation to throw CancellationError.")
    } catch is CancellationError {
    } catch {
      Issue.record("Expected CancellationError, got \(error).")
    }
    await termination.wait()
    expectNoDifference(fetch.isLoading, false)
    expectNoDifference(fetch.loadError, nil)
  }

  @Test
  func fetchSubscribeWithoutOperationRecordsError() async throws {
    let fetch = Fetch<Int>(wrappedValue: 0)

    do {
      _ = try await fetch.subscribe(using: mockClient(recording: ObservationTermination()))
      Issue.record("Expected @Fetch without a subscribe operation to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .implementationFailed)
      expectNoDifference(error.operation, "subscribe Fetch")
      expectNoDifference(fetch.loadError?.operation, "subscribe Fetch")
      expectNoDifference(fetch.isLoading, false)
    } catch {
      Issue.record("Unexpected error: \(error).")
    }
  }

  @Test
  func projectedFetchLifecycleAPIsWorkFromImmutableModels() async throws {
    let baseDate = Date(timeIntervalSince1970: 1_700_000_178)
    let client = finiteObservationClient([
      [],
      [
        typedTodoSnapshot(
          id: "todo-immutable-wrapper",
          text: "Immutable wrapper",
          isCompleted: false,
          createdAt: baseDate
        )
      ],
    ])
    let model = ImmutableProjectedFetchLifecycleModel()

    try await model.exercise(using: client)

    expectNoDifference(model.todos.map(\.text), ["Immutable wrapper"])
    expectNoDifference(model.todo?.text, "Immutable wrapper")
    expectNoDifference(model.count, 1)
    expectNoDifference(model.$todos.loadError, nil)
    expectNoDifference(model.$todo.loadError, nil)
    expectNoDifference(model.$count.loadError, nil)
  }

  @Test
  func localIDPropertyWrapperStartsNil() {
    @LocalID("device") var localID: String?

    expectNoDifference(localID, nil)
    expectNoDifference($localID.loadError, nil)
    expectNoDifference($localID.isLoading, false)
  }

  @Test
  func localIDPropertyWrapperSupportsCachedInitialValue() {
    @LocalID("device") var localID: String? = "cached-device"

    expectNoDifference(localID, "cached-device")
    expectNoDifference($localID.loadError, nil)
    expectNoDifference($localID.isLoading, false)
  }

  @Test
  func localIDPropertyWrapperLoadsUsingDependencyClient() async throws {
    let recorder = LocalIDRecorder()
    let client = localIDClient(recorder)

    try await withDependencies {
      $0.defaultInstantSwiftData = client
    } operation: {
      @LocalID("device") var localID: String?

      try await $localID.load()

      expectNoDifference(localID, "local-id-device")
      expectNoDifference($localID.loadError, nil)
      expectNoDifference($localID.isLoading, false)
    }

    let recordedNames = await recorder.recordedNames()
    expectNoDifference(recordedNames, ["device"])
  }

  @Test
  func localIDPropertyWrapperReloadsWhenNameChanges() async throws {
    let recorder = LocalIDRecorder()
    let client = localIDClient(recorder)

    @LocalID("device") var localID: String?
    try await $localID.load(using: client)
    expectNoDifference(localID, "local-id-device")

    try await $localID.load("session", using: client)
    expectNoDifference(localID, "local-id-session")
    expectNoDifference($localID.loadError, nil)
    expectNoDifference($localID.isLoading, false)
    let recordedNames = await recorder.recordedNames()
    expectNoDifference(recordedNames, ["device", "session"])
  }

  @Test
  func localIDPropertyWrapperTaskBindsResolvedValue() async throws {
    let recorder = LocalIDRecorder()
    let client = localIDClient(recorder)

    @LocalID var localID: String?

    try await $localID.task("session", using: client)

    expectNoDifference(localID, "local-id-session")
    expectNoDifference($localID.loadError, nil)
    expectNoDifference($localID.isLoading, false)
    let recordedNames = await recorder.recordedNames()
    expectNoDifference(recordedNames, ["session"])
  }

  @Test
  func platformAdapterWrappersTaskBindFiniteSubscriptionEmissions() async throws {
    let client = adapterSurfaceClient()
    let room = InstantRoomHandle(type: "chat", id: "lobby")

    @LocalID var localID: String?
    try await $localID.task("compose", using: client)
    expectNoDifference(localID, "local-compose")
    expectNoDifference($localID.loadError, nil)
    expectNoDifference($localID.isLoading, false)

    let authSession = AuthSession()
    try await authSession.task(using: client)
    expectNoDifference(authSession.wrappedValue?.userID, "user-adapter")
    expectNoDifference(authSession.loadError, nil)
    expectNoDifference(authSession.isLoading, false)

    let presence = RoomPresence()
    try await presence.task(room: room, using: client)
    expectNoDifference(presence.wrappedValue.map(\.userID), ["presence-chat-lobby"])
    expectNoDifference(presence.loadError, nil)
    expectNoDifference(presence.isLoading, false)

    let messages = RoomTopicMessages()
    try await messages.task(room: room, topic: "sendEmoji", limit: 1, using: client)
    expectNoDifference(messages.wrappedValue.map(\.id), ["topic-sendEmoji-1"])
    expectNoDifference(messages.loadError, nil)
    expectNoDifference(messages.isLoading, false)

    let files = StoredFiles()
    try await files.task(using: client)
    expectNoDifference(files.wrappedValue.map(\.id), ["file-adapter"])
    expectNoDifference(files.loadError, nil)
    expectNoDifference(files.isLoading, false)

    let chunks = StreamChunks()
    try await chunks.task("chat/lobby", limit: 1, using: client)
    expectNoDifference(chunks.wrappedValue.map(\.id), ["chunk-chat/lobby-1"])
    expectNoDifference(chunks.loadError, nil)
    expectNoDifference(chunks.isLoading, false)

    let shares = Shares()
    try await shares.task(using: client)
    expectNoDifference(shares.wrappedValue.map(\.share.id), ["share-adapter"])
    expectNoDifference(shares.loadError, nil)
    expectNoDifference(shares.isLoading, false)
  }

  @Test
  func sharesTaskCancellationTerminatesUnderlyingObservation() async throws {
    let termination = ObservationTermination()
    let shares = Shares()
    let task = Task {
      try await shares.task(using: sharesObservationClient(recording: termination))
    }

    try await waitForShares(shares, ids: ["share-live"])

    task.cancel()
    do {
      try await task.value
      Issue.record("Expected @Shares task cancellation to throw CancellationError.")
    } catch is CancellationError {
    } catch {
      Issue.record("Expected CancellationError, got \(error).")
    }
    await termination.wait()
    expectNoDifference(shares.loadError, nil)
    expectNoDifference(shares.isLoading, false)
  }

  @Test
  func localIDPropertyWrapperRecordsMissingNameError() async throws {
    @LocalID var localID: String?

    do {
      try await $localID.load(using: localIDClient(LocalIDRecorder()))
      Issue.record("Expected @LocalID without a name to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .implementationFailed)
      expectNoDifference(error.operation, "load LocalID")
      expectNoDifference($localID.loadError?.operation, "load LocalID")
    } catch {
      Issue.record("Unexpected error: \(error).")
    }

    expectNoDifference(localID, nil)
    expectNoDifference($localID.isLoading, false)
  }

  @Test
  func localIDPropertyWrapperPreservesCachedValueAndRecordsError() async throws {
    let expectedError = InstantError(
      code: .implementationFailed,
      operation: "resolve test LocalID",
      message: "local id failed",
      recovery: "Retry with a working client."
    )
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
      localID: { _ in throw expectedError }
    )

    @LocalID("device") var localID: String? = "cached-device"

    do {
      try await $localID.load(using: client)
      Issue.record("Expected @LocalID to surface client failures.")
    } catch let error as InstantError {
      expectNoDifference(error.operation, "resolve test LocalID")
      expectNoDifference($localID.loadError?.operation, "resolve test LocalID")
    } catch {
      Issue.record("Unexpected error: \(error).")
    }

    expectNoDifference(localID, "cached-device")
    expectNoDifference($localID.isLoading, false)
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
  func typedMutationSurfaceIsClosedForInstamlPermissivenessParity() async throws {
    let source =
      "upstream/instant/client/packages/core/__tests__/src/instaml.test.ts "
      + "instatx should not be too permissive "
      + "[adapted: Swift has no dynamic unknown operation member; supported mutations lower to closed InstantTripleOperation cases.]"
    let time = InstantTimestamp(milliseconds: 1_700_000_220_000)
    let recorder = TransactionRecorder()
    let mock = InstantSwiftDataClient(
      transact: { transaction in
        await recorder.record(transaction)
        return InstantStoreMutationResult(
          transactionID: transaction.id,
          changedEntityIDs: ["todo-not-permissive"],
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
      $0.defaultInstantSwiftData = mock
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var db
      let result = try await db.transact(
        id: "tx-instaml-not-permissive",
        createdAt: time
      ) {
        TypedTodo.update(
          id: InstantID(rawValue: "todo-not-permissive"),
          TypedTodo.text.set("New Title")
        )
      }

      expectNoDifference(result.transactionID, "tx-instaml-not-permissive", source)
      expectNoDifference(result.tripleCount, 2, source)
    }

    let transactions = await recorder.transactions
    expectNoDifference(
      transactions,
      [
        InstantStoreTransaction(
          id: "tx-instaml-not-permissive",
          operations: [
            .insert(
              InstantTriple(
                entityID: "todo-not-permissive",
                attributeID: "todos/id",
                value: .string("todo-not-permissive"),
                txID: "tx-instaml-not-permissive",
                txTime: time
              )
            ),
            .insert(
              InstantTriple(
                entityID: "todo-not-permissive",
                attributeID: "todos/text",
                value: .string("New Title"),
                txID: "tx-instaml-not-permissive",
                txTime: time
              )
            ),
          ]
        )
      ],
      source
    )
  }

  @Test
  func typedTransactionBuilderSkipsEmptyMutationBody() async throws {
    let baseDate = Date(timeIntervalSince1970: 1_700_000_210)
    let fixedUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000988")!

    try await withDependencies {
      $0.date.now = baseDate
      $0.uuid = .constant(fixedUUID)
      try await $0.bootstrapInstantSwiftData(
        appID: "typed-empty-transact-\(UUID().uuidString)",
        context: .test,
        initialAttributes: TypedTodo.instantAttributes
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var db

      let empty = try await db.transact(id: "tx-empty-builder") {
      }
      expectNoDifference(empty.transactionID, "tx-empty-builder")
      expectNoDifference(empty.changedEntityIDs, [])
      expectNoDifference(empty.tripleCount, 0)
      let pendingAfterEmpty = await db.pendingMutations()
      expectNoDifference(pendingAfterEmpty, [])

      try await db.transact(id: "tx-empty-builder") {
        TypedTodo.create(
          id: InstantID(rawValue: "todo-after-empty-builder"),
          TypedTodo.text.set("After empty builder"),
          TypedTodo.isCompleted.set(false),
          TypedTodo.createdAt.set(baseDate)
        )
      }

      let todos = try await db.query(TypedTodo.query)
      expectNoDifference(todos.map(\.id.rawValue), ["todo-after-empty-builder"])
      let pendingAfterWrite = await db.pendingMutations()
      expectNoDifference(pendingAfterWrite.map(\.id), ["tx-empty-builder"])
    }
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

  @Test
  func fetchAllTaskBindsSubscriptionEmissionsIntoWrappedValue() async throws {
    let baseDate = Date(timeIntervalSince1970: 1_700_000_350)
    let client = finiteObservationClient([
      [],
      [
        typedTodoSnapshot(
          id: "todo-bound",
          text: "Bound through task",
          isCompleted: false,
          createdAt: baseDate
        )
      ],
    ])

    let fetch = FetchAll<TypedTodo>(TypedTodo.query.order(TypedTodo.createdAt))
    try await fetch.task(using: client)

    expectNoDifference(fetch.wrappedValue.map(\.text), ["Bound through task"])
    expectNoDifference(fetch.loadError, nil)
    expectNoDifference(fetch.isLoading, false)
  }

  @Test
  func fetchOneTaskBindsSubscriptionEmissionsIntoWrappedValue() async throws {
    let baseDate = Date(timeIntervalSince1970: 1_700_000_360)
    let client = finiteObservationClient([
      [],
      [
        typedTodoSnapshot(
          id: "todo-first-bound",
          text: "First bound",
          isCompleted: false,
          createdAt: baseDate
        ),
        typedTodoSnapshot(
          id: "todo-second-bound",
          text: "Second bound",
          isCompleted: false,
          createdAt: baseDate.addingTimeInterval(1)
        ),
      ],
    ])

    let fetch = FetchOne<TypedTodo?>(TypedTodo.query.order(TypedTodo.createdAt))
    try await fetch.task(using: client)

    expectNoDifference(fetch.wrappedValue?.text, "First bound")
    expectNoDifference(fetch.loadError, nil)
    expectNoDifference(fetch.isLoading, false)
  }

  @Test
  func fetchSubscriptionTaskCancelsUnderlyingObservation() async throws {
    let termination = ObservationTermination()
    let mock = mockClient(recording: termination)

    let fetch = FetchAll<TypedTodo>(TypedTodo.query)
    let subscription = try await fetch.subscribe(using: mock)
    let task = Task {
      try await subscription.task
    }

    task.cancel()
    do {
      try await task.value
      Issue.record("Expected parent task cancellation to throw CancellationError.")
    } catch is CancellationError {
    } catch {
      Issue.record("Expected CancellationError, got \(error).")
    }
    await termination.wait()
  }

  @Test
  func fetchSubscriptionTaskCompletesWhenSubscriptionExplicitlyCancelled() async throws {
    let termination = ObservationTermination()
    let mock = mockClient(recording: termination)

    let fetch = FetchAll<TypedTodo>(TypedTodo.query)
    let subscription = try await fetch.subscribe(using: mock)
    let task = Task {
      do {
        try await subscription.task
        return nil as String?
      } catch {
        return String(describing: error)
      }
    }

    try await Task.sleep(nanoseconds: 10_000_000)
    subscription.cancel()
    let error = await task.value

    await termination.wait()
    expectNoDifference(error, nil)
  }

  @Test
  func cancellingOneFetchSubscriptionDoesNotCancelAnother() async throws {
    let firstTermination = ObservationTermination()
    let secondTermination = ObservationTermination()
    let secondCompletion = CompletionFlag()

    let firstFetch = FetchAll<TypedTodo>(TypedTodo.query)
    let firstSubscription = try await firstFetch.subscribe(
      using: mockClient(recording: firstTermination)
    )
    let firstTask = Task {
      do {
        try await firstSubscription.task
        return nil as String?
      } catch {
        return String(describing: error)
      }
    }

    let secondFetch = FetchAll<TypedTodo>(TypedTodo.query)
    let secondSubscription = try await secondFetch.subscribe(
      using: mockClient(recording: secondTermination)
    )
    let secondTask = Task {
      do {
        try await secondSubscription.task
      } catch {
        await secondCompletion.recordError(String(describing: error))
      }
      await secondCompletion.record()
    }

    firstSubscription.cancel()
    let firstError = await firstTask.value
    await firstTermination.wait()
    try await Task.sleep(nanoseconds: 10_000_000)

    expectNoDifference(firstError, nil)
    #expect(await secondCompletion.value == false)

    secondSubscription.cancel()
    await secondTask.value
    await secondTermination.wait()
    #expect(await secondCompletion.value)
    let secondError = await secondCompletion.error
    expectNoDifference(secondError, nil)
  }

  @Test
  func fetchSubscriptionTaskDoesNotConsumeValues() async throws {
    let stream = AsyncThrowingStream<String, Error>.makeStream(
      bufferingPolicy: .bufferingNewest(1)
    )
    let subscription = FetchSubscription<String>(stream: stream.stream) {
      stream.continuation.finish()
    }
    let lifetime = Task {
      try await subscription.task
    }

    try await Task.sleep(nanoseconds: 10_000_000)
    stream.continuation.yield("visible to callers")
    stream.continuation.finish()

    var iterator = subscription.makeAsyncIterator()
    let value = try await iterator.next()
    expectNoDifference(value, "visible to callers")

    lifetime.cancel()
    do {
      try await lifetime.value
    } catch is CancellationError {
    }
  }

  @Test
  func fetchAllTaskCancellationTerminatesUnderlyingObservation() async throws {
    let termination = ObservationTermination()
    let mock = mockClient(recording: termination)
    let fetch = FetchAll<TypedTodo>(TypedTodo.query)
    let task = Task {
      let fetch = fetch
      try await fetch.task(using: mock)
    }

    try await Task.sleep(nanoseconds: 10_000_000)
    task.cancel()
    do {
      try await task.value
      Issue.record("Expected wrapper task cancellation to throw CancellationError.")
    } catch is CancellationError {
    } catch {
      Issue.record("Expected CancellationError, got \(error).")
    }
    await termination.wait()
    expectNoDifference(fetch.isLoading, false)
    expectNoDifference(fetch.loadError, nil)
  }

  @Test
  func fetchAllTaskPreservesLastValueAndRecordsDecodeError() async throws {
    let baseDate = Date(timeIntervalSince1970: 1_700_000_365)
    let client = stagedObservationClient([
      [
        typedTodoSnapshot(
          id: "todo-before-error",
          text: "Before error",
          isCompleted: false,
          createdAt: baseDate
        )
      ],
      [
        InstantEntitySnapshot(id: "todo-invalid", namespace: TypedTodo.instantNamespace, values: [:])
      ],
    ])

    let fetch = FetchAll<TypedTodo>(TypedTodo.query.order(TypedTodo.createdAt))
    do {
      try await fetch.task(using: client)
      Issue.record("Expected malformed subscription emission to fail decoding.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .decodeFailed)
    }

    #expect(fetch.wrappedValue.map(\.text) == ["Before error"])
    expectNoDifference(fetch.loadError?.code, .decodeFailed)
    expectNoDifference(fetch.isLoading, false)
  }

  @Test
  func fetchAllLoadPreservesLastValueAndRecordsDecodeError() async throws {
    let baseDate = Date(timeIntervalSince1970: 1_700_000_365.5)
    let todo = TypedTodo(
      id: InstantID(rawValue: "todo-before-load-error"),
      text: "Before load error",
      isCompleted: false,
      createdAt: baseDate
    )
    let recorder = ClientCallRecorder(
      queryResults: [
        [
          InstantEntitySnapshot(
            id: "todo-invalid-load",
            namespace: TypedTodo.instantNamespace,
            values: [:]
          )
        ]
      ]
    )
    let fetch = FetchAll<TypedTodo>(
      wrappedValue: [todo],
      TypedTodo.query.order(TypedTodo.createdAt)
    )

    do {
      try await fetch.load(using: recordingClient(recorder))
      Issue.record("Expected malformed query result to fail decoding.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .decodeFailed)
      expectNoDifference(error.operation, "decode typed todo")
    }

    expectNoDifference(fetch.wrappedValue.map(\.text), ["Before load error"])
    expectNoDifference(fetch.loadError?.code, .decodeFailed)
    expectNoDifference(fetch.loadError?.operation, "decode typed todo")
    expectNoDifference(fetch.isLoading, false)
    let counts = await recorder.counts()
    expectNoDifference(counts.queryCount, 1)
    expectNoDifference(counts.observationCount, 0)
  }

  @Test
  func fetchAllLoadNilQueryClearsResultsWithoutCallingClient() async throws {
    let todo = TypedTodo(
      id: InstantID(rawValue: "todo-nil-query"),
      text: "Cached",
      isCompleted: false,
      createdAt: Date(timeIntervalSince1970: 1_700_000_366)
    )
    let recorder = ClientCallRecorder()
    let fetch = FetchAll<TypedTodo>(wrappedValue: [todo], TypedTodo.query)
    fetch.loadError = InstantError(
      code: .implementationFailed,
      operation: "previous load",
      message: "previous failure",
      recovery: "Retry with a query."
    )
    fetch.isLoading = true

    try await fetch.load(nil as InstantEntityQuery<TypedTodo>?, using: recordingClient(recorder))

    expectNoDifference(fetch.wrappedValue, [])
    expectNoDifference(fetch.loadError, nil)
    expectNoDifference(fetch.isLoading, false)
    let counts = await recorder.counts()
    expectNoDifference(counts.queryCount, 0)
    expectNoDifference(counts.observationCount, 0)
  }

  @Test
  func fetchOneLoadNilQuerySetsOptionalValueToNilWithoutCallingClient() async throws {
    let todo = TypedTodo(
      id: InstantID(rawValue: "todo-one-nil-query"),
      text: "Cached one",
      isCompleted: false,
      createdAt: Date(timeIntervalSince1970: 1_700_000_367)
    )
    let recorder = ClientCallRecorder()
    let fetch = FetchOne<TypedTodo?>(wrappedValue: todo, TypedTodo.query)
    fetch.loadError = InstantError(
      code: .implementationFailed,
      operation: "previous optional load",
      message: "previous failure",
      recovery: "Retry with a query."
    )
    fetch.isLoading = true

    try await fetch.load(nil as InstantEntityQuery<TypedTodo>?, using: recordingClient(recorder))

    expectNoDifference(fetch.wrappedValue, nil)
    expectNoDifference(fetch.loadError, nil)
    expectNoDifference(fetch.isLoading, false)
    let counts = await recorder.counts()
    expectNoDifference(counts.queryCount, 0)
    expectNoDifference(counts.observationCount, 0)
  }

  @Test
  func fetchOneSubscribeNilQueryReturnsFinishedSubscriptionWithoutCallingClient() async throws {
    let todo = TypedTodo(
      id: InstantID(rawValue: "todo-one-subscribe-nil-query"),
      text: "Optional subscribe cached",
      isCompleted: false,
      createdAt: Date(timeIntervalSince1970: 1_700_000_367.5)
    )
    let recorder = ClientCallRecorder()
    let fetch = FetchOne<TypedTodo?>(wrappedValue: todo, TypedTodo.query)

    let subscription = try await fetch.subscribe(
      nil as InstantEntityQuery<TypedTodo>?,
      using: recordingClient(recorder)
    )
    var iterator = subscription.makeAsyncIterator()
    let first = try await iterator.next()

    #expect(first == nil)
    try await subscription.task
    expectNoDifference(fetch.wrappedValue, nil)
    expectNoDifference(fetch.loadError, nil)
    expectNoDifference(fetch.isLoading, false)
    let counts = await recorder.counts()
    expectNoDifference(counts.queryCount, 0)
    expectNoDifference(counts.observationCount, 0)
  }

  @Test
  func fetchAllTaskNilQueryDoesNotStartObservationAndClearsLoading() async throws {
    let todo = TypedTodo(
      id: InstantID(rawValue: "todo-task-nil-query"),
      text: "Task cached",
      isCompleted: false,
      createdAt: Date(timeIntervalSince1970: 1_700_000_368)
    )
    let recorder = ClientCallRecorder()
    let fetch = FetchAll<TypedTodo>(wrappedValue: [todo], TypedTodo.query)
    fetch.isLoading = true

    try await fetch.task(nil as InstantEntityQuery<TypedTodo>?, using: recordingClient(recorder))

    expectNoDifference(fetch.wrappedValue, [])
    expectNoDifference(fetch.loadError, nil)
    expectNoDifference(fetch.isLoading, false)
    let counts = await recorder.counts()
    expectNoDifference(counts.queryCount, 0)
    expectNoDifference(counts.observationCount, 0)
  }

  @Test
  func fetchOneTaskNilQueryDoesNotStartObservationAndClearsLoading() async throws {
    let todo = TypedTodo(
      id: InstantID(rawValue: "todo-one-task-nil-query"),
      text: "Optional task cached",
      isCompleted: false,
      createdAt: Date(timeIntervalSince1970: 1_700_000_368.25)
    )
    let recorder = ClientCallRecorder()
    let fetch = FetchOne<TypedTodo?>(wrappedValue: todo, TypedTodo.query)
    fetch.isLoading = true

    try await fetch.task(nil as InstantEntityQuery<TypedTodo>?, using: recordingClient(recorder))

    expectNoDifference(fetch.wrappedValue, nil)
    expectNoDifference(fetch.loadError, nil)
    expectNoDifference(fetch.isLoading, false)
    let counts = await recorder.counts()
    expectNoDifference(counts.queryCount, 0)
    expectNoDifference(counts.observationCount, 0)
  }

  @Test
  func fetchAllSubscribeNilQueryReturnsFinishedSubscriptionWithoutCallingClient() async throws {
    let todo = TypedTodo(
      id: InstantID(rawValue: "todo-subscribe-nil-query"),
      text: "Subscribe cached",
      isCompleted: false,
      createdAt: Date(timeIntervalSince1970: 1_700_000_368.5)
    )
    let recorder = ClientCallRecorder()
    let fetch = FetchAll<TypedTodo>(wrappedValue: [todo], TypedTodo.query)

    let subscription = try await fetch.subscribe(
      nil as InstantEntityQuery<TypedTodo>?,
      using: recordingClient(recorder)
    )
    var iterator = subscription.makeAsyncIterator()
    let first = try await iterator.next()

    #expect(first == nil)
    try await subscription.task
    expectNoDifference(fetch.wrappedValue, [])
    expectNoDifference(fetch.loadError, nil)
    expectNoDifference(fetch.isLoading, false)
    let counts = await recorder.counts()
    expectNoDifference(counts.queryCount, 0)
    expectNoDifference(counts.observationCount, 0)
  }

  @Test
  func fetchAllDynamicQueryPreservesCachedPriorResultsOnNonNilError() async throws {
    let cached = typedTodoSnapshot(
      id: "todo-dynamic-cached",
      text: "Cached dynamic result",
      isCompleted: false,
      createdAt: Date(timeIntervalSince1970: 1_700_000_369)
    )
    let recorder = ClientCallRecorder(
      queryResults: [[cached]],
      fallbackError: InstantError(
        code: .implementationFailed,
        operation: "query dynamic FetchAll",
        message: "dynamic query failed",
        recovery: "Retry with a valid dynamic query."
      )
    )
    let client = recordingClient(recorder)
    let fetch = FetchAll<TypedTodo>(TypedTodo.query.order(TypedTodo.createdAt))

    try await fetch.load(TypedTodo.query.order(TypedTodo.createdAt), using: client)
    expectNoDifference(fetch.wrappedValue.map(\.text), ["Cached dynamic result"])

    do {
      try await fetch.load(
        TypedTodo.query.where(TypedTodo.text == "missing"),
        using: client
      )
      Issue.record("Expected non-nil dynamic query failure.")
    } catch let error as InstantError {
      expectNoDifference(error.operation, "query dynamic FetchAll")
    } catch {
      Issue.record("Unexpected error: \(error).")
    }

    expectNoDifference(fetch.wrappedValue.map(\.text), ["Cached dynamic result"])
    expectNoDifference(fetch.loadError?.operation, "query dynamic FetchAll")
    expectNoDifference(fetch.isLoading, false)
    let counts = await recorder.counts()
    expectNoDifference(counts.queryCount, 2)
    expectNoDifference(counts.observationCount, 0)
  }

  #if canImport(Observation)
    @Test
    func observableModelCaseStudyWritesCountsAndDeletesThroughWrappers() async throws {
      let baseDate = Date(timeIntervalSince1970: 1_700_000_369.125)
      let fixedUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000705")!

      try await withDependencies {
        $0.date.now = baseDate
        $0.uuid = .constant(fixedUUID)
        try await $0.bootstrapInstantSwiftData(
          appID: "observable-case-studies-\(UUID().uuidString)",
          context: .test,
          initialAttributes: TypedTodo.instantAttributes
        )
      } operation: {
        let model = TypedTodoObservableFactsModel()
        let titleChange = ObservationChangeFlag()
        let initialTitles = withObservationTracking {
          model.visibleTitles
        } onChange: {
          titleChange.record()
        }
        expectNoDifference(initialTitles, [])

        try await model.increment(body: "Observable fact 1", createdAt: baseDate)
        try await model.increment(
          body: "Observable fact 2",
          createdAt: baseDate.addingTimeInterval(1)
        )

        expectNoDifference(model.number, 2)
        expectNoDifference(model.facts.map(\.text), [
          "Observable fact 2",
          "Observable fact 1",
        ])
        expectNoDifference(model.visibleTitles, [
          "Observable fact 2",
          "Observable fact 1",
        ])
        expectNoDifference(model.factsCount, 2)
        expectNoDifference(model.$facts.loadError, nil)
        expectNoDifference(model.$factsCount.loadError, nil)
        #expect(titleChange.value)

        try await model.deleteFact(indices: IndexSet(integer: 0))

        expectNoDifference(model.facts.map(\.text), ["Observable fact 1"])
        expectNoDifference(model.visibleTitles, ["Observable fact 1"])
        expectNoDifference(model.factsCount, 1)
        expectNoDifference(model.$facts.isLoading, false)
        expectNoDifference(model.$factsCount.isLoading, false)
      }
    }

    @Test
    func observableModelLoadsDynamicFetchQueriesThroughWrapperState() async throws {
      let open = typedTodoSnapshot(
        id: "todo-observable-open",
        text: "Open",
        isCompleted: false,
        createdAt: Date(timeIntervalSince1970: 1_700_000_369.25)
      )
      let done = typedTodoSnapshot(
        id: "todo-observable-done",
        text: "Done",
        isCompleted: true,
        createdAt: Date(timeIntervalSince1970: 1_700_000_369.5)
      )
      let recorder = ClientCallRecorder(queryResults: [[open], [done]])
      let client = recordingClient(recorder)
      let model = TypedTodoObservableSearchModel()
      let titleChange = ObservationChangeFlag()
      let initiallyObservedTitles = withObservationTracking {
        model.visibleTitles
      } onChange: {
        titleChange.record()
      }
      expectNoDifference(initiallyObservedTitles, [])
      #expect(titleChange.value == false)

      model.searchText = "Open"
      model.isCompleted = false
      try await model.refresh(using: client)

      expectNoDifference(model.todos.map(\.text), ["Open"])
      expectNoDifference(model.visibleTitles, ["Open"])
      #expect(titleChange.value)
      expectNoDifference(model.$todos.loadError, nil)
      expectNoDifference(model.$todos.isLoading, false)

      model.searchText = ""
      model.isCompleted = nil
      try await model.refresh(using: client)

      expectNoDifference(model.todos, [])
      expectNoDifference(model.$todos.loadError, nil)
      expectNoDifference(model.$todos.isLoading, false)

      model.searchText = "Done"
      model.isCompleted = true
      try await model.refresh(using: client)

      expectNoDifference(model.todos.map(\.text), ["Done"])
      let plans = await recorder.queryPlans()
      expectNoDifference(
        plans.map(\.filters),
        [
          [
            .equals(field: "text", value: .string("Open")),
            .equals(field: "isCompleted", value: .bool(false)),
          ],
          [
            .equals(field: "text", value: .string("Done")),
            .equals(field: "isCompleted", value: .bool(true)),
          ],
        ]
      )
      expectNoDifference(
        plans.map(\.order),
        [
          InstantQueryOrder("createdAt"),
          InstantQueryOrder("createdAt"),
        ]
      )
      let counts = await recorder.counts()
      expectNoDifference(counts.queryCount, 2)
      expectNoDifference(counts.observationCount, 0)
    }
  #endif

  #if canImport(SwiftUI)
    @Test
    func fetchWrappersAcceptSQLiteDataStyleAnimationInitializers() async throws {
      let baseDate = Date(timeIntervalSince1970: 1_700_000_369)
      let fixedUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000706")!
      let defaultTodo = TypedTodo(
        id: InstantID(rawValue: "todo-animation-default"),
        text: "Animation default",
        isCompleted: false,
        createdAt: baseDate.addingTimeInterval(-1)
      )

      try await withDependencies {
        $0.date.now = baseDate
        $0.uuid = .constant(fixedUUID)
        try await $0.bootstrapInstantSwiftData(
          appID: "fetch-animation-\(UUID().uuidString)",
          context: .test,
          initialAttributes: TypedTodo.instantAttributes
        )
      } operation: {
        @Dependency(\.defaultInstantSwiftData) var db

        try await db.transact(id: "tx-fetch-animation-create") {
          TypedTodo.create(
            id: InstantID(rawValue: "todo-animation-first"),
            TypedTodo.text.set("Animation first"),
            TypedTodo.isCompleted.set(false),
            TypedTodo.createdAt.set(baseDate)
          )
          TypedTodo.create(
            id: InstantID(rawValue: "todo-animation-second"),
            TypedTodo.text.set("Animation second"),
            TypedTodo.isCompleted.set(true),
            TypedTodo.createdAt.set(baseDate.addingTimeInterval(1))
          )
        }

        @FetchAll(
          TypedTodo.query.order(TypedTodo.createdAt),
          animation: .default
        )
        var animatedTodos: [TypedTodo]
        try await $animatedTodos.load()
        expectNoDifference(animatedTodos.map(\.text), ["Animation first", "Animation second"])

        @FetchOne(
          TypedTodo.query.order(TypedTodo.createdAt),
          animation: .default
        )
        var animatedTodo: TypedTodo?
        try await $animatedTodo.load()
        expectNoDifference(animatedTodo?.text, "Animation first")

        let requiredTodo = FetchOne(
          wrappedValue: defaultTodo,
          TypedTodo.query.order(TypedTodo.createdAt),
          animation: .default
        )
        try await requiredTodo.load()
        expectNoDifference(requiredTodo.wrappedValue.text, "Animation first")

        let animatedTitles = FetchAll<String>(
          TypedTodo.query.order(TypedTodo.createdAt),
          selecting: TypedTodo.text,
          animation: .default
        )
        try await animatedTitles.load()
        expectNoDifference(animatedTitles.wrappedValue, ["Animation first", "Animation second"])

        @Fetch(
          wrappedValue: FetchCounter(count: 0),
          load: { client in
            FetchCounter(count: try await client.query(TypedTodo.query).count)
          },
          animation: .default
        )
        var animatedCount: FetchCounter
        try await $animatedCount.load()
        expectNoDifference(animatedCount.count, 2)

        let requestFetch = Fetch(
          wrappedValue: TypedTodoFacts(),
          TypedTodoFactsRequest(
            rowsQuery: TypedTodo.query.where(TypedTodo.isCompleted == false),
            countQuery: TypedTodo.query
          ),
          animation: .default
        )
        try await requestFetch.load()
        expectNoDifference(requestFetch.wrappedValue.todos.map(\.text), ["Animation first"])
        expectNoDifference(requestFetch.wrappedValue.count, 2)
      }
    }

    @Test
    func projectedFetchWrappersExposeSwiftUIBindings() {
      let todo = TypedTodo(
        id: InstantID(rawValue: "todo-binding"),
        text: "Binding",
        isCompleted: false,
        createdAt: Date(timeIntervalSince1970: 1_700_000_370)
      )

      let all = FetchAll<TypedTodo>()
      all.binding.wrappedValue = [todo]
      expectNoDifference(all.wrappedValue.map(\.text), ["Binding"])
      expectNoDifference(all.count, 1)

      let infinite = InfiniteQuery<TypedTodo>()
      infinite.binding.wrappedValue = [todo]
      expectNoDifference(infinite.wrappedValue.map(\.text), ["Binding"])
      expectNoDifference(infinite.count, 1)

      let one = FetchOne<TypedTodo?>()
      one.binding.wrappedValue = todo
      expectNoDifference(one.wrappedValue?.text, "Binding")

      let required = FetchOne(wrappedValue: todo)
      expectNoDifference(required.text, "Binding")
      required.text.wrappedValue = "Edited through member binding"
      expectNoDifference(required.wrappedValue.text, "Edited through member binding")

      let count = Fetch(wrappedValue: FetchCounter(count: 0))
      count.binding.wrappedValue = FetchCounter(count: 42)
      expectNoDifference(count.wrappedValue.count, 42)
      count.count.wrappedValue = 1729
      expectNoDifference(count.wrappedValue.count, 1729)
    }

    @Test
    func projectedPlatformAdapterWrappersExposeSwiftUIBindings() {
      let room = InstantRoomHandle(type: "chat", id: "binding")
      let session = adapterAuthSession(userID: "user-binding")
      let presenceMember = adapterPresenceMember(room: room, userID: "presence-binding")
      let topicMessage = adapterTopicMessage(room: room, topic: "sendEmoji", id: "topic-binding")
      let file = adapterStoredFile(id: "file-binding")
      let chunk = adapterStreamChunk(streamID: "chat/binding", id: "chunk-binding")
      let share = adapterShareSnapshot(id: "share-binding")

      @LocalID var localID: String?
      $localID.binding.wrappedValue = "local-binding"
      expectNoDifference(localID, "local-binding")

      @AuthSession var auth: InstantAuthSession?
      $auth.binding.wrappedValue = session
      expectNoDifference(auth?.userID, "user-binding")

      @RoomPresence var presence: [InstantRoomPresenceMember]
      $presence.binding.wrappedValue = [presenceMember]
      expectNoDifference(presence.map(\.userID), ["presence-binding"])

      @RoomTopicMessages var messages: [InstantRoomTopicMessage]
      $messages.binding.wrappedValue = [topicMessage]
      expectNoDifference(messages.map(\.id), ["topic-binding"])

      @StoredFiles var files: [InstantStoredFile]
      $files.binding.wrappedValue = [file]
      expectNoDifference(files.map(\.id), ["file-binding"])

      @StreamChunks var chunks: [InstantStreamChunk]
      $chunks.binding.wrappedValue = [chunk]
      expectNoDifference(chunks.map(\.id), ["chunk-binding"])

      @Shares var shares: [InstantShareSnapshot]
      $shares.binding.wrappedValue = [share]
      expectNoDifference(shares.map(\.share.id), ["share-binding"])
    }
  #endif
}

private actor TransactionRecorder {
  private(set) var transactions: [InstantStoreTransaction] = []

  func record(_ transaction: InstantStoreTransaction) {
    transactions.append(transaction)
  }
}

private struct DerivedFetchFailure: Error, CustomStringConvertible, Sendable {
  var description: String {
    "derived fetch failed"
  }
}

private struct FetchCounter: Hashable, Sendable {
  var count: Int
}

private actor InfiniteQuerySubscriptionRecorder {
  private var loadNextPageCount = 0
  private var unsubscribeCount = 0

  func recordLoadNextPage() {
    loadNextPageCount += 1
  }

  func recordUnsubscribe() {
    unsubscribeCount += 1
  }

  func counts() -> (loadNextPageCount: Int, unsubscribeCount: Int) {
    (loadNextPageCount, unsubscribeCount)
  }
}

private func adapterSurfaceClient() -> InstantSwiftDataClient {
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
    observe: { _ in finiteStream([] as [InstantQueryEmission]) },
    pendingMutations: { [] },
    localID: { name in "local-\(name)" },
    authSession: { adapterAuthSession(userID: "user-load") },
    observeAuthSession: {
      finiteStream([adapterAuthSession(userID: "user-adapter")])
    },
    roomPresence: { room in
      [adapterPresenceMember(room: room, userID: "presence-load")]
    },
    observeRoomPresence: { room in
      finiteStream([
        [adapterPresenceMember(room: room, userID: "presence-\(room.type)-\(room.id)")]
      ])
    },
    roomTopicMessages: { room, topic, limit in
      let messages = [
        adapterTopicMessage(room: room, topic: topic, id: "topic-load-1"),
        adapterTopicMessage(room: room, topic: topic, id: "topic-load-2"),
      ]
      return Array(messages.prefix(limit ?? messages.count))
    },
    observeRoomTopicMessages: { room, topic in
      finiteStream([
        [
          adapterTopicMessage(room: room, topic: topic, id: "topic-\(topic)-1"),
          adapterTopicMessage(room: room, topic: topic, id: "topic-\(topic)-2"),
        ],
      ])
    },
    storedFiles: { [adapterStoredFile(id: "file-load")] },
    observeStoredFiles: {
      finiteStream([[adapterStoredFile(id: "file-adapter")]])
    },
    streamChunks: { streamID, limit in
      let chunks = [
        adapterStreamChunk(streamID: streamID, id: "chunk-load-1"),
        adapterStreamChunk(streamID: streamID, id: "chunk-load-2"),
      ]
      return Array(chunks.prefix(limit ?? chunks.count))
    },
    observeStreamChunks: { streamID in
      finiteStream([
        [
          adapterStreamChunk(streamID: streamID, id: "chunk-\(streamID)-1"),
          adapterStreamChunk(streamID: streamID, id: "chunk-\(streamID)-2"),
        ],
      ])
    },
    shares: { [adapterShareSnapshot(id: "share-load")] },
    observeShares: {
      finiteStream([[adapterShareSnapshot(id: "share-adapter")]])
    }
  )
}

private func sharesObservationClient(recording termination: ObservationTermination)
  -> InstantSwiftDataClient
{
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
    observe: { _ in finiteStream([] as [InstantQueryEmission]) },
    pendingMutations: { [] },
    localID: { name in "local-\(name)" },
    shares: { [] },
    observeShares: {
      AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
        continuation.yield([adapterShareSnapshot(id: "share-live")])
        continuation.onTermination = { @Sendable _ in
          Task {
            await termination.record()
          }
        }
      }
    }
  )
}

private func adapterAuthSession(userID: String) -> InstantAuthSession {
  InstantAuthSession(
    appID: "adapter-app",
    userID: userID,
    refreshToken: "refresh-\(userID)",
    isGuest: false,
    createdAt: adapterTimestamp,
    updatedAt: adapterTimestamp
  )
}

private func adapterPresenceMember(
  room: InstantRoomHandle,
  userID: String
) -> InstantRoomPresenceMember {
  InstantRoomPresenceMember(
    appID: "adapter-app",
    room: room,
    userID: userID,
    values: ["name": .string(userID)],
    updatedAt: adapterTimestamp
  )
}

private func adapterTopicMessage(
  room: InstantRoomHandle,
  topic: String,
  id: String
) -> InstantRoomTopicMessage {
  InstantRoomTopicMessage(
    id: id,
    appID: "adapter-app",
    room: room,
    topic: topic,
    userID: "user-adapter",
    payload: .object(["topic": .string(topic)]),
    createdAt: adapterTimestamp
  )
}

private func adapterStoredFile(id: String) -> InstantStoredFile {
  InstantStoredFile(
    id: id,
    appID: "adapter-app",
    name: "\(id).txt",
    contentType: "text/plain",
    byteCount: 12,
    localPath: "/tmp/\(id).txt",
    ownerUserID: "user-adapter",
    createdAt: adapterTimestamp,
    updatedAt: adapterTimestamp
  )
}

private func adapterStreamChunk(streamID: String, id: String) -> InstantStreamChunk {
  InstantStreamChunk(
    id: id,
    appID: "adapter-app",
    streamID: streamID,
    index: id.hasSuffix("-1") ? 0 : 1,
    payload: .object(["streamID": .string(streamID)]),
    userID: "user-adapter",
    createdAt: adapterTimestamp
  )
}

private func adapterShareSnapshot(id: String) -> InstantShareSnapshot {
  InstantShareSnapshot(
    share: InstantShare(
      id: id,
      appID: "adapter-app",
      rootNamespace: "todos",
      rootID: "todo-\(id)",
      ownerUserID: "user-adapter",
      token: "token-\(id)",
      createdAt: adapterTimestamp,
      updatedAt: adapterTimestamp
    ),
    memberships: [
      InstantShareMembership(
        appID: "adapter-app",
        shareID: id,
        userID: "user-adapter",
        role: .owner,
        acceptedAt: adapterTimestamp
      )
    ]
  )
}

private func finiteStream<Element: Sendable>(_ values: [Element]) -> AsyncStream<Element> {
  AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
    for value in values {
      continuation.yield(value)
    }
    continuation.finish()
  }
}

private func waitForShares(_ shares: Shares, ids expectedIDs: [String]) async throws {
  for _ in 0..<100 {
    if shares.wrappedValue.map(\.share.id) == expectedIDs {
      return
    }
    try await Task.sleep(nanoseconds: 1_000_000)
  }
  expectNoDifference(shares.wrappedValue.map(\.share.id), expectedIDs)
}

private let adapterTimestamp = InstantTimestamp(milliseconds: 1_700_000_390_000)

// SAFETY: mutable state is protected by `lock`.
private final class ObservationChangeFlag: @unchecked Sendable {
  private let lock = NSLock()
  private var didChange = false

  var value: Bool {
    lock.lock()
    defer { lock.unlock() }
    return didChange
  }

  func record() {
    lock.lock()
    didChange = true
    lock.unlock()
  }
}

private actor ClientCallRecorder {
  private var queryResults: [[InstantEntitySnapshot]]
  private var fallbackError: InstantError?
  private var queryCount = 0
  private var observationCount = 0
  private var plans: [InstantQueryPlan] = []

  init(
    queryResults: [[InstantEntitySnapshot]] = [],
    fallbackError: InstantError? = nil
  ) {
    self.queryResults = queryResults
    self.fallbackError = fallbackError
  }

  func query(plan: InstantQueryPlan) throws -> [InstantEntitySnapshot] {
    queryCount += 1
    plans.append(plan)
    if !queryResults.isEmpty {
      return queryResults.removeFirst()
    }
    if let fallbackError {
      throw fallbackError
    }
    return []
  }

  func observe(plan: InstantQueryPlan) -> AsyncStream<InstantQueryEmission> {
    observationCount += 1
    return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
      continuation.yield(InstantQueryEmission(queryID: plan.id, sequence: 0, values: []))
      continuation.finish()
    }
  }

  func counts() -> (queryCount: Int, observationCount: Int) {
    (queryCount, observationCount)
  }

  func queryPlans() -> [InstantQueryPlan] {
    plans
  }
}

private actor DynamicRequestObservationRecorder {
  enum Request: Hashable, Sendable {
    case open
    case done
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
    plan.filters.contains(.equals(field: "isCompleted", value: .bool(true)))
      ? .done
      : .open
  }
}

private struct TypedTodoFacts: Equatable, Sendable {
  var todos: [TypedTodo] = []
  var count = 0
}

private struct TypedTodoFactsRequest: InstantFetchKeyRequest {
  var rowsQuery: InstantEntityQuery<TypedTodo>
  var countQuery: InstantEntityQuery<TypedTodo>

  func fetch(using client: InstantSwiftDataClient) async throws -> TypedTodoFacts {
    let todos = try await client.query(rowsQuery)
    let count = try await client.query(countQuery).count
    return TypedTodoFacts(todos: todos, count: count)
  }

  func subscribe(using client: InstantSwiftDataClient) async throws -> FetchSubscription<TypedTodoFacts> {
    let subscription = await client.subscribe(rowsQuery)
    let stream = AsyncThrowingStream<TypedTodoFacts, Error>.makeStream(
      bufferingPolicy: .bufferingNewest(1)
    )
    let task = Task {
      do {
        for try await todos in subscription {
          try Task.checkCancellation()
          stream.continuation.yield(TypedTodoFacts(todos: todos, count: todos.count))
        }
        stream.continuation.finish()
      } catch {
        stream.continuation.finish(throwing: error)
      }
    }
    stream.continuation.onTermination = { @Sendable _ in
      task.cancel()
      subscription.cancel()
    }
    return FetchSubscription<TypedTodoFacts>(stream: stream.stream) {
      task.cancel()
      subscription.cancel()
      stream.continuation.finish()
    }
  }
}

private struct FetchOnlyCountRequest: InstantFetchKeyRequest {
  func fetch(using client: InstantSwiftDataClient) async throws -> Int {
    try await client.query(TypedTodo.query).count
  }
}

private struct ImmutableProjectedFetchLifecycleModel {
  @FetchAll var todos: [TypedTodo]
  @FetchOne var todo: TypedTodo?
  @Fetch var count = 0

  func exercise(using client: InstantSwiftDataClient) async throws {
    let query = TypedTodo.query.order(TypedTodo.createdAt)

    try await $todos.load(query, using: client)
    let todosSubscription = try await $todos.subscribe(query, using: client)
    todosSubscription.cancel()
    try await $todos.task(query, using: client)

    try await $todo.load(query, using: client)
    let todoSubscription = try await $todo.subscribe(query, using: client)
    todoSubscription.cancel()
    try await $todo.task(query, using: client)

    try await $count.load(
      { client in
        try await client.query(query).count
      },
      subscribe: { client in
        await client.subscribe(query).map(\.count)
      },
      using: client
    )
    let countSubscription = try await $count.subscribe(
      { client in
        await client.subscribe(query).map(\.count)
      },
      using: client
    )
    countSubscription.cancel()
    try await $count.task(
      { client in
        await client.subscribe(query).map(\.count)
      },
      using: client
    )
  }
}

private actor LocalIDRecorder {
  private var names: [String] = []

  func resolve(_ name: String) -> String {
    names.append(name)
    return "local-id-\(name)"
  }

  func recordedNames() -> [String] {
    names
  }
}

private func recordingClient(_ recorder: ClientCallRecorder) -> InstantSwiftDataClient {
  InstantSwiftDataClient(
    transact: { transaction in
      InstantStoreMutationResult(
        transactionID: transaction.id,
        changedEntityIDs: [],
        tripleCount: 0,
        emissions: []
      )
    },
    query: { plan in
      try await recorder.query(plan: plan)
    },
    observe: { plan in
      await recorder.observe(plan: plan)
    },
    pendingMutations: { [] },
    localID: { name in "recording-\(name)" }
  )
}

private func dynamicRequestObservationClient(
  _ recorder: DynamicRequestObservationRecorder
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
    localID: { name in "dynamic-request-\(name)" }
  )
}

private func localIDClient(_ recorder: LocalIDRecorder) -> InstantSwiftDataClient {
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
    observe: { _ in AsyncStream { continuation in continuation.finish() } },
    pendingMutations: { [] },
    localID: { name in
      await recorder.resolve(name)
    }
  )
}

private func waitForTypedCondition(
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
    message: "Timed out waiting for typed API test condition.",
    recovery: "Inspect the controlled test client, subscription lifecycle, and wrapper state."
  )
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

private func finiteObservationClient(
  _ emissions: [[InstantEntitySnapshot]]
) -> InstantSwiftDataClient {
  InstantSwiftDataClient(
    transact: { _ in
      InstantStoreMutationResult(
        transactionID: "tx",
        changedEntityIDs: [],
        tripleCount: 0,
        emissions: []
      )
    },
    query: { _ in
      emissions.last ?? []
    },
    observe: { plan in
      AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
        for (sequence, values) in emissions.enumerated() {
          continuation.yield(
            InstantQueryEmission(queryID: plan.id, sequence: Int64(sequence), values: values)
          )
        }
        continuation.finish()
      }
    },
    pendingMutations: { [] },
    localID: { name in "mock-\(name)" }
  )
}

private func stagedObservationClient(
  _ emissions: [[InstantEntitySnapshot]],
  nanosecondsBetweenEmissions: UInt64 = 10_000_000
) -> InstantSwiftDataClient {
  InstantSwiftDataClient(
    transact: { _ in
      InstantStoreMutationResult(
        transactionID: "tx",
        changedEntityIDs: [],
        tripleCount: 0,
        emissions: []
      )
    },
    query: { _ in
      emissions.last ?? []
    },
    observe: { plan in
      AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
        let task = Task {
          for (sequence, values) in emissions.enumerated() {
            continuation.yield(
              InstantQueryEmission(queryID: plan.id, sequence: Int64(sequence), values: values)
            )
            try? await Task.sleep(nanoseconds: nanosecondsBetweenEmissions)
          }
          continuation.finish()
        }
        continuation.onTermination = { @Sendable _ in
          task.cancel()
        }
      }
    },
    pendingMutations: { [] },
    localID: { name in "mock-\(name)" }
  )
}

private func makeUnusedFetchSubscription(using client: InstantSwiftDataClient) async throws {
  let fetch = FetchAll<TypedTodo>(TypedTodo.query)
  let subscription = try await fetch.subscribe(using: client)
  withExtendedLifetime(subscription) {}
}

private func typedTodoSnapshot(
  id: String,
  text: String,
  isCompleted: Bool,
  createdAt: Date
) -> InstantEntitySnapshot {
  InstantEntitySnapshot(
    id: id,
    namespace: TypedTodo.instantNamespace,
    values: [
      "text": .one(.string(text)),
      "isCompleted": .one(.bool(isCompleted)),
      "createdAt": .one(.date(createdAt)),
    ]
  )
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

private actor CompletionFlag {
  private var didComplete = false
  private var recordedError: String?

  var value: Bool {
    didComplete
  }

  var error: String? {
    recordedError
  }

  func record() {
    didComplete = true
  }

  func recordError(_ error: String) {
    recordedError = error
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

#if canImport(Observation)
  @Observable
  private final class TypedTodoObservableFactsModel {
    var number = 0
    var visibleTitles: [String] = []

    @ObservationIgnored
    @FetchAll(TypedTodo.query.order(TypedTodo.createdAt, .descending))
    var facts: [TypedTodo] = []

    @ObservationIgnored
    @Fetch(
      wrappedValue: 0,
      load: { client in
        try await client.query(TypedTodo.query).count
      }
    )
    var factsCount

    @ObservationIgnored
    @Dependency(\.defaultInstantSwiftData) var database

    func increment(body: String, createdAt: Date) async throws {
      let nextNumber = number + 1
      number = nextNumber
      let id = InstantID<TypedTodo>(rawValue: "observable-fact-\(nextNumber)")
      try await database.transact(id: "tx-observable-facts-increment-\(nextNumber)") {
        TypedTodo.create(
          id: id,
          TypedTodo.text.set(body),
          TypedTodo.isCompleted.set(false),
          TypedTodo.createdAt.set(createdAt)
        )
      }
      try await reload()
    }

    func deleteFact(indices: IndexSet) async throws {
      let ids = indices.compactMap { index in
        facts.indices.contains(index) ? facts[index].id : nil
      }
      try await database.transact(id: "tx-observable-facts-delete") {
        for id in ids {
          TypedTodo.delete(id: id)
        }
      }
      try await reload()
    }

    private func reload() async throws {
      try await $facts.load()
      try await $factsCount.load()
      visibleTitles = facts.map(\.text)
    }
  }

  @Observable
  private final class TypedTodoObservableSearchModel {
    var searchText = ""
    var isCompleted: Bool?
    var visibleTitles: [String] = []

    @ObservationIgnored
    @FetchAll
    var todos: [TypedTodo] = []

    func refresh(using client: InstantSwiftDataClient) async throws {
      let text = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
      var query: InstantEntityQuery<TypedTodo>?
      if !text.isEmpty || isCompleted != nil {
        var builtQuery = TypedTodo.query.order(TypedTodo.createdAt)
        if !text.isEmpty {
          builtQuery = builtQuery.where(TypedTodo.text == text)
        }
        if let isCompleted {
          builtQuery = builtQuery.where(TypedTodo.isCompleted == isCompleted)
        }
        query = builtQuery
      }

      try await $todos.load(query, using: client)
      visibleTitles = todos.map(\.text)
    }
  }
#endif

private struct RequiredTypedTodoFetchOneModel {
  @FetchOne var todo: TypedTodo

  init(defaultTodo: TypedTodo) {
    _todo = FetchOne(wrappedValue: defaultTodo, TypedTodo.query.order(TypedTodo.createdAt))
  }

  mutating func load() async throws {
    try await $todo.load()
  }
}

@InstantEntity
private struct MacroGeneratedTodo: Hashable, Codable, InstantEntityModel {
  var id: InstantID<MacroGeneratedTodo>
  var title: String
  var score: Int
  var dueAt: Date?
  var metadata: JSONValue
  var isCompleted = false

  init(
    id: InstantID<MacroGeneratedTodo>,
    title: String,
    score: Int,
    dueAt: Date?,
    metadata: JSONValue,
    isCompleted: Bool = false
  ) {
    self.id = id
    self.title = title
    self.score = score
    self.dueAt = dueAt
    self.metadata = metadata
    self.isCompleted = isCompleted
  }

  init(snapshot: InstantEntitySnapshot) throws {
    guard case let .string(title) = snapshot.values["title"]?.first else {
      throw Self.decodeError(snapshot: snapshot, field: "title", expected: "string")
    }
    guard case let .number(score) = snapshot.values["score"]?.first else {
      throw Self.decodeError(snapshot: snapshot, field: "score", expected: "number")
    }
    let dueAt: Date?
    switch snapshot.values["dueAt"]?.first {
    case .none, .some(.null):
      dueAt = nil
    case let .some(.date(value)):
      dueAt = value
    default:
      throw Self.decodeError(snapshot: snapshot, field: "dueAt", expected: "date or null")
    }
    guard case let .json(metadata) = snapshot.values["metadata"]?.first else {
      throw Self.decodeError(snapshot: snapshot, field: "metadata", expected: "json")
    }
    guard case let .bool(isCompleted) = snapshot.values["isCompleted"]?.first else {
      throw Self.decodeError(snapshot: snapshot, field: "isCompleted", expected: "boolean")
    }

    self.init(
      id: InstantID(rawValue: snapshot.id),
      title: title,
      score: Int(score),
      dueAt: dueAt,
      metadata: metadata,
      isCompleted: isCompleted
    )
  }

  private static func decodeError(
    snapshot: InstantEntitySnapshot,
    field: String,
    expected: String
  ) -> InstantError {
    InstantError(
      code: .decodeFailed,
      operation: "decode macro generated todo",
      namespace: instantNamespace,
      path: field,
      localID: snapshot.id,
      message: "Expected \(expected) for macro generated todo field '\(field)'.",
      recovery: "Check the Instant entity schema and server values for the macro generated todo namespace."
    )
  }
}

@InstantEntity
private struct MacroGeneratedUser: Hashable, Codable, InstantEntityModel {
  var id: InstantID<MacroGeneratedUser>
  var name: String

  init(snapshot: InstantEntitySnapshot) throws {
    self.id = InstantID(rawValue: snapshot.id)
    if case let .string(name) = snapshot.values["name"]?.first {
      self.name = name
    } else {
      self.name = ""
    }
  }
}

@InstantEntity
private struct MacroGeneratedPost: Hashable, Codable, InstantEntityModel {
  var id: InstantID<MacroGeneratedPost>
  var title: String

  @InstantRelation(reverse: "posts")
  var author: InstantID<MacroGeneratedUser>

  init(snapshot: InstantEntitySnapshot) throws {
    self.id = InstantID(rawValue: snapshot.id)
    if case let .string(title) = snapshot.values["title"]?.first {
      self.title = title
    } else {
      self.title = ""
    }
    if case let .ref(authorID) = snapshot.values["author"]?.first {
      self.author = InstantID(rawValue: authorID)
    } else {
      self.author = InstantID(rawValue: "")
    }
  }
}

@InstantEntity
private struct MacroGeneratedOptionalUser: Hashable, Codable, InstantEntityModel {
  var id: InstantID<MacroGeneratedOptionalUser>
  var name: String

  init(snapshot: InstantEntitySnapshot) throws {
    self.id = InstantID(rawValue: snapshot.id)
    if case let .string(name) = snapshot.values["name"]?.first {
      self.name = name
    } else {
      self.name = ""
    }
  }
}

@InstantEntity
private struct MacroGeneratedOptionalPost: Hashable, Codable, InstantEntityModel {
  var id: InstantID<MacroGeneratedOptionalPost>
  var title: String

  @InstantRelation(reverse: "posts")
  var author: InstantID<MacroGeneratedOptionalUser>?

  init(snapshot: InstantEntitySnapshot) throws {
    self.id = InstantID(rawValue: snapshot.id)
    if case let .string(title) = snapshot.values["title"]?.first {
      self.title = title
    } else {
      self.title = ""
    }
    if case let .ref(authorID) = snapshot.values["author"]?.first {
      self.author = InstantID(rawValue: authorID)
    } else {
      self.author = nil
    }
  }
}

@InstantEntity
private struct DraftWithUndeclaredFieldTodo: Hashable, Codable, InstantEntityModel {
  var id: InstantID<DraftWithUndeclaredFieldTodo>
  var title: String
  var serverManaged = "server"

  static let title = InstantAttributePath<DraftWithUndeclaredFieldTodo, String>("title")

  static let instantAttributes = [
    InstantAttribute(
      id: "draftWithUndeclaredFieldTodos/title",
      namespace: instantNamespace,
      name: "title",
      valueType: .string,
      isIndexed: true
    )
  ]

  init(
    id: InstantID<DraftWithUndeclaredFieldTodo>,
    title: String,
    serverManaged: String = "server"
  ) {
    self.id = id
    self.title = title
    self.serverManaged = serverManaged
  }

  init(snapshot: InstantEntitySnapshot) throws {
    guard case let .string(title) = snapshot.values["title"]?.first else {
      throw InstantError(
        code: .decodeFailed,
        operation: "decode draft with undeclared field todo",
        namespace: Self.instantNamespace,
        path: "title",
        localID: snapshot.id,
        message: "Expected string for draft-with-undeclared-field todo field 'title'.",
        recovery:
          "Check the Instant entity schema and server values for the draft-with-undeclared-field todo namespace."
      )
    }
    self.id = InstantID(rawValue: snapshot.id)
    self.title = title
  }
}

@InstantEntity
private struct DraftBackedTodo: Hashable, Codable, InstantEntityModel {
  var id: InstantID<DraftBackedTodo>
  var title: String
  var isCompleted = false
  var createdAt: Date
  var notes: String? = nil
  let localFormSource: String

  static let title = InstantAttributePath<DraftBackedTodo, String>(
    "title",
    attributeID: "draftBackedTodos/body"
  )
  static let isCompleted = InstantAttributePath<DraftBackedTodo, Bool>("isCompleted")
  static let createdAt = InstantAttributePath<DraftBackedTodo, Date>("createdAt")
  static let notes = InstantAttributePath<DraftBackedTodo, String?>("notes")

  static let instantAttributes = [
    InstantAttribute(
      id: "draftBackedTodos/body",
      namespace: instantNamespace,
      name: "title",
      valueType: .string,
      isIndexed: true
    ),
    InstantAttribute(
      id: "draftBackedTodos/isCompleted",
      namespace: instantNamespace,
      name: "isCompleted",
      valueType: .boolean,
      isIndexed: true
    ),
    InstantAttribute(
      id: "draftBackedTodos/createdAt",
      namespace: instantNamespace,
      name: "createdAt",
      valueType: .date,
      isIndexed: true
    ),
    InstantAttribute(
      id: "draftBackedTodos/notes",
      namespace: instantNamespace,
      name: "notes",
      valueType: .string,
      isRequired: false,
      isIndexed: false
    ),
  ]

  init(
    id: InstantID<DraftBackedTodo>,
    title: String,
    isCompleted: Bool,
    createdAt: Date,
    notes: String? = nil,
    localFormSource: String = "swiftui-form"
  ) {
    self.id = id
    self.title = title
    self.isCompleted = isCompleted
    self.createdAt = createdAt
    self.notes = notes
    self.localFormSource = localFormSource
  }

  init(snapshot: InstantEntitySnapshot) throws {
    guard case let .string(title) = snapshot.values["title"]?.first else {
      throw Self.decodeError(snapshot: snapshot, field: "title", expected: "string")
    }
    guard case let .bool(isCompleted) = snapshot.values["isCompleted"]?.first else {
      throw Self.decodeError(snapshot: snapshot, field: "isCompleted", expected: "boolean")
    }
    guard case let .date(createdAt) = snapshot.values["createdAt"]?.first else {
      throw Self.decodeError(snapshot: snapshot, field: "createdAt", expected: "date")
    }
    let notes: String?
    switch snapshot.values["notes"]?.first {
    case .none, .some(.null):
      notes = nil
    case let .some(.string(value)):
      notes = value
    default:
      throw Self.decodeError(snapshot: snapshot, field: "notes", expected: "string or null")
    }

    self.id = InstantID(rawValue: snapshot.id)
    self.title = title
    self.isCompleted = isCompleted
    self.createdAt = createdAt
    self.notes = notes
    self.localFormSource = "swiftui-form"
  }

  private static func decodeError(
    snapshot: InstantEntitySnapshot,
    field: String,
    expected: String
  ) -> InstantError {
    InstantError(
      code: .decodeFailed,
      operation: "decode draft-backed todo",
      namespace: instantNamespace,
      path: field,
      localID: snapshot.id,
      message: "Expected \(expected) for draft-backed todo field '\(field)'.",
      recovery: "Check the Instant entity schema and server values for the draft-backed todo namespace."
    )
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

private struct TypedMalformedReverseUser: Hashable, Codable, InstantEntityModel {
  var id: InstantID<TypedMalformedReverseUser>

  static let instantNamespace = "malformedUsers"
  static let instantAttributes: [InstantAttribute] = []

  init(snapshot: InstantEntitySnapshot) throws {
    self.id = InstantID(rawValue: snapshot.id)
  }
}

private struct TypedMalformedReversePost: Hashable, Codable, InstantEntityModel {
  var id: InstantID<TypedMalformedReversePost>

  static let instantNamespace = "malformedPosts"
  static let author =
    InstantAttributePath<TypedMalformedReversePost, InstantID<TypedMalformedReverseUser>>("author")
  static let instantAttributes = [
    InstantAttribute(
      id: "malformedPosts/author",
      namespace: instantNamespace,
      name: "author",
      valueType: .ref,
      isIndexed: true,
      forwardIdentity: "malformedPosts/author",
      reverseIdentity: "malformedUsers/",
      linkNamespace: TypedMalformedReverseUser.instantNamespace
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
  static let posts = InstantReverseRelation<TypedUser, TypedPost>(attribute: TypedPost.author)
  static let editedPosts = InstantReverseRelation<TypedUser, TypedPost>(attribute: TypedPost.editor)

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
  static let editor = InstantAttributePath<TypedPost, InstantID<TypedUser>>("editor")

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
    InstantAttribute(
      id: "posts/editor",
      namespace: instantNamespace,
      name: "editor",
      valueType: .ref,
      isIndexed: true,
      forwardIdentity: "posts/editor",
      reverseIdentity: "users/editedPosts",
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
