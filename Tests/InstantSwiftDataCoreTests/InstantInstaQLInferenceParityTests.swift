import CustomDump
import Foundation
@testable import InstantSwiftDataCore
import Testing

@Suite(.serialized)
struct InstantInstaQLInferenceParityTests {
  @Test
  func upstreamInstaQLManyToManyWithInferenceMaterializesArrays() async throws {
    let fixture = InstaQLInferenceFixture.manyToMany()
    let store = InstantStore(snapshot: fixture.snapshot)

    let posts = await store.materializeInstaQL(
      fixture.forwardQuery,
      cardinalityInference: true
    )
    let tags = await store.materializeInstaQL(
      fixture.reverseQuery,
      cardinalityInference: true
    )

    let relation = try #require(fixture.relationAttribute)
    expectNoDifference(relation.cardinality, .many, instaQLManyToManyInferenceSource)
    expectNoDifference(relation.isUnique, false, instaQLManyToManyInferenceSource)
    expectNoDifference(relation.forwardIdentity, "posts/tags", instaQLManyToManyInferenceSource)
    expectNoDifference(relation.reverseIdentity, "tags/posts", instaQLManyToManyInferenceSource)
    expectNoDifference(relation.linkNamespace, "tags", instaQLManyToManyInferenceSource)
    expectNoDifference(posts.map(\.id), ["post1"], instaQLManyToManyInferenceSource)
    expectNoDifference(
      posts.first?["tags"]?.objects?.map(\.id),
      ["tag1"],
      instaQLManyToManyInferenceSource
    )
    expectNoDifference(posts.first?["tags"]?.object, nil, instaQLManyToManyInferenceSource)
    expectNoDifference(
      posts.first?["tags"]?.objects?.map(\.namespace),
      ["tags"],
      instaQLManyToManyInferenceSource
    )
    expectNoDifference(tags.map(\.id), ["tag1"], instaQLManyToManyInferenceSource)
    expectNoDifference(
      tags.first?["posts"]?.objects?.map(\.id),
      ["post1"],
      instaQLManyToManyInferenceSource
    )
    expectNoDifference(tags.first?["posts"]?.object, nil, instaQLManyToManyInferenceSource)
    expectNoDifference(
      tags.first?["posts"]?.objects?.map(\.namespace),
      ["posts"],
      instaQLManyToManyInferenceSource
    )
  }

  @Test
  func upstreamInstaQLOneToOneWithInferenceMaterializesSingularCardinality() async throws {
    let fixture = InstaQLInferenceFixture.oneToOne()
    let store = InstantStore(snapshot: fixture.snapshot)

    let users = await store.materializeInstaQL(
      fixture.forwardQuery,
      cardinalityInference: true
    )
    let profiles = await store.materializeInstaQL(
      fixture.reverseQuery,
      cardinalityInference: true
    )

    let relation = try #require(fixture.relationAttribute)
    expectNoDifference(relation.cardinality, .one, instaQLOneToOneInferenceSource)
    expectNoDifference(relation.isUnique, true, instaQLOneToOneInferenceSource)
    expectNoDifference(relation.forwardIdentity, "users/profile", instaQLOneToOneInferenceSource)
    expectNoDifference(relation.reverseIdentity, "profiles/user", instaQLOneToOneInferenceSource)
    expectNoDifference(relation.linkNamespace, "profiles", instaQLOneToOneInferenceSource)
    expectNoDifference(users.map(\.id), ["user1"], instaQLOneToOneInferenceSource)
    expectNoDifference(profiles.map(\.id), ["profile1"], instaQLOneToOneInferenceSource)
    expectNoDifference(
      users.first?["profile"]?.object?.id,
      "profile1",
      instaQLOneToOneInferenceSource
    )
    expectNoDifference(users.first?["profile"]?.objects, nil, instaQLOneToOneInferenceSource)
    expectNoDifference(
      users.first?["profile"]?.object?["id"]?.scalar,
      .string("profile1"),
      instaQLOneToOneInferenceSource
    )
    expectNoDifference(
      profiles.first?["user"]?.object?.id,
      "user1",
      instaQLOneToOneInferenceSource
    )
    expectNoDifference(profiles.first?["user"]?.objects, nil, instaQLOneToOneInferenceSource)
    expectNoDifference(
      profiles.first?["user"]?.object?["id"]?.scalar,
      .string("user1"),
      instaQLOneToOneInferenceSource
    )
  }

  @Test
  func upstreamInstaQLOneToOneWithoutInferenceKeepsArraySurface() async throws {
    let fixture = InstaQLInferenceFixture.oneToOne()
    let store = InstantStore(snapshot: fixture.snapshot)

    let users = await store.materializeInstaQL(
      fixture.forwardQuery,
      cardinalityInference: false
    )
    let profiles = await store.materializeInstaQL(
      fixture.reverseQuery,
      cardinalityInference: false
    )

    let relation = try #require(fixture.relationAttribute)
    expectNoDifference(relation.cardinality, .one, instaQLOneToOneWithoutInferenceSource)
    expectNoDifference(relation.isUnique, true, instaQLOneToOneWithoutInferenceSource)
    expectNoDifference(relation.forwardIdentity, "users/profile", instaQLOneToOneWithoutInferenceSource)
    expectNoDifference(relation.reverseIdentity, "profiles/user", instaQLOneToOneWithoutInferenceSource)
    expectNoDifference(relation.linkNamespace, "profiles", instaQLOneToOneWithoutInferenceSource)
    expectNoDifference(users.map(\.id), ["user1"], instaQLOneToOneWithoutInferenceSource)
    expectNoDifference(profiles.map(\.id), ["profile1"], instaQLOneToOneWithoutInferenceSource)
    expectNoDifference(
      users.first?["profile"]?.objects?.map(\.id),
      ["profile1"],
      instaQLOneToOneWithoutInferenceSource
    )
    expectNoDifference(users.first?["profile"]?.object, nil, instaQLOneToOneWithoutInferenceSource)
    expectNoDifference(
      users.first?["profile"]?.objects?.count,
      1,
      instaQLOneToOneWithoutInferenceSource
    )
    expectNoDifference(
      profiles.first?["user"]?.objects?.map(\.id),
      ["user1"],
      instaQLOneToOneWithoutInferenceSource
    )
    expectNoDifference(profiles.first?["user"]?.object, nil, instaQLOneToOneWithoutInferenceSource)
    expectNoDifference(
      profiles.first?["user"]?.objects?.count,
      1,
      instaQLOneToOneWithoutInferenceSource
    )
  }
}

private struct InstaQLInferenceFixture {
  var snapshot: InstantStoreSnapshot
  var forwardQuery: InstantQueryPlan
  var reverseQuery: InstantQueryPlan
  var relationAttribute: InstantAttribute? {
    snapshot.attributes.first { $0.valueType == .ref }
  }

  static func manyToMany() -> Self {
    let relationAttribute = InstantAttribute(
      id: "attrs/posts-tags",
      namespace: "posts",
      name: "tags",
      valueType: .ref,
      cardinality: .many,
      isUnique: false,
      forwardIdentity: "posts/tags",
      reverseIdentity: "tags/posts",
      linkNamespace: "tags"
    )
    return Self(
      snapshot: InstantStoreSnapshot(
        attributes: [
          relationAttribute,
          .primaryKey(namespace: "posts"),
          .primaryKey(namespace: "tags"),
        ],
        triples: [
          triple("post1", "posts/id", .string("post1")),
          triple("tag1", "tags/id", .string("tag1")),
          triple("post1", relationAttribute.id, .ref("tag1")),
        ]
      ),
      forwardQuery: InstantQueryPlan(
        id: "instaql-inference.posts-with-tags",
        namespace: "posts",
        includes: [
          InstantQueryInclude(
            "tags",
            query: InstantQueryIncludePlan(id: "instaql-inference.tags", namespace: "tags")
          )
        ]
      ),
      reverseQuery: InstantQueryPlan(
        id: "instaql-inference.tags-with-posts",
        namespace: "tags",
        includes: [
          InstantQueryInclude(
            "posts",
            direction: .reverse,
            query: InstantQueryIncludePlan(id: "instaql-inference.posts", namespace: "posts")
          )
        ]
      )
    )
  }

  static func oneToOne() -> Self {
    let relationAttribute = InstantAttribute(
      id: "attrs/users-profile",
      namespace: "users",
      name: "profile",
      valueType: .ref,
      cardinality: .one,
      isUnique: true,
      forwardIdentity: "users/profile",
      reverseIdentity: "profiles/user",
      linkNamespace: "profiles"
    )
    return Self(
      snapshot: InstantStoreSnapshot(
        attributes: [
          relationAttribute,
          .primaryKey(namespace: "users"),
          .primaryKey(namespace: "profiles"),
        ],
        triples: [
          triple("user1", "users/id", .string("user1")),
          triple("profile1", "profiles/id", .string("profile1")),
          triple("user1", relationAttribute.id, .ref("profile1")),
        ]
      ),
      forwardQuery: InstantQueryPlan(
        id: "instaql-inference.users-with-profile",
        namespace: "users",
        includes: [
          InstantQueryInclude(
            "profile",
            query: InstantQueryIncludePlan(id: "instaql-inference.profiles", namespace: "profiles")
          )
        ]
      ),
      reverseQuery: InstantQueryPlan(
        id: "instaql-inference.profiles-with-user",
        namespace: "profiles",
        includes: [
          InstantQueryInclude(
            "user",
            direction: .reverse,
            query: InstantQueryIncludePlan(id: "instaql-inference.users", namespace: "users")
          )
        ]
      )
    )
  }

  private static func triple(
    _ entityID: String,
    _ attributeID: String,
    _ value: InstantValue
  ) -> InstantTriple {
    InstantTriple(
      entityID: entityID,
      attributeID: attributeID,
      value: value,
      txID: "tx-instaql-inference",
      txTime: InstantTimestamp(milliseconds: 1_700_000_050_000)
    )
  }
}

private let instaQLManyToManyInferenceSource =
  "upstream/instant/client/packages/core/__tests__/src/instaqlInference.test.ts many-to-many with inference [adapted: Swift InstaQL projection keeps many relationships array-shaped and asserts forward/reverse materialization.]"

private let instaQLOneToOneInferenceSource =
  "upstream/instant/client/packages/core/__tests__/src/instaqlInference.test.ts one-to-one with inference [adapted: Swift InstaQL projection returns singular linked objects when cardinality inference is enabled.]"

private let instaQLOneToOneWithoutInferenceSource =
  "upstream/instant/client/packages/core/__tests__/src/instaqlInference.test.ts one-to-one without inference [adapted: Swift InstaQL projection keeps linked objects array-shaped when cardinality inference is disabled.]"
