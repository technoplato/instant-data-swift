import CustomDump
import Foundation
@testable import InstantSwiftDataCore
import Testing

@Suite(.serialized)
struct InstantStoreParityTests {
  @Test
  func parityCoverageReportRecordsCurrentSourceProvenance() {
    let report = InstantSwiftDataParityCoverage.current

    expectNoDifference(report.event, "parity-report")
    expectNoDifference(report.coverageComplete, false)
    expectNoDifference(report.recordCount, 98)
    expectNoDifference(report.exactCount, 19)
    expectNoDifference(report.adaptedCount, 76)
    expectNoDifference(report.blockedCount, 3)
    expectNoDifference(report.notApplicableCount, 0)
    #expect(report.sourceFiles.contains("upstream/instant/client/packages/core/__tests__/src/instaml.test.ts"))
    #expect(report.sourceFiles.contains("upstream/instant/client/packages/core/__tests__/src/store.test.ts"))
    #expect(report.sourceFiles.contains("upstream/instant/client/packages/core/__tests__/src/utils/dates.test.ts"))
    #expect(report.sourceFiles.contains("upstream/sqlite-data/Sources/SQLiteData/Documentation.docc/Articles/CloudKitSync.md"))
    #expect(report.sourceFiles.contains("upstream/sqlite-data/Tests/SQLiteDataTests/FetchTests.swift"))
    #expect(report.sourceFiles.contains("upstream/sqlite-data/Tests/SQLiteDataTests/FetchSubscriptionTests.swift"))
    #expect(report.swiftFiles.contains("Tests/InstantSwiftDataCoreTests/InstantDateCoercionTests.swift"))
    #expect(report.swiftFiles.contains("Tests/InstantSwiftDataMacrosTests/InstantEntityMacroTests.swift"))
    #expect(report.swiftFiles.contains("Tests/InstantSwiftDataTests/TypedAPITests.swift"))
    #expect(report.records.contains { $0.id == "instant.store.simple-add" && $0.status == .exact })
    #expect(report.records.contains { $0.id == "instant.store.link-unlink-multi" && $0.status == .adapted })
    #expect(report.records.contains { $0.id == "instant.store.link-unlink-without-update" && $0.status == .adapted })
    #expect(report.records.contains { $0.id == "instant.store.on-delete-reverse-cascade" && $0.status == .adapted })
    #expect(report.records.contains { $0.id == "instant.store.rule-params-no-op" && $0.status == .exact })
    #expect(report.records.contains { $0.id == "instant.store.recursive-links-same-id" && $0.status == .adapted })
    #expect(report.records.contains { $0.id == "instant.store.v0-store-restore" && $0.status == .adapted })
    #expect(report.records.contains { $0.id == "instant.query.simple-without-where" && $0.status == .exact })
    #expect(report.records.contains { $0.id == "instant.query.simple-where-expected-keys" && $0.status == .adapted })
    #expect(report.records.contains { $0.id == "instant.query.where-deep-like-prefix-suffix" && $0.status == .exact })
    #expect(report.records.contains { $0.id == "instant.query.nested-wheres" && $0.status == .adapted })
    #expect(report.records.contains { $0.id == "instant.query.missing-namespaces-attributes" && $0.status == .adapted })
    #expect(report.records.contains { $0.id == "instant.query.relation-filter-refs" && $0.status == .adapted })
    #expect(report.records.contains { $0.id == "instant.query.create-update-triples" && $0.status == .adapted })
    #expect(report.records.contains { $0.id == "instant.query.object-values" && $0.status == .exact })
    #expect(report.records.contains { $0.id == "instant.instaml.mode-update" && $0.status == .adapted })
    #expect(report.records.contains { $0.id == "instant.instaml.invalid-link-lookup-attr" && $0.status == .adapted })
    #expect(report.records.contains { $0.id == "instant.instaml.dotted-lookup-attribute" && $0.status == .adapted })
    #expect(report.records.contains { $0.id == "instant.instaml.lookup-link-value-arrays" && $0.status == .adapted })
    #expect(report.records.contains { $0.id == "instant.instaml.no-duplicate-ref-attrs" && $0.status == .adapted })
    #expect(report.records.contains { $0.id == "instant.instaml.schema-attrs-and-links" && $0.status == .adapted })
    #expect(report.records.contains { $0.id == "instant.instaml.schema-no-duplicate-ref-attrs" && $0.status == .adapted })
    #expect(report.records.contains { $0.id == "instant.instaml.schema-custom-lookup-attrs" && $0.status == .adapted })
    #expect(report.records.contains { $0.id == "instant.instaml.schema-lookup-link-value" && $0.status == .adapted })
    #expect(report.records.contains { $0.id == "instant.instaml.schema-lookup-link-value-arrays" && $0.status == .adapted })
    #expect(report.records.contains { $0.id == "instant.instaml.schema-ref-lookup-attrs" && $0.status == .adapted })
    #expect(report.records.contains { $0.id == "instant.instaml.schema-ref-lookup-link-value" && $0.status == .adapted })
    #expect(report.records.contains { $0.id == "instant.instaml.schema-checked-data-types" && $0.status == .adapted })
    #expect(report.records.contains { $0.id == "instant.instaml.closed-mutation-surface" && $0.status == .adapted })
    #expect(report.records.contains { $0.id == "instant.store.date-conversion" && $0.status == .adapted })
    #expect(report.records.contains { $0.id == "instant.store.json-serialization" && $0.status == .adapted })
    #expect(report.records.contains { $0.id == "instant.utils.date-coercion" && $0.status == .adapted })
    #expect(report.records.contains { $0.id == "sqlite.fetch-subscription.explicit-cancel" && $0.status == .adapted })
    #expect(report.records.contains { $0.id == "sqlite.fetch-one.initializer-defaults" && $0.status == .adapted })
    #expect(report.records.contains { $0.id == "sqlite.fetch-one.scalar-selection" && $0.status == .adapted })
    #expect(report.records.contains { $0.id == "sqlite.fetch-one.dynamic-query" && $0.status == .adapted })
    #expect(report.records.contains { $0.id == "sqlite.fetch-one.nil-query" && $0.status == .adapted })
    #expect(report.records.contains { $0.id == "sqlite.fetch-wrappers.basic-matrix" && $0.status == .adapted })
    #expect(report.records.contains { $0.id == "sqlite.fetch-all.concurrency" && $0.status == .adapted })
    #expect(report.records.contains { $0.id == "sqlite.fetch-all.decode-failure" && $0.status == .adapted })
    #expect(report.records.contains { $0.id == "sqlite.fetch-all.scalar-selection" && $0.status == .adapted })
    #expect(report.records.contains { $0.id == "sqlite.fetch.transaction-request" && $0.status == .adapted })
    #expect(report.records.contains { $0.id == "sqlite.case-studies.animation-initializers" && $0.status == .adapted })
    #expect(report.records.contains { $0.id == "sqlite.case-studies.swiftui-direct-wrappers" && $0.status == .adapted })
    #expect(report.records.contains { $0.id == "sqlite.case-studies.observable-model" && $0.status == .adapted })
    #expect(report.records.contains { $0.id == "sqlite.case-studies.uikit-controller" && $0.status == .adapted })
    #expect(report.records.contains { $0.id == "sqlite.draft.macro-generation" && $0.status == .adapted })
    #expect(report.records.contains { $0.id == "sqlite.draft.nil-id-create" && $0.status == .adapted })
    #expect(report.records.contains { $0.id == "sqlite.draft.existing-edit" && $0.status == .adapted })
    #expect(report.records.contains { $0.id == "sqlite.draft.generated-field-exclusion" && $0.status == .adapted })
    #expect(report.records.contains { $0.id == "sqlite.integration.filtered-reload" && $0.status == .adapted })
    #expect(report.records.contains { $0.id == "sqlite.reminders.search-tags" && $0.status == .adapted })
    #expect(report.records.contains { $0.id == "sqlite.syncups.record-meeting" && $0.status == .adapted })
    #expect(report.records.contains { $0.id == "instant.live-transport.swift-to-typescript" && $0.status == .blocked })

    let evidenceRows = report.evidenceRows(appID: "parity-test")
    expectNoDifference(evidenceRows.count, report.recordCount)
    expectNoDifference(evidenceRows.first?.caseID, "validation.parity.report")
    expectNoDifference(evidenceRows.first?.appID, "parity-test")
    expectNoDifference(evidenceRows.first?.event, "parity-record")
    expectNoDifference(evidenceRows.first?.ok, true)
    expectNoDifference(evidenceRows.last?.ok, false)
  }

  @Test
  func simpleAddMaterializesScalarAttribute() async throws {
    let source = storeParitySource(
      "simple add",
      status: "exact: a single scalar write creates and materializes the entity."
    )
    let time = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: temporaryCacheURL(),
        initialAttributes: [
          InstantAttribute(
            id: "users/handle",
            namespace: "users",
            name: "handle",
            valueType: .string
          )
        ]
      )
    )

    let result = try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-simple-add",
        operations: [
          .insert(triple("user-1", "users/handle", .string("bobby"), txID: "tx-simple-add", time: time))
        ]
      ),
      createdAt: time
    )

    let users = try await runtime.query(InstantQueryPlan(id: "users", namespace: "users"))
    expectNoDifference(result.changedEntityIDs, ["user-1"], source)
    expectNoDifference(result.tripleCount, 1, source)
    expectNoDifference(users.map(\.id), ["user-1"], source)
    expectNoDifference(users.map { $0.values["handle"]?.first }, [.string("bobby")], source)
  }

  @Test
  func cardinalityOneAddKeepsLastValueInSameTransaction() async throws {
    let source = storeParitySource(
      "cardinality-one add",
      status: "exact: cardinality-one attrs keep only the latest value in a transaction."
    )
    let time = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: temporaryCacheURL(),
        initialAttributes: [
          InstantAttribute(
            id: "users/handle",
            namespace: "users",
            name: "handle",
            valueType: .string
          )
        ]
      )
    )

    let result = try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-cardinality-one-add",
        operations: [
          .insert(triple("user-1", "users/handle", .string("bobby"), txID: "tx-cardinality-one-add", time: time)),
          .insert(triple("user-1", "users/handle", .string("bob"), txID: "tx-cardinality-one-add", time: time)),
        ]
      ),
      createdAt: time
    )

    let users = try await runtime.query(InstantQueryPlan(id: "users", namespace: "users"))
    expectNoDifference(result.changedEntityIDs, ["user-1"], source)
    expectNoDifference(result.tripleCount, 1, source)
    expectNoDifference(users.map { $0.values["handle"]?.first }, [.string("bob")], source)
  }

  @Test
  func linkAndUnlinkPortsUpstreamUserBookshelfShape() async throws {
    let source = storeParitySource(
      "link/unlink",
      status: "exact: user/bookshelf scalar writes and links materialize, unlink, and relink."
    )
    let time = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: temporaryCacheURL(),
        initialAttributes: userBookshelfAttributes()
      )
    )
    let query = usersWithBookshelvesQuery()

    let initial = try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-link-unlink",
        operations: [
          .insert(triple("user-1", "users/handle", .string("bobby"), txID: "tx-link-unlink", time: time)),
          .insert(triple("user-1", "users/bookshelves", .ref("bookshelf-1"), txID: "tx-link-unlink", time: time)),
          .insert(triple("bookshelf-1", "bookshelves/name", .string("my books"), txID: "tx-link-unlink", time: time)),
        ]
      ),
      createdAt: time
    )

    var users = try await runtime.query(query)
    expectNoDifference(initial.changedEntityIDs, ["bookshelf-1", "user-1"], source)
    expectNoDifference(initial.tripleCount, 3, source)
    expectNoDifference(users.map { $0.values["handle"]?.first }, [.string("bobby")], source)
    expectNoDifference(users.first?.values["bookshelves"]?.values, [.ref("bookshelf-1")], source)
    expectNoDifference(users.first?.links?["bookshelves"]?.map(\.id), ["bookshelf-1"], source)
    expectNoDifference(
      users.first?.links?["bookshelves"]?.map { $0.values["name"]?.first },
      [.string("my books")],
      source
    )

    let relinked = try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-link-unlink-relink",
        operations: [
          .insert(
            triple(
              "bookshelf-2",
              "bookshelves/name",
              .string("my second books"),
              txID: "tx-link-unlink-relink",
              time: time
            )
          ),
          .retract(
            triple(
              "user-1",
              "users/bookshelves",
              .ref("bookshelf-1"),
              txID: "tx-link-unlink-relink",
              time: time
            )
          ),
          .insert(
            triple(
              "user-1",
              "users/bookshelves",
              .ref("bookshelf-2"),
              txID: "tx-link-unlink-relink",
              time: time
            )
          ),
        ]
      ),
      createdAt: InstantTimestamp(milliseconds: time.milliseconds + 1)
    )

    users = try await runtime.query(query)
    expectNoDifference(
      relinked.changedEntityIDs,
      ["bookshelf-1", "bookshelf-2", "user-1"],
      source
    )
    expectNoDifference(users.first?.values["bookshelves"]?.values, [.ref("bookshelf-2")], source)
    expectNoDifference(users.first?.links?["bookshelves"]?.map(\.id), ["bookshelf-2"], source)
    expectNoDifference(
      users.first?.links?["bookshelves"]?.map { $0.values["name"]?.first },
      [.string("my second books")],
      source
    )
  }

  @Test
  func deleteEntityRemovesEntityAndInboundReferences() async throws {
    let source = storeParitySource(
      "delete entity",
      status: "exact: deleting an entity removes its triples and inbound references."
    )
    let time = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: temporaryCacheURL(),
        initialAttributes: userBookshelfAttributes()
      )
    )

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-delete-entity-seed",
        operations: [
          .insert(triple("user-1", "users/handle", .string("bobby"), txID: "tx-delete-entity-seed", time: time)),
          .insert(triple("user-1", "users/bookshelves", .ref("bookshelf-1"), txID: "tx-delete-entity-seed", time: time)),
          .insert(
            triple(
              "bookshelf-1",
              "bookshelves/name",
              .string("my books"),
              txID: "tx-delete-entity-seed",
              time: time
            )
          ),
        ]
      ),
      createdAt: time
    )

    var snapshot = await runtime.store.snapshot()
    expectNoDifference(
      snapshot.triples.filter { $0.entityID == "bookshelf-1" }.map(\.value),
      [.string("my books")],
      source
    )
    expectNoDifference(
      snapshot.triples.filter { $0.value == .ref("bookshelf-1") }.map(\.entityID),
      ["user-1"],
      source
    )

    let deleted = try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-delete-entity",
        operations: [.deleteEntity("bookshelf-1")]
      ),
      createdAt: InstantTimestamp(milliseconds: time.milliseconds + 1)
    )
    snapshot = await runtime.store.snapshot()
    let users = try await runtime.query(usersWithBookshelvesQuery())
    let bookshelves = try await runtime.query(InstantQueryPlan(id: "bookshelves", namespace: "bookshelves"))

    expectNoDifference(deleted.changedEntityIDs, ["bookshelf-1", "user-1"], source)
    expectNoDifference(deleted.tripleCount, 1, source)
    expectNoDifference(
      snapshot.triples.filter { $0.entityID == "bookshelf-1" }.map(\.value),
      [],
      source
    )
    expectNoDifference(
      snapshot.triples.filter { $0.value == .ref("bookshelf-1") }.map(\.entityID),
      [],
      source
    )
    expectNoDifference(users.map(\.id), ["user-1"], source)
    expectNoDifference(users.first?.values["bookshelves"]?.values, nil, source)
    expectNoDifference(users.first?.links?["bookshelves"]?.map(\.id), [], source)
    expectNoDifference(bookshelves.map(\.id), [], source)
  }

  @Test
  func onDeleteCascadePortsUpstreamBookSeriesShape() async throws {
    let source = storeParitySource(
      "on-delete cascade",
      status: "exact: deleting the first book cascades through prequel links."
    )
    let time = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: temporaryCacheURL(),
        initialAttributes: bookCascadeAttributes(
          linkName: "prequel",
          reverseName: "next",
          onDelete: .cascade
        )
      )
    )
    let book1Time = time
    let book2Time = InstantTimestamp(milliseconds: time.milliseconds + 1)
    let book3Time = InstantTimestamp(milliseconds: time.milliseconds + 2)

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-on-delete-cascade-seed",
        operations: [
          .insert(triple("book-1", "books/title", .string("book1"), txID: "tx-on-delete-cascade-seed", time: book1Time)),
          .insert(triple("book-1", "books/description", .string("series"), txID: "tx-on-delete-cascade-seed", time: book1Time)),
          .insert(triple("book-2", "books/title", .string("book2"), txID: "tx-on-delete-cascade-seed", time: book2Time)),
          .insert(triple("book-2", "books/description", .string("series"), txID: "tx-on-delete-cascade-seed", time: book2Time)),
          .insert(triple("book-2", "books/prequel", .ref("book-1"), txID: "tx-on-delete-cascade-seed", time: book2Time)),
          .insert(triple("book-3", "books/title", .string("book3"), txID: "tx-on-delete-cascade-seed", time: book3Time)),
          .insert(triple("book-3", "books/description", .string("series"), txID: "tx-on-delete-cascade-seed", time: book3Time)),
          .insert(triple("book-3", "books/prequel", .ref("book-2"), txID: "tx-on-delete-cascade-seed", time: book3Time)),
        ]
      ),
      createdAt: time
    )

    var books = try await runtime.query(bookSeriesQuery(id: "books.series.before-forward-cascade"))
    expectNoDifference(
      books.map { $0.values["title"]?.first },
      [.string("book1"), .string("book2"), .string("book3")],
      source
    )

    let deleted = try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-on-delete-cascade-delete",
        operations: [.deleteEntity("book-1")]
      ),
      createdAt: InstantTimestamp(milliseconds: time.milliseconds + 3)
    )

    books = try await runtime.query(bookSeriesQuery(id: "books.series.after-forward-cascade"))
    expectNoDifference(deleted.changedEntityIDs, ["book-1", "book-2", "book-3"], source)
    expectNoDifference(deleted.tripleCount, 0, source)
    expectNoDifference(books.map { $0.values["title"]?.first }, [], source)
  }

  @Test
  func onDeleteReverseCascadePortsUpstreamBookSeriesShape() async throws {
    let source = storeParitySource(
      "on-delete-reverse cascade",
      status: "exact: deleting the source book cascades through next links."
    )
    let time = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: temporaryCacheURL(),
        initialAttributes: bookCascadeAttributes(
          linkName: "next",
          reverseName: "prequel",
          cardinality: .many,
          onDeleteReverse: .cascade
        )
      )
    )
    let book2Time = time
    let book3Time = InstantTimestamp(milliseconds: time.milliseconds + 1)
    let book1Time = InstantTimestamp(milliseconds: time.milliseconds + 2)

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-on-delete-reverse-cascade-seed",
        operations: [
          .insert(triple("book-2", "books/title", .string("book2"), txID: "tx-on-delete-reverse-cascade-seed", time: book2Time)),
          .insert(triple("book-2", "books/description", .string("series"), txID: "tx-on-delete-reverse-cascade-seed", time: book2Time)),
          .insert(triple("book-3", "books/title", .string("book3"), txID: "tx-on-delete-reverse-cascade-seed", time: book3Time)),
          .insert(triple("book-3", "books/description", .string("series"), txID: "tx-on-delete-reverse-cascade-seed", time: book3Time)),
          .insert(triple("book-1", "books/title", .string("book1"), txID: "tx-on-delete-reverse-cascade-seed", time: book1Time)),
          .insert(triple("book-1", "books/description", .string("series"), txID: "tx-on-delete-reverse-cascade-seed", time: book1Time)),
          .insert(triple("book-1", "books/next", .ref("book-2"), txID: "tx-on-delete-reverse-cascade-seed", time: book1Time)),
          .insert(triple("book-1", "books/next", .ref("book-3"), txID: "tx-on-delete-reverse-cascade-seed", time: book1Time)),
        ]
      ),
      createdAt: time
    )

    var books = try await runtime.query(bookSeriesQuery(id: "books.series.before-reverse-cascade"))
    expectNoDifference(
      books.map { $0.values["title"]?.first },
      [.string("book2"), .string("book3"), .string("book1")],
      source
    )

    let deleted = try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-on-delete-reverse-cascade-delete",
        operations: [.deleteEntity("book-1")]
      ),
      createdAt: InstantTimestamp(milliseconds: time.milliseconds + 3)
    )

    books = try await runtime.query(bookSeriesQuery(id: "books.series.after-reverse-cascade"))
    expectNoDifference(deleted.changedEntityIDs, ["book-1", "book-2", "book-3"], source)
    expectNoDifference(deleted.tripleCount, 0, source)
    expectNoDifference(books.map { $0.values["title"]?.first }, [], source)
  }

  @Test
  func linkAndUnlinkWithoutScalarUpdatesMaintainForwardAndReverseIndexes() async throws {
    let source = storeParitySource(
      "link/unlink without update",
      status: "adapted: Swift asserts forward and reverse materialized links."
    )
    let time = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: temporaryCacheURL(),
        initialAttributes: TodoProjectExample.attributes
      )
    )

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-link-unlink-seed",
        operations: TodoExample.createOperations(
          id: "todo-1",
          text: "Wire links",
          createdAt: time,
          transactionID: "tx-link-unlink-seed"
        ) + TodoProjectExample.createProjectOperations(
          id: "project-1",
          title: "Launch",
          createdAt: time,
          transactionID: "tx-link-unlink-seed"
        ) + TodoProjectExample.createProjectOperations(
          id: "project-2",
          title: "Archive",
          createdAt: time,
          transactionID: "tx-link-unlink-seed"
        )
      ),
      createdAt: time
    )

    let linkResult = try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-link-without-update",
        operations: TodoProjectExample.linkOperations(
          todoID: "todo-1",
          projectID: "project-1",
          updatedAt: InstantTimestamp(milliseconds: time.milliseconds + 1),
          transactionID: "tx-link-without-update"
        )
      ),
      createdAt: InstantTimestamp(milliseconds: time.milliseconds + 1)
    )
    expectNoDifference(linkResult.changedEntityIDs, ["project-1", "todo-1"], source)

    var todos = try await runtime.query(TodoProjectExample.todosWithProjectQuery)
    expectNoDifference(todos.first?.values["project"]?.first, .ref("project-1"), source)
    expectNoDifference(todos.first?.links?["project"]?.map(\.id), ["project-1"], source)
    var projects = try await runtime.query(TodoProjectExample.projectsWithTodosQuery)
    expectNoDifference(
      projects.first { $0.id == "project-1" }?.links?["todos"]?.map(\.id),
      ["todo-1"],
      source
    )

    let relinkResult = try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-unlink-and-link",
        operations: TodoProjectExample.unlinkOperations(
          todoID: "todo-1",
          projectID: "project-1",
          updatedAt: InstantTimestamp(milliseconds: time.milliseconds + 2),
          transactionID: "tx-unlink-and-link"
        ) + TodoProjectExample.linkOperations(
          todoID: "todo-1",
          projectID: "project-2",
          updatedAt: InstantTimestamp(milliseconds: time.milliseconds + 2),
          transactionID: "tx-unlink-and-link"
        )
      ),
      createdAt: InstantTimestamp(milliseconds: time.milliseconds + 2)
    )
    expectNoDifference(relinkResult.changedEntityIDs, ["project-1", "project-2", "todo-1"], source)

    todos = try await runtime.query(TodoProjectExample.todosWithProjectQuery)
    expectNoDifference(todos.first?.values["project"]?.first, .ref("project-2"), source)
    expectNoDifference(todos.first?.links?["project"]?.map(\.id), ["project-2"], source)
    expectNoDifference(
      todos.first?.links?["project"]?.first?.values["title"]?.first,
      .string("Archive"),
      source
    )
    projects = try await runtime.query(TodoProjectExample.projectsWithTodosQuery)
    expectNoDifference(
      projects.first { $0.id == "project-1" }?.links?["todos"]?.map(\.id),
      [],
      source
    )
    expectNoDifference(
      projects.first { $0.id == "project-2" }?.links?["todos"]?.map(\.id),
      ["todo-1"],
      source
    )
    expectNoDifference(
      projects.first { $0.id == "project-2" }?.links?["todos"]?.first?.values["text"]?.first,
      .string("Wire links"),
      source
    )
  }

  @Test
  func manyLinkUnlinkAndRelinkPortsUpstreamMultiLinkShape() async throws {
    let source = storeParitySource(
      "link/unlink multi",
      status: "adapted: Swift uses article/tag many-ref fixtures and reverse includes."
    )
    let time = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let attributes = articleTagAttributes()
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: temporaryCacheURL(),
        initialAttributes: attributes
      )
    )
    let query = InstantQueryPlan(
      id: "articles.with-tags",
      namespace: "articles",
      includes: [
        InstantQueryInclude(
          "tags",
          query: InstantQueryIncludePlan(
            id: "tags.included",
            namespace: "tags",
            order: InstantQueryOrder("name")
          )
        )
      ]
    )

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-many-link-seed",
        operations: [
          .insert(triple("article-1", "articles/title", .string("Build"), txID: "tx-many-link-seed", time: time)),
          .insert(triple("article-2", "articles/title", .string("Second"), txID: "tx-many-link-seed", time: time)),
          .insert(triple("tag-swift", "tags/name", .string("Swift"), txID: "tx-many-link-seed", time: time)),
          .insert(triple("tag-data", "tags/name", .string("Data"), txID: "tx-many-link-seed", time: time)),
          .insert(triple("tag-ui", "tags/name", .string("UI"), txID: "tx-many-link-seed", time: time)),
          .insert(triple("article-1", "articles/tags", .ref("tag-swift"), txID: "tx-many-link-seed", time: time)),
          .insert(triple("article-1", "articles/tags", .ref("tag-data"), txID: "tx-many-link-seed", time: time)),
          .insert(triple("article-2", "articles/tags", .ref("tag-ui"), txID: "tx-many-link-seed", time: time)),
        ]
      ),
      createdAt: time
    )

    var articles = try await runtime.query(query)
    expectNoDifference(
      articles.first { $0.id == "article-1" }?.values["tags"]?.values,
      [.ref("tag-data"), .ref("tag-swift")],
      source
    )
    expectNoDifference(
      articles.first { $0.id == "article-1" }?.links?["tags"]?.map(\.id),
      ["tag-data", "tag-swift"],
      source
    )
    expectNoDifference(
      articles.first { $0.id == "article-1" }?.links?["tags"]?.map { $0.values["name"]?.first },
      [.string("Data"), .string("Swift")],
      source
    )
    var tags = try await runtime.query(tagsWithArticlesQuery())
    expectNoDifference(
      tags.first { $0.id == "tag-data" }?.links?["articles"]?.map(\.id),
      ["article-1"],
      source
    )
    expectNoDifference(
      tags.first { $0.id == "tag-swift" }?.links?["articles"]?.map(\.id),
      ["article-1"],
      source
    )
    expectNoDifference(
      tags.first { $0.id == "tag-ui" }?.links?["articles"]?.map(\.id),
      ["article-2"],
      source
    )

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-many-unlink-relink",
        operations: [
          .retract(triple("article-1", "articles/tags", .ref("tag-swift"), txID: "tx-many-unlink-relink", time: time)),
          .retract(triple("article-1", "articles/tags", .ref("tag-data"), txID: "tx-many-unlink-relink", time: time)),
          .insert(triple("article-1", "articles/tags", .ref("tag-ui"), txID: "tx-many-unlink-relink", time: time)),
        ]
      ),
      createdAt: InstantTimestamp(milliseconds: time.milliseconds + 1)
    )

    articles = try await runtime.query(query)
    expectNoDifference(
      articles.first { $0.id == "article-1" }?.values["tags"]?.values,
      [.ref("tag-ui")],
      source
    )
    expectNoDifference(
      articles.first { $0.id == "article-1" }?.links?["tags"]?.map(\.id),
      ["tag-ui"],
      source
    )
    expectNoDifference(
      articles.first { $0.id == "article-1" }?.links?["tags"]?.first?.values["name"]?.first,
      .string("UI"),
      source
    )
    tags = try await runtime.query(tagsWithArticlesQuery())
    expectNoDifference(
      tags.first { $0.id == "tag-data" }?.links?["articles"]?.map(\.id),
      [],
      source
    )
    expectNoDifference(
      tags.first { $0.id == "tag-swift" }?.links?["articles"]?.map(\.id),
      [],
      source
    )
    expectNoDifference(
      tags.first { $0.id == "tag-ui" }?.links?["articles"]?.map(\.id),
      ["article-1", "article-2"],
      source
    )
  }

  @Test
  func storeSnapshotJSONRoundTripsAndRestoresMaterializedLinks() async throws {
    let source = storeParitySource(
      "JSON serialization round-trips",
      status: "adapted: Swift snapshots encode attributes and triples, then rematerialize links."
    )
    let time = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: temporaryCacheURL(),
        initialAttributes: TodoProjectExample.attributes
      )
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-snapshot-roundtrip",
        operations: TodoExample.createOperations(
          id: "todo-1",
          text: "Restore snapshot",
          createdAt: time,
          transactionID: "tx-snapshot-roundtrip"
        ) + TodoProjectExample.createProjectOperations(
          id: "project-1",
          title: "Launch",
          createdAt: time,
          transactionID: "tx-snapshot-roundtrip"
        ) + TodoProjectExample.linkOperations(
          todoID: "todo-1",
          projectID: "project-1",
          updatedAt: time,
          transactionID: "tx-snapshot-roundtrip"
        )
      ),
      createdAt: time
    )

    let snapshot = await runtime.store.snapshot()
    let data = try JSONEncoder().encode(snapshot)
    let decoded = try JSONDecoder().decode(InstantStoreSnapshot.self, from: data)
    expectNoDifference(decoded, snapshot, source)

    let restoredStore = InstantStore(snapshot: decoded)
    let restoredTodos = await restoredStore.materialize(TodoProjectExample.todosWithProjectQuery)
    let liveTodos = try await runtime.query(TodoProjectExample.todosWithProjectQuery)
    expectNoDifference(restoredTodos, liveTodos, source)
    let restoredProjects = await restoredStore.materialize(TodoProjectExample.projectsWithTodosQuery)
    let liveProjects = try await runtime.query(TodoProjectExample.projectsWithTodosQuery)
    expectNoDifference(restoredProjects, liveProjects, source)
  }

  @Test
  func ruleParamsNoOpsAndFollowingUpdateMaterializes() async throws {
    let source = storeParitySource(
      "ruleParams no-ops",
      status: "exact: rule params do not change the local store, while following writes still apply."
    )
    let time = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: temporaryCacheURL(),
        initialAttributes: [
          InstantAttribute(
            id: "users/handle",
            namespace: "users",
            name: "handle",
            valueType: .string
          )
        ]
      )
    )

    let result = try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-rule-params-no-op",
        operations: [
          .ruleParams(
            entityID: "user-rule-params",
            namespace: "users",
            params: .object(["guestId": .string("bobby")])
          ),
          .insert(
            triple(
              "user-rule-params",
              "users/handle",
              .string("bobby"),
              txID: "tx-rule-params-no-op",
              time: time
            )
          ),
        ]
      ),
      createdAt: time
    )

    let users = try await runtime.query(InstantQueryPlan(id: "rule-params.users", namespace: "users"))
    expectNoDifference(result.changedEntityIDs, ["user-rule-params"], source)
    expectNoDifference(result.tripleCount, 1, source)
    expectNoDifference(users.map { $0.values["handle"]?.first }, [.string("bobby")], source)
  }

  @Test
  func addingAndRenamingAttributesReindexesExistingTriples() async throws {
    let newAttrSource = storeParitySource(
      "new attrs",
      status: "adapted: Swift merges link attributes and reindexes existing triples."
    )
    let updateAttrSource = storeParitySource(
      "update attr",
      status: "adapted: Swift updates an attribute name by replacing the attribute with the same id."
    )
    let deleteAttrSource = storeParitySource(
      "delete attr",
      status: "adapted: Swift replaces the attribute set and hides triples for removed attrs."
    )
    let time = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let handle = InstantAttribute(
      id: "users/handle",
      namespace: "users",
      name: "handle",
      valueType: .string
    )
    let fullName = InstantAttribute(
      id: "users/fullName",
      namespace: "users",
      name: "fullName",
      valueType: .string
    )
    let colorsName = InstantAttribute(
      id: "colors/name",
      namespace: "colors",
      name: "name",
      valueType: .string
    )
    let usersColors = InstantAttribute(
      id: "users/colors",
      namespace: "users",
      name: "colors",
      valueType: .ref,
      cardinality: .many,
      forwardIdentity: "users/colors",
      reverseIdentity: "colors/users",
      linkNamespace: "colors"
    )
    let store = InstantStore(
      snapshot: InstantStoreSnapshot(
        attributes: [handle, fullName],
        triples: [
          triple("user-1", "users/handle", .string("bobby"), txID: "tx-attrs", time: time),
          triple("user-1", "users/fullName", .string("Bob Bobby"), txID: "tx-attrs", time: time),
          triple("user-1", "users/colors", .ref("color-1"), txID: "tx-attrs", time: time),
          triple("color-1", "colors/name", .string("red"), txID: "tx-attrs", time: time),
        ]
      )
    )

    var users = await store.materialize(InstantQueryPlan(id: "users", namespace: "users"))
    expectNoDifference(users.first?.values["handle"]?.first, .string("bobby"), newAttrSource)
    expectNoDifference(users.first?.values["fullName"]?.first, .string("Bob Bobby"), newAttrSource)
    #expect(users.first?.values["colors"] == nil)

    _ = await store.mergeAttributes([colorsName, usersColors])
    let usersWithColors = await store.materialize(
      InstantQueryPlan(
        id: "users.colors",
        namespace: "users",
        includes: [InstantQueryInclude("colors")]
      )
    )
    expectNoDifference(
      usersWithColors.first?.values["colors"]?.values,
      [.ref("color-1")],
      newAttrSource
    )
    expectNoDifference(usersWithColors.first?.links?["colors"]?.map(\.id), ["color-1"], newAttrSource)
    expectNoDifference(
      usersWithColors.first?.links?["colors"]?.first?.values["name"]?.first,
      .string("red"),
      newAttrSource
    )
    let colorsWithUsers = await store.materialize(
      InstantQueryPlan(
        id: "colors.users",
        namespace: "colors",
        includes: [InstantQueryInclude("users", direction: .reverse)]
      )
    )
    expectNoDifference(
      colorsWithUsers.first?.links?["users"]?.map(\.id),
      ["user-1"],
      newAttrSource
    )
    expectNoDifference(
      colorsWithUsers.first?.links?["users"]?.first?.values["handle"]?.first,
      .string("bobby"),
      newAttrSource
    )

    let renamedFullName = InstantAttribute(
      id: "users/fullName",
      namespace: "users",
      name: "fullNamez",
      valueType: .string
    )
    _ = await store.mergeAttributes([renamedFullName])

    users = await store.materialize(InstantQueryPlan(id: "users.renamed", namespace: "users"))
    #expect(users.first?.values["fullName"] == nil)
    expectNoDifference(users.first?.values["fullNamez"]?.first, .string("Bob Bobby"), updateAttrSource)

    _ = await store.replaceAttributes([handle, colorsName, usersColors])

    users = await store.materialize(InstantQueryPlan(id: "users.deleted-attr", namespace: "users"))
    expectNoDifference(users.first?.values["handle"]?.first, .string("bobby"), deleteAttrSource)
    #expect(users.first?.values["fullNamez"] == nil)
    let usersAfterDeleteAttr = await store.materialize(
      InstantQueryPlan(
        id: "users.deleted-attr.colors",
        namespace: "users",
        includes: [InstantQueryInclude("colors")]
      )
    )
    expectNoDifference(
      usersAfterDeleteAttr.first?.links?["colors"]?.map(\.id),
      ["color-1"],
      deleteAttrSource
    )
  }

  @Test
  func storeDeepMergePortsUpstreamObjectArrayAndNullSemantics() async throws {
    let source = storeParitySource(
      "deepMerge",
      status: "adapted: Swift JSONValue has null but not undefined, so null deletion and array overwrite are covered."
    )
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: temporaryCacheURL(),
        initialAttributes: [
          InstantAttribute(
            id: "games/state",
            namespace: "games",
            name: "state",
            valueType: .json
          )
        ]
      )
    )
    let time = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let secondTime = InstantTimestamp(milliseconds: time.milliseconds + 5)
    let mergeTime = InstantTimestamp(milliseconds: time.milliseconds + 10)

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-game-state-seed",
        operations: [
          .insert(
            InstantTriple(
              entityID: "game-1",
              attributeID: "games/state",
              value: .json(
                .object([
                  "score": .number(100),
                  "playerStats": .object([
                    "health": .number(50),
                    "mana": .number(30),
                    "ambitions": .object(["win": .bool(true)]),
                  ]),
                  "inventory": .array([.string("sword"), .string("potion")]),
                  "locations": .array([.string("forest"), .string("castle")]),
                  "level": .number(2),
                ])
              ),
              txID: "tx-game-state-seed",
              txTime: time
            )
          ),
          .insert(
            InstantTriple(
              entityID: "game-2",
              attributeID: "games/state",
              value: .json(.object(["level": .number(1)])),
              txID: "tx-game-state-seed",
              txTime: secondTime
            )
          )
        ]
      ),
      createdAt: time
    )

    let mergeResult = try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-game-state-merge",
        operations: [
          .merge(
            InstantTriple(
              entityID: "game-1",
              attributeID: "games/state",
              value: .json(
                .object([
                  "playerStats": .object([
                    "health": .null,
                    "mana": .number(40),
                    "stamina": .number(20),
                    "ambitions": .object([
                      "acquireWisdom": .bool(true),
                      "find": .array([.string("love")]),
                    ]),
                  ]),
                  "inventory": .array([.string("shield")]),
                  "score": .null,
                  "locations": .array([.string("forest"), .null, .string("castle")]),
                ])
              ),
              txID: "tx-game-state-merge",
              txTime: mergeTime
            )
          ),
          .merge(
            InstantTriple(
              entityID: "game-missing",
              attributeID: "games/state",
              value: .json(.object(["level": .number(99)])),
              txID: "tx-game-state-merge",
              txTime: mergeTime
            )
          )
        ]
      ),
      createdAt: mergeTime
    )
    expectNoDifference(mergeResult.changedEntityIDs, ["game-1"], source)

    let games = try await runtime.query(
      InstantQueryPlan(id: "games", namespace: "games", order: .serverCreatedAt)
    )
    expectNoDifference(games.map(\.id), ["game-1", "game-2"], source)
    let state = try #require(games.first { $0.id == "game-1" }?.values["state"]?.first)
    expectNoDifference(
      state,
      .json(
        .object([
          "playerStats": .object([
            "mana": .number(40),
            "stamina": .number(20),
            "ambitions": .object([
              "win": .bool(true),
              "acquireWisdom": .bool(true),
              "find": .array([.string("love")]),
            ]),
          ]),
          "inventory": .array([.string("shield")]),
          "locations": .array([.string("forest"), .null, .string("castle")]),
          "level": .number(2),
        ])
      ),
      source
    )
  }

  @Test
  func recursiveLinksWithSameRawIDDeleteOnlyRequestedNamespace() async throws {
    let source = storeParitySource(
      "recursive links w same id",
      status: "adapted: Swift uses deleteEntityInNamespace for the schema-aware delete step."
    )
    let time = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let sameID = "shared-raw-id"
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: temporaryCacheURL(),
        initialAttributes: [
          InstantAttribute(
            id: "todos/title",
            namespace: "todos",
            name: "title",
            valueType: .string,
            isRequired: false
          ),
          InstantAttribute(
            id: "todos/completed",
            namespace: "todos",
            name: "completed",
            valueType: .boolean,
            isRequired: false
          ),
          InstantAttribute(
            id: "todos/createdBy",
            namespace: "todos",
            name: "createdBy",
            valueType: .ref,
            isIndexed: true,
            forwardIdentity: "todos/createdBy",
            reverseIdentity: "fakeUsers/todos",
            linkNamespace: "fakeUsers",
            onDelete: .cascade
          ),
          InstantAttribute(
            id: "fakeUsers/email",
            namespace: "fakeUsers",
            name: "email",
            valueType: .string,
            isRequired: false,
            isIndexed: true,
            isUnique: true
          ),
        ]
      )
    )

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-recursive-same-id-seed",
        operations: [
          .insert(
            triple(
              sameID,
              "todos/title",
              .string("todo"),
              txID: "tx-recursive-same-id-seed",
              time: time
            )
          ),
          .insert(
            triple(
              sameID,
              "todos/completed",
              .bool(false),
              txID: "tx-recursive-same-id-seed",
              time: time
            )
          ),
          .insert(
            triple(
              sameID,
              "fakeUsers/email",
              .string("test@test.com"),
              txID: "tx-recursive-same-id-seed",
              time: time
            )
          ),
          .insert(
            triple(
              sameID,
              "todos/createdBy",
              .ref(sameID),
              txID: "tx-recursive-same-id-seed",
              time: time
            )
          ),
        ]
      ),
      createdAt: time
    )

    var todos = try await runtime.query(InstantQueryPlan(id: "recursive.todos", namespace: "todos"))
    var fakeUsers = try await runtime.query(
      InstantQueryPlan(id: "recursive.fake-users", namespace: "fakeUsers")
    )
    expectNoDifference(todos.map(\.id), [sameID], source)
    expectNoDifference(fakeUsers.map(\.id), [sameID], source)

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-recursive-same-id-delete-todo",
        operations: [
          .deleteEntityInNamespace(entityID: sameID, namespace: "todos")
        ]
      ),
      createdAt: InstantTimestamp(milliseconds: time.milliseconds + 1)
    )

    todos = try await runtime.query(InstantQueryPlan(id: "recursive.todos.after", namespace: "todos"))
    fakeUsers = try await runtime.query(
      InstantQueryPlan(id: "recursive.fake-users.after", namespace: "fakeUsers")
    )
    expectNoDifference(todos.map(\.id), [], source)
    expectNoDifference(fakeUsers.map(\.id), [sameID], source)
    expectNoDifference(fakeUsers.first?.values["email"]?.first, .string("test@test.com"), source)
  }

  @Test
  func dateConversionMaterializesDateTypedSchemaValues() async throws {
    let dateSource = storeParitySource(
      "date conversion",
      status: "exact: date inputs materialize as Date values for date attributes."
    )
    let numberSource = storeParitySource(
      "date conversion",
      status: "adapted: Swift always materializes date attributes as Date values, including number inputs."
    )
    let time = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let dateInput = Date(timeIntervalSince1970: 1_700_000_000)
    let numberMilliseconds = 99_999_999_999_999.0
    let numberDate = Date(timeIntervalSince1970: numberMilliseconds / 1000)

    let dateRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: temporaryCacheURL(),
        initialAttributes: dateConversionTodoAttributes()
      )
    )
    try await dateRuntime.transact(
      InstantStoreTransaction(
        id: "tx-date-conversion-date",
        operations: [
          .insert(triple("todo-date", "todos/title", .string("todo"), txID: "tx-date-conversion-date", time: time)),
          .insert(triple("todo-date", "todos/completed", .bool(false), txID: "tx-date-conversion-date", time: time)),
          .insert(triple("todo-date", "todos/createdAt", .date(dateInput), txID: "tx-date-conversion-date", time: time)),
        ]
      ),
      createdAt: time
    )
    let dateTodos = try await dateRuntime.query(InstantQueryPlan(id: "date-conversion.date", namespace: "todos"))
    expectNoDifference(dateTodos.count, 1, dateSource)
    expectNoDifference(
      dateTodos.map { storeParityISOString(from: $0.values["createdAt"]?.first) },
      [storeParityISOString(from: dateInput)],
      dateSource
    )

    let numberRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: temporaryCacheURL(),
        initialAttributes: dateConversionTodoAttributes()
      )
    )
    try await numberRuntime.transact(
      InstantStoreTransaction(
        id: "tx-date-conversion-number",
        operations: [
          .insert(triple("todo-number", "todos/title", .string("todo"), txID: "tx-date-conversion-number", time: time)),
          .insert(triple("todo-number", "todos/completed", .bool(false), txID: "tx-date-conversion-number", time: time)),
          .insert(
            triple(
              "todo-number",
              "todos/createdAt",
              .number(numberMilliseconds),
              txID: "tx-date-conversion-number",
              time: time
            )
          ),
        ]
      ),
      createdAt: time
    )
    let numberTodos = try await numberRuntime.query(
      InstantQueryPlan(id: "date-conversion.number", namespace: "todos")
    )
    expectNoDifference(numberTodos.count, 1, numberSource)
    expectNoDifference(
      numberTodos.map { storeParityISOString(from: $0.values["createdAt"]?.first) },
      [storeParityISOString(from: numberDate)],
      numberSource
    )
  }

  @Test
  func v0StoreSnapshotRestoresFromLegacyAttrsPayload() async throws {
    let source = storeParitySource(
      "v0 store restores",
      status: "adapted: Swift accepts legacy attrs/triples snapshot payloads and rematerializes indexes."
    )
    let time = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: temporaryCacheURL(),
        initialAttributes: userBookshelfAttributes()
      )
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-v0-restore-seed",
        operations: [
          .insert(triple("user-1", "users/handle", .string("bobby"), txID: "tx-v0-restore-seed", time: time)),
          .insert(triple("user-1", "users/bookshelves", .ref("bookshelf-1"), txID: "tx-v0-restore-seed", time: time)),
          .insert(triple("bookshelf-1", "bookshelves/name", .string("my books"), txID: "tx-v0-restore-seed", time: time)),
        ]
      ),
      createdAt: time
    )

    let snapshot = await runtime.store.snapshot()
    let legacyData = try JSONEncoder().encode(
      LegacyStoreSnapshotPayload(attrs: snapshot.attributes, triples: snapshot.triples)
    )
    let decoded = try JSONDecoder().decode(InstantStoreSnapshot.self, from: legacyData)
    expectNoDifference(decoded, snapshot, source)

    let restoredStore = InstantStore(snapshot: decoded)
    let restoredUsers = await restoredStore.materialize(usersWithBookshelvesQuery())
    let liveUsers = try await runtime.query(usersWithBookshelvesQuery())
    expectNoDifference(restoredUsers, liveUsers, source)
  }

  private func temporaryCacheURL() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataStoreParityTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("state.sqlite")
  }

  private func triple(
    _ entityID: String,
    _ attributeID: String,
    _ value: InstantValue,
    txID: String,
    time: InstantTimestamp
  ) -> InstantTriple {
    InstantTriple(
      entityID: entityID,
      attributeID: attributeID,
      value: value,
      txID: txID,
      txTime: time
    )
  }

  private func articleTagAttributes() -> [InstantAttribute] {
    [
      InstantAttribute(
        id: "articles/title",
        namespace: "articles",
        name: "title",
        valueType: .string
      ),
      InstantAttribute(
        id: "articles/tags",
        namespace: "articles",
        name: "tags",
        valueType: .ref,
        cardinality: .many,
        forwardIdentity: "articles/tags",
        reverseIdentity: "tags/articles",
        linkNamespace: "tags"
      ),
      InstantAttribute(
        id: "tags/name",
        namespace: "tags",
        name: "name",
        valueType: .string
      ),
    ]
  }

  private func tagsWithArticlesQuery() -> InstantQueryPlan {
    InstantQueryPlan(
      id: "tags.with-articles",
      namespace: "tags",
      order: InstantQueryOrder("name"),
      includes: [
        InstantQueryInclude(
          "articles",
          direction: .reverse,
          query: InstantQueryIncludePlan(
            id: "articles.included",
            namespace: "articles",
            order: InstantQueryOrder("title")
          )
        )
      ]
    )
  }

  private func userBookshelfAttributes() -> [InstantAttribute] {
    [
      InstantAttribute(
        id: "users/handle",
        namespace: "users",
        name: "handle",
        valueType: .string,
        isIndexed: true
      ),
      InstantAttribute(
        id: "users/bookshelves",
        namespace: "users",
        name: "bookshelves",
        valueType: .ref,
        cardinality: .many,
        isIndexed: true,
        forwardIdentity: "users/bookshelves",
        reverseIdentity: "bookshelves/users",
        linkNamespace: "bookshelves"
      ),
      InstantAttribute(
        id: "bookshelves/name",
        namespace: "bookshelves",
        name: "name",
        valueType: .string,
        isIndexed: true
      ),
    ]
  }

  private func usersWithBookshelvesQuery() -> InstantQueryPlan {
    InstantQueryPlan(
      id: "users.with-bookshelves",
      namespace: "users",
      filters: [.equals(field: "handle", value: .string("bobby"))],
      includes: [
        InstantQueryInclude(
          "bookshelves",
          query: InstantQueryIncludePlan(
            id: "bookshelves.included",
            namespace: "bookshelves",
            order: InstantQueryOrder("name")
          )
        )
      ]
    )
  }

  private func bookCascadeAttributes(
    linkName: String,
    reverseName: String,
    cardinality: InstantCardinality = .one,
    onDelete: InstantDeleteRule = .none,
    onDeleteReverse: InstantDeleteRule = .none
  ) -> [InstantAttribute] {
    [
      InstantAttribute(
        id: "books/title",
        namespace: "books",
        name: "title",
        valueType: .string
      ),
      InstantAttribute(
        id: "books/description",
        namespace: "books",
        name: "description",
        valueType: .string,
        isIndexed: true
      ),
      InstantAttribute(
        id: "books/\(linkName)",
        namespace: "books",
        name: linkName,
        valueType: .ref,
        cardinality: cardinality,
        isIndexed: true,
        forwardIdentity: "books/\(linkName)",
        reverseIdentity: "books/\(reverseName)",
        linkNamespace: "books",
        onDelete: onDelete,
        onDeleteReverse: onDeleteReverse
      ),
    ]
  }

  private func bookSeriesQuery(id: String) -> InstantQueryPlan {
    InstantQueryPlan(
      id: id,
      namespace: "books",
      filters: [.equals(field: "description", value: .string("series"))]
    )
  }

  private func dateConversionTodoAttributes() -> [InstantAttribute] {
    [
      InstantAttribute(
        id: "todos/title",
        namespace: "todos",
        name: "title",
        valueType: .string,
        isRequired: false
      ),
      InstantAttribute(
        id: "todos/completed",
        namespace: "todos",
        name: "completed",
        valueType: .boolean,
        isRequired: false
      ),
      InstantAttribute(
        id: "todos/createdAt",
        namespace: "todos",
        name: "createdAt",
        valueType: .date,
        isRequired: false
      ),
    ]
  }

  private func storeParityISOString(from value: InstantValue?) -> String? {
    guard case let .date(date) = value else { return nil }
    return storeParityISOString(from: date)
  }

  private func storeParityISOString(from date: Date) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
    return formatter.string(from: date)
  }
}

private let upstreamStoreTestSource =
  "upstream/instant/client/packages/core/__tests__/src/store.test.ts"

private func storeParitySource(_ testName: String, status: String) -> String {
  "\(upstreamStoreTestSource) \(testName) [\(status)]"
}

private struct LegacyStoreSnapshotPayload: Encodable {
  var attrs: [InstantAttribute]
  var triples: [InstantTriple]
  var cardinalityInference: [String: String] = [:]
  var linkIndex: [String: String] = [:]
  var useDateObjects = true
  var type = "store"

  private enum CodingKeys: String, CodingKey {
    case attrs
    case triples
    case cardinalityInference
    case linkIndex
    case useDateObjects
    case type = "__type"
  }
}
