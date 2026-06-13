import CustomDump
import Foundation
@testable import InstantSwiftDataCore
import Testing

@Suite(.serialized)
struct InstantQueryValidationParityTests {
  @Test
  func upstreamTopLevelEntityNames() async throws {
    let runtime = try await queryValidationRuntime()
    let source = queryValidationSource(
      "top level entitiy names",
      assertion: "lines 106-127 namespace validation",
      status: "adapted: Swift validates one InstantQueryPlan namespace at a time."
    )

    let posts = try await runtime.query(
      InstantQueryPlan(id: "query-validation-parity.posts", namespace: "posts")
    )
    expectNoDifference(posts, [], source)

    let users = try await runtime.query(
      InstantQueryPlan(id: "query-validation-parity.users", namespace: "users")
    )
    expectNoDifference(users, [], source)

    await expectQueryValidation(
      namespace: "notInSchema",
      path: nil,
      source
    ) {
      _ = try await runtime.query(
        InstantQueryPlan(id: "query-validation-parity.not-in-schema", namespace: "notInSchema")
      )
    }

    let schemalessRuntime = try await queryValidationRuntime(initialAttributes: [])
    let schemaless = try await schemalessRuntime.query(
      InstantQueryPlan(
        id: "query-validation-parity.schemaless-random",
        namespace: "somethingsuperRandomButNoSchema"
      )
    )
    expectNoDifference(schemaless, [], source)
  }

  @Test
  func upstreamLinks() async throws {
    let runtime = try await queryValidationRuntime()
    let source = queryValidationSource(
      "links",
      assertion: "lines 131-155 relation validation",
      status: "adapted: Swift expresses nested query objects as InstantQueryInclude values."
    )

    let postsWithComments = try await runtime.query(
      InstantQueryPlan(
        id: "query-validation-parity.posts.comments",
        namespace: "posts",
        includes: [
          InstantQueryInclude("comments")
        ]
      )
    )
    expectNoDifference(postsWithComments, [], source)

    await expectQueryValidation(
      namespace: "posts",
      path: "doesNotExist",
      source
    ) {
      _ = try await runtime.query(
        InstantQueryPlan(
          id: "query-validation-parity.posts.missing-relation",
          namespace: "posts",
          includes: [
            InstantQueryInclude("doesNotExist")
          ]
        )
      )
    }

    await expectQueryValidation(
      namespace: "posts",
      path: "unlinkedWithAnything",
      source
    ) {
      _ = try await runtime.query(
        InstantQueryPlan(
          id: "query-validation-parity.posts.unlinked",
          namespace: "posts",
          includes: [
            InstantQueryInclude("unlinkedWithAnything")
          ]
        )
      )
    }
  }

  @Test
  func upstreamWhereClauseTypeValidation() async throws {
    let runtime = try await queryValidationRuntime()
    let source = queryValidationSource(
      "where clause type validation",
      assertion: "lines 241-272 string field value types",
      status: "adapted: Swift has no InstantValueType.any, so this covers the schema-backed string cases."
    )

    let valid = try await runtime.query(
      InstantQueryPlan(
        id: "query-validation-parity.users.valid-string-filters",
        namespace: "users",
        filters: [
          .equals(field: "name", value: .string("John")),
          .equals(field: "email", value: .string("john@example.com")),
        ]
      )
    )
    expectNoDifference(valid, [], source)

    await expectQueryValidation(
      namespace: "users",
      path: "name",
      source
    ) {
      _ = try await runtime.query(
        InstantQueryPlan(
          id: "query-validation-parity.users.invalid-name-type",
          namespace: "users",
          filters: [.equals(field: "name", value: .number(123))]
        )
      )
    }

    await expectQueryValidation(
      namespace: "users",
      path: "email",
      source
    ) {
      _ = try await runtime.query(
        InstantQueryPlan(
          id: "query-validation-parity.users.invalid-email-type",
          namespace: "users",
          filters: [.equals(field: "email", value: .bool(true))]
        )
      )
    }
  }

  @Test
  func upstreamWhereClauseOperatorValueTypes() async throws {
    let runtime = try await queryValidationRuntime()
    let source = queryValidationSource(
      "where clause operators",
      assertion: "lines 307-371 $in element types; lines 409-504 string/pattern/null operators",
      status:
        "adapted: Swift's enum makes unknown operators, non-array 'in' values, and non-string pattern payloads unrepresentable."
    )

    let validIn = try await runtime.query(
      InstantQueryPlan(
        id: "query-validation-parity.users.valid-in",
        namespace: "users",
        filters: [.in(field: "name", values: [.string("John"), .string("Jane")])]
      )
    )
    expectNoDifference(validIn, [], source)

    await expectQueryValidation(
      namespace: "users",
      path: "name",
      source
    ) {
      _ = try await runtime.query(
        InstantQueryPlan(
          id: "query-validation-parity.users.invalid-in",
          namespace: "users",
          filters: [.in(field: "name", values: [.string("John"), .number(123)])]
        )
      )
    }

    let validComparison = try await runtime.query(
      InstantQueryPlan(
        id: "query-validation-parity.posts.valid-comparison",
        namespace: "posts",
        filters: [.greaterThan(field: "title", value: .string("A"))]
      )
    )
    expectNoDifference(validComparison, [], source)

    await expectQueryValidation(
      namespace: "posts",
      path: "title",
      source
    ) {
      _ = try await runtime.query(
        InstantQueryPlan(
          id: "query-validation-parity.posts.invalid-comparison-type",
          namespace: "posts",
          filters: [.lessThan(field: "title", value: .number(123))]
        )
      )
    }

    let validLike = try await runtime.query(
      InstantQueryPlan(
        id: "query-validation-parity.users.valid-like",
        namespace: "users",
        filters: [.like(field: "name", pattern: "%John%")]
      )
    )
    expectNoDifference(validLike, [], source)

    await expectQueryValidation(namespace: "users", path: "name", source) {
      _ = try await runtime.query(
        InstantQueryPlan(
          id: "query-validation-parity.users.invalid-unindexed-ilike",
          namespace: "users",
          filters: [.iLike(field: "name", pattern: "%john%")]
        )
      )
    }

    let validILike = try await runtime.query(
      InstantQueryPlan(
        id: "query-validation-parity.users.valid-indexed-ilike",
        namespace: "users",
        filters: [.iLike(field: "email", pattern: "%EXAMPLE.COM")]
      )
    )
    expectNoDifference(validILike, [], source)
  }

  @Test
  func upstreamWhereClauseIDValidation() async throws {
    let runtime = try await queryValidationRuntime()
    let source = queryValidationSource(
      "where clause id validation",
      assertion: "lines 530-563 id value types",
      status: "adapted: Swift's synthetic primary-key attribute is validated as a string field."
    )

    let validID = try await runtime.query(
      InstantQueryPlan(
        id: "query-validation-parity.users.valid-id",
        namespace: "users",
        filters: [.equals(field: "id", value: .string("user-123"))]
      )
    )
    expectNoDifference(validID, [], source)

    await expectQueryValidation(
      namespace: "users",
      path: "id",
      source
    ) {
      _ = try await runtime.query(
        InstantQueryPlan(
          id: "query-validation-parity.users.invalid-id",
          namespace: "users",
          filters: [.equals(field: "id", value: .number(123))]
        )
      )
    }

    let validIDIn = try await runtime.query(
      InstantQueryPlan(
        id: "query-validation-parity.users.valid-id-in",
        namespace: "users",
        filters: [.in(field: "id", values: [.string("user-1"), .string("user-2")])]
      )
    )
    expectNoDifference(validIDIn, [], source)
  }

  @Test
  func upstreamWhereClauseLogicalOperators() async throws {
    let runtime = try await queryValidationRuntime()
    let source = queryValidationSource(
      "where clause logical operators",
      assertion: "lines 565-598 logical and/or validation",
      status: "ported: Swift's enum expresses logical clauses as recursive filter arrays."
    )

    let validOr = try await runtime.query(
      InstantQueryPlan(
        id: "query-validation-parity.users.valid-or",
        namespace: "users",
        filters: [
          .or([
            .equals(field: "name", value: .string("John")),
            .equals(field: "email", value: .string("jane@example.com")),
          ])
        ]
      )
    )
    expectNoDifference(validOr, [], source)

    let validAnd = try await runtime.query(
      InstantQueryPlan(
        id: "query-validation-parity.users.valid-and",
        namespace: "users",
        filters: [
          .and([
            .equals(field: "name", value: .string("John")),
            .isNotNull(field: "bio"),
          ])
        ]
      )
    )
    expectNoDifference(validAnd, [], source)

    await expectQueryValidation(namespace: "users", path: "name", source) {
      _ = try await runtime.query(
        InstantQueryPlan(
          id: "query-validation-parity.users.invalid-or",
          namespace: "users",
          filters: [.or([.equals(field: "name", value: .number(123))])]
        )
      )
    }
  }

  @Test
  func upstreamWhereClauseDotNotationValidation() async throws {
    let runtime = try await queryValidationRuntime()
    let source = queryValidationSource(
      "where clause dot notation validation",
      assertion: "lines 600-792 relation path, id, $in, and direct relation ref filters",
      status:
        "adapted: Swift makes non-string like/ilike payloads unrepresentable and accepts the typed iLike case required by the package plan."
    )

    let validDotNotationCases: [(String, String, [InstantQueryFilter])] = [
      (
        "users.posts-title",
        "users",
        [.equals(field: "posts.title", value: .string("Some Title"))]
      ),
      (
        "posts.author-name",
        "posts",
        [.equals(field: "author.name", value: .string("John Doe"))]
      ),
      (
        "users.posts-comments-body",
        "users",
        [.equals(field: "posts.comments.body", value: .string("Great comment!"))]
      ),
      (
        "users.posts-title-like",
        "users",
        [.like(field: "posts.title", pattern: "%tutorial%")]
      ),
      (
        "users.posts-title-ilike",
        "users",
        [.iLike(field: "posts.title", pattern: "%TUTORIAL%")]
      ),
      (
        "users.friends-name",
        "users",
        [.equals(field: "friends.name", value: .string("Friend Name"))]
      ),
      (
        "users.posts-title-in",
        "users",
        [.in(field: "posts.title", values: [.string("Title 1"), .string("Title 2")])]
      ),
      (
        "users.posts-id",
        "users",
        [.equals(field: "posts.id", value: .string("post-1"))]
      ),
      (
        "posts.author-bio-null",
        "posts",
        [.isNull(field: "author.bio")]
      ),
      (
        "comments.post-ref",
        "comments",
        [.equals(field: "post", value: .ref("post-1"))]
      ),
      (
        "users.posts-comments-ref",
        "users",
        [.equals(field: "posts.comments", value: .ref("comment-1"))]
      ),
    ]

    for (id, namespace, filters) in validDotNotationCases {
      let result = try await runtime.query(
        InstantQueryPlan(
          id: "query-validation-parity.\(id)",
          namespace: namespace,
          filters: filters
        )
      )
      expectNoDifference(result, [], source)
    }

    let invalidDotNotationCases: [(String, String, String, String, [InstantQueryFilter])] = [
      (
        "invalid-link",
        "users",
        "users",
        "invalidLink.title",
        [.equals(field: "invalidLink.title", value: .string("value"))]
      ),
      (
        "nonexistent-attribute",
        "users",
        "posts",
        "posts.nonexistent",
        [.equals(field: "posts.nonexistent", value: .string("value"))]
      ),
      (
        "unlinked-namespace",
        "users",
        "users",
        "unlinkedWithAnything.animal",
        [.equals(field: "unlinkedWithAnything.animal", value: .string("cat"))]
      ),
      (
        "wrong-dot-type",
        "users",
        "posts",
        "posts.title",
        [.equals(field: "posts.title", value: .number(123))]
      ),
      (
        "wrong-dot-in-type",
        "users",
        "posts",
        "posts.title",
        [.in(field: "posts.title", values: [.string("Title 1"), .number(123)])]
      ),
      (
        "wrong-direct-relation-ref",
        "comments",
        "comments",
        "post",
        [.equals(field: "post", value: .string("not-a-uuid"))]
      ),
      (
        "wrong-final-relation-ref",
        "users",
        "posts",
        "posts.comments",
        [.equals(field: "posts.comments", value: .string("not-a-uuid"))]
      ),
    ]

    for (id, namespace, expectedNamespace, path, filters) in invalidDotNotationCases {
      await expectQueryValidation(namespace: expectedNamespace, path: path, source) {
        _ = try await runtime.query(
          InstantQueryPlan(
            id: "query-validation-parity.\(id)",
            namespace: namespace,
            filters: filters
          )
        )
      }
    }
  }

  @Test
  func upstreamNestedIncludePaginationRestriction() async throws {
    let runtime = try await queryValidationRuntime()
    let source = queryValidationSource(
      "pagination parameters can only be used at top-level namespaces",
      assertion: "lines 795-981 nested pagination validation",
      status:
        "adapted: Swift allows pagination only on InstantQueryPlan; converting a plan into an include rejects pagination and nested includes."
    )

    let validTopLevelPagination = try await runtime.queryOnce(
      InstantQueryPlan(
        id: "query-validation-parity.posts.top-level-pagination",
        namespace: "posts",
        offset: 20,
        limit: 10,
        first: 5
      )
    )
    expectNoDifference(validTopLevelPagination.values.map(\.id), [], source)

    let validTopLevelBeforeInclusive = try await runtime.queryOnce(
      InstantQueryPlan(
        id: "query-validation-parity.posts.top-level-before-inclusive",
        namespace: "posts",
        before: InstantQueryCursor(
          entityID: "post-1",
          sortValue: .string("cursor"),
          inclusive: true
        )
      )
    )
    expectNoDifference(validTopLevelBeforeInclusive.values.map(\.id), [], source)

    let validTopLevelAfterInclusive = try await runtime.queryOnce(
      InstantQueryPlan(
        id: "query-validation-parity.posts.top-level-after-inclusive",
        namespace: "posts",
        after: InstantQueryCursor(
          entityID: "post-1",
          sortValue: .string("cursor"),
          inclusive: true
        )
      )
    )
    expectNoDifference(validTopLevelAfterInclusive.values.map(\.id), [], source)

    let validFilteredInclude = InstantQueryInclude(
      "posts",
      direction: .reverse,
      query: InstantQueryPlan(
        id: "query-validation-parity.users.posts.filtered-include",
        namespace: "posts",
        filters: [.equals(field: "title", value: .string("Test"))],
        order: InstantQueryOrder("title"),
        selectedFields: ["title"]
      )
    )
    #expect(validFilteredInclude != nil, "Expected filtered include to be supported. \(source)")

    let cursor = InstantQueryCursor(entityID: "post-1", sortValue: .string("cursor"))
    let paginatedIncludePlans: [InstantQueryPlan] = [
      InstantQueryPlan(
        id: "query-validation-parity.users.posts.offset",
        namespace: "posts",
        offset: 10
      ),
      InstantQueryPlan(
        id: "query-validation-parity.users.posts.first",
        namespace: "posts",
        first: 5
      ),
      InstantQueryPlan(
        id: "query-validation-parity.users.posts.after",
        namespace: "posts",
        after: cursor
      ),
      InstantQueryPlan(
        id: "query-validation-parity.users.posts.last",
        namespace: "posts",
        last: 5
      ),
      InstantQueryPlan(
        id: "query-validation-parity.users.posts.before",
        namespace: "posts",
        before: cursor
      ),
    ]

    for plan in paginatedIncludePlans {
      #expect(
        InstantQueryInclude("posts", direction: .reverse, query: plan) == nil,
        "\(source) rejected include plan \(plan.id)"
      )
    }

    let swiftOnlySource =
      "Swift include conversion guard: InstantQueryIncludePlan intentionally omits pagination and nested include storage, so conversion rejects those plans before dropping fields."
    let swiftOnlyUnsupportedIncludePlans: [InstantQueryPlan] = [
      InstantQueryPlan(
        id: "query-validation-parity.users.posts.limit",
        namespace: "posts",
        limit: 5
      ),
      InstantQueryPlan(
        id: "query-validation-parity.users.posts.nested-include",
        namespace: "posts",
        includes: [InstantQueryInclude("comments")]
      ),
    ]

    for plan in swiftOnlyUnsupportedIncludePlans {
      #expect(
        InstantQueryInclude("posts", direction: .reverse, query: plan) == nil,
        "\(swiftOnlySource) rejected include plan \(plan.id)"
      )
    }
  }

  @Test
  func swiftSchemaBackedFilterValueEdges() async throws {
    let runtime = try await queryValidationRuntime()
    let source =
      "Swift core query filter value validation: dates coerce, refs/json are strict, nested fields validate their target attribute."

    let validDateString = try await runtime.query(
      InstantQueryPlan(
        id: "query-validation-parity.posts.valid-date-string",
        namespace: "posts",
        filters: [.equals(field: "publishedAt", value: .string("2025-01-15T20:53:08.200Z"))]
      )
    )
    expectNoDifference(validDateString, [], source)

    let validDateNumber = try await runtime.query(
      InstantQueryPlan(
        id: "query-validation-parity.posts.valid-date-number",
        namespace: "posts",
        filters: [.greaterThan(field: "publishedAt", value: .number(1_642_234_800_000))]
      )
    )
    expectNoDifference(validDateNumber, [], source)

    await expectQueryValidation(namespace: "posts", path: "publishedAt", source) {
      _ = try await runtime.query(
        InstantQueryPlan(
          id: "query-validation-parity.posts.invalid-date",
          namespace: "posts",
          filters: [.equals(field: "publishedAt", value: .bool(true))]
        )
      )
    }

    let validRef = try await runtime.query(
      InstantQueryPlan(
        id: "query-validation-parity.posts.valid-ref",
        namespace: "posts",
        filters: [.equals(field: "comments", value: .ref("comment-1"))]
      )
    )
    expectNoDifference(validRef, [], source)

    await expectQueryValidation(namespace: "posts", path: "comments", source) {
      _ = try await runtime.query(
        InstantQueryPlan(
          id: "query-validation-parity.posts.invalid-ref-string",
          namespace: "posts",
          filters: [.equals(field: "comments", value: .string("comment-1"))]
        )
      )
    }

    await expectQueryValidation(namespace: "posts", path: "comments", source) {
      _ = try await runtime.query(
        InstantQueryPlan(
          id: "query-validation-parity.posts.invalid-ref-range",
          namespace: "posts",
          filters: [.greaterThan(field: "comments", value: .ref("comment-1"))]
        )
      )
    }

    let validJSON = try await runtime.query(
      InstantQueryPlan(
        id: "query-validation-parity.users.valid-json",
        namespace: "users",
        filters: [
          .equals(field: "stuff", value: .json(.object(["custom": .string("value")])))
        ]
      )
    )
    expectNoDifference(validJSON, [], source)

    await expectQueryValidation(namespace: "users", path: "stuff", source) {
      _ = try await runtime.query(
        InstantQueryPlan(
          id: "query-validation-parity.users.invalid-json-string",
          namespace: "users",
          filters: [.equals(field: "stuff", value: .string("value"))]
        )
      )
    }

    let validNestedID = try await runtime.query(
      InstantQueryPlan(
        id: "query-validation-parity.posts.valid-nested-id",
        namespace: "posts",
        filters: [.equals(field: "comments.id", value: .string("comment-1"))]
      )
    )
    expectNoDifference(validNestedID, [], source)

    await expectQueryValidation(namespace: "comments", path: "comments.body", source) {
      _ = try await runtime.query(
        InstantQueryPlan(
          id: "query-validation-parity.posts.invalid-nested-body",
          namespace: "posts",
          filters: [.equals(field: "comments.body", value: .number(123))]
        )
      )
    }
  }
}

private let upstreamQueryValidationTestSource =
  "upstream/instant/client/packages/core/__tests__/src/queryValidation.test.ts"

private func queryValidationSource(
  _ testName: String,
  assertion: String,
  status: String
) -> String {
  "\(upstreamQueryValidationTestSource) \(testName) \(assertion) [\(status)]"
}

private func queryValidationRuntime(
  initialAttributes: [InstantAttribute] = queryValidationParityAttributes()
) async throws -> InstantRuntime {
  try await InstantRuntime.bootstrap(
    configuration: InstantRuntimeConfiguration(
      appID: "query-validation-parity",
      persistenceURL: temporaryQueryValidationCacheURL(),
      initialAttributes: initialAttributes
    )
  )
}

private func temporaryQueryValidationCacheURL() throws -> URL {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("InstantSwiftDataQueryValidationParity-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  return directory.appendingPathComponent("state.sqlite")
}

private func queryValidationParityAttributes() -> [InstantAttribute] {
  [
    InstantAttribute(
      id: "users/name",
      namespace: "users",
      name: "name",
      valueType: .string
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
      id: "users/stuff",
      namespace: "users",
      name: "stuff",
      valueType: .json,
      isIndexed: true
    ),
    InstantAttribute(
      id: "users/bio",
      namespace: "users",
      name: "bio",
      valueType: .string,
      isRequired: false,
      isIndexed: false
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
      id: "posts/publishedAt",
      namespace: "posts",
      name: "publishedAt",
      valueType: .date,
      isIndexed: true
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
      id: "posts/comments",
      namespace: "posts",
      name: "comments",
      valueType: .ref,
      cardinality: .many,
      isIndexed: true,
      forwardIdentity: "posts/comments",
      reverseIdentity: "comments/post",
      linkNamespace: "comments"
    ),
    InstantAttribute(
      id: "comments/body",
      namespace: "comments",
      name: "body",
      valueType: .string,
      isIndexed: true
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
    InstantAttribute(
      id: "unlinkedWithAnything/animal",
      namespace: "unlinkedWithAnything",
      name: "animal",
      valueType: .string,
      isIndexed: true
    ),
  ]
}

private func expectQueryValidation(
  namespace: String,
  path: String?,
  _ source: String,
  operation: () async throws -> Void
) async {
  do {
    try await operation()
    #expect(Bool(false), "Expected query validation to fail. \(source)")
  } catch let error as InstantError {
    expectNoDifference(error.code, .validationFailed, source)
    expectNoDifference(error.operation, "validate query", source)
    expectNoDifference(error.namespace, namespace, source)
    expectNoDifference(error.path, path, source)
  } catch {
    #expect(Bool(false), "Unexpected error: \(error). \(source)")
  }
}
