import Foundation

public struct MicroblogUserRecord: Hashable, Codable, Sendable, Identifiable {
  public var id: String
  public var email: String?
  public var imageURL: String?
  public var type: String?

  public init(id: String, email: String? = nil, imageURL: String? = nil, type: String? = nil) {
    self.id = id
    self.email = email
    self.imageURL = imageURL
    self.type = type
  }
}

public struct MicroblogProfileRecord: Hashable, Codable, Sendable, Identifiable {
  public var id: String
  public var userID: String
  public var displayName: String
  public var handle: String

  public init(id: String, userID: String, displayName: String, handle: String) {
    self.id = id
    self.userID = userID
    self.displayName = displayName
    self.handle = handle
  }
}

public struct MicroblogPostRecord: Hashable, Codable, Sendable, Identifiable {
  public var id: String
  public var authorProfileID: String
  public var color: String
  public var content: String
  public var timestamp: InstantTimestamp

  public init(
    id: String,
    authorProfileID: String,
    color: String,
    content: String,
    timestamp: InstantTimestamp
  ) {
    self.id = id
    self.authorProfileID = authorProfileID
    self.color = color
    self.content = content
    self.timestamp = timestamp
  }
}

public struct MicroblogLikeRecord: Hashable, Codable, Sendable, Identifiable {
  public var id: String
  public var userID: String
  public var postID: String

  public init(id: String, userID: String, postID: String) {
    self.id = id
    self.userID = userID
    self.postID = postID
  }
}

public struct MicroblogFeedPostRecord: Hashable, Codable, Sendable, Identifiable {
  public var id: String { post.id }
  public var post: MicroblogPostRecord
  public var author: MicroblogProfileRecord?
  public var likes: [MicroblogLikeRecord]

  public init(
    post: MicroblogPostRecord,
    author: MicroblogProfileRecord?,
    likes: [MicroblogLikeRecord]
  ) {
    self.post = post
    self.author = author
    self.likes = likes
  }
}

public enum MicroblogExample {
  public static let usersNamespace = "$users"
  public static let profilesNamespace = "profiles"
  public static let postsNamespace = "posts"
  public static let likesNamespace = "likes"

  public static let seedPosts: [SeedPost] = [
    SeedPost(
      slug: "sarahchen",
      author: "Sarah Chen",
      handle: "sarahchen",
      color: "bg-blue-100",
      content: "Just launched my new project! Really excited to share it with everyone.",
      hoursAgo: 2,
      likes: 12
    ),
    SeedPost(
      slug: "alexrivera",
      author: "Alex Rivera",
      handle: "alexrivera",
      color: "bg-purple-100",
      content: "Beautiful sunset today. Nature never stops amazing me.",
      hoursAgo: 4,
      likes: 19
    ),
    SeedPost(
      slug: "jordanlee",
      author: "Jordan Lee",
      handle: "jordanlee",
      color: "bg-pink-100",
      content: "Working on something cool with Next.js and TypeScript. Updates coming soon!",
      hoursAgo: 6,
      likes: 7
    ),
  ]

  public static let attributes: [InstantAttribute] = [
    .primaryKey(namespace: usersNamespace),
    InstantAttribute(
      id: "$users/email",
      namespace: usersNamespace,
      name: "email",
      valueType: .string,
      isRequired: false,
      isIndexed: true,
      isUnique: true
    ),
    InstantAttribute(
      id: "$users/imageURL",
      namespace: usersNamespace,
      name: "imageURL",
      valueType: .string,
      isRequired: false
    ),
    InstantAttribute(
      id: "$users/type",
      namespace: usersNamespace,
      name: "type",
      valueType: .string,
      isRequired: false
    ),
    .primaryKey(namespace: profilesNamespace),
    InstantAttribute(
      id: "profiles/displayName",
      namespace: profilesNamespace,
      name: "displayName",
      valueType: .string,
      isIndexed: true
    ),
    InstantAttribute(
      id: "profiles/handle",
      namespace: profilesNamespace,
      name: "handle",
      valueType: .string,
      isIndexed: true,
      isUnique: true
    ),
    InstantAttribute(
      id: "profiles/user",
      namespace: profilesNamespace,
      name: "user",
      valueType: .ref,
      isIndexed: true,
      isUnique: true,
      forwardIdentity: "profiles/user",
      reverseIdentity: "$users/profile",
      linkNamespace: usersNamespace,
      onDelete: .cascade
    ),
    .primaryKey(namespace: postsNamespace),
    InstantAttribute(
      id: "posts/color",
      namespace: postsNamespace,
      name: "color",
      valueType: .string,
      isIndexed: true
    ),
    InstantAttribute(
      id: "posts/content",
      namespace: postsNamespace,
      name: "content",
      valueType: .string
    ),
    InstantAttribute(
      id: "posts/timestamp",
      namespace: postsNamespace,
      name: "timestamp",
      valueType: .number,
      isIndexed: true
    ),
    InstantAttribute(
      id: "posts/author",
      namespace: postsNamespace,
      name: "author",
      valueType: .ref,
      isIndexed: true,
      forwardIdentity: "posts/author",
      reverseIdentity: "profiles/posts",
      linkNamespace: profilesNamespace,
      onDelete: .cascade
    ),
    .primaryKey(namespace: likesNamespace),
    InstantAttribute(
      id: "likes/userId",
      namespace: likesNamespace,
      name: "userId",
      valueType: .string,
      isIndexed: true
    ),
    InstantAttribute(
      id: "likes/postId",
      namespace: likesNamespace,
      name: "postId",
      valueType: .string,
      isIndexed: true
    ),
    InstantAttribute(
      id: "likes/user",
      namespace: likesNamespace,
      name: "user",
      valueType: .ref,
      isIndexed: true,
      forwardIdentity: "likes/user",
      reverseIdentity: "profiles/likes",
      linkNamespace: profilesNamespace,
      onDelete: .cascade
    ),
    InstantAttribute(
      id: "likes/post",
      namespace: likesNamespace,
      name: "post",
      valueType: .ref,
      isIndexed: true,
      forwardIdentity: "likes/post",
      reverseIdentity: "posts/likes",
      linkNamespace: postsNamespace,
      onDelete: .cascade
    ),
  ]

  public static let usersQuery = InstantQueryPlan(
    id: "examples.microblog.users",
    namespace: usersNamespace
  )

  public static let profilesQuery = InstantQueryPlan(
    id: "examples.microblog.profiles",
    namespace: profilesNamespace,
    order: InstantQueryOrder("handle", .ascending)
  )

  public static let postsQuery = InstantQueryPlan(
    id: "examples.microblog.posts",
    namespace: postsNamespace,
    order: InstantQueryOrder("timestamp", .descending)
  )

  public static let likesQuery = InstantQueryPlan(
    id: "examples.microblog.likes",
    namespace: likesNamespace
  )

  public static let feedQuery = InstantQueryPlan(
    id: "examples.microblog.feed",
    namespace: postsNamespace,
    order: InstantQueryOrder("timestamp", .descending),
    includes: [
      InstantQueryInclude(
        "author",
        query: InstantQueryIncludePlan(
          id: "examples.microblog.feed.authors",
          namespace: profilesNamespace,
          selectedFields: ["displayName", "handle", "user"]
        )
      ),
      InstantQueryInclude(
        "likes",
        direction: .reverse,
        query: InstantQueryIncludePlan(
          id: "examples.microblog.feed.likes",
          namespace: likesNamespace,
          selectedFields: ["userId", "postId"]
        )
      ),
    ]
  )

  public static func profileForUserQuery(_ userID: String) -> InstantQueryPlan {
    InstantQueryPlan(
      id: "examples.microblog.profile.\(userID)",
      namespace: profilesNamespace,
      filters: [.equals(field: "user", value: .ref(userID))]
    )
  }

  public static func likesForPostQuery(_ postID: String) -> InstantQueryPlan {
    InstantQueryPlan(
      id: "examples.microblog.likes.post.\(postID)",
      namespace: likesNamespace,
      filters: [.equals(field: "post", value: .ref(postID))]
    )
  }

  public static func seedOperations(
    ids: SeedIDs,
    baseTimestamp: InstantTimestamp,
    transactionID: String
  ) -> [InstantTripleOperation] {
    seedPosts.enumerated().flatMap { index, seed in
      let userID = ids.userIDs[index]
      let postID = ids.postIDs[index]
      let postTimestamp = InstantTimestamp(
        milliseconds: baseTimestamp.milliseconds - Int64(seed.hoursAgo * 60 * 60 * 1000)
      )
      let likeOperations = ids.likeIDs[index].map { likeID in
        upsertLikeOperations(
          id: likeID,
          userID: userID,
          postID: postID,
          transactionID: transactionID,
          updatedAt: postTimestamp
        )
      }
      return upsertUserOperations(
        id: userID,
        email: nil,
        imageURL: nil,
        type: nil,
        transactionID: transactionID,
        updatedAt: postTimestamp
      )
        + upsertProfileOperations(
          id: userID,
          userID: userID,
          displayName: seed.author,
          handle: seed.handle,
          transactionID: transactionID,
          updatedAt: postTimestamp
        )
        + upsertPostOperations(
          id: postID,
          authorProfileID: userID,
          color: seed.color,
          content: seed.content,
          timestamp: postTimestamp,
          transactionID: transactionID
        )
        + likeOperations.flatMap { $0 }
    }
  }

  public static func createProfileOperations(
    userID: String,
    displayName: String,
    handle: String,
    transactionID: String,
    updatedAt: InstantTimestamp
  ) -> [InstantTripleOperation] {
    [
      .requireEntityMissing(entityID: userID, namespace: profilesNamespace)
    ]
      + upsertUserOperations(
        id: userID,
        email: nil,
        imageURL: nil,
        type: nil,
        transactionID: transactionID,
        updatedAt: updatedAt
      )
      + upsertProfileOperations(
        id: userID,
        userID: userID,
        displayName: displayName,
        handle: handle,
        transactionID: transactionID,
        updatedAt: updatedAt
      )
  }

  public static func upsertUserOperations(
    id: String,
    email: String?,
    imageURL: String?,
    type: String?,
    transactionID: String,
    updatedAt: InstantTimestamp
  ) -> [InstantTripleOperation] {
    var operations = [
      identityOperation(
        id: id,
        namespace: usersNamespace,
        updatedAt: updatedAt,
        transactionID: transactionID
      )
    ]
    if let email {
      operations.append(
        scalarOperation(
          id: id,
          attributeID: "$users/email",
          value: .string(email),
          transactionID: transactionID,
          updatedAt: updatedAt
        )
      )
    }
    if let imageURL {
      operations.append(
        scalarOperation(
          id: id,
          attributeID: "$users/imageURL",
          value: .string(imageURL),
          transactionID: transactionID,
          updatedAt: updatedAt
        )
      )
    }
    if let type {
      operations.append(
        scalarOperation(
          id: id,
          attributeID: "$users/type",
          value: .string(type),
          transactionID: transactionID,
          updatedAt: updatedAt
        )
      )
    }
    return operations
  }

  public static func upsertProfileOperations(
    id: String,
    userID: String,
    displayName: String,
    handle: String,
    transactionID: String,
    updatedAt: InstantTimestamp
  ) -> [InstantTripleOperation] {
    [
      identityOperation(
        id: id,
        namespace: profilesNamespace,
        updatedAt: updatedAt,
        transactionID: transactionID
      ),
      scalarOperation(
        id: id,
        attributeID: "profiles/displayName",
        value: .string(displayName),
        transactionID: transactionID,
        updatedAt: updatedAt
      ),
      scalarOperation(
        id: id,
        attributeID: "profiles/handle",
        value: .string(handle),
        transactionID: transactionID,
        updatedAt: updatedAt
      ),
      scalarOperation(
        id: id,
        attributeID: "profiles/user",
        value: .ref(userID),
        transactionID: transactionID,
        updatedAt: updatedAt
      ),
    ]
  }

  public static func createPostOperations(
    id: String,
    authorProfileID: String,
    color: String,
    content: String,
    timestamp: InstantTimestamp,
    transactionID: String
  ) -> [InstantTripleOperation] {
    [
      .requireEntityMissing(entityID: id, namespace: postsNamespace),
      .requireEntityExists(entityID: authorProfileID, namespace: profilesNamespace),
    ]
      + upsertPostOperations(
        id: id,
        authorProfileID: authorProfileID,
        color: color,
        content: content,
        timestamp: timestamp,
        transactionID: transactionID
      )
  }

  public static func upsertPostOperations(
    id: String,
    authorProfileID: String,
    color: String,
    content: String,
    timestamp: InstantTimestamp,
    transactionID: String
  ) -> [InstantTripleOperation] {
    [
      identityOperation(
        id: id,
        namespace: postsNamespace,
        updatedAt: timestamp,
        transactionID: transactionID
      ),
      scalarOperation(
        id: id,
        attributeID: "posts/color",
        value: .string(color),
        transactionID: transactionID,
        updatedAt: timestamp
      ),
      scalarOperation(
        id: id,
        attributeID: "posts/content",
        value: .string(content),
        transactionID: transactionID,
        updatedAt: timestamp
      ),
      scalarOperation(
        id: id,
        attributeID: "posts/timestamp",
        value: .number(Double(timestamp.milliseconds)),
        transactionID: transactionID,
        updatedAt: timestamp
      ),
      scalarOperation(
        id: id,
        attributeID: "posts/author",
        value: .ref(authorProfileID),
        transactionID: transactionID,
        updatedAt: timestamp
      ),
    ]
  }

  public static func createLikeOperations(
    id: String,
    userID: String,
    postID: String,
    transactionID: String,
    updatedAt: InstantTimestamp
  ) -> [InstantTripleOperation] {
    [
      .requireEntityMissing(entityID: id, namespace: likesNamespace),
      .requireEntityExists(entityID: userID, namespace: profilesNamespace),
      .requireEntityExists(entityID: postID, namespace: postsNamespace),
    ]
      + upsertLikeOperations(
        id: id,
        userID: userID,
        postID: postID,
        transactionID: transactionID,
        updatedAt: updatedAt
      )
  }

  public static func upsertLikeOperations(
    id: String,
    userID: String,
    postID: String,
    transactionID: String,
    updatedAt: InstantTimestamp
  ) -> [InstantTripleOperation] {
    [
      identityOperation(
        id: id,
        namespace: likesNamespace,
        updatedAt: updatedAt,
        transactionID: transactionID
      ),
      scalarOperation(
        id: id,
        attributeID: "likes/userId",
        value: .string(userID),
        transactionID: transactionID,
        updatedAt: updatedAt
      ),
      scalarOperation(
        id: id,
        attributeID: "likes/postId",
        value: .string(postID),
        transactionID: transactionID,
        updatedAt: updatedAt
      ),
      scalarOperation(
        id: id,
        attributeID: "likes/user",
        value: .ref(userID),
        transactionID: transactionID,
        updatedAt: updatedAt
      ),
      scalarOperation(
        id: id,
        attributeID: "likes/post",
        value: .ref(postID),
        transactionID: transactionID,
        updatedAt: updatedAt
      ),
    ]
  }

  public static func deleteUserOperations(id: String) -> [InstantTripleOperation] {
    [
      .requireEntityExists(entityID: id, namespace: usersNamespace),
      .deleteEntityInNamespace(entityID: id, namespace: usersNamespace),
    ]
  }

  public static func deletePostOperations(id: String) -> [InstantTripleOperation] {
    [
      .requireEntityExists(entityID: id, namespace: postsNamespace),
      .deleteEntityInNamespace(entityID: id, namespace: postsNamespace),
    ]
  }

  public static func deleteLikeOperations(id: String) -> [InstantTripleOperation] {
    [
      .requireEntityExists(entityID: id, namespace: likesNamespace),
      .deleteEntityInNamespace(entityID: id, namespace: likesNamespace),
    ]
  }

  public static func decodeUsers(
    _ snapshots: [InstantEntitySnapshot]
  ) throws -> [MicroblogUserRecord] {
    try snapshots.map { snapshot in
      MicroblogUserRecord(
        id: snapshot.id,
        email: try optionalString("email", from: snapshot, namespace: usersNamespace),
        imageURL: try optionalString("imageURL", from: snapshot, namespace: usersNamespace),
        type: try optionalString("type", from: snapshot, namespace: usersNamespace)
      )
    }
  }

  public static func decodeProfiles(
    _ snapshots: [InstantEntitySnapshot]
  ) throws -> [MicroblogProfileRecord] {
    try snapshots.map(decodeProfile)
  }

  public static func decodePosts(
    _ snapshots: [InstantEntitySnapshot]
  ) throws -> [MicroblogPostRecord] {
    try snapshots.map(decodePost)
  }

  public static func decodeLikes(
    _ snapshots: [InstantEntitySnapshot]
  ) throws -> [MicroblogLikeRecord] {
    try snapshots.map(decodeLike)
  }

  public static func decodeFeed(
    _ snapshots: [InstantEntitySnapshot]
  ) throws -> [MicroblogFeedPostRecord] {
    try snapshots.map { snapshot in
      let post = try decodePost(snapshot)
      let author = try snapshot.links?["author"]?.first.map(decodeProfile)
      let likes = try (snapshot.links?["likes"] ?? []).map(decodeLike)
      return MicroblogFeedPostRecord(post: post, author: author, likes: likes)
    }
  }

  private static func decodeProfile(
    _ snapshot: InstantEntitySnapshot
  ) throws -> MicroblogProfileRecord {
    try decodeProfile(InstantLinkedEntitySnapshot(snapshot))
  }

  private static func decodeProfile(
    _ snapshot: InstantLinkedEntitySnapshot
  ) throws -> MicroblogProfileRecord {
    MicroblogProfileRecord(
      id: snapshot.id,
      userID: try refField("user", from: snapshot, namespace: profilesNamespace),
      displayName: try stringField("displayName", from: snapshot, namespace: profilesNamespace),
      handle: try stringField("handle", from: snapshot, namespace: profilesNamespace)
    )
  }

  private static func decodePost(
    _ snapshot: InstantEntitySnapshot
  ) throws -> MicroblogPostRecord {
    MicroblogPostRecord(
      id: snapshot.id,
      authorProfileID: try refField("author", from: snapshot, namespace: postsNamespace),
      color: try stringField("color", from: snapshot, namespace: postsNamespace),
      content: try stringField("content", from: snapshot, namespace: postsNamespace),
      timestamp: InstantTimestamp(
        milliseconds: try integerNumberField("timestamp", from: snapshot, namespace: postsNamespace)
      )
    )
  }

  private static func decodeLike(
    _ snapshot: InstantEntitySnapshot
  ) throws -> MicroblogLikeRecord {
    try decodeLike(InstantLinkedEntitySnapshot(snapshot))
  }

  private static func decodeLike(
    _ snapshot: InstantLinkedEntitySnapshot
  ) throws -> MicroblogLikeRecord {
    MicroblogLikeRecord(
      id: snapshot.id,
      userID: try stringField("userId", from: snapshot, namespace: likesNamespace),
      postID: try stringField("postId", from: snapshot, namespace: likesNamespace)
    )
  }

  private static func identityOperation(
    id: String,
    namespace: String,
    updatedAt: InstantTimestamp,
    transactionID: String
  ) -> InstantTripleOperation {
    scalarOperation(
      id: id,
      attributeID: InstantAttribute.primaryKeyID(namespace: namespace),
      value: .string(id),
      transactionID: transactionID,
      updatedAt: updatedAt
    )
  }

  private static func scalarOperation(
    id: String,
    attributeID: String,
    value: InstantValue,
    transactionID: String,
    updatedAt: InstantTimestamp
  ) -> InstantTripleOperation {
    .insert(
      InstantTriple(
        entityID: id,
        attributeID: attributeID,
        value: value,
        txID: transactionID,
        txTime: updatedAt
      )
    )
  }

  private static func stringField(
    _ field: String,
    from snapshot: InstantEntitySnapshot,
    namespace: String
  ) throws -> String {
    try stringField(field, from: InstantLinkedEntitySnapshot(snapshot), namespace: namespace)
  }

  private static func stringField(
    _ field: String,
    from snapshot: InstantLinkedEntitySnapshot,
    namespace: String
  ) throws -> String {
    guard case let .string(value) = snapshot.values[field]?.first else {
      throw decodeError(namespace: namespace, id: snapshot.id, field: field, expected: "string")
    }
    return value
  }

  private static func optionalString(
    _ field: String,
    from snapshot: InstantEntitySnapshot,
    namespace: String
  ) throws -> String? {
    guard let value = snapshot.values[field]?.first else { return nil }
    guard case let .string(string) = value else {
      throw decodeError(namespace: namespace, id: snapshot.id, field: field, expected: "string")
    }
    return string
  }

  private static func refField(
    _ field: String,
    from snapshot: InstantEntitySnapshot,
    namespace: String
  ) throws -> String {
    try refField(field, from: InstantLinkedEntitySnapshot(snapshot), namespace: namespace)
  }

  private static func refField(
    _ field: String,
    from snapshot: InstantLinkedEntitySnapshot,
    namespace: String
  ) throws -> String {
    guard case let .ref(value) = snapshot.values[field]?.first else {
      throw decodeError(namespace: namespace, id: snapshot.id, field: field, expected: "ref")
    }
    return value
  }

  private static func integerNumberField(
    _ field: String,
    from snapshot: InstantEntitySnapshot,
    namespace: String
  ) throws -> Int64 {
    guard case let .number(value) = snapshot.values[field]?.first,
      value.rounded() == value
    else {
      throw decodeError(
        namespace: namespace,
        id: snapshot.id,
        field: field,
        expected: "integer number"
      )
    }
    return Int64(value)
  }

  private static func decodeError(
    namespace: String,
    id: String,
    field: String,
    expected: String
  ) -> InstantError {
    InstantError(
      code: .decodeFailed,
      operation: "decode microblog example",
      namespace: namespace,
      path: field,
      localID: id,
      message: "Expected \(expected) for microblog field '\(field)'.",
      recovery: "Inspect the local microblog example triples and attributes."
    )
  }
}

extension MicroblogExample {
  public struct SeedPost: Hashable, Codable, Sendable {
    public var slug: String
    public var author: String
    public var handle: String
    public var color: String
    public var content: String
    public var hoursAgo: Int
    public var likes: Int

    public init(
      slug: String,
      author: String,
      handle: String,
      color: String,
      content: String,
      hoursAgo: Int,
      likes: Int
    ) {
      self.slug = slug
      self.author = author
      self.handle = handle
      self.color = color
      self.content = content
      self.hoursAgo = hoursAgo
      self.likes = likes
    }
  }

  public struct SeedIDs: Hashable, Codable, Sendable {
    public var userIDs: [String]
    public var postIDs: [String]
    public var likeIDs: [[String]]

    public init(userIDs: [String], postIDs: [String], likeIDs: [[String]]) {
      self.userIDs = userIDs
      self.postIDs = postIDs
      self.likeIDs = likeIDs
    }
  }
}
