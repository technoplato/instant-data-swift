import Foundation
import InstantSwiftDataCore

public struct InstantEntitySchema: Hashable, Codable, Sendable, Identifiable {
  public var id: String { namespace }
  public var typeName: String
  public var namespace: String
  public var attributes: [InstantAttribute]

  public init(
    typeName: String,
    namespace: String? = nil,
    attributes: [InstantAttribute]
  ) {
    self.typeName = typeName
    self.namespace = namespace ?? InstantNamespace.defaultName(for: typeName)
    self.attributes = attributes
  }
}

public struct InstantSchemaDocument: Hashable, Codable, Sendable {
  public var entities: [InstantEntitySchema]
  public var links: [InstantLinkSchema]
  public var rooms: [InstantRoomSchema]

  public init(
    entities: [InstantEntitySchema],
    links: [InstantLinkSchema] = [],
    rooms: [InstantRoomSchema] = []
  ) {
    self.entities = entities
    self.links = links
    self.rooms = rooms
  }

  public var attributes: [InstantAttribute] {
    entities.flatMap(\.attributes) + links.flatMap(\.attributes)
  }
}

public struct InstantRoomSchema: Hashable, Codable, Sendable, Identifiable {
  public var id: String { name }
  public var name: String
  public var presence: InstantRoomPayloadSchema
  public var topics: [InstantRoomTopicSchema]

  public init(
    name: String,
    presence: InstantRoomPayloadSchema,
    topics: [InstantRoomTopicSchema] = []
  ) {
    self.name = name
    self.presence = presence
    self.topics = topics
  }
}

public struct InstantRoomTopicSchema: Hashable, Codable, Sendable, Identifiable {
  public var id: String { name }
  public var name: String
  public var payload: InstantRoomPayloadSchema

  public init(
    name: String,
    payload: InstantRoomPayloadSchema
  ) {
    self.name = name
    self.payload = payload
  }
}

public struct InstantRoomPayloadSchema: Hashable, Codable, Sendable {
  public var attributes: [InstantAttribute]

  public init(attributes: [InstantAttribute] = []) {
    self.attributes = attributes
  }
}

public struct InstantLinkSchema: Hashable, Codable, Sendable, Identifiable {
  public var id: String { name }
  public var name: String
  public var forward: InstantLinkEndpoint
  public var reverse: InstantLinkEndpoint
  public var isRequired: Bool?

  public init(
    name: String,
    forward: InstantLinkEndpoint,
    reverse: InstantLinkEndpoint,
    isRequired: Bool? = nil
  ) {
    self.name = name
    self.forward = forward
    self.reverse = reverse
    self.isRequired = isRequired
  }

  public var attributes: [InstantAttribute] {
    [
      InstantAttribute(
        id: "\(forward.namespace)/\(forward.label)",
        namespace: forward.namespace,
        name: forward.label,
        valueType: .ref,
        isRequired: isRequired == true,
        cardinality: forward.cardinality,
        isIndexed: true,
        isUnique: reverse.cardinality == .one,
        forwardIdentity: "\(forward.namespace)/\(forward.label)",
        reverseIdentity: "\(reverse.namespace)/\(reverse.label)",
        linkNamespace: reverse.namespace,
        onDelete: forward.onDelete,
        onDeleteReverse: reverse.onDelete
      )
    ]
  }
}

public struct InstantLinkEndpoint: Hashable, Codable, Sendable {
  public var namespace: String
  public var cardinality: InstantCardinality
  public var label: String
  public var onDelete: InstantDeleteRule

  public init(
    namespace: String,
    cardinality: InstantCardinality,
    label: String,
    onDelete: InstantDeleteRule = .none
  ) {
    self.namespace = namespace
    self.cardinality = cardinality
    self.label = label
    self.onDelete = onDelete
  }
}

public enum InstantSchemaValidationError: Error, Equatable, Sendable, CustomStringConvertible {
  case invalidLinkCascadeEndpoint(
    link: String,
    endpoint: String,
    cardinality: InstantCardinality
  )
  case unsupportedRefAttribute(namespace: String, name: String)

  public var description: String {
    switch self {
    case .invalidLinkCascadeEndpoint(let link, let endpoint, let cardinality):
      "Link '\(link)' \(endpoint) endpoint has invalid cascade delete for cardinality '\(cardinality.rawValue)'. Cascade delete is only supported on has: \"one\" links."
    case .unsupportedRefAttribute(let namespace, let name):
      "Attribute '\(namespace)/\(name)' is a ref attribute. Encode relationships with the schema links section instead."
    }
  }
}

public struct InstantPermissionsDocument: Hashable, Codable, Sendable {
  public var attrs: InstantAttributePermissions?
  public var defaults: InstantDefaultPermissions?
  public var rateLimits: [InstantRateLimit]
  public var namespaces: [InstantNamespacePermissions]

  public init(
    attrs: InstantAttributePermissions? = nil,
    defaults: InstantDefaultPermissions? = nil,
    rateLimits: [InstantRateLimit] = [],
    namespaces: [InstantNamespacePermissions]
  ) {
    self.attrs = attrs
    self.defaults = defaults
    self.rateLimits = rateLimits
    self.namespaces = namespaces
  }
}

public struct InstantNamespacePermissions: Hashable, Codable, Sendable, Identifiable {
  public var id: String { namespace }
  public var namespace: String
  public var allow: [InstantPermissionAction: String]
  public var link: [String: String]
  public var unlink: [String: String]
  public var bind: [InstantPermissionBinding]
  public var fields: [String: String]

  public init(
    namespace: String,
    allow: [InstantPermissionAction: String] = [:],
    link: [String: String] = [:],
    unlink: [String: String] = [:],
    bind: [InstantPermissionBinding] = [],
    fields: [String: String] = [:]
  ) {
    self.namespace = namespace
    self.allow = allow
    self.link = link
    self.unlink = unlink
    self.bind = bind
    self.fields = fields
  }

  public static func allowAll(namespace: String) -> Self {
    Self(
      namespace: namespace,
      allow: Dictionary(
        uniqueKeysWithValues: InstantPermissionAction.entityActions.map { ($0, "true") }
      )
    )
  }
}

public enum InstantPermissionAction: String, CaseIterable, Codable, Sendable {
  case `default` = "$default"
  case view
  case create
  case update
  case delete

  public static let entityActions: [Self] = [.view, .create, .update, .delete]
}

public struct InstantPermissionBinding: Hashable, Codable, Sendable {
  public var name: String
  public var expression: String

  public init(_ name: String, _ expression: String) {
    self.name = name
    self.expression = expression
  }
}

public struct InstantDefaultPermissions: Hashable, Codable, Sendable {
  public var allow: [InstantPermissionAction: String]
  public var link: [String: String]
  public var unlink: [String: String]
  public var bind: [InstantPermissionBinding]

  public init(
    allow: [InstantPermissionAction: String] = [:],
    link: [String: String] = [:],
    unlink: [String: String] = [:],
    bind: [InstantPermissionBinding] = []
  ) {
    self.allow = allow
    self.link = link
    self.unlink = unlink
    self.bind = bind
  }
}

public struct InstantAttributePermissions: Hashable, Codable, Sendable {
  public var allow: [InstantPermissionAction: String]
  public var bind: [InstantPermissionBinding]

  public init(
    allow: [InstantPermissionAction: String] = [:],
    bind: [InstantPermissionBinding] = []
  ) {
    self.allow = allow
    self.bind = bind
  }
}

public struct InstantRateLimit: Hashable, Codable, Sendable, Identifiable {
  public var id: String { name }
  public var name: String
  public var limits: [InstantRateLimitLimit]

  public init(name: String, limits: [InstantRateLimitLimit]) {
    self.name = name
    self.limits = limits
  }
}

public struct InstantRateLimitLimit: Hashable, Codable, Sendable {
  public var capacity: Int
  public var refill: InstantRateLimitRefill?

  public init(capacity: Int, refill: InstantRateLimitRefill? = nil) {
    self.capacity = capacity
    self.refill = refill
  }
}

public struct InstantRateLimitRefill: Hashable, Codable, Sendable {
  public var amount: Int?
  public var period: String?
  public var type: InstantRateLimitRefillType?

  public init(
    amount: Int? = nil,
    period: String? = nil,
    type: InstantRateLimitRefillType? = nil
  ) {
    self.amount = amount
    self.period = period
    self.type = type
  }
}

public enum InstantRateLimitRefillType: String, Codable, Sendable {
  case interval
  case greedy
}

public enum InstantPermissionsValidationError: Error, Equatable, Sendable, CustomStringConvertible {
  case reservedFieldRule(namespace: String, field: String)
  case emptyRateLimit(name: String)
  case invalidRateLimitCapacity(name: String, capacity: Int)
  case invalidRateLimitRefillAmount(name: String, amount: Int)
  case invalidRateLimitRefillPeriod(name: String, period: String)

  public var description: String {
    switch self {
    case .reservedFieldRule(let namespace, let field):
      "Field rule '\(namespace).\(field)' is invalid; Instant permissions do not allow rules for id."
    case .emptyRateLimit(let name):
      "Rate limit '\(name)' must contain at least one limit."
    case .invalidRateLimitCapacity(let name, let capacity):
      "Rate limit '\(name)' has invalid capacity \(capacity); capacity must be positive."
    case .invalidRateLimitRefillAmount(let name, let amount):
      "Rate limit '\(name)' has invalid refill amount \(amount); amount must be positive."
    case .invalidRateLimitRefillPeriod(let name, let period):
      "Rate limit '\(name)' has invalid refill period '\(period)'; period must be between 1 second and 24 hours."
    }
  }
}

public enum InstantNamespace {
  public static func defaultName(for typeName: String) -> String {
    let leadingLowercased = typeName.prefix(1).lowercased() + String(typeName.dropFirst())

    if leadingLowercased.hasSuffix("y"),
      let previous = leadingLowercased.dropLast().last,
      !"aeiou".contains(previous)
    {
      return String(leadingLowercased.dropLast()) + "ies"
    }

    if leadingLowercased.hasSuffix("s")
      || leadingLowercased.hasSuffix("x")
      || leadingLowercased.hasSuffix("z")
      || leadingLowercased.hasSuffix("ch")
      || leadingLowercased.hasSuffix("sh")
    {
      return leadingLowercased + "es"
    }

    return leadingLowercased + "s"
  }

  public static func isRedundantOverride(_ override: String, for typeName: String) -> Bool {
    override == defaultName(for: typeName)
  }
}

public enum InstantSchemaExamples {
  public static let todos = InstantEntitySchema(
    typeName: "Todo",
    attributes: TodoExample.attributes
  )

  public static let todosRoom = InstantRoomSchema(
    name: "todos",
    presence: InstantRoomPayloadSchema()
  )

  public static let todosDocument = InstantSchemaDocument(
    entities: [todos],
    rooms: [todosRoom]
  )

  public static let typingIndicatorRoom = InstantRoomSchema(
    name: "typing-indicator-example",
    presence: InstantRoomPayloadSchema(
      attributes: [
        InstantAttribute(
          id: "rooms/typing-indicator-example/presence/id",
          namespace: "rooms/typing-indicator-example/presence",
          name: "id",
          valueType: .string
        ),
        InstantAttribute(
          id: "rooms/typing-indicator-example/presence/chat-input",
          namespace: "rooms/typing-indicator-example/presence",
          name: "chat-input",
          valueType: .boolean,
          isRequired: false
        ),
      ]
    )
  )

  public static let typingIndicatorDocument = InstantSchemaDocument(
    entities: [],
    rooms: [typingIndicatorRoom]
  )

  public static let typingIndicatorPermissions = InstantPermissionsDocument(
    namespaces: []
  )

  public static let avatarStackRoom = InstantRoomSchema(
    name: "avatars-example",
    presence: InstantRoomPayloadSchema(
      attributes: [
        InstantAttribute(
          id: "rooms/avatars-example/presence/name",
          namespace: "rooms/avatars-example/presence",
          name: "name",
          valueType: .string
        )
      ]
    )
  )

  public static let avatarStackDocument = InstantSchemaDocument(
    entities: [],
    rooms: [avatarStackRoom]
  )

  public static let avatarStackPermissions = InstantPermissionsDocument(
    namespaces: []
  )

  public static let cursorsRoom = InstantRoomSchema(
    name: "cursors-example",
    presence: InstantRoomPayloadSchema(
      attributes: [
        InstantAttribute(
          id: "rooms/cursors-example/presence/cursors-space-default--cursors-example-123",
          namespace: "rooms/cursors-example/presence",
          name: "cursors-space-default--cursors-example-123",
          valueType: .json,
          isRequired: false
        )
      ]
    )
  )

  public static let cursorsDocument = InstantSchemaDocument(
    entities: [],
    rooms: [cursorsRoom]
  )

  public static let cursorsPermissions = InstantPermissionsDocument(
    namespaces: []
  )

  public static let customCursorsRoom = InstantRoomSchema(
    name: "cursors-example",
    presence: InstantRoomPayloadSchema(
      attributes: [
        InstantAttribute(
          id: "rooms/cursors-example/presence/name",
          namespace: "rooms/cursors-example/presence",
          name: "name",
          valueType: .string
        ),
        InstantAttribute(
          id: "rooms/cursors-example/presence/cursors-space-default--cursors-example-124",
          namespace: "rooms/cursors-example/presence",
          name: "cursors-space-default--cursors-example-124",
          valueType: .json,
          isRequired: false
        ),
      ]
    )
  )

  public static let customCursorsDocument = InstantSchemaDocument(
    entities: [],
    rooms: [customCursorsRoom]
  )

  public static let customCursorsPermissions = InstantPermissionsDocument(
    namespaces: []
  )

  public static let mergeTileGameBoard = InstantEntitySchema(
    typeName: "MergeTileGameV3Board",
    namespace: "boards",
    attributes: [
      .primaryKey(namespace: "boards"),
      InstantAttribute(
        id: "boards/state",
        namespace: "boards",
        name: "state",
        valueType: .json
      ),
    ]
  )

  public static let mergeTileGameRoom = InstantRoomSchema(
    name: "tile-game-example",
    presence: InstantRoomPayloadSchema(
      attributes: [
        InstantAttribute(
          id: "rooms/tile-game-example/presence/color",
          namespace: "rooms/tile-game-example/presence",
          name: "color",
          valueType: .string
        )
      ]
    )
  )

  public static let mergeTileGameDocument = InstantSchemaDocument(
    entities: [mergeTileGameBoard],
    rooms: [mergeTileGameRoom]
  )

  public static let mergeTileGamePermissions = InstantPermissionsDocument(
    namespaces: [.allowAll(namespace: "boards")]
  )

  public static let reactionsRoom = InstantRoomSchema(
    name: "topics-example",
    presence: InstantRoomPayloadSchema(),
    topics: [
      InstantRoomTopicSchema(
        name: "emoji",
        payload: InstantRoomPayloadSchema(
          attributes: [
            InstantAttribute(
              id: "rooms/topics-example/topics/emoji/name",
              namespace: "rooms/topics-example/topics/emoji",
              name: "name",
              valueType: .string
            ),
            InstantAttribute(
              id: "rooms/topics-example/topics/emoji/directionAngle",
              namespace: "rooms/topics-example/topics/emoji",
              name: "directionAngle",
              valueType: .number
            ),
            InstantAttribute(
              id: "rooms/topics-example/topics/emoji/rotationAngle",
              namespace: "rooms/topics-example/topics/emoji",
              name: "rotationAngle",
              valueType: .number
            ),
          ]
        )
      )
    ]
  )

  public static let reactionsDocument = InstantSchemaDocument(
    entities: [],
    rooms: [reactionsRoom]
  )

  public static let reactionsPermissions = InstantPermissionsDocument(
    namespaces: []
  )

  public static let todoPermissions = InstantPermissionsDocument(
    namespaces: [
      .allowAll(namespace: TodoExample.namespace)
    ]
  )

  public static let mobileChatFiles = InstantEntitySchema(
    typeName: "MobileChatFile",
    namespace: "$files",
    attributes: [
      .primaryKey(namespace: "$files"),
      InstantAttribute(
        id: "$files/path",
        namespace: "$files",
        name: "path",
        valueType: .string,
        isIndexed: true,
        isUnique: true
      ),
      InstantAttribute(
        id: "$files/url",
        namespace: "$files",
        name: "url",
        valueType: .string
      ),
    ]
  )

  public static let mobileChatUsers = InstantEntitySchema(
    typeName: "MobileChatUser",
    namespace: "$users",
    attributes: [
      .primaryKey(namespace: "$users"),
      InstantAttribute(
        id: "$users/email",
        namespace: "$users",
        name: "email",
        valueType: .string,
        isRequired: false,
        isIndexed: true,
        isUnique: true
      ),
      InstantAttribute(
        id: "$users/imageURL",
        namespace: "$users",
        name: "imageURL",
        valueType: .string,
        isRequired: false
      ),
      InstantAttribute(
        id: "$users/type",
        namespace: "$users",
        name: "type",
        valueType: .string,
        isRequired: false
      ),
    ]
  )

  public static let mobileChatProfiles = InstantEntitySchema(
    typeName: "MobileChatProfile",
    namespace: "profiles",
    attributes: [
      .primaryKey(namespace: "profiles"),
      InstantAttribute(
        id: "profiles/displayName",
        namespace: "profiles",
        name: "displayName",
        valueType: .string
      ),
    ]
  )

  public static let mobileChatChannels = InstantEntitySchema(
    typeName: "MobileChatChannel",
    namespace: "channels",
    attributes: [
      .primaryKey(namespace: "channels"),
      InstantAttribute(
        id: "channels/name",
        namespace: "channels",
        name: "name",
        valueType: .string,
        isIndexed: true
      ),
    ]
  )

  public static let mobileChatMessages = InstantEntitySchema(
    typeName: "MobileChatMessage",
    namespace: "messages",
    attributes: [
      .primaryKey(namespace: "messages"),
      InstantAttribute(
        id: "messages/content",
        namespace: "messages",
        name: "content",
        valueType: .string
      ),
      InstantAttribute(
        id: "messages/timestamp",
        namespace: "messages",
        name: "timestamp",
        valueType: .number,
        isIndexed: true
      ),
    ]
  )

  public static let mobileChatRoom = InstantRoomSchema(
    name: "chat",
    presence: InstantRoomPayloadSchema(
      attributes: [
        InstantAttribute(
          id: "rooms/chat/presence/profileId",
          namespace: "rooms/chat/presence",
          name: "profileId",
          valueType: .string
        ),
        InstantAttribute(
          id: "rooms/chat/presence/displayName",
          namespace: "rooms/chat/presence",
          name: "displayName",
          valueType: .string
        ),
      ]
    ),
    topics: [
      InstantRoomTopicSchema(
        name: "typing",
        payload: InstantRoomPayloadSchema(
          attributes: [
            InstantAttribute(
              id: "rooms/chat/topics/typing/isTyping",
              namespace: "rooms/chat/topics/typing",
              name: "isTyping",
              valueType: .boolean
            )
          ]
        )
      ),
      InstantRoomTopicSchema(
        name: "emoji",
        payload: InstantRoomPayloadSchema(
          attributes: [
            InstantAttribute(
              id: "rooms/chat/topics/emoji/name",
              namespace: "rooms/chat/topics/emoji",
              name: "name",
              valueType: .string
            ),
            InstantAttribute(
              id: "rooms/chat/topics/emoji/directionAngle",
              namespace: "rooms/chat/topics/emoji",
              name: "directionAngle",
              valueType: .number
            ),
            InstantAttribute(
              id: "rooms/chat/topics/emoji/rotationAngle",
              namespace: "rooms/chat/topics/emoji",
              name: "rotationAngle",
              valueType: .number
            ),
          ]
        )
      ),
    ]
  )

  public static let mobileChatDocument = InstantSchemaDocument(
    entities: [
      mobileChatFiles,
      mobileChatUsers,
      mobileChatProfiles,
      mobileChatChannels,
      mobileChatMessages,
    ],
    links: [
      InstantLinkSchema(
        name: "$usersLinkedPrimaryUser",
        forward: InstantLinkEndpoint(
          namespace: "$users",
          cardinality: .one,
          label: "linkedPrimaryUser",
          onDelete: .cascade
        ),
        reverse: InstantLinkEndpoint(
          namespace: "$users",
          cardinality: .many,
          label: "linkedGuestUsers"
        )
      ),
      InstantLinkSchema(
        name: "userProfile",
        forward: InstantLinkEndpoint(
          namespace: "profiles",
          cardinality: .one,
          label: "user",
          onDelete: .cascade
        ),
        reverse: InstantLinkEndpoint(
          namespace: "$users",
          cardinality: .one,
          label: "profile"
        )
      ),
      InstantLinkSchema(
        name: "authorMessages",
        forward: InstantLinkEndpoint(
          namespace: "messages",
          cardinality: .one,
          label: "author",
          onDelete: .cascade
        ),
        reverse: InstantLinkEndpoint(
          namespace: "profiles",
          cardinality: .many,
          label: "messages"
        )
      ),
      InstantLinkSchema(
        name: "channelMessages",
        forward: InstantLinkEndpoint(
          namespace: "messages",
          cardinality: .one,
          label: "channel",
          onDelete: .cascade
        ),
        reverse: InstantLinkEndpoint(
          namespace: "channels",
          cardinality: .many,
          label: "messages"
        )
      ),
    ],
    rooms: [mobileChatRoom]
  )

  public static let mobileChatPermissions = InstantPermissionsDocument(
    namespaces: [
      InstantNamespacePermissions(
        namespace: "$files",
        allow: Dictionary(
          uniqueKeysWithValues: InstantPermissionAction.entityActions.map {
            ($0, "auth.id != null")
          }
        )
      ),
      InstantNamespacePermissions(
        namespace: "$users",
        allow: [.view: "auth.id != null"]
      ),
      InstantNamespacePermissions(
        namespace: "channels",
        allow: Dictionary(
          uniqueKeysWithValues: InstantPermissionAction.entityActions.map {
            ($0, "auth.id != null")
          }
        )
      ),
      InstantNamespacePermissions(
        namespace: "messages",
        allow: [
          .view: "auth.id != null",
          .create: "isAuthor",
          .update: "isAuthor",
          .delete: "isAuthor",
        ],
        bind: [
          InstantPermissionBinding(
            "isAuthor",
            "auth.id in data.ref('author.user.id')"
          )
        ]
      ),
      InstantNamespacePermissions(
        namespace: "profiles",
        allow: [
          .view: "auth.id != null",
          .create: "isSelf",
          .update: "isSelf",
          .delete: "isSelf",
        ],
        bind: [
          InstantPermissionBinding("isSelf", "auth.id in data.ref('user.id')")
        ]
      ),
    ]
  )

  public static let validationProfiles = InstantEntitySchema(
    typeName: "Profile",
    namespace: "profiles",
    attributes: [
      InstantAttribute(
        id: "profiles/handle",
        namespace: "profiles",
        name: "handle",
        valueType: .string,
        isIndexed: true,
        isUnique: true
      ),
      InstantAttribute(
        id: "profiles/displayName",
        namespace: "profiles",
        name: "displayName",
        valueType: .string
      ),
      InstantAttribute(
        id: "profiles/createdAt",
        namespace: "profiles",
        name: "createdAt",
        valueType: .date,
        isIndexed: true
      ),
    ]
  )

  public static let validationPosts = InstantEntitySchema(
    typeName: "Post",
    namespace: "posts",
    attributes: [
      InstantAttribute(
        id: "posts/content",
        namespace: "posts",
        name: "content",
        valueType: .string
      ),
      InstantAttribute(
        id: "posts/createdAt",
        namespace: "posts",
        name: "createdAt",
        valueType: .date,
        isIndexed: true
      ),
    ]
  )

  public static let recordingActionAttachments = InstantEntitySchema(
    typeName: "V3CaptureAttachment",
    namespace: "v3_capture_attachments",
    attributes: [
      InstantAttribute(
        id: "v3_capture_attachments/kind",
        namespace: "v3_capture_attachments",
        name: "kind",
        valueType: .string,
        isIndexed: true
      ),
      InstantAttribute(
        id: "v3_capture_attachments/contents",
        namespace: "v3_capture_attachments",
        name: "contents",
        valueType: .string
      ),
      InstantAttribute(
        id: "v3_capture_attachments/offsetMilliseconds",
        namespace: "v3_capture_attachments",
        name: "offsetMilliseconds",
        valueType: .number,
        isIndexed: true
      ),
    ]
  )

  public static let recordingActionUsers = InstantEntitySchema(
    typeName: "InstantUser",
    namespace: "$users",
    attributes: [
      InstantAttribute(
        id: "$users/email",
        namespace: "$users",
        name: "email",
        valueType: .string,
        isRequired: false,
        isIndexed: true,
        isUnique: true
      )
    ]
  )

  public static let recordingActionMembers = InstantEntitySchema(
    typeName: "V3CaptureMember",
    namespace: "v3_capture_members",
    attributes: [
      InstantAttribute(
        id: "v3_capture_members/role",
        namespace: "v3_capture_members",
        name: "role",
        valueType: .string,
        isIndexed: true
      )
    ]
  )

  public static let recordingActionRecordings = InstantEntitySchema(
    typeName: "V3CaptureRecording",
    namespace: "v3_capture_recordings",
    attributes: [
      InstantAttribute(
        id: "v3_capture_recordings/title",
        namespace: "v3_capture_recordings",
        name: "title",
        valueType: .string,
        isIndexed: true
      ),
      InstantAttribute(
        id: "v3_capture_recordings/deviceID",
        namespace: "v3_capture_recordings",
        name: "deviceID",
        valueType: .string,
        isIndexed: true
      ),
      InstantAttribute(
        id: "v3_capture_recordings/state",
        namespace: "v3_capture_recordings",
        name: "state",
        valueType: .string,
        isIndexed: true
      ),
      InstantAttribute(
        id: "v3_capture_recordings/durationMilliseconds",
        namespace: "v3_capture_recordings",
        name: "durationMilliseconds",
        valueType: .number,
        isIndexed: true
      ),
    ]
  )

  public static let recordingActionTranscriptions = InstantEntitySchema(
    typeName: "V3CaptureTranscription",
    namespace: "v3_capture_transcriptions",
    attributes: [
      InstantAttribute(
        id: "v3_capture_transcriptions/state",
        namespace: "v3_capture_transcriptions",
        name: "state",
        valueType: .string,
        isIndexed: true
      )
    ]
  )

  public static let recordingActionPlaybackRoom = InstantRoomSchema(
    name: "recording.playback",
    presence: InstantRoomPayloadSchema(
      attributes: [
        InstantAttribute(
          id: "rooms/recording.playback/presence/userID",
          namespace: "rooms/recording.playback/presence",
          name: "userID",
          valueType: .string
        ),
        InstantAttribute(
          id: "rooms/recording.playback/presence/displayName",
          namespace: "rooms/recording.playback/presence",
          name: "displayName",
          valueType: .string
        ),
        InstantAttribute(
          id: "rooms/recording.playback/presence/isPlaying",
          namespace: "rooms/recording.playback/presence",
          name: "isPlaying",
          valueType: .boolean
        ),
        InstantAttribute(
          id: "rooms/recording.playback/presence/offsetSeconds",
          namespace: "rooms/recording.playback/presence",
          name: "offsetSeconds",
          valueType: .number
        ),
        InstantAttribute(
          id: "rooms/recording.playback/presence/focusedSegmentID",
          namespace: "rooms/recording.playback/presence",
          name: "focusedSegmentID",
          valueType: .string,
          isRequired: false
        ),
      ]
    ),
    topics: [
      InstantRoomTopicSchema(
        name: "reaction",
        payload: InstantRoomPayloadSchema(
          attributes: [
            InstantAttribute(
              id: "rooms/recording.playback/topics/reaction/emoji",
              namespace: "rooms/recording.playback/topics/reaction",
              name: "emoji",
              valueType: .string
            ),
            InstantAttribute(
              id: "rooms/recording.playback/topics/reaction/offsetSeconds",
              namespace: "rooms/recording.playback/topics/reaction",
              name: "offsetSeconds",
              valueType: .number
            ),
          ]
        )
      ),
      InstantRoomTopicSchema(
        name: "commentDraft",
        payload: InstantRoomPayloadSchema(
          attributes: [
            InstantAttribute(
              id: "rooms/recording.playback/topics/commentDraft/text",
              namespace: "rooms/recording.playback/topics/commentDraft",
              name: "text",
              valueType: .string
            ),
            InstantAttribute(
              id: "rooms/recording.playback/topics/commentDraft/offsetSeconds",
              namespace: "rooms/recording.playback/topics/commentDraft",
              name: "offsetSeconds",
              valueType: .number
            ),
          ]
        )
      ),
      InstantRoomTopicSchema(
        name: "commentCommitted",
        payload: InstantRoomPayloadSchema(
          attributes: [
            InstantAttribute(
              id: "rooms/recording.playback/topics/commentCommitted/commentID",
              namespace: "rooms/recording.playback/topics/commentCommitted",
              name: "commentID",
              valueType: .string
            )
          ]
        )
      ),
    ]
  )

  public static let recordingActionDocument = InstantSchemaDocument(
    entities: [
      recordingActionUsers,
      recordingActionAttachments,
      recordingActionMembers,
      recordingActionRecordings,
      recordingActionTranscriptions,
    ],
    links: [
      InstantLinkSchema(
        name: "v3_capture_attachmentsRecording",
        forward: InstantLinkEndpoint(
          namespace: "v3_capture_attachments",
          cardinality: .one,
          label: "recording",
          onDelete: .cascade
        ),
        reverse: InstantLinkEndpoint(
          namespace: "v3_capture_recordings",
          cardinality: .many,
          label: "attachments"
        ),
        isRequired: true
      ),
      InstantLinkSchema(
        name: "v3_capture_membersRecording",
        forward: InstantLinkEndpoint(
          namespace: "v3_capture_members",
          cardinality: .one,
          label: "recording",
          onDelete: .cascade
        ),
        reverse: InstantLinkEndpoint(
          namespace: "v3_capture_recordings",
          cardinality: .many,
          label: "members"
        ),
        isRequired: true
      ),
      InstantLinkSchema(
        name: "v3_capture_membersUser",
        forward: InstantLinkEndpoint(
          namespace: "v3_capture_members",
          cardinality: .one,
          label: "user"
        ),
        reverse: InstantLinkEndpoint(
          namespace: "$users",
          cardinality: .many,
          label: "recordingMemberships"
        ),
        isRequired: true
      ),
      InstantLinkSchema(
        name: "v3_capture_recordingsOwner",
        forward: InstantLinkEndpoint(
          namespace: "v3_capture_recordings",
          cardinality: .one,
          label: "owner"
        ),
        reverse: InstantLinkEndpoint(
          namespace: "$users",
          cardinality: .many,
          label: "recordings"
        ),
        isRequired: true
      ),
      InstantLinkSchema(
        name: "v3_capture_transcriptionsRecording",
        forward: InstantLinkEndpoint(
          namespace: "v3_capture_transcriptions",
          cardinality: .one,
          label: "recording",
          onDelete: .cascade
        ),
        reverse: InstantLinkEndpoint(
          namespace: "v3_capture_recordings",
          cardinality: .many,
          label: "transcriptions"
        ),
        isRequired: true
      ),
    ],
    rooms: [recordingActionPlaybackRoom]
  )

  public static let sharingLists = InstantEntitySchema(
    typeName: "V3SharedList",
    namespace: "v3_shared_lists",
    attributes: [
      InstantAttribute(
        id: "v3_shared_lists/title",
        namespace: "v3_shared_lists",
        name: "title",
        valueType: .string,
        isIndexed: true
      ),
      InstantAttribute(
        id: "v3_shared_lists/value",
        namespace: "v3_shared_lists",
        name: "value",
        valueType: .number,
        isIndexed: true
      ),
    ]
  )

  public static let sharingShares = InstantEntitySchema(
    typeName: "InstantShare",
    namespace: "v3_shares",
    attributes: [
      InstantAttribute(
        id: "v3_shares/token",
        namespace: "v3_shares",
        name: "token",
        valueType: .string,
        isIndexed: true,
        isUnique: true
      ),
      InstantAttribute(
        id: "v3_shares/rootNamespace",
        namespace: "v3_shares",
        name: "rootNamespace",
        valueType: .string,
        isIndexed: true
      ),
      InstantAttribute(
        id: "v3_shares/rootID",
        namespace: "v3_shares",
        name: "rootID",
        valueType: .string,
        isIndexed: true
      ),
      InstantAttribute(
        id: "v3_shares/createdAt",
        namespace: "v3_shares",
        name: "createdAt",
        valueType: .date,
        isIndexed: true
      ),
      InstantAttribute(
        id: "v3_shares/updatedAt",
        namespace: "v3_shares",
        name: "updatedAt",
        valueType: .date,
        isIndexed: true
      ),
      InstantAttribute(
        id: "v3_shares/revokedAt",
        namespace: "v3_shares",
        name: "revokedAt",
        valueType: .date,
        isRequired: false,
        isIndexed: true
      ),
    ]
  )

  public static let sharingMemberships = InstantEntitySchema(
    typeName: "InstantShareMembership",
    namespace: "v3_share_memberships",
    attributes: [
      InstantAttribute(
        id: "v3_share_memberships/role",
        namespace: "v3_share_memberships",
        name: "role",
        valueType: .string,
        isIndexed: true
      ),
      InstantAttribute(
        id: "v3_share_memberships/acceptedAt",
        namespace: "v3_share_memberships",
        name: "acceptedAt",
        valueType: .date,
        isIndexed: true
      ),
      InstantAttribute(
        id: "v3_share_memberships/revokedAt",
        namespace: "v3_share_memberships",
        name: "revokedAt",
        valueType: .date,
        isRequired: false,
        isIndexed: true
      ),
    ]
  )

  public static let sharingDocument = InstantSchemaDocument(
    entities: [
      recordingActionUsers,
      sharingMemberships,
      sharingLists,
      sharingShares,
    ],
    links: [
      InstantLinkSchema(
        name: "v3_share_membershipsShare",
        forward: InstantLinkEndpoint(
          namespace: "v3_share_memberships",
          cardinality: .one,
          label: "share",
          onDelete: .cascade
        ),
        reverse: InstantLinkEndpoint(
          namespace: "v3_shares",
          cardinality: .many,
          label: "memberships"
        ),
        isRequired: true
      ),
      InstantLinkSchema(
        name: "v3_share_membershipsUser",
        forward: InstantLinkEndpoint(
          namespace: "v3_share_memberships",
          cardinality: .one,
          label: "user"
        ),
        reverse: InstantLinkEndpoint(
          namespace: "$users",
          cardinality: .many,
          label: "shareMemberships"
        ),
        isRequired: true
      ),
      InstantLinkSchema(
        name: "v3_shared_listsOwner",
        forward: InstantLinkEndpoint(
          namespace: "v3_shared_lists",
          cardinality: .one,
          label: "owner"
        ),
        reverse: InstantLinkEndpoint(
          namespace: "$users",
          cardinality: .many,
          label: "ownedSharedLists"
        ),
        isRequired: true
      ),
      InstantLinkSchema(
        name: "v3_shared_listsReaders",
        forward: InstantLinkEndpoint(
          namespace: "v3_shared_lists",
          cardinality: .many,
          label: "readers"
        ),
        reverse: InstantLinkEndpoint(
          namespace: "$users",
          cardinality: .many,
          label: "readableSharedLists"
        )
      ),
      InstantLinkSchema(
        name: "v3_shared_listsWriters",
        forward: InstantLinkEndpoint(
          namespace: "v3_shared_lists",
          cardinality: .many,
          label: "writers"
        ),
        reverse: InstantLinkEndpoint(
          namespace: "$users",
          cardinality: .many,
          label: "writableSharedLists"
        )
      ),
      InstantLinkSchema(
        name: "v3_sharesOwner",
        forward: InstantLinkEndpoint(
          namespace: "v3_shares",
          cardinality: .one,
          label: "owner"
        ),
        reverse: InstantLinkEndpoint(
          namespace: "$users",
          cardinality: .many,
          label: "ownedShares"
        ),
        isRequired: true
      ),
      InstantLinkSchema(
        name: "v3_sharesRoot",
        forward: InstantLinkEndpoint(
          namespace: "v3_shares",
          cardinality: .one,
          label: "root"
        ),
        reverse: InstantLinkEndpoint(
          namespace: "v3_shared_lists",
          cardinality: .one,
          label: "share"
        ),
        isRequired: true
      ),
    ]
  )

  public static let voiceTrailDocument = InstantSchemaDocument(
    entities: [
      recordingActionUsers,
      recordingActionAttachments,
      recordingActionRecordings,
      recordingActionTranscriptions,
      sharingMemberships,
      sharingShares,
    ],
    links: [
      InstantLinkSchema(
        name: "v3_capture_attachmentsRecording",
        forward: InstantLinkEndpoint(
          namespace: "v3_capture_attachments",
          cardinality: .one,
          label: "recording",
          onDelete: .cascade
        ),
        reverse: InstantLinkEndpoint(
          namespace: "v3_capture_recordings",
          cardinality: .many,
          label: "attachments"
        ),
        isRequired: true
      ),
      InstantLinkSchema(
        name: "v3_capture_recordingsOwner",
        forward: InstantLinkEndpoint(
          namespace: "v3_capture_recordings",
          cardinality: .one,
          label: "owner"
        ),
        reverse: InstantLinkEndpoint(
          namespace: "$users",
          cardinality: .many,
          label: "recordings"
        ),
        isRequired: true
      ),
      InstantLinkSchema(
        name: "v3_capture_recordingsReaders",
        forward: InstantLinkEndpoint(
          namespace: "v3_capture_recordings",
          cardinality: .many,
          label: "readers"
        ),
        reverse: InstantLinkEndpoint(
          namespace: "$users",
          cardinality: .many,
          label: "readableRecordings"
        )
      ),
      InstantLinkSchema(
        name: "v3_capture_recordingsWriters",
        forward: InstantLinkEndpoint(
          namespace: "v3_capture_recordings",
          cardinality: .many,
          label: "writers"
        ),
        reverse: InstantLinkEndpoint(
          namespace: "$users",
          cardinality: .many,
          label: "writableRecordings"
        )
      ),
      InstantLinkSchema(
        name: "v3_capture_transcriptionsRecording",
        forward: InstantLinkEndpoint(
          namespace: "v3_capture_transcriptions",
          cardinality: .one,
          label: "recording",
          onDelete: .cascade
        ),
        reverse: InstantLinkEndpoint(
          namespace: "v3_capture_recordings",
          cardinality: .many,
          label: "transcriptions"
        ),
        isRequired: true
      ),
      InstantLinkSchema(
        name: "v3_share_membershipsShare",
        forward: InstantLinkEndpoint(
          namespace: "v3_share_memberships",
          cardinality: .one,
          label: "share",
          onDelete: .cascade
        ),
        reverse: InstantLinkEndpoint(
          namespace: "v3_shares",
          cardinality: .many,
          label: "memberships"
        ),
        isRequired: true
      ),
      InstantLinkSchema(
        name: "v3_share_membershipsUser",
        forward: InstantLinkEndpoint(
          namespace: "v3_share_memberships",
          cardinality: .one,
          label: "user"
        ),
        reverse: InstantLinkEndpoint(
          namespace: "$users",
          cardinality: .many,
          label: "shareMemberships"
        ),
        isRequired: true
      ),
      InstantLinkSchema(
        name: "v3_sharesOwner",
        forward: InstantLinkEndpoint(
          namespace: "v3_shares",
          cardinality: .one,
          label: "owner"
        ),
        reverse: InstantLinkEndpoint(
          namespace: "$users",
          cardinality: .many,
          label: "ownedShares"
        ),
        isRequired: true
      ),
      InstantLinkSchema(
        name: "v3_sharesRoot",
        forward: InstantLinkEndpoint(
          namespace: "v3_shares",
          cardinality: .one,
          label: "root"
        ),
        reverse: InstantLinkEndpoint(
          namespace: "v3_capture_recordings",
          cardinality: .one,
          label: "share"
        ),
        isRequired: true
      ),
    ],
    rooms: [recordingActionPlaybackRoom]
  )

  public static let voiceTrailPermissions = InstantPermissionsDocument(
    namespaces: [
      InstantNamespacePermissions(
        namespace: "$users",
        allow: [.view: "auth.id != null"]
      ),
      recordingChildPermissions(namespace: "v3_capture_attachments"),
      InstantNamespacePermissions(
        namespace: "v3_capture_recordings",
        allow: [
          .view: "isOwner || isWriter || isReader",
          .create: "isOwner",
          .update: "isOwner || isWriter",
          .delete: "isOwner",
        ],
        bind: recordingRoleBindings
      ),
      recordingChildPermissions(namespace: "v3_capture_transcriptions"),
      InstantNamespacePermissions(
        namespace: "v3_share_memberships",
        allow: [
          .view: "isSelf || isShareOwner",
          .create: "isSelf || isShareOwner",
          .update: "isShareOwner",
          .delete: "isShareOwner",
        ],
        bind: [
          InstantPermissionBinding("isSelf", "auth.id in data.ref('user.id')"),
          InstantPermissionBinding("isShareOwner", "auth.id in data.ref('share.owner.id')"),
        ]
      ),
      InstantNamespacePermissions(
        namespace: "v3_shares",
        allow: [
          .view: "isOwner || isMember",
          .create: "isOwner",
          .update: "isOwner",
          .delete: "isOwner",
        ],
        bind: [
          InstantPermissionBinding("isOwner", "auth.id in data.ref('owner.id')"),
          InstantPermissionBinding("isMember", "auth.id in data.ref('memberships.user.id')"),
        ]
      ),
    ]
  )

  private static let recordingRoleBindings = [
    InstantPermissionBinding("isOwner", "auth.id in data.ref('owner.id')"),
    InstantPermissionBinding("isWriter", "auth.id in data.ref('writers.id')"),
    InstantPermissionBinding("isReader", "auth.id in data.ref('readers.id')"),
  ]

  private static func recordingChildPermissions(
    namespace: String
  ) -> InstantNamespacePermissions {
    InstantNamespacePermissions(
      namespace: namespace,
      allow: [
        .view: "isOwner || isWriter || isReader",
        .create: "isOwner || isWriter",
        .update: "isOwner || isWriter",
        .delete: "isOwner || isWriter",
      ],
      bind: [
        InstantPermissionBinding(
          "isOwner",
          "auth.id in data.ref('recording.owner.id')"
        ),
        InstantPermissionBinding(
          "isWriter",
          "auth.id in data.ref('recording.writers.id')"
        ),
        InstantPermissionBinding(
          "isReader",
          "auth.id in data.ref('recording.readers.id')"
        ),
      ]
    )
  }

  public static let sharingPermissions = InstantPermissionsDocument(
    namespaces: [
      InstantNamespacePermissions(
        namespace: "$users",
        allow: [
          .view: "auth.id != null",
        ]
      ),
      InstantNamespacePermissions(
        namespace: "v3_share_memberships",
        allow: [
          .view: "isSelf || isShareOwner",
          .create: "isSelf || isShareOwner",
          .update: "isShareOwner",
          .delete: "isShareOwner",
        ],
        bind: [
          InstantPermissionBinding("isSelf", "auth.id in data.ref('user.id')"),
          InstantPermissionBinding("isShareOwner", "auth.id in data.ref('share.owner.id')"),
        ]
      ),
      InstantNamespacePermissions(
        namespace: "v3_shared_lists",
        allow: [
          .view: "isOwner || isWriter || isReader",
          .create: "isOwner",
          .update: "isOwner || isWriter",
          .delete: "isOwner",
        ],
        bind: [
          InstantPermissionBinding("isOwner", "auth.id in data.ref('owner.id')"),
          InstantPermissionBinding("isWriter", "auth.id in data.ref('writers.id')"),
          InstantPermissionBinding("isReader", "auth.id in data.ref('readers.id')"),
        ]
      ),
      InstantNamespacePermissions(
        namespace: "v3_shares",
        allow: [
          .view: "isOwner || isMember",
          .create: "isOwner",
          .update: "isOwner",
          .delete: "isOwner",
        ],
        bind: [
          InstantPermissionBinding("isOwner", "auth.id in data.ref('owner.id')"),
          InstantPermissionBinding("isMember", "auth.id in data.ref('memberships.user.id')"),
        ]
      ),
    ]
  )

  public static let validationDocument = InstantSchemaDocument(
    entities: [
      validationProfiles,
      validationPosts,
    ],
    links: [
      InstantLinkSchema(
        name: "postAuthor",
        forward: InstantLinkEndpoint(
          namespace: "posts",
          cardinality: .one,
          label: "author"
        ),
        reverse: InstantLinkEndpoint(
          namespace: "profiles",
          cardinality: .many,
          label: "posts"
        )
      )
    ],
    rooms: [
      InstantRoomSchema(
        name: "validation",
        presence: InstantRoomPayloadSchema(
          attributes: [
            InstantAttribute(
              id: "rooms/validation/presence/name",
              namespace: "rooms/validation/presence",
              name: "name",
              valueType: .string
            ),
            InstantAttribute(
              id: "rooms/validation/presence/cursorX",
              namespace: "rooms/validation/presence",
              name: "cursorX",
              valueType: .number,
              isRequired: false
            ),
            InstantAttribute(
              id: "rooms/validation/presence/cursorY",
              namespace: "rooms/validation/presence",
              name: "cursorY",
              valueType: .number,
              isRequired: false
            ),
          ]
        ),
        topics: [
          InstantRoomTopicSchema(
            name: "ping",
            payload: InstantRoomPayloadSchema(
              attributes: [
                InstantAttribute(
                  id: "rooms/validation/topics/ping/message",
                  namespace: "rooms/validation/topics/ping",
                  name: "message",
                  valueType: .string
                ),
                InstantAttribute(
                  id: "rooms/validation/topics/ping/sentAt",
                  namespace: "rooms/validation/topics/ping",
                  name: "sentAt",
                  valueType: .date
                ),
              ]
            )
          )
        ]
      )
    ]
  )

  public static let validationPermissions = InstantPermissionsDocument(
    namespaces: [
      .allowAll(namespace: "$files"),
      .allowAll(namespace: "posts"),
      .allowAll(namespace: "profiles"),
    ]
  )

  public static let recordingActionValidationPermissions = InstantPermissionsDocument(
    namespaces: [
      .allowAll(namespace: "v3_capture_attachments"),
      .allowAll(namespace: "v3_capture_members"),
      .allowAll(namespace: "v3_capture_recordings"),
      .allowAll(namespace: "v3_capture_transcriptions"),
    ]
  )
}

public struct TypeScriptSchemaPrinter: Sendable {
  public init() {}

  public func printSchema(_ entities: [InstantEntitySchema]) throws -> String {
    try printSchema(InstantSchemaDocument(entities: entities))
  }

  public func printSchema(_ document: InstantSchemaDocument) throws -> String {
    try validate(document)

    var lines: [String] = [
      "import { i } from '@instantdb/core';",
      "",
      "export default i.schema({",
      "  entities: {",
    ]

    for entity in document.entities.sorted(by: { $0.namespace < $1.namespace }) {
      lines.append("    \(TypeScriptPrinterSupport.propertyKey(entity.namespace)): i.entity({")
      for attribute in printableAttributes(entity.attributes).sorted(by: { $0.name < $1.name }) {
        lines.append(
          "      \(TypeScriptPrinterSupport.propertyKey(attribute.name)): \(typeExpression(for: attribute)),"
        )
      }
      lines.append("    }),")
    }

    lines.append("  },")

    if !document.links.isEmpty {
      lines.append("  links: {")
      for link in document.links.sorted(by: { $0.name < $1.name }) {
        lines.append("    \(TypeScriptPrinterSupport.propertyKey(link.name)): {")
        lines.append("      forward: {")
        lines.append(contentsOf: endpointLines(for: link.forward, isRequired: link.isRequired))
        lines.append("      },")
        lines.append("      reverse: {")
        lines.append(contentsOf: endpointLines(for: link.reverse))
        lines.append("      },")
        lines.append("    },")
      }
      lines.append("  },")
    }

    if !document.rooms.isEmpty {
      lines.append("  rooms: {")
      for room in document.rooms.sorted(by: { $0.name < $1.name }) {
        lines.append("    \(TypeScriptPrinterSupport.propertyKey(room.name)): {")
        appendEntityExpression(
          to: &lines,
          name: "presence",
          attributes: room.presence.attributes,
          indentation: "      "
        )
        if !room.topics.isEmpty {
          lines.append("      topics: {")
          for topic in room.topics.sorted(by: { $0.name < $1.name }) {
            appendEntityExpression(
              to: &lines,
              name: topic.name,
              attributes: topic.payload.attributes,
              indentation: "        "
            )
          }
          lines.append("      },")
        }
        lines.append("    },")
      }
      lines.append("  },")
    }

    lines.append(contentsOf: [
      "});",
      "",
    ])

    return lines.joined(separator: "\n")
  }

  private func appendEntityExpression(
    to lines: inout [String],
    name: String,
    attributes: [InstantAttribute],
    indentation: String
  ) {
    if attributes.isEmpty {
      lines.append("\(indentation)\(TypeScriptPrinterSupport.propertyKey(name)): i.entity({}),")
      return
    }

    lines.append("\(indentation)\(TypeScriptPrinterSupport.propertyKey(name)): i.entity({")
    for attribute in printableAttributes(attributes).sorted(by: { $0.name < $1.name }) {
      lines.append(
        "\(indentation)  \(TypeScriptPrinterSupport.propertyKey(attribute.name)): \(typeExpression(for: attribute)),"
      )
    }
    lines.append("\(indentation)}),")
  }

  private func printableAttributes(_ attributes: [InstantAttribute]) -> [InstantAttribute] {
    attributes.filter { !$0.primaryKey }
  }

  private func validate(_ document: InstantSchemaDocument) throws {
    for entity in document.entities {
      try validatePrintableAttributes(entity.attributes)
    }
    for room in document.rooms {
      try validatePrintableAttributes(room.presence.attributes)
      for topic in room.topics {
        try validatePrintableAttributes(topic.payload.attributes)
      }
    }
    for link in document.links {
      try validateCascadeEndpoint(
        link: link.name,
        endpoint: "forward",
        value: link.forward
      )
      try validateCascadeEndpoint(
        link: link.name,
        endpoint: "reverse",
        value: link.reverse
      )
    }
  }

  private func validatePrintableAttributes(_ attributes: [InstantAttribute]) throws {
    for attribute in printableAttributes(attributes) where attribute.valueType == .ref {
      throw InstantSchemaValidationError.unsupportedRefAttribute(
        namespace: attribute.namespace,
        name: attribute.name
      )
    }
  }

  private func validateCascadeEndpoint(
    link: String,
    endpoint: String,
    value: InstantLinkEndpoint
  ) throws {
    guard value.onDelete == .cascade, value.cardinality != .one else { return }
    throw InstantSchemaValidationError.invalidLinkCascadeEndpoint(
      link: link,
      endpoint: endpoint,
      cardinality: value.cardinality
    )
  }

  private func endpointLines(
    for endpoint: InstantLinkEndpoint,
    isRequired: Bool? = nil
  ) -> [String] {
    var lines = [
      "        on: \(TypeScriptPrinterSupport.stringLiteral(endpoint.namespace)),",
      "        has: \(TypeScriptPrinterSupport.stringLiteral(endpoint.cardinality.rawValue)),",
      "        label: \(TypeScriptPrinterSupport.stringLiteral(endpoint.label)),",
    ]
    if let isRequired {
      lines.append("        required: \(isRequired),")
    }
    if endpoint.onDelete == .cascade {
      lines.append("        onDelete: \(TypeScriptPrinterSupport.stringLiteral("cascade")),")
    }
    return lines
  }

  private func typeExpression(for attribute: InstantAttribute) -> String {
    let scalar =
      switch attribute.valueType {
      case .string:
        "i.string()"
      case .number:
        "i.number()"
      case .boolean:
        "i.boolean()"
      case .date:
        "i.date()"
      case .json:
        "i.json()"
      case .any:
        "i.any()"
      case .ref:
        preconditionFailure("Ref attributes must be printed from schema links.")
      }

    var expression = scalar
    if !attribute.isRequired {
      expression += ".optional()"
    }
    if attribute.isIndexed {
      expression += ".indexed()"
    }
    if attribute.isUnique {
      expression += ".unique()"
    }
    return expression
  }
}

public enum TypeScriptInstantRulesPackage: String, Sendable {
  case core = "@instantdb/core"
  case react = "@instantdb/react"
}

public struct TypeScriptPermissionsPrinter: Sendable {
  public var package: TypeScriptInstantRulesPackage

  public init(package: TypeScriptInstantRulesPackage = .core) {
    self.package = package
  }

  public func printPermissions(_ document: InstantPermissionsDocument) throws -> String {
    try validate(document)

    var lines: [String] = [
      "// Docs: https://www.instantdb.com/docs/permissions",
      "",
      "import type { InstantRules } from \(TypeScriptPrinterSupport.stringLiteral(package.rawValue));",
      "",
      "const rules = {",
    ]

    if let attrs = document.attrs {
      lines.append("  attrs: {")
      lines.append(
        contentsOf: printRuleBlock(
          allow: attrs.allow,
          link: [:],
          unlink: [:],
          bind: attrs.bind,
          fields: nil,
          indentation: "    "
        )
      )
      lines.append("  },")
    }

    if let defaults = document.defaults {
      lines.append("  \(TypeScriptPrinterSupport.propertyKey("$default")): {")
      lines.append(
        contentsOf: printRuleBlock(
          allow: defaults.allow,
          link: defaults.link,
          unlink: defaults.unlink,
          bind: defaults.bind,
          fields: nil,
          indentation: "    "
        )
      )
      lines.append("  },")
    }

    if !document.rateLimits.isEmpty {
      lines.append("  \(TypeScriptPrinterSupport.propertyKey("$rateLimits")): {")
      for rateLimit in document.rateLimits.sorted(by: { $0.name < $1.name }) {
        lines.append("    \(TypeScriptPrinterSupport.propertyKey(rateLimit.name)): {")
        lines.append("      limits: [")
        for limit in rateLimit.limits {
          lines.append(contentsOf: printRateLimit(limit, indentation: "        "))
        }
        lines.append("      ],")
        lines.append("    },")
      }
      lines.append("  },")
    }

    for namespace in document.namespaces.sorted(by: { $0.namespace < $1.namespace }) {
      lines.append("  \(TypeScriptPrinterSupport.propertyKey(namespace.namespace)): {")
      lines.append(
        contentsOf: printRuleBlock(
          allow: namespace.allow,
          link: namespace.link,
          unlink: namespace.unlink,
          bind: namespace.bind,
          fields: namespace.fields,
          indentation: "    "
        )
      )
      lines.append("  },")
    }

    lines.append(contentsOf: [
      "} satisfies InstantRules;",
      "",
      "export default rules;",
      "",
    ])

    return lines.joined(separator: "\n")
  }

  private func validate(_ document: InstantPermissionsDocument) throws {
    for namespace in document.namespaces {
      if namespace.fields.keys.contains("id") {
        throw InstantPermissionsValidationError.reservedFieldRule(
          namespace: namespace.namespace,
          field: "id"
        )
      }
    }

    for rateLimit in document.rateLimits {
      guard !rateLimit.limits.isEmpty else {
        throw InstantPermissionsValidationError.emptyRateLimit(name: rateLimit.name)
      }

      for limit in rateLimit.limits {
        guard limit.capacity > 0 else {
          throw InstantPermissionsValidationError.invalidRateLimitCapacity(
            name: rateLimit.name,
            capacity: limit.capacity
          )
        }
        if let amount = limit.refill?.amount, amount <= 0 {
          throw InstantPermissionsValidationError.invalidRateLimitRefillAmount(
            name: rateLimit.name,
            amount: amount
          )
        }
        if let period = limit.refill?.period,
          !Self.isValidRateLimitRefillPeriod(period)
        {
          throw InstantPermissionsValidationError.invalidRateLimitRefillPeriod(
            name: rateLimit.name,
            period: period
          )
        }
      }
    }
  }

  private static func isValidRateLimitRefillPeriod(_ period: String) -> Bool {
    let parts =
      period
      .split(whereSeparator: \.isWhitespace)
      .map { String($0).lowercased() }
    guard parts.count == 2,
      let value = Double(parts[0]),
      value > 0
    else {
      return false
    }

    let seconds =
      switch parts[1] {
      case "second", "seconds":
        value
      case "minute", "minutes":
        value * 60
      case "hour", "hours":
        value * 60 * 60
      case "day", "days":
        value * 24 * 60 * 60
      default:
        -1.0
      }

    return seconds >= 1 && seconds <= 24 * 60 * 60
  }

  private func printRuleBlock(
    allow: [InstantPermissionAction: String],
    link: [String: String],
    unlink: [String: String],
    bind: [InstantPermissionBinding],
    fields: [String: String]?,
    indentation: String
  ) -> [String] {
    var lines: [String] = []
    if allow.isEmpty, link.isEmpty, unlink.isEmpty {
      lines.append("\(indentation)allow: {},")
    } else {
      lines.append("\(indentation)allow: {")
      for action in InstantPermissionAction.allCases {
        guard let expression = allow[action] else { continue }
        lines.append(
          "\(indentation)  \(TypeScriptPrinterSupport.propertyKey(action.rawValue)): \(TypeScriptPrinterSupport.stringLiteral(expression)),"
        )
      }
      if !link.isEmpty {
        lines.append("\(indentation)  link: {")
        for (name, expression) in link.sorted(by: { $0.key < $1.key }) {
          lines.append(
            "\(indentation)    \(TypeScriptPrinterSupport.propertyKey(name)): \(TypeScriptPrinterSupport.stringLiteral(expression)),"
          )
        }
        lines.append("\(indentation)  },")
      }
      if !unlink.isEmpty {
        lines.append("\(indentation)  unlink: {")
        for (name, expression) in unlink.sorted(by: { $0.key < $1.key }) {
          lines.append(
            "\(indentation)    \(TypeScriptPrinterSupport.propertyKey(name)): \(TypeScriptPrinterSupport.stringLiteral(expression)),"
          )
        }
        lines.append("\(indentation)  },")
      }
      lines.append("\(indentation)},")
    }

    if !bind.isEmpty {
      lines.append("\(indentation)bind: [")
      for binding in bind {
        lines.append(
          "\(indentation)  \(TypeScriptPrinterSupport.stringLiteral(binding.name)), \(TypeScriptPrinterSupport.stringLiteral(binding.expression)),"
        )
      }
      lines.append("\(indentation)],")
    }

    if let fields, !fields.isEmpty {
      lines.append("\(indentation)fields: {")
      for (name, expression) in fields.sorted(by: { $0.key < $1.key }) {
        lines.append(
          "\(indentation)  \(TypeScriptPrinterSupport.propertyKey(name)): \(TypeScriptPrinterSupport.stringLiteral(expression)),"
        )
      }
      lines.append("\(indentation)},")
    }

    return lines
  }

  private func printRateLimit(
    _ limit: InstantRateLimitLimit,
    indentation: String
  ) -> [String] {
    guard let refill = limit.refill else {
      return ["\(indentation){ capacity: \(limit.capacity) },"]
    }

    var refillParts: [String] = []
    if let amount = refill.amount {
      refillParts.append("amount: \(amount)")
    }
    if let period = refill.period {
      refillParts.append("period: \(TypeScriptPrinterSupport.stringLiteral(period))")
    }
    if let type = refill.type {
      refillParts.append("type: \(TypeScriptPrinterSupport.stringLiteral(type.rawValue))")
    }

    if refillParts.isEmpty {
      return ["\(indentation){ capacity: \(limit.capacity), refill: {} },"]
    }

    return [
      "\(indentation){ capacity: \(limit.capacity), refill: { \(refillParts.joined(separator: ", ")) } },"
    ]
  }
}

private enum TypeScriptPrinterSupport {
  static func propertyKey(_ key: String) -> String {
    guard !key.hasPrefix("$"),
      isIdentifier(key)
    else {
      return stringLiteral(key)
    }
    return key
  }

  static func stringLiteral(_ string: String) -> String {
    var result = "\""
    for scalar in string.unicodeScalars {
      switch scalar {
      case "\"":
        result += "\\\""
      case "\\":
        result += "\\\\"
      case "\n":
        result += "\\n"
      case "\r":
        result += "\\r"
      case "\t":
        result += "\\t"
      case "\u{08}":
        result += "\\b"
      case "\u{0C}":
        result += "\\f"
      case let scalar where scalar.value < 0x20:
        let hex = String(scalar.value, radix: 16)
        result += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
      default:
        result.unicodeScalars.append(scalar)
      }
    }
    result += "\""
    return result
  }

  private static func isIdentifier(_ key: String) -> Bool {
    guard let first = key.unicodeScalars.first,
      CharacterSet(charactersIn: "_$").contains(first)
        || CharacterSet.letters.contains(first)
    else { return false }

    return key.unicodeScalars.dropFirst().allSatisfy {
      CharacterSet(charactersIn: "_$").contains($0)
        || CharacterSet.alphanumerics.contains($0)
    }
  }
}
