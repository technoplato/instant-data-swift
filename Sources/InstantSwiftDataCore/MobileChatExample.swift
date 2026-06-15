import Foundation

public struct MobileChatUserRecord: Hashable, Codable, Sendable, Identifiable {
  public var id: String
  public var email: String?
  public var imageURL: String?
  public var type: String?
  public var linkedPrimaryUserID: String?

  public init(
    id: String,
    email: String? = nil,
    imageURL: String? = nil,
    type: String? = nil,
    linkedPrimaryUserID: String? = nil
  ) {
    self.id = id
    self.email = email
    self.imageURL = imageURL
    self.type = type
    self.linkedPrimaryUserID = linkedPrimaryUserID
  }
}

public struct MobileChatProfileRecord: Hashable, Codable, Sendable, Identifiable {
  public var id: String
  public var userID: String
  public var displayName: String

  public init(id: String, userID: String, displayName: String) {
    self.id = id
    self.userID = userID
    self.displayName = displayName
  }
}

public struct MobileChatChannelRecord: Hashable, Codable, Sendable, Identifiable {
  public var id: String
  public var name: String

  public init(id: String, name: String) {
    self.id = id
    self.name = name
  }
}

public struct MobileChatMessageRecord: Hashable, Codable, Sendable, Identifiable {
  public var id: String
  public var channelID: String
  public var authorProfileID: String?
  public var content: String
  public var timestamp: InstantTimestamp
  public var author: MobileChatProfileRecord?
  public var authorUser: MobileChatUserRecord?

  public init(
    id: String,
    channelID: String,
    authorProfileID: String? = nil,
    content: String,
    timestamp: InstantTimestamp,
    author: MobileChatProfileRecord? = nil,
    authorUser: MobileChatUserRecord? = nil
  ) {
    self.id = id
    self.channelID = channelID
    self.authorProfileID = authorProfileID
    self.content = content
    self.timestamp = timestamp
    self.author = author
    self.authorUser = authorUser
  }
}

public enum MobileChatExample {
  public static let filesNamespace = "$files"
  public static let usersNamespace = "$users"
  public static let profilesNamespace = "mobileProfiles"
  public static let channelsNamespace = "mobileChannels"
  public static let messagesNamespace = "mobileMessages"

  public static let generalChannelIDName = "examples.mobile-chat.channels.general"
  public static let randomChannelIDName = "examples.mobile-chat.channels.random"
  public static let seedUserIDName = "examples.mobile-chat.users.instant"
  public static let welcomeMessageIDName = "examples.mobile-chat.messages.general.welcome"
  public static let randomMessageIDName = "examples.mobile-chat.messages.random.seed"

  public static let attributes: [InstantAttribute] = [
    .primaryKey(namespace: filesNamespace),
    InstantAttribute(
      id: "$files/path",
      namespace: filesNamespace,
      name: "path",
      valueType: .string,
      isIndexed: true,
      isUnique: true
    ),
    InstantAttribute(
      id: "$files/url",
      namespace: filesNamespace,
      name: "url",
      valueType: .string
    ),

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
    InstantAttribute(
      id: "$users/linkedPrimaryUser",
      namespace: usersNamespace,
      name: "linkedPrimaryUser",
      valueType: .ref,
      isRequired: false,
      isIndexed: true,
      forwardIdentity: "$users/linkedPrimaryUser",
      reverseIdentity: "$users/linkedGuestUsers",
      linkNamespace: usersNamespace,
      onDelete: .cascade
    ),

    .primaryKey(namespace: profilesNamespace),
    InstantAttribute(
      id: "mobileProfiles/displayName",
      namespace: profilesNamespace,
      name: "displayName",
      valueType: .string
    ),
    InstantAttribute(
      id: "mobileProfiles/user",
      namespace: profilesNamespace,
      name: "user",
      valueType: .ref,
      isIndexed: true,
      isUnique: true,
      forwardIdentity: "mobileProfiles/user",
      reverseIdentity: "$users/mobileProfile",
      linkNamespace: usersNamespace,
      onDelete: .cascade
    ),

    .primaryKey(namespace: channelsNamespace),
    InstantAttribute(
      id: "mobileChannels/name",
      namespace: channelsNamespace,
      name: "name",
      valueType: .string,
      isIndexed: true
    ),

    .primaryKey(namespace: messagesNamespace),
    InstantAttribute(
      id: "mobileMessages/content",
      namespace: messagesNamespace,
      name: "content",
      valueType: .string
    ),
    InstantAttribute(
      id: "mobileMessages/timestamp",
      namespace: messagesNamespace,
      name: "timestamp",
      valueType: .number,
      isIndexed: true
    ),
    InstantAttribute(
      id: "mobileMessages/author",
      namespace: messagesNamespace,
      name: "author",
      valueType: .ref,
      isRequired: false,
      isIndexed: true,
      forwardIdentity: "mobileMessages/author",
      reverseIdentity: "mobileProfiles/messages",
      linkNamespace: profilesNamespace,
      onDelete: .cascade
    ),
    InstantAttribute(
      id: "mobileMessages/channel",
      namespace: messagesNamespace,
      name: "channel",
      valueType: .ref,
      isIndexed: true,
      forwardIdentity: "mobileMessages/channel",
      reverseIdentity: "mobileChannels/messages",
      linkNamespace: channelsNamespace,
      onDelete: .cascade
    ),
  ]

  public static let usersQuery = InstantQueryPlan(
    id: "examples.mobile-chat.users",
    namespace: usersNamespace
  )

  public static let profilesQuery = InstantQueryPlan(
    id: "examples.mobile-chat.profiles",
    namespace: profilesNamespace,
    order: InstantQueryOrder("displayName", .ascending)
  )

  public static let channelsQuery = InstantQueryPlan(
    id: "examples.mobile-chat.channels",
    namespace: channelsNamespace,
    order: InstantQueryOrder("name", .ascending)
  )

  public static let messagesQuery = InstantQueryPlan(
    id: "examples.mobile-chat.messages",
    namespace: messagesNamespace,
    order: InstantQueryOrder("timestamp", .ascending),
    includes: [messageAuthorInclude(id: "examples.mobile-chat.messages.authors")]
  )

  public static func profileForUserQuery(_ userID: String) -> InstantQueryPlan {
    InstantQueryPlan(
      id: "examples.mobile-chat.profile.\(userID)",
      namespace: profilesNamespace,
      filters: [.equals(field: "user.id", value: .string(userID))]
    )
  }

  public static func messagesForChannelQuery(_ channelID: String) -> InstantQueryPlan {
    InstantQueryPlan(
      id: "examples.mobile-chat.messages.\(channelID)",
      namespace: messagesNamespace,
      filters: [.equals(field: "channel.id", value: .string(channelID))],
      order: InstantQueryOrder("timestamp", .ascending),
      includes: [messageAuthorInclude(id: "examples.mobile-chat.messages.\(channelID).authors")]
    )
  }

  public static func room(forChannelID channelID: String) -> InstantRoomHandle {
    InstantRoomHandle(type: "chat", id: channelID)
  }

  public static func presenceValues(profile: MobileChatProfileRecord) -> [String: JSONValue] {
    [
      "profileId": .string(profile.id),
      "displayName": .string(profile.displayName),
    ]
  }

  public static func seedOperations(
    ids: SeedIDs,
    baseTimestamp: InstantTimestamp,
    transactionID: String
  ) -> [InstantTripleOperation] {
    let generalTimestamp = baseTimestamp
    let randomTimestamp = InstantTimestamp(milliseconds: baseTimestamp.milliseconds + 1)
    let welcomeTimestamp = InstantTimestamp(milliseconds: baseTimestamp.milliseconds + 2)
    let randomMessageTimestamp = InstantTimestamp(milliseconds: baseTimestamp.milliseconds + 3)

    return upsertChannelOperations(
      id: ids.generalChannelID,
      name: "general",
      transactionID: transactionID,
      updatedAt: generalTimestamp
    )
      + upsertChannelOperations(
        id: ids.randomChannelID,
        name: "random",
        transactionID: transactionID,
        updatedAt: randomTimestamp
      )
      + upsertUserOperations(
        id: ids.seedUserID,
        email: "instant@example.com",
        imageURL: nil,
        type: nil,
        linkedPrimaryUserID: nil,
        transactionID: transactionID,
        updatedAt: welcomeTimestamp
      )
      + upsertProfileOperations(
        id: ids.seedUserID,
        userID: ids.seedUserID,
        displayName: "Instant",
        transactionID: transactionID,
        updatedAt: welcomeTimestamp
      )
      + upsertMessageOperations(
        id: ids.welcomeMessageID,
        channelID: ids.generalChannelID,
        authorProfileID: ids.seedUserID,
        content: "Welcome to Instant mobile chat.",
        timestamp: welcomeTimestamp,
        transactionID: transactionID
      )
      + upsertMessageOperations(
        id: ids.randomMessageID,
        channelID: ids.randomChannelID,
        authorProfileID: ids.seedUserID,
        content: "Use this room for anything else.",
        timestamp: randomMessageTimestamp,
        transactionID: transactionID
      )
  }

  public static func createProfileOperations(
    userID: String,
    displayName: String,
    email: String? = nil,
    transactionID: String,
    updatedAt: InstantTimestamp
  ) -> [InstantTripleOperation] {
    upsertUserOperations(
      id: userID,
      email: email,
      imageURL: nil,
      type: nil,
      linkedPrimaryUserID: nil,
      transactionID: transactionID,
      updatedAt: updatedAt
    )
      + upsertProfileOperations(
        id: userID,
        userID: userID,
        displayName: displayName,
        transactionID: transactionID,
        updatedAt: updatedAt
      )
  }

  public static func upsertUserOperations(
    id: String,
    email: String?,
    imageURL: String?,
    type: String?,
    linkedPrimaryUserID: String?,
    transactionID: String,
    updatedAt: InstantTimestamp
  ) -> [InstantTripleOperation] {
    var operations = [
      identityOperation(
        id: id,
        namespace: usersNamespace,
        transactionID: transactionID,
        updatedAt: updatedAt
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
    if let linkedPrimaryUserID {
      operations.append(
        scalarOperation(
          id: id,
          attributeID: "$users/linkedPrimaryUser",
          value: .ref(linkedPrimaryUserID),
          transactionID: transactionID,
          updatedAt: updatedAt
        )
      )
    }
    return operations
  }

  public static func upsertChannelOperations(
    id: String,
    name: String,
    transactionID: String,
    updatedAt: InstantTimestamp
  ) -> [InstantTripleOperation] {
    [
      identityOperation(
        id: id,
        namespace: channelsNamespace,
        transactionID: transactionID,
        updatedAt: updatedAt
      ),
      scalarOperation(
        id: id,
        attributeID: "mobileChannels/name",
        value: .string(name),
        transactionID: transactionID,
        updatedAt: updatedAt
      ),
    ]
  }

  public static func upsertProfileOperations(
    id: String,
    userID: String,
    displayName: String,
    transactionID: String,
    updatedAt: InstantTimestamp
  ) -> [InstantTripleOperation] {
    [
      identityOperation(
        id: id,
        namespace: profilesNamespace,
        transactionID: transactionID,
        updatedAt: updatedAt
      ),
      scalarOperation(
        id: id,
        attributeID: "mobileProfiles/displayName",
        value: .string(displayName),
        transactionID: transactionID,
        updatedAt: updatedAt
      ),
      scalarOperation(
        id: id,
        attributeID: "mobileProfiles/user",
        value: .ref(userID),
        transactionID: transactionID,
        updatedAt: updatedAt
      ),
    ]
  }

  public static func createMessageOperations(
    id: String,
    channelID: String,
    authorProfileID: String?,
    content: String,
    timestamp: InstantTimestamp,
    transactionID: String
  ) -> [InstantTripleOperation] {
    var operations: [InstantTripleOperation] = [
      .requireEntityMissing(entityID: id, namespace: messagesNamespace),
      .requireEntityExists(entityID: channelID, namespace: channelsNamespace),
    ]
    if let authorProfileID {
      operations.append(.requireEntityExists(entityID: authorProfileID, namespace: profilesNamespace))
    }
    operations.append(
      contentsOf: upsertMessageOperations(
        id: id,
        channelID: channelID,
        authorProfileID: authorProfileID,
        content: content,
        timestamp: timestamp,
        transactionID: transactionID
      )
    )
    return operations
  }

  public static func upsertMessageOperations(
    id: String,
    channelID: String,
    authorProfileID: String?,
    content: String,
    timestamp: InstantTimestamp,
    transactionID: String
  ) -> [InstantTripleOperation] {
    var operations: [InstantTripleOperation] = [
      identityOperation(
        id: id,
        namespace: messagesNamespace,
        transactionID: transactionID,
        updatedAt: timestamp
      ),
      scalarOperation(
        id: id,
        attributeID: "mobileMessages/content",
        value: .string(content),
        transactionID: transactionID,
        updatedAt: timestamp
      ),
      scalarOperation(
        id: id,
        attributeID: "mobileMessages/timestamp",
        value: .number(Double(timestamp.milliseconds)),
        transactionID: transactionID,
        updatedAt: timestamp
      ),
      scalarOperation(
        id: id,
        attributeID: "mobileMessages/channel",
        value: .ref(channelID),
        transactionID: transactionID,
        updatedAt: timestamp
      ),
    ]

    if let authorProfileID {
      operations.append(
        scalarOperation(
          id: id,
          attributeID: "mobileMessages/author",
          value: .ref(authorProfileID),
          transactionID: transactionID,
          updatedAt: timestamp
        )
      )
    }

    return operations
  }

  public static func deleteChannelOperations(id: String) -> [InstantTripleOperation] {
    [
      .requireEntityExists(entityID: id, namespace: channelsNamespace),
      .deleteEntityInNamespace(entityID: id, namespace: channelsNamespace),
    ]
  }

  public static func deleteProfileOperations(id: String) -> [InstantTripleOperation] {
    [
      .requireEntityExists(entityID: id, namespace: profilesNamespace),
      .deleteEntityInNamespace(entityID: id, namespace: profilesNamespace),
    ]
  }

  public static func deleteUserOperations(id: String) -> [InstantTripleOperation] {
    [
      .requireEntityExists(entityID: id, namespace: usersNamespace),
      .deleteEntityInNamespace(entityID: id, namespace: usersNamespace),
    ]
  }

  public static func deleteMessageOperations(id: String) -> [InstantTripleOperation] {
    [
      .requireEntityExists(entityID: id, namespace: messagesNamespace),
      .deleteEntityInNamespace(entityID: id, namespace: messagesNamespace),
    ]
  }

  public static func decodeUsers(_ snapshots: [InstantEntitySnapshot]) throws
    -> [MobileChatUserRecord]
  {
    try snapshots.map { snapshot in
      MobileChatUserRecord(
        id: snapshot.id,
        email: try optionalString("email", from: snapshot, namespace: usersNamespace),
        imageURL: try optionalString("imageURL", from: snapshot, namespace: usersNamespace),
        type: try optionalString("type", from: snapshot, namespace: usersNamespace),
        linkedPrimaryUserID: try optionalRef(
          "linkedPrimaryUser",
          from: snapshot,
          namespace: usersNamespace
        )
      )
    }
  }

  public static func decodeProfiles(_ snapshots: [InstantEntitySnapshot]) throws
    -> [MobileChatProfileRecord]
  {
    try snapshots.map(decodeProfile)
  }

  public static func decodeChannels(_ snapshots: [InstantEntitySnapshot]) throws
    -> [MobileChatChannelRecord]
  {
    try snapshots.map { snapshot in
      MobileChatChannelRecord(
        id: snapshot.id,
        name: try stringField("name", from: snapshot, namespace: channelsNamespace)
      )
    }
  }

  public static func decodeMessages(_ snapshots: [InstantEntitySnapshot]) throws
    -> [MobileChatMessageRecord]
  {
    try snapshots.map(decodeMessage)
  }

  private static func messageAuthorInclude(id: String) -> InstantQueryInclude {
    InstantQueryInclude(
      "author",
      query: InstantQueryIncludePlan(
        id: id,
        namespace: profilesNamespace,
        selectedFields: ["displayName", "user"],
        includes: [
          InstantQueryInclude(
            "user",
            query: InstantQueryIncludePlan(
              id: "\(id).users",
              namespace: usersNamespace,
              selectedFields: ["email", "imageURL", "type", "linkedPrimaryUser"]
            )
          )
        ]
      )
    )
  }

  private static func decodeMessage(
    _ snapshot: InstantEntitySnapshot
  ) throws -> MobileChatMessageRecord {
    let author = try snapshot.links?["author"]?.first.map(decodeProfile)
    let authorUser = try snapshot.links?["author"]?.first?.links?["user"]?.first
      .map(decodeUser)
    let authorProfileID = try optionalRef("author", from: snapshot, namespace: messagesNamespace)

    return MobileChatMessageRecord(
      id: snapshot.id,
      channelID: try refField("channel", from: snapshot, namespace: messagesNamespace),
      authorProfileID: authorProfileID,
      content: try stringField("content", from: snapshot, namespace: messagesNamespace),
      timestamp: InstantTimestamp(
        milliseconds: try integerNumberField("timestamp", from: snapshot, namespace: messagesNamespace)
      ),
      author: author,
      authorUser: authorUser
    )
  }

  private static func decodeProfile(
    _ snapshot: InstantEntitySnapshot
  ) throws -> MobileChatProfileRecord {
    try decodeProfile(InstantLinkedEntitySnapshot(snapshot))
  }

  private static func decodeProfile(
    _ snapshot: InstantLinkedEntitySnapshot
  ) throws -> MobileChatProfileRecord {
    MobileChatProfileRecord(
      id: snapshot.id,
      userID: try refField("user", from: snapshot, namespace: profilesNamespace),
      displayName: try stringField("displayName", from: snapshot, namespace: profilesNamespace)
    )
  }

  private static func decodeUser(
    _ snapshot: InstantLinkedEntitySnapshot
  ) throws -> MobileChatUserRecord {
    MobileChatUserRecord(
      id: snapshot.id,
      email: try optionalString("email", from: snapshot, namespace: usersNamespace),
      imageURL: try optionalString("imageURL", from: snapshot, namespace: usersNamespace),
      type: try optionalString("type", from: snapshot, namespace: usersNamespace),
      linkedPrimaryUserID: try optionalRef(
        "linkedPrimaryUser",
        from: snapshot,
        namespace: usersNamespace
      )
    )
  }

  private static func identityOperation(
    id: String,
    namespace: String,
    transactionID: String,
    updatedAt: InstantTimestamp
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
    try optionalString(field, from: InstantLinkedEntitySnapshot(snapshot), namespace: namespace)
  }

  private static func optionalString(
    _ field: String,
    from snapshot: InstantLinkedEntitySnapshot,
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

  private static func optionalRef(
    _ field: String,
    from snapshot: InstantEntitySnapshot,
    namespace: String
  ) throws -> String? {
    try optionalRef(field, from: InstantLinkedEntitySnapshot(snapshot), namespace: namespace)
  }

  private static func optionalRef(
    _ field: String,
    from snapshot: InstantLinkedEntitySnapshot,
    namespace: String
  ) throws -> String? {
    guard let value = snapshot.values[field]?.first else { return nil }
    guard case let .ref(ref) = value else {
      throw decodeError(namespace: namespace, id: snapshot.id, field: field, expected: "ref")
    }
    return ref
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
      operation: "decode mobile chat example",
      namespace: namespace,
      path: field,
      localID: id,
      message: "Expected \(expected) for mobile chat field '\(field)'.",
      recovery: "Inspect the local mobile chat example triples and attributes."
    )
  }
}

extension MobileChatExample {
  public struct SeedIDs: Hashable, Codable, Sendable {
    public var generalChannelID: String
    public var randomChannelID: String
    public var seedUserID: String
    public var welcomeMessageID: String
    public var randomMessageID: String

    public init(
      generalChannelID: String,
      randomChannelID: String,
      seedUserID: String,
      welcomeMessageID: String,
      randomMessageID: String
    ) {
      self.generalChannelID = generalChannelID
      self.randomChannelID = randomChannelID
      self.seedUserID = seedUserID
      self.welcomeMessageID = welcomeMessageID
      self.randomMessageID = randomMessageID
    }
  }
}
