import CustomDump
import Foundation
@testable import InstantSwiftDataCore
import Testing

@Suite(.serialized)
struct InstantTransactionValidationParityTests {
  @Test
  func upstreamValidatesBasicTransactionChunks() async throws {
    let runtime = try await parityRuntime()
    let time = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let source = transactionValidationSource(
      "validates basic transaction chunk",
      assertion: "lines 88-106 basic chunk and chunk arrays",
      status:
        "adapted: Swift transactions are already structured, so this covers valid concrete chunks."
    )

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-parity-basic",
        operations: [
          .insert(
            triple("user-basic", "users/name", .string("John"), txID: "tx-parity-basic", time: time)
          ),
          .insert(
            triple(
              "user-basic", "users/email", .string("john@example.com"), txID: "tx-parity-basic",
              time: time)),
        ]
      ),
      createdAt: time
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-parity-array",
        operations: [
          .insert(
            triple("user-array", "users/name", .string("Jane"), txID: "tx-parity-array", time: time)
          ),
          .insert(
            triple(
              "user-array", "users/email", .string("jane@example.com"), txID: "tx-parity-array",
              time: time)),
          .insert(
            triple(
              "post-array", "posts/title", .string("Hello"), txID: "tx-parity-array", time: time)),
          .insert(
            triple(
              "post-array", "posts/body", .string("World"), txID: "tx-parity-array", time: time)),
        ]
      ),
      createdAt: time
    )

    let users = try await runtime.query(
      InstantQueryPlan(id: "parity.basic.users", namespace: "users"))
    expectNoDifference(users.map(\.id), ["user-array", "user-basic"], source)
  }

  @Test
  func upstreamValidatesCreateAndUpdateOperations() async throws {
    let runtime = try await parityRuntime()
    let time = InstantTimestamp(milliseconds: 1_700_000_000_010)
    let source = transactionValidationSource(
      "validates create/update operations",
      assertion: "lines 109-169 create/update valid, wrong type, and unknown attrs",
      status:
        "adapted: Swift writes triples directly, so unknown scalar attrs remain permissive while declared attrs are type checked."
    )

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-parity-create",
        operations: [
          .insert(
            triple(
              "user-create", "users/name", .string("John"), txID: "tx-parity-create", time: time)),
          .insert(
            triple(
              "user-create", "users/email", .string("john-create@example.com"),
              txID: "tx-parity-create", time: time)),
          .insert(
            triple(
              "user-create", "users/bio", .string("Developer"), txID: "tx-parity-create", time: time
            )),
          .insert(
            triple(
              "user-create", "users/unknownField", .string("value"), txID: "tx-parity-create",
              time: time)),
        ]
      ),
      createdAt: time
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-parity-update",
        operations: [
          .insert(
            triple(
              "user-create", "users/name", .string("Jane"), txID: "tx-parity-update", time: time)),
          .insert(
            triple(
              "user-create", "users/bio", .string("Updated bio"), txID: "tx-parity-update",
              time: time)),
        ]
      ),
      createdAt: time
    )

    let users = try await runtime.query(
      InstantQueryPlan(id: "parity.create.users", namespace: "users"))
    expectNoDifference(users.map { $0.values["name"]?.first }, [.string("Jane")], source)
    expectNoDifference(users.map { $0.values["unknownField"]?.first }, [nil], source)

    await expectTransactionValidation(namespace: "unknownNamespace", path: nil, source: source) {
      try await runtime.transact(
        InstantStoreTransaction(
          id: "tx-parity-unknown-namespace",
          operations: [
            .insert(
              triple(
                "unknown-1",
                "unknownNamespace/field",
                .string("value"),
                txID: "tx-parity-unknown-namespace",
                time: time
              )
            )
          ]
        ),
        createdAt: time
      )
    }

    await expectTransactionValidation(namespace: "unknownNamespace", path: nil, source: source) {
      try await runtime.transact(
        InstantStoreTransaction(
          id: "tx-parity-unknown-namespace-id",
          operations: [
            .insert(
              triple(
                "unknown-1",
                "unknownNamespace/id",
                .string("unknown-1"),
                txID: "tx-parity-unknown-namespace-id",
                time: time
              )
            )
          ]
        ),
        createdAt: time
      )
    }

    await expectTransactionValidation(namespace: "users", path: "name", source: source) {
      try await runtime.transact(
        InstantStoreTransaction(
          id: "tx-parity-create-wrong-number",
          operations: [
            .insert(
              triple(
                "user-create-wrong",
                "users/name",
                .number(123),
                txID: "tx-parity-create-wrong-number",
                time: time
              )
            )
          ]
        ),
        createdAt: time
      )
    }

    await expectTransactionValidation(namespace: "users", path: "name", source: source) {
      try await runtime.transact(
        InstantStoreTransaction(
          id: "tx-parity-update-wrong-bool",
          operations: [
            .insert(
              triple(
                "user-create",
                "users/name",
                .bool(true),
                txID: "tx-parity-update-wrong-bool",
                time: time
              )
            )
          ]
        ),
        createdAt: time
      )
    }
  }

  @Test
  func upstreamValidatesMergeAndDeleteOperations() async throws {
    let runtime = try await parityRuntime()
    let time = InstantTimestamp(milliseconds: 1_700_000_000_020)
    let source = transactionValidationSource(
      "validates merge/delete operations",
      assertion: "lines 172-187 merge valid, merge wrong type, and delete valid",
      status: "adapted: Swift merge is a triple operation and delete removes the entity by id."
    )

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-parity-merge-seed",
        operations: [
          .insert(
            triple(
              "user-merge", "users/name", .string("John"), txID: "tx-parity-merge-seed", time: time)
          ),
          .insert(
            triple(
              "user-merge", "users/email", .string("john-merge@example.com"),
              txID: "tx-parity-merge-seed", time: time)),
          .insert(
            triple(
              "user-merge",
              "users/stuff",
              .json(.object(["custom": .string("before")])),
              txID: "tx-parity-merge-seed",
              time: time
            )
          ),
        ]
      ),
      createdAt: time
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-parity-merge",
        operations: [
          .merge(
            triple(
              "user-merge",
              "users/stuff",
              .json(.object(["other": .string("value")])),
              txID: "tx-parity-merge",
              time: time
            )
          )
        ]
      ),
      createdAt: time
    )
    let merged = try await runtime.query(
      InstantQueryPlan(id: "parity.merge.users", namespace: "users"))
    expectNoDifference(
      merged.first?.values["stuff"]?.first,
      .json(.object(["custom": .string("before"), "other": .string("value")])),
      source
    )

    await expectTransactionValidation(namespace: "users", path: "name", source: source) {
      try await runtime.transact(
        InstantStoreTransaction(
          id: "tx-parity-merge-wrong-type",
          operations: [
            .merge(
              triple(
                "user-merge",
                "users/name",
                .number(123),
                txID: "tx-parity-merge-wrong-type",
                time: time
              )
            )
          ]
        ),
        createdAt: time
      )
    }

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-parity-delete",
        operations: [.deleteEntity("user-merge")]
      ),
      createdAt: time
    )
    let afterDelete = try await runtime.query(
      InstantQueryPlan(id: "parity.merge.after-delete", namespace: "users"))
    expectNoDifference(afterDelete.map(\.id), [], source)
  }

  @Test
  func upstreamValidatesLinkAndUnlinkOperations() async throws {
    let runtime = try await parityRuntime()
    let time = InstantTimestamp(milliseconds: 1_700_000_000_030)
    let source = transactionValidationSource(
      "validates link/unlink operations",
      assertion: "lines 189-222 valid links, arrays, unknown links, and invalid link values",
      status:
        "adapted: Swift links are ref triples; inserting multiple triples represents an array link, and retracting represents unlink."
    )

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-parity-link-seed",
        operations: [
          .insert(
            triple(
              "user-link", "users/name", .string("John"), txID: "tx-parity-link-seed", time: time)),
          .insert(
            triple(
              "post-link-1", "posts/title", .string("Hello"), txID: "tx-parity-link-seed",
              time: time)),
          .insert(
            triple(
              "post-link-2", "posts/title", .string("Again"), txID: "tx-parity-link-seed",
              time: time)),
          .insert(
            triple(
              "comment-link", "comments/body", .string("Nice"), txID: "tx-parity-link-seed",
              time: time)),
        ]
      ),
      createdAt: time
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-parity-link",
        operations: [
          .insert(
            triple(
              "post-link-1", "posts/author", .ref("user-link"), txID: "tx-parity-link", time: time)),
          .insert(
            triple(
              "post-link-2", "posts/author", .ref("user-link"), txID: "tx-parity-link", time: time)),
          .insert(
            triple(
              "comment-link", "comments/post", .ref("post-link-1"), txID: "tx-parity-link",
              time: time)),
        ]
      ),
      createdAt: time
    )
    var posts = try await runtime.query(
      InstantQueryPlan(id: "parity.link.posts", namespace: "posts"))
    expectNoDifference(
      posts.map { $0.values["author"]?.first }, [.ref("user-link"), .ref("user-link")], source)

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-parity-unlink",
        operations: [
          .retract(
            triple(
              "post-link-2", "posts/author", .ref("user-link"), txID: "tx-parity-unlink", time: time
            ))
        ]
      ),
      createdAt: time
    )
    posts = try await runtime.query(InstantQueryPlan(id: "parity.unlink.posts", namespace: "posts"))
    expectNoDifference(posts.map { $0.values["author"]?.first }, [.ref("user-link"), nil], source)

    await expectTransactionValidation(namespace: nil, path: "users/unknownLink", source: source) {
      try await runtime.transact(
        InstantStoreTransaction(
          id: "tx-parity-unknown-link",
          operations: [
            .insert(
              triple(
                "user-link",
                "users/unknownLink",
                .ref("post-link-1"),
                txID: "tx-parity-unknown-link",
                time: time
              )
            )
          ]
        ),
        createdAt: time
      )
    }

    await expectTransactionValidation(namespace: "posts", path: "author", source: source) {
      try await runtime.transact(
        InstantStoreTransaction(
          id: "tx-parity-invalid-link-value",
          operations: [
            .insert(
              triple(
                "post-link-1",
                "posts/author",
                .string("not-a-ref"),
                txID: "tx-parity-invalid-link-value",
                time: time
              )
            )
          ]
        ),
        createdAt: time
      )
    }
  }

  @Test
  func upstreamValidatesChainedOperationsAndMultipleEntityTypes() async throws {
    let runtime = try await parityRuntime()
    let time = InstantTimestamp(milliseconds: 1_700_000_000_040)
    let source = transactionValidationSource(
      "validates chained operations and multiple entity types",
      assertion: "lines 305-358 chains, users/posts/comments, and self links",
      status:
        "adapted: Swift chains are a single transaction containing the same concrete create, update, and link triples."
    )

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-parity-chain",
        operations: [
          .insert(
            triple("user-chain", "users/name", .string("John"), txID: "tx-parity-chain", time: time)
          ),
          .insert(
            triple(
              "user-chain", "users/email", .string("john-chain@example.com"),
              txID: "tx-parity-chain", time: time)),
          .insert(
            triple(
              "user-chain", "users/bio", .string("Updated"), txID: "tx-parity-chain", time: time)),
          .insert(
            triple(
              "user-friend", "users/name", .string("Friend"), txID: "tx-parity-chain", time: time)),
          .insert(
            triple(
              "post-chain", "posts/title", .string("Hello"), txID: "tx-parity-chain", time: time)),
          .insert(
            triple(
              "post-chain", "posts/body", .string("World"), txID: "tx-parity-chain", time: time)),
          .insert(
            triple(
              "comment-chain", "comments/body", .string("Nice post!"), txID: "tx-parity-chain",
              time: time)),
          .insert(
            triple(
              "post-chain", "posts/author", .ref("user-chain"), txID: "tx-parity-chain", time: time)
          ),
          .insert(
            triple(
              "comment-chain", "comments/post", .ref("post-chain"), txID: "tx-parity-chain",
              time: time)),
          .insert(
            triple(
              "user-chain", "users/friends", .ref("user-friend"), txID: "tx-parity-chain",
              time: time)),
        ]
      ),
      createdAt: time
    )

    let users = try await runtime.query(
      InstantQueryPlan(id: "parity.chain.users", namespace: "users"))
    let posts = try await runtime.query(
      InstantQueryPlan(id: "parity.chain.posts", namespace: "posts"))
    let comments = try await runtime.query(
      InstantQueryPlan(id: "parity.chain.comments", namespace: "comments"))
    expectNoDifference(users.map(\.id), ["user-chain", "user-friend"], source)
    expectNoDifference(posts.map { $0.values["author"]?.first }, [.ref("user-chain")], source)
    expectNoDifference(comments.map { $0.values["post"]?.first }, [.ref("post-chain")], source)

    await expectTransactionValidation(
      namespace: nil, path: "users/unlinkedWithAnything", source: source
    ) {
      try await runtime.transact(
        InstantStoreTransaction(
          id: "tx-parity-unlinked-link",
          operations: [
            .insert(
              triple(
                "user-chain",
                "users/unlinkedWithAnything",
                .ref("unlinked-1"),
                txID: "tx-parity-unlinked-link",
                time: time
              )
            )
          ]
        ),
        createdAt: time
      )
    }
  }

  @Test
  func upstreamValidatesWithoutSchemaAndAdaptsLocalIDFormat() async throws {
    let withoutSchemaSource = transactionValidationSource(
      "validates without schema",
      assertion: "lines 360-368 arbitrary entity, scalar, and link-shaped values without a schema",
      status:
        "exact: when no attributes are declared, Swift accepts arbitrary namespaces and values."
    )
    let uuidSource = transactionValidationSource(
      "validates UUID format for entity IDs",
      assertion: "lines 371-387 entity id validation",
      status:
        "adapted: Swift's local store accepts stable local IDs that are not UUIDs."
    )
    let time = InstantTimestamp(milliseconds: 1_700_000_000_042)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: temporaryParityCacheURL(),
        initialAttributes: []
      )
    )

    let result = try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-parity-without-schema",
        operations: [
          .insert(
            triple(
              "not a valid uuid",
              "randomEntity/anyField",
              .string("anyValue"),
              txID: "tx-parity-without-schema",
              time: time
            )
          ),
          .insert(
            triple(
              "not a valid uuid",
              "randomEntity/anyNumber",
              .number(123),
              txID: "tx-parity-without-schema",
              time: time
            )
          ),
          .insert(
            triple(
              "not a valid uuid",
              "randomEntity/anyLink",
              .ref("also-not-a-uuid"),
              txID: "tx-parity-without-schema",
              time: time
            )
          ),
        ]
      ),
      createdAt: time
    )

    let snapshot = await runtime.store.snapshot()
    expectNoDifference(result.changedEntityIDs, ["not a valid uuid"], uuidSource)
    expectNoDifference(result.tripleCount, 3, withoutSchemaSource)
    expectNoDifference(
      snapshot.triples.map { $0.attributeID },
      ["randomEntity/anyField", "randomEntity/anyLink", "randomEntity/anyNumber"],
      withoutSchemaSource
    )
  }

  @Test
  func upstreamValidatesDateAndLookupValueTypes() async throws {
    let runtime = try await parityRuntime()
    let time = InstantTimestamp(milliseconds: 1_700_000_000_045)
    let source = transactionValidationSource(
      "validates attribute types and lookup proxy",
      assertion: "lines 244-280 and 415-449 date-compatible lookup values",
      status:
        "adapted: Swift has no any type, so this covers declared string/json/date/ref compatibility and date lookup coercion."
    )

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-parity-date-values",
        operations: [
          .insert(
            triple(
              "user-date-string", "users/name", .string("String Date"),
              txID: "tx-parity-date-values", time: time)),
          .insert(
            triple(
              "user-date-string", "users/email", .string("date-string@example.com"),
              txID: "tx-parity-date-values", time: time)),
          .insert(
            triple(
              "user-date-string",
              "users/createdAt",
              .string("2025-01-15 20:53:08.200"),
              txID: "tx-parity-date-values",
              time: time
            )
          ),
          .insert(
            triple(
              "user-date-number", "users/name", .string("Number Date"),
              txID: "tx-parity-date-values", time: time)),
          .insert(
            triple(
              "user-date-number", "users/email", .string("date-number@example.com"),
              txID: "tx-parity-date-values", time: time)),
          .insert(
            triple(
              "user-date-number",
              "users/createdAt",
              .number(1_642_234_800_000),
              txID: "tx-parity-date-values",
              time: time
            )
          ),
          .insert(
            triple(
              "user-date-string",
              "users/stuff",
              .json(.object(["complex": .string("object")])),
              txID: "tx-parity-date-values",
              time: time
            )
          ),
        ]
      ),
      createdAt: time
    )
    let ordered = try await runtime.query(
      InstantQueryPlan(
        id: "parity.date.users",
        namespace: "users",
        order: InstantQueryOrder("createdAt")
      )
    )
    expectNoDifference(ordered.map(\.id), ["user-date-number", "user-date-string"], source)
    let dateMilliseconds = ordered.compactMap { entity -> Int64? in
      entity.values["createdAt"]?.first?.storeParityDateMilliseconds
    }
    #expect(dateMilliseconds == [1_642_234_800_000, 1_736_974_388_200], "\(source)")

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-parity-date-lookup-source",
        operations: [
          .insertByLookup(
            entity: InstantLookupRef(
              attributeID: "users/createdAt", value: .string("2025-01-15 20:53:08.200")),
            attributeID: "users/bio",
            value: .string("Found by date"),
            txID: "tx-parity-date-lookup-source",
            txTime: time
          )
        ]
      ),
      createdAt: time
    )
    let dateLookupUsers = try await runtime.query(
      InstantQueryPlan(id: "parity.date.lookup.users", namespace: "users")
    )
    expectNoDifference(
      dateLookupUsers.first(where: { $0.id == "user-date-string" })?.values["bio"]?.first,
      .string("Found by date"), source)

    await expectTransactionValidation(namespace: "users", path: "createdAt", source: source) {
      try await runtime.transact(
        InstantStoreTransaction(
          id: "tx-parity-date-wrong",
          operations: [
            .insert(
              triple(
                "user-date-wrong",
                "users/createdAt",
                .bool(true),
                txID: "tx-parity-date-wrong",
                time: time
              )
            )
          ]
        ),
        createdAt: time
      )
    }

    let strictDateSource = transactionValidationSource(
      "lookup proxy",
      assertion: "line 433 date lookup proxy note",
      status:
        "Swift-local tightening: local date writes and lookup values must coerce before indexing."
    )
    await expectTransactionValidation(namespace: "users", path: "createdAt", source: strictDateSource)
    {
      try await runtime.transact(
        InstantStoreTransaction(
          id: "tx-parity-date-unparseable",
          operations: [
            .insert(
              triple(
                "user-date-unparseable",
                "users/createdAt",
                .string("8932"),
                txID: "tx-parity-date-unparseable",
                time: time
              )
            )
          ]
        ),
        createdAt: time
      )
    }

    await expectTransactionValidation(namespace: "users", path: "createdAt", source: strictDateSource)
    {
      try await runtime.transact(
        InstantStoreTransaction(
          id: "tx-parity-date-nan",
          operations: [
            .insert(
              triple(
                "user-date-nan",
                "users/createdAt",
                .date(Date(timeIntervalSince1970: .nan)),
                txID: "tx-parity-date-nan",
                time: time
              )
            )
          ]
        ),
        createdAt: time
      )
    }

    let numberSource = transactionValidationSource(
      "validates attribute types",
      assertion: "line 35 number validator rejects NaN",
      status: "adapted: Swift rejects non-finite number writes before local indexing."
    )
    await expectTransactionValidation(namespace: "users", path: "score", source: numberSource) {
      try await runtime.transact(
        InstantStoreTransaction(
          id: "tx-parity-number-nan",
          operations: [
            .insert(
              triple(
                "user-number-nan",
                "users/score",
                .number(.nan),
                txID: "tx-parity-number-nan",
                time: time
              )
            )
          ]
        ),
        createdAt: time
      )
    }

    await expectTransactionValidation(namespace: "users", path: "users/unknownNumber", source: numberSource) {
      try await runtime.transact(
        InstantStoreTransaction(
          id: "tx-parity-unknown-number-nan",
          operations: [
            .insert(
              triple(
                "user-unknown-number-nan",
                "users/unknownNumber",
                .number(.nan),
                txID: "tx-parity-unknown-number-nan",
                time: time
              )
            )
          ]
        ),
        createdAt: time
      )
    }

    await expectTransactionValidation(namespace: "users", path: "stuff", source: numberSource) {
      try await runtime.transact(
        InstantStoreTransaction(
          id: "tx-parity-json-nan",
          operations: [
            .insert(
              triple(
                "user-json-nan",
                "users/stuff",
                .json(.object(["nested": .number(.nan)])),
                txID: "tx-parity-json-nan",
                time: time
              )
            )
          ]
        ),
        createdAt: time
      )
    }

    await expectTransactionValidation(namespace: "users", path: "rank", source: numberSource) {
      try await runtime.transact(
        InstantStoreTransaction(
          id: "tx-parity-lookup-number-nan",
          operations: [
            .insertByLookup(
              entity: InstantLookupRef(attributeID: "users/rank", value: .number(.nan)),
              attributeID: "users/name",
              value: .string("Nope"),
              txID: "tx-parity-lookup-number-nan",
              txTime: time
            )
          ]
        ),
        createdAt: time
      )
    }
  }

  @Test
  func upstreamAllowsLookupValuesForEntityWrites() async throws {
    let runtime = try await parityRuntime()
    let time = InstantTimestamp(milliseconds: 1_700_000_000_000)
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-parity-seed-user",
        operations: [
          .insert(
            triple(
              "user-1", "users/name", .string("Before"), txID: "tx-parity-seed-user", time: time)),
          .insert(
            triple(
              "user-1", "users/email", .string("john@example.net"), txID: "tx-parity-seed-user",
              time: time)),
        ]
      ),
      createdAt: time
    )

    let source = transactionValidationSource(
      "allows lookup values in square bracket",
      assertion: "line 392 lookup source update",
      status: "adapted: Swift core uses insertByLookup over a declared unique attribute."
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-parity-update-user-by-lookup",
        operations: [
          .insertByLookup(
            entity: InstantLookupRef(
              attributeID: "users/email", value: .string("john@example.net")),
            attributeID: "users/name",
            value: .string("John"),
            txID: "tx-parity-update-user-by-lookup",
            txTime: time
          )
        ]
      ),
      createdAt: time
    )

    let users = try await runtime.query(
      InstantQueryPlan(id: "parity.users", namespace: "users")
    )
    expectNoDifference(users.map { $0.values["name"]?.first }, [.string("John")], source)
  }

  @Test
  func upstreamAllowsLookupValuesInLinks() async throws {
    let runtime = try await parityRuntime()
    let time = InstantTimestamp(milliseconds: 1_700_000_000_050)
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-parity-seed-source-link-lookup",
        operations: [
          .insert(
            triple(
              "user-1", "users/name", .string("John"), txID: "tx-parity-seed-source-link-lookup",
              time: time)),
          .insert(
            triple(
              "user-1", "users/email", .string("john@example.net"),
              txID: "tx-parity-seed-source-link-lookup", time: time)),
          .insert(
            triple(
              "post-1", "posts/title", .string("Hello"), txID: "tx-parity-seed-source-link-lookup",
              time: time)),
          .insert(
            triple(
              "post-1", "posts/slug", .string("hello"), txID: "tx-parity-seed-source-link-lookup",
              time: time)),
        ]
      ),
      createdAt: time
    )

    let source = transactionValidationSource(
      "allows lookup values in link",
      assertion: "line 398 lookup link value",
      status:
        "adapted: Swift stores users.posts as posts.author, so the linked post lookup is the physical posts/author entity and uses unique posts/slug."
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-parity-link-source-by-lookup",
        operations: [
          .insertByLookup(
            entity: InstantLookupRef(attributeID: "posts/slug", value: .string("hello")),
            attributeID: "posts/author",
            value: .ref("user-1"),
            txID: "tx-parity-link-source-by-lookup",
            txTime: time
          )
        ]
      ),
      createdAt: time
    )

    let posts = try await runtime.query(
      InstantQueryPlan(id: "parity.lookup-source.posts", namespace: "posts")
    )
    expectNoDifference(posts.map { $0.values["author"]?.first }, [.ref("user-1")], source)
  }

  @Test
  func upstreamAllowsLookupSourceIDsInLinks() async throws {
    let runtime = try await parityRuntime()
    let time = InstantTimestamp(milliseconds: 1_700_000_000_100)
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-parity-seed-link-lookup",
        operations: [
          .insert(
            triple(
              "user-1", "users/name", .string("John"), txID: "tx-parity-seed-link-lookup",
              time: time)),
          .insert(
            triple(
              "user-1", "users/email", .string("john@example.net"),
              txID: "tx-parity-seed-link-lookup", time: time)),
          .insert(
            triple(
              "post-1", "posts/title", .string("Hello"), txID: "tx-parity-seed-link-lookup",
              time: time)),
        ]
      ),
      createdAt: time
    )

    let source = transactionValidationSource(
      "allows lookup values in square bracket",
      assertion: "line 394 lookup source link",
      status:
        "adapted: Swift stores users.posts as posts.author, so the source user lookup is the physical posts/author ref value."
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-parity-link-by-lookup",
        operations: [
          .insert(
            triple(
              "post-1",
              "posts/author",
              .lookupRef(
                InstantLookupRef(attributeID: "users/email", value: .string("john@example.net"))),
              txID: "tx-parity-link-by-lookup",
              time: time
            )
          )
        ]
      ),
      createdAt: time
    )

    let posts = try await runtime.query(
      InstantQueryPlan(id: "parity.posts", namespace: "posts")
    )
    expectNoDifference(posts.map { $0.values["author"]?.first }, [.ref("user-1")], source)
  }

  @Test
  func upstreamValidatesLookupProxyUniqueAttributes() async throws {
    let time = InstantTimestamp(milliseconds: 1_700_000_000_150)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "transaction-validation-lookup-proxy",
        persistenceURL: temporaryParityCacheURL(),
        initialAttributes: animalLookupProxyAttributes()
      )
    )
    let source = transactionValidationSource(
      "lookup proxy",
      assertion: "lines 415-449 unique string/date lookup attrs and non-unique lookup rejection",
      status:
        "adapted: Swift core validates lookup attrs at runtime, including date coercion for unique date lookups."
    )

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-parity-animal-seed",
        operations: [
          .insert(triple("otter-name", "otter/name", .string("Old Otter"), txID: "tx-parity-animal-seed", time: time)),
          .insert(triple("otter-name", "otter/uniqueName", .string("8932"), txID: "tx-parity-animal-seed", time: time)),
          .insert(triple("otter-date", "otter/name", .string("Date Otter"), txID: "tx-parity-animal-seed", time: time)),
          .insert(
            triple(
              "otter-date",
              "otter/uniqueDate",
              .date(Date(timeIntervalSince1970: 1_736_974_388.2)),
              txID: "tx-parity-animal-seed",
              time: time
            )
          ),
          .insert(triple("elephant-1", "elephant/name", .string("Old Elephant"), txID: "tx-parity-animal-seed", time: time)),
          .insert(triple("elephant-1", "elephant/uniqueIdNumber", .string("1234567890"), txID: "tx-parity-animal-seed", time: time)),
          .insert(triple("elephant-1", "elephant/favoriteColor", .string("blue"), txID: "tx-parity-animal-seed", time: time)),
        ]
      ),
      createdAt: time
    )

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-parity-animal-lookups",
        operations: [
          .insertByLookup(
            entity: InstantLookupRef(attributeID: "otter/uniqueName", value: .string("8932")),
            attributeID: "otter/name",
            value: .string("Name lookup otter"),
            txID: "tx-parity-animal-lookups",
            txTime: time
          ),
          .insertByLookup(
            entity: InstantLookupRef(
              attributeID: "otter/uniqueDate",
              value: .string("2025-01-15T20:53:08.200Z")
            ),
            attributeID: "otter/name",
            value: .string("Date lookup otter"),
            txID: "tx-parity-animal-lookups",
            txTime: time
          ),
          .insertByLookup(
            entity: InstantLookupRef(
              attributeID: "elephant/uniqueIdNumber",
              value: .string("1234567890")
            ),
            attributeID: "elephant/name",
            value: .string("Lookup elephant"),
            txID: "tx-parity-animal-lookups",
            txTime: time
          ),
        ]
      ),
      createdAt: InstantTimestamp(milliseconds: time.milliseconds + 1)
    )

    let otters = try await runtime.query(InstantQueryPlan(id: "parity.lookup-proxy.otters", namespace: "otter"))
    let elephants = try await runtime.query(
      InstantQueryPlan(id: "parity.lookup-proxy.elephants", namespace: "elephant")
    )
    expectNoDifference(otters.map(\.id), ["otter-date", "otter-name"], source)
    expectNoDifference(
      otters.map { $0.values["name"]?.first },
      [.string("Date lookup otter"), .string("Name lookup otter")],
      source
    )
    expectNoDifference(elephants.map { $0.values["name"]?.first }, [.string("Lookup elephant")], source)

    do {
      try await runtime.transact(
        InstantStoreTransaction(
          id: "tx-parity-animal-nonunique-lookup",
          operations: [
            .insertByLookup(
              entity: InstantLookupRef(attributeID: "elephant/favoriteColor", value: .string("blue")),
              attributeID: "elephant/name",
              value: .string("Invalid lookup"),
              txID: "tx-parity-animal-nonunique-lookup",
              txTime: time
            )
          ]
        ),
        createdAt: InstantTimestamp(milliseconds: time.milliseconds + 2)
      )
      #expect(Bool(false), "Expected non-unique animal lookup to fail. \(source)")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed, source)
      expectNoDifference(error.operation, "lookup entity", source)
      expectNoDifference(error.namespace, "elephant", source)
      expectNoDifference(error.path, "favoriteColor", source)
    } catch {
      #expect(Bool(false), "Unexpected error: \(error). \(source)")
    }
  }

  @Test
  func upstreamRejectsNonUniqueLookupAttributes() async throws {
    let runtime = try await parityRuntime()
    let time = InstantTimestamp(milliseconds: 1_700_000_000_200)
    let source = transactionValidationSource(
      "lookup proxy",
      assertion: "line 444 TypeScript-only non-unique lookup constraint",
      status:
        "Swift-only adaptation: upstream enforces this at compile time; Swift core rejects non-unique lookup attrs at runtime."
    )

    do {
      try await runtime.transact(
        InstantStoreTransaction(
          id: "tx-parity-nonunique-lookup",
          operations: [
            .insertByLookup(
              entity: InstantLookupRef(attributeID: "users/name", value: .string("John")),
              attributeID: "users/email",
              value: .string("john@example.net"),
              txID: "tx-parity-nonunique-lookup",
              txTime: time
            )
          ]
        ),
        createdAt: time
      )
      #expect(Bool(false), "Expected non-unique lookup to fail. \(source)")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed, source)
      expectNoDifference(error.operation, "lookup entity", source)
      expectNoDifference(error.namespace, "users", source)
      expectNoDifference(error.path, "name", source)
    } catch {
      #expect(Bool(false), "Unexpected error: \(error). \(source)")
    }
  }

  @Test
  func upstreamRejectsLookupValuesThatDoNotMatchLinkNamespace() async throws {
    let runtime = try await parityRuntime()
    let time = InstantTimestamp(milliseconds: 1_700_000_000_300)
    let source =
      "Swift-only additional coverage: lookup refs for ref values must belong to the declared link namespace."

    do {
      try await runtime.transact(
        InstantStoreTransaction(
          id: "tx-parity-wrong-link-lookup",
          operations: [
            .insert(
              triple(
                "post-1",
                "posts/author",
                .lookupRef(InstantLookupRef(attributeID: "posts/slug", value: .string("hello"))),
                txID: "tx-parity-wrong-link-lookup",
                time: time
              )
            )
          ]
        ),
        createdAt: time
      )
      #expect(Bool(false), "Expected wrong-namespace link lookup to fail. \(source)")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed, source)
      expectNoDifference(error.operation, "lookup entity", source)
      expectNoDifference(error.namespace, "users", source)
      expectNoDifference(error.path, "slug", source)
    } catch {
      #expect(Bool(false), "Unexpected error: \(error). \(source)")
    }
  }
}

private let upstreamTransactionValidationTestSource =
  "upstream/instant/client/packages/core/__tests__/src/transactionValidation.test.ts"

private func transactionValidationSource(
  _ testName: String,
  assertion: String,
  status: String
) -> String {
  "\(upstreamTransactionValidationTestSource) \(testName) \(assertion) [\(status)]"
}

private func expectTransactionValidation(
  namespace: String?,
  path: String?,
  source: String,
  _ operation: () async throws -> Void
) async {
  do {
    try await operation()
    #expect(Bool(false), "Expected transaction validation to fail. \(source)")
  } catch let error as InstantError {
    expectNoDifference(error.code, .validationFailed, source)
    expectNoDifference(error.namespace, namespace, source)
    expectNoDifference(error.path, path, source)
  } catch {
    #expect(Bool(false), "Unexpected error: \(error). \(source)")
  }
}

private func parityRuntime() async throws -> InstantRuntime {
  try await InstantRuntime.bootstrap(
    configuration: InstantRuntimeConfiguration(
      appID: "transaction-validation-parity",
      persistenceURL: temporaryParityCacheURL(),
      initialAttributes: transactionValidationParityAttributes()
    )
  )
}

private func temporaryParityCacheURL() throws -> URL {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("InstantSwiftDataTransactionParity-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  return directory.appendingPathComponent("state.sqlite")
}

private func transactionValidationParityAttributes() -> [InstantAttribute] {
  // Adapted from transactionValidation.test.ts: Swift core needs explicit unique
  // lookup attributes and stores the users.posts link as posts.author.
  [
    InstantAttribute(
      id: "users/name",
      namespace: "users",
      name: "name",
      valueType: .string,
      isIndexed: true
    ),
    InstantAttribute(
      id: "users/email",
      namespace: "users",
      name: "email",
      valueType: .string,
      isIndexed: true,
      isUnique: true
    ),
    InstantAttribute(
      id: "users/bio",
      namespace: "users",
      name: "bio",
      valueType: .string,
      isRequired: false
    ),
    InstantAttribute(
      id: "users/stuff",
      namespace: "users",
      name: "stuff",
      valueType: .json,
      isRequired: false
    ),
    InstantAttribute(
      id: "users/createdAt",
      namespace: "users",
      name: "createdAt",
      valueType: .date,
      isRequired: false,
      isIndexed: true,
      isUnique: true
    ),
    InstantAttribute(
      id: "users/score",
      namespace: "users",
      name: "score",
      valueType: .number,
      isRequired: false
    ),
    InstantAttribute(
      id: "users/rank",
      namespace: "users",
      name: "rank",
      valueType: .number,
      isRequired: false,
      isUnique: true
    ),
    InstantAttribute(
      id: "users/friends",
      namespace: "users",
      name: "friends",
      valueType: .ref,
      cardinality: .many,
      isIndexed: true,
      forwardIdentity: "users/friends",
      reverseIdentity: "users/_friends",
      linkNamespace: "users"
    ),
    InstantAttribute(
      id: "posts/title",
      namespace: "posts",
      name: "title",
      valueType: .string,
      isIndexed: true
    ),
    InstantAttribute(
      id: "posts/body",
      namespace: "posts",
      name: "body",
      valueType: .string,
      isIndexed: true
    ),
    InstantAttribute(
      id: "posts/slug",
      namespace: "posts",
      name: "slug",
      valueType: .string,
      isIndexed: true,
      isUnique: true
    ),
    InstantAttribute(
      id: "posts/author",
      namespace: "posts",
      name: "author",
      valueType: .ref,
      isIndexed: true,
      forwardIdentity: "posts/author",
      reverseIdentity: "users/posts",
      linkNamespace: "users"
    ),
    InstantAttribute(
      id: "comments/body",
      namespace: "comments",
      name: "body",
      valueType: .string
    ),
    InstantAttribute(
      id: "comments/post",
      namespace: "comments",
      name: "post",
      valueType: .ref,
      isIndexed: true,
      forwardIdentity: "comments/post",
      reverseIdentity: "posts/comments",
      linkNamespace: "posts"
    ),
  ]
}

private func animalLookupProxyAttributes() -> [InstantAttribute] {
  [
    InstantAttribute(
      id: "otter/name",
      namespace: "otter",
      name: "name",
      valueType: .string
    ),
    InstantAttribute(
      id: "otter/uniqueName",
      namespace: "otter",
      name: "uniqueName",
      valueType: .string,
      isIndexed: true,
      isUnique: true
    ),
    InstantAttribute(
      id: "otter/uniqueDate",
      namespace: "otter",
      name: "uniqueDate",
      valueType: .date,
      isIndexed: true,
      isUnique: true
    ),
    InstantAttribute(
      id: "elephant/name",
      namespace: "elephant",
      name: "name",
      valueType: .string
    ),
    InstantAttribute(
      id: "elephant/uniqueIdNumber",
      namespace: "elephant",
      name: "uniqueIdNumber",
      valueType: .string,
      isIndexed: true,
      isUnique: true
    ),
    InstantAttribute(
      id: "elephant/favoriteColor",
      namespace: "elephant",
      name: "favoriteColor",
      valueType: .string
    ),
  ]
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

extension InstantValue {
  fileprivate var storeParityDateMilliseconds: Int64? {
    guard case .date(let date) = self else { return nil }
    return Int64((date.timeIntervalSince1970 * 1000).rounded())
  }
}
