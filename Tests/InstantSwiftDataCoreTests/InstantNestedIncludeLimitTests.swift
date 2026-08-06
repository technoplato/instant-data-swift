import CustomDump
import Foundation
import InstantSwiftDataCore
import Testing

/// ADR 0015 L1 — per-parent nested limit/first/last on reverse includes.
@Suite("InstantNestedIncludeLimit")
struct InstantNestedIncludeLimitTests {
  @Test
  func reverseIncludeLimitKeepsTwoNewestChildrenPerParent() async throws {
    let time = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let attributes = [
      InstantAttribute(
        id: "users/id",
        namespace: "users",
        name: "id",
        valueType: .string,
        isRequired: true,
        isIndexed: true,
        isUnique: true
      ),
      InstantAttribute(
        id: "posts/id",
        namespace: "posts",
        name: "id",
        valueType: .string,
        isRequired: true,
        isIndexed: true,
        isUnique: true
      ),
      InstantAttribute(
        id: "posts/title",
        namespace: "posts",
        name: "title",
        valueType: .string,
        isRequired: false,
        isIndexed: true
      ),
      InstantAttribute(
        id: "posts/createdAtMs",
        namespace: "posts",
        name: "createdAtMs",
        valueType: .number,
        isRequired: false,
        isIndexed: true
      ),
      InstantAttribute(
        id: "posts/author",
        namespace: "posts",
        name: "author",
        valueType: .ref,
        isRequired: false,
        cardinality: .one,
        isIndexed: true,
        forwardIdentity: "posts/author",
        reverseIdentity: "users/posts",
        linkNamespace: "users"
      ),
    ]

    let cacheURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("instant-nested-include-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: cacheURL) }

    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "nested-include-limit-test",
        persistenceURL: cacheURL,
        initialAttributes: attributes
      )
    )

    func insertPost(id: String, title: String, createdAtMs: Double) -> InstantStoreTransaction {
      InstantStoreTransaction(
        id: "tx-\(id)",
        operations: [
          .insert(
            InstantTriple(
              entityID: id,
              attributeID: "posts/id",
              value: .string(id),
              txID: "tx-\(id)",
              txTime: time
            )
          ),
          .insert(
            InstantTriple(
              entityID: id,
              attributeID: "posts/title",
              value: .string(title),
              txID: "tx-\(id)",
              txTime: time
            )
          ),
          .insert(
            InstantTriple(
              entityID: id,
              attributeID: "posts/createdAtMs",
              value: .number(createdAtMs),
              txID: "tx-\(id)",
              txTime: time
            )
          ),
          .insert(
            InstantTriple(
              entityID: id,
              attributeID: "posts/author",
              value: .ref("user-1"),
              txID: "tx-\(id)",
              txTime: time
            )
          ),
        ]
      )
    }

    _ = try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-user",
        operations: [
          .insert(
            InstantTriple(
              entityID: "user-1",
              attributeID: "users/id",
              value: .string("user-1"),
              txID: "tx-user",
              txTime: time
            )
          )
        ]
      )
    )
    for (index, title) in ["oldest", "middle", "newest"].enumerated() {
      _ = try await runtime.transact(
        insertPost(
          id: "post-\(index)",
          title: title,
          createdAtMs: Double(1_000 + index)
        )
      )
    }

    let users = try await runtime.query(
      InstantQueryPlan(
        id: "users.with-limited-posts",
        namespace: "users",
        includes: [
          InstantQueryInclude(
            "posts",
            direction: .reverse,
            query: InstantQueryPlan(
              id: "users.posts.limit-2",
              namespace: "posts",
              order: InstantQueryOrder("createdAtMs", .descending),
              limit: 2
            )
          )!
        ]
      )
    )

    let userIDs = users.map { $0.id }
    expectNoDifference(userIDs, ["user-1"])
    let linked = users.first?.links?["posts"] ?? []
    let linkedIDs = linked.map { $0.id }
    // Newest first after descending order, then limit 2.
    expectNoDifference(linkedIDs, ["post-2", "post-1"])
    let titles = linked.compactMap { link -> String? in
      guard case .string(let title)? = link.values["title"]?.first else { return nil }
      return title
    }
    expectNoDifference(titles, ["newest", "middle"])
  }
}
