import Foundation

public struct ChatChannelRecord: Hashable, Codable, Sendable, Identifiable {
  public var id: String
  public var title: String
  public var createdAt: InstantTimestamp

  public init(id: String, title: String, createdAt: InstantTimestamp) {
    self.id = id
    self.title = title
    self.createdAt = createdAt
  }
}

public struct ChatMessageRecord: Hashable, Codable, Sendable, Identifiable {
  public var id: String
  public var channelID: String
  public var text: String
  public var authorName: String
  public var authorUserID: String?
  public var createdAt: InstantTimestamp

  public init(
    id: String,
    channelID: String,
    text: String,
    authorName: String,
    authorUserID: String? = nil,
    createdAt: InstantTimestamp
  ) {
    self.id = id
    self.channelID = channelID
    self.text = text
    self.authorName = authorName
    self.authorUserID = authorUserID
    self.createdAt = createdAt
  }
}

public enum ChatExample {
  public static let channelsNamespace = "chatChannels"
  public static let messagesNamespace = "chatMessages"

  public static let generalChannelIDName = "examples.chat.channels.general"
  public static let randomChannelIDName = "examples.chat.channels.random"
  public static let welcomeMessageIDName = "examples.chat.messages.general.welcome"
  public static let randomMessageIDName = "examples.chat.messages.random.seed"

  public static let attributes: [InstantAttribute] = [
    .primaryKey(namespace: channelsNamespace),
    InstantAttribute(
      id: "chatChannels/title",
      namespace: channelsNamespace,
      name: "title",
      valueType: .string,
      isIndexed: true
    ),
    InstantAttribute(
      id: "chatChannels/createdAt",
      namespace: channelsNamespace,
      name: "createdAt",
      valueType: .date,
      isIndexed: true
    ),
    .primaryKey(namespace: messagesNamespace),
    InstantAttribute(
      id: "chatMessages/channel",
      namespace: messagesNamespace,
      name: "channel",
      valueType: .ref,
      isRequired: true,
      isIndexed: true,
      forwardIdentity: "chatMessages/channel",
      reverseIdentity: "chatChannels/messages",
      linkNamespace: channelsNamespace
    ),
    InstantAttribute(
      id: "chatMessages/text",
      namespace: messagesNamespace,
      name: "text",
      valueType: .string
    ),
    InstantAttribute(
      id: "chatMessages/authorName",
      namespace: messagesNamespace,
      name: "authorName",
      valueType: .string,
      isIndexed: true
    ),
    InstantAttribute(
      id: "chatMessages/authorUserID",
      namespace: messagesNamespace,
      name: "authorUserID",
      valueType: .string,
      isRequired: false,
      isIndexed: true
    ),
    InstantAttribute(
      id: "chatMessages/createdAt",
      namespace: messagesNamespace,
      name: "createdAt",
      valueType: .date,
      isIndexed: true
    ),
  ]

  public static let channelsQuery = InstantQueryPlan(
    id: "examples.chat.channels",
    namespace: channelsNamespace,
    order: InstantQueryOrder("createdAt", .ascending)
  )

  public static let messagesQuery = InstantQueryPlan(
    id: "examples.chat.messages",
    namespace: messagesNamespace,
    order: InstantQueryOrder("createdAt", .ascending)
  )

  public static func messagesForChannelQuery(_ channelID: String) -> InstantQueryPlan {
    InstantQueryPlan(
      id: "examples.chat.messages.\(channelID)",
      namespace: messagesNamespace,
      filters: [.equals(field: "channel", value: .ref(channelID))],
      order: InstantQueryOrder("createdAt", .ascending)
    )
  }

  public static func seedOperations(
    generalChannelID: String,
    randomChannelID: String,
    welcomeMessageID: String,
    randomMessageID: String,
    createdAt: InstantTimestamp,
    transactionID: String
  ) -> [InstantTripleOperation] {
    upsertChannelOperations(
      id: generalChannelID,
      title: "general",
      createdAt: createdAt,
      transactionID: transactionID
    )
      + upsertChannelOperations(
        id: randomChannelID,
        title: "random",
        createdAt: InstantTimestamp(milliseconds: createdAt.milliseconds + 1),
        transactionID: transactionID
      )
      + upsertMessageOperations(
        id: welcomeMessageID,
        channelID: generalChannelID,
        text: "Welcome to Instant chat.",
        authorName: "Instant",
        authorUserID: nil,
        createdAt: InstantTimestamp(milliseconds: createdAt.milliseconds + 2),
        transactionID: transactionID
      )
      + upsertMessageOperations(
        id: randomMessageID,
        channelID: randomChannelID,
        text: "Use this channel for anything else.",
        authorName: "Instant",
        authorUserID: nil,
        createdAt: InstantTimestamp(milliseconds: createdAt.milliseconds + 3),
        transactionID: transactionID
      )
  }

  public static func createChannelOperations(
    id: String,
    title: String,
    createdAt: InstantTimestamp,
    transactionID: String
  ) -> [InstantTripleOperation] {
    [
      .requireEntityMissing(entityID: id, namespace: channelsNamespace)
    ]
      + upsertChannelOperations(
        id: id,
        title: title,
        createdAt: createdAt,
        transactionID: transactionID
      )
  }

  public static func upsertChannelOperations(
    id: String,
    title: String,
    createdAt: InstantTimestamp,
    transactionID: String
  ) -> [InstantTripleOperation] {
    [
      identityOperation(
        id: id,
        namespace: channelsNamespace,
        updatedAt: createdAt,
        transactionID: transactionID
      ),
      .insert(
        InstantTriple(
          entityID: id,
          attributeID: "chatChannels/title",
          value: .string(title),
          txID: transactionID,
          txTime: createdAt
        )
      ),
      .insert(
        InstantTriple(
          entityID: id,
          attributeID: "chatChannels/createdAt",
          value: dateValue(createdAt),
          txID: transactionID,
          txTime: createdAt
        )
      ),
    ]
  }

  public static func createMessageOperations(
    id: String,
    channelID: String,
    text: String,
    authorName: String,
    authorUserID: String?,
    createdAt: InstantTimestamp,
    transactionID: String
  ) -> [InstantTripleOperation] {
    [
      .requireEntityMissing(entityID: id, namespace: messagesNamespace),
      .requireEntityExists(entityID: channelID, namespace: channelsNamespace),
    ]
      + upsertMessageOperations(
        id: id,
        channelID: channelID,
        text: text,
        authorName: authorName,
        authorUserID: authorUserID,
        createdAt: createdAt,
        transactionID: transactionID
      )
  }

  public static func upsertMessageOperations(
    id: String,
    channelID: String,
    text: String,
    authorName: String,
    authorUserID: String?,
    createdAt: InstantTimestamp,
    transactionID: String
  ) -> [InstantTripleOperation] {
    var operations: [InstantTripleOperation] = [
      identityOperation(
        id: id,
        namespace: messagesNamespace,
        updatedAt: createdAt,
        transactionID: transactionID
      ),
      .insert(
        InstantTriple(
          entityID: id,
          attributeID: "chatMessages/channel",
          value: .ref(channelID),
          txID: transactionID,
          txTime: createdAt
        )
      ),
      .insert(
        InstantTriple(
          entityID: id,
          attributeID: "chatMessages/text",
          value: .string(text),
          txID: transactionID,
          txTime: createdAt
        )
      ),
      .insert(
        InstantTriple(
          entityID: id,
          attributeID: "chatMessages/authorName",
          value: .string(authorName),
          txID: transactionID,
          txTime: createdAt
        )
      ),
      .insert(
        InstantTriple(
          entityID: id,
          attributeID: "chatMessages/createdAt",
          value: dateValue(createdAt),
          txID: transactionID,
          txTime: createdAt
        )
      ),
    ]

    if let authorUserID {
      operations.append(
        .insert(
          InstantTriple(
            entityID: id,
            attributeID: "chatMessages/authorUserID",
            value: .string(authorUserID),
            txID: transactionID,
            txTime: createdAt
          )
        )
      )
    }

    return operations
  }

  public static func deleteMessageOperations(id: String) -> [InstantTripleOperation] {
    [
      .requireEntityExists(entityID: id, namespace: messagesNamespace),
      .deleteEntityInNamespace(entityID: id, namespace: messagesNamespace),
    ]
  }

  public static func deleteChannelOperations(id: String) -> [InstantTripleOperation] {
    [
      .requireEntityExists(entityID: id, namespace: channelsNamespace),
      .deleteEntityInNamespace(entityID: id, namespace: channelsNamespace),
    ]
  }

  public static func decodeChannels(
    _ snapshots: [InstantEntitySnapshot]
  ) throws -> [ChatChannelRecord] {
    try snapshots.map { snapshot in
      guard case let .string(title) = snapshot.values["title"]?.first else {
        throw decodeError(
          namespace: channelsNamespace,
          id: snapshot.id,
          field: "title",
          expected: "string"
        )
      }
      guard case let .date(createdAt) = snapshot.values["createdAt"]?.first else {
        throw decodeError(
          namespace: channelsNamespace,
          id: snapshot.id,
          field: "createdAt",
          expected: "date"
        )
      }
      return ChatChannelRecord(
        id: snapshot.id,
        title: title,
        createdAt: timestamp(from: createdAt)
      )
    }
  }

  public static func decodeMessages(
    _ snapshots: [InstantEntitySnapshot]
  ) throws -> [ChatMessageRecord] {
    try snapshots.map { snapshot in
      guard case let .ref(channelID) = snapshot.values["channel"]?.first else {
        throw decodeError(
          namespace: messagesNamespace,
          id: snapshot.id,
          field: "channel",
          expected: "ref"
        )
      }
      guard case let .string(text) = snapshot.values["text"]?.first else {
        throw decodeError(
          namespace: messagesNamespace,
          id: snapshot.id,
          field: "text",
          expected: "string"
        )
      }
      guard case let .string(authorName) = snapshot.values["authorName"]?.first else {
        throw decodeError(
          namespace: messagesNamespace,
          id: snapshot.id,
          field: "authorName",
          expected: "string"
        )
      }
      guard case let .date(createdAt) = snapshot.values["createdAt"]?.first else {
        throw decodeError(
          namespace: messagesNamespace,
          id: snapshot.id,
          field: "createdAt",
          expected: "date"
        )
      }

      let authorUserID: String?
      if let value = snapshot.values["authorUserID"]?.first {
        guard case let .string(rawAuthorUserID) = value else {
          throw decodeError(
            namespace: messagesNamespace,
            id: snapshot.id,
            field: "authorUserID",
            expected: "string"
          )
        }
        authorUserID = rawAuthorUserID
      } else {
        authorUserID = nil
      }

      return ChatMessageRecord(
        id: snapshot.id,
        channelID: channelID,
        text: text,
        authorName: authorName,
        authorUserID: authorUserID,
        createdAt: timestamp(from: createdAt)
      )
    }
  }

  private static func identityOperation(
    id: String,
    namespace: String,
    updatedAt: InstantTimestamp,
    transactionID: String
  ) -> InstantTripleOperation {
    .insert(
      InstantTriple(
        entityID: id,
        attributeID: InstantAttribute.primaryKeyID(namespace: namespace),
        value: .string(id),
        txID: transactionID,
        txTime: updatedAt
      )
    )
  }

  private static func dateValue(_ timestamp: InstantTimestamp) -> InstantValue {
    .date(Date(timeIntervalSince1970: Double(timestamp.milliseconds) / 1000))
  }

  private static func timestamp(from date: Date) -> InstantTimestamp {
    InstantTimestamp(
      milliseconds: Int64((date.timeIntervalSince1970 * 1000).rounded())
    )
  }

  private static func decodeError(
    namespace: String,
    id: String,
    field: String,
    expected: String
  ) -> InstantError {
    InstantError(
      code: .decodeFailed,
      operation: "decode chat example",
      namespace: namespace,
      path: field,
      localID: id,
      message: "Expected \(expected) for chat field '\(field)'.",
      recovery: "Inspect the local chat example triples and attributes."
    )
  }
}
