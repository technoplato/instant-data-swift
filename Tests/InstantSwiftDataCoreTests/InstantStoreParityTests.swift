import CustomDump
import Foundation
@testable import InstantSwiftDataCore
import Testing

@Suite(.serialized)
struct InstantStoreParityTests {
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
}

private let upstreamStoreTestSource =
  "upstream/instant/client/packages/core/__tests__/src/store.test.ts"

private func storeParitySource(_ testName: String, status: String) -> String {
  "\(upstreamStoreTestSource) \(testName) [\(status)]"
}
