import Foundation
import InstantSwiftData
import InstantSwiftDataSchema

public enum VoiceTrailSchema {
  public static var attributes: [InstantAttribute] {
    InstantSchemaExamples.voiceTrailDocument.attributes
  }
}

public struct VoiceTrailUser: Hashable, Codable, InstantEntityModel {
  public struct Signup: Sendable {}

  public var id: InstantID<Self>
  public var email: String?

  public static let instantNamespace = "$users"
  public static let email = InstantAttributePath<Self, String?>("email")
  public static let instantAttributes = [
    InstantAttribute(
      id: "$users/email",
      namespace: instantNamespace,
      name: "email",
      valueType: .string,
      isRequired: false,
      isIndexed: true,
      isUnique: true
    )
  ]

  public init(snapshot: InstantEntitySnapshot) throws {
    id = InstantID(rawValue: snapshot.id)
    if case let .string(email) = snapshot.values["email"]?.first {
      self.email = email
    } else {
      self.email = nil
    }
  }
}

public enum VoiceTrailAuthProviders: InstantAuthProviderCatalog {
  public static let magicCode = AuthProvider.magicCode(
    email: .instant,
    extraFields: VoiceTrailUser.Signup.self
  )
  public static let apple = AuthProvider.apple(
    clientName: "apple-ios",
    presentation: .native
  )
  public static let google = AuthProvider.google(
    clientName: "google-ios",
    presentation: .native
  )
  public static let all = [magicCode, apple, google]
}

public struct VoiceTrailRecording: Hashable, Codable, InstantEntityModel {
  public var id: InstantID<Self>
  public var title: String
  public var ownerID: InstantID<VoiceTrailUser>
  public var deviceID: String
  public var state: String
  public var durationMilliseconds: Int
  public var viewerMembership: VoiceTrailViewerMembership?

  public static let instantNamespace = "v3_capture_recordings"
  public static let identifier = InstantAttributePath<Self, String>("id")
  public static let title = InstantAttributePath<Self, String>("title")
  public static let owner = InstantAttributePath<Self, InstantID<VoiceTrailUser>>("owner")
  public static let readers = InstantAttributePath<Self, InstantID<VoiceTrailUser>>("readers")
  public static let writers = InstantAttributePath<Self, InstantID<VoiceTrailUser>>("writers")
  public static let share = InstantReverseRelation<Self, VoiceTrailShare>(
    attribute: VoiceTrailShare.root
  )
  public static let deviceID = InstantAttributePath<Self, String>("deviceID")
  public static let state = InstantAttributePath<Self, String>("state")
  public static let durationMilliseconds = InstantAttributePath<Self, Int>(
    "durationMilliseconds"
  )
  public static let instantAttributes = [
    InstantAttribute.primaryKey(namespace: instantNamespace),
    InstantAttribute(
      id: "v3_capture_recordings/title",
      namespace: instantNamespace,
      name: "title",
      valueType: .string,
      isIndexed: true
    ),
    InstantAttribute(
      id: "v3_capture_recordings/owner",
      namespace: instantNamespace,
      name: "owner",
      valueType: .ref,
      isRequired: true,
      isIndexed: true,
      forwardIdentity: "v3_capture_recordings/owner",
      reverseIdentity: "$users/recordings",
      linkNamespace: VoiceTrailUser.instantNamespace
    ),
    InstantAttribute(
      id: "v3_capture_recordings/readers",
      namespace: instantNamespace,
      name: "readers",
      valueType: .ref,
      cardinality: .many,
      isIndexed: true,
      forwardIdentity: "v3_capture_recordings/readers",
      reverseIdentity: "$users/readableRecordings",
      linkNamespace: VoiceTrailUser.instantNamespace
    ),
    InstantAttribute(
      id: "v3_capture_recordings/writers",
      namespace: instantNamespace,
      name: "writers",
      valueType: .ref,
      cardinality: .many,
      isIndexed: true,
      forwardIdentity: "v3_capture_recordings/writers",
      reverseIdentity: "$users/writableRecordings",
      linkNamespace: VoiceTrailUser.instantNamespace
    ),
    InstantAttribute(
      id: "v3_capture_recordings/deviceID",
      namespace: instantNamespace,
      name: "deviceID",
      valueType: .string,
      isIndexed: true
    ),
    InstantAttribute(
      id: "v3_capture_recordings/state",
      namespace: instantNamespace,
      name: "state",
      valueType: .string,
      isIndexed: true
    ),
    InstantAttribute(
      id: "v3_capture_recordings/durationMilliseconds",
      namespace: instantNamespace,
      name: "durationMilliseconds",
      valueType: .number,
      isIndexed: true
    ),
  ]

  public init(snapshot: InstantEntitySnapshot) throws {
    guard case let .string(title) = snapshot.values["title"]?.first,
      case let .ref(ownerID) = snapshot.values["owner"]?.first,
      case let .string(deviceID) = snapshot.values["deviceID"]?.first,
      case let .string(state) = snapshot.values["state"]?.first,
      case let .number(durationMilliseconds) = snapshot.values["durationMilliseconds"]?.first
    else {
      throw InstantError(
        code: .decodeFailed,
        operation: "decode VoiceTrail recording",
        namespace: Self.instantNamespace,
        localID: snapshot.id,
        message: "Expected title, owner, device, state, and duration values.",
        recovery: "Keep the app recording model aligned with the generated VoiceTrail schema."
      )
    }
    id = InstantID(rawValue: snapshot.id)
    self.title = title
    self.ownerID = InstantID(rawValue: ownerID)
    self.deviceID = deviceID
    self.state = state
    self.durationMilliseconds = Int(durationMilliseconds)
    self.viewerMembership = try snapshot.links?["share"]?.first
      .flatMap { $0.links?["memberships"]?.first }
      .map(VoiceTrailViewerMembership.init)
  }

  public var viewerRole: InstantShareRole? {
    viewerMembership?.role
  }
}

public enum VoiceTrailRecordingScope: String, CaseIterable, Hashable, Identifiable, Sendable {
  case mine
  case shared

  public var id: Self { self }

  public var title: String {
    switch self {
    case .mine: "Mine"
    case .shared: "Shared"
    }
  }
}

public struct VoiceTrailShare: Hashable, Codable, InstantEntityModel {
  public var id: InstantID<Self>

  public static let instantNamespace = "v3_shares"
  public static let owner = InstantAttributePath<Self, InstantID<VoiceTrailUser>>("owner")
  public static let root = InstantAttributePath<Self, InstantID<VoiceTrailRecording>>("root")
  public static let memberships = InstantReverseRelation<Self, VoiceTrailShareMembership>(
    attribute: VoiceTrailShareMembership.share
  )
  public static let instantAttributes = [
    InstantAttribute.primaryKey(namespace: instantNamespace),
    InstantAttribute(
      id: "v3_shares/token",
      namespace: instantNamespace,
      name: "token",
      valueType: .string,
      isIndexed: true,
      isUnique: true
    ),
    InstantAttribute(
      id: "v3_shares/rootNamespace",
      namespace: instantNamespace,
      name: "rootNamespace",
      valueType: .string,
      isIndexed: true
    ),
    InstantAttribute(
      id: "v3_shares/rootID",
      namespace: instantNamespace,
      name: "rootID",
      valueType: .string,
      isIndexed: true
    ),
    InstantAttribute(
      id: "v3_shares/createdAt",
      namespace: instantNamespace,
      name: "createdAt",
      valueType: .date,
      isIndexed: true
    ),
    InstantAttribute(
      id: "v3_shares/updatedAt",
      namespace: instantNamespace,
      name: "updatedAt",
      valueType: .date,
      isIndexed: true
    ),
    InstantAttribute(
      id: "v3_shares/revokedAt",
      namespace: instantNamespace,
      name: "revokedAt",
      valueType: .date,
      isRequired: false,
      isIndexed: true
    ),
    InstantAttribute(
      id: "v3_shares/owner",
      namespace: instantNamespace,
      name: "owner",
      valueType: .ref,
      isRequired: true,
      isIndexed: true,
      forwardIdentity: "v3_shares/owner",
      reverseIdentity: "$users/ownedShares",
      linkNamespace: VoiceTrailUser.instantNamespace
    ),
    InstantAttribute(
      id: "v3_shares/root",
      namespace: instantNamespace,
      name: "root",
      valueType: .ref,
      isRequired: true,
      isIndexed: true,
      isUnique: true,
      forwardIdentity: "v3_shares/root",
      reverseIdentity: "v3_capture_recordings/share",
      linkNamespace: VoiceTrailRecording.instantNamespace
    ),
  ]

  public init(snapshot: InstantEntitySnapshot) throws {
    id = InstantID(rawValue: snapshot.id)
  }
}

public struct VoiceTrailShareMembership: Hashable, Codable, InstantEntityModel {
  public var id: InstantID<Self>

  public static let instantNamespace = "v3_share_memberships"
  public static let role = InstantAttributePath<Self, String>("role")
  public static let acceptedAt = InstantAttributePath<Self, Date>("acceptedAt")
  public static let share = InstantAttributePath<Self, InstantID<VoiceTrailShare>>("share")
  public static let user = InstantAttributePath<Self, InstantID<VoiceTrailUser>>("user")
  public static let instantAttributes = [
    InstantAttribute.primaryKey(namespace: instantNamespace),
    InstantAttribute(
      id: "v3_share_memberships/role",
      namespace: instantNamespace,
      name: "role",
      valueType: .string,
      isIndexed: true
    ),
    InstantAttribute(
      id: "v3_share_memberships/acceptedAt",
      namespace: instantNamespace,
      name: "acceptedAt",
      valueType: .date,
      isIndexed: true
    ),
    InstantAttribute(
      id: "v3_share_memberships/revokedAt",
      namespace: instantNamespace,
      name: "revokedAt",
      valueType: .date,
      isRequired: false,
      isIndexed: true
    ),
    InstantAttribute(
      id: "v3_share_memberships/share",
      namespace: instantNamespace,
      name: "share",
      valueType: .ref,
      isRequired: true,
      isIndexed: true,
      forwardIdentity: "v3_share_memberships/share",
      reverseIdentity: "v3_shares/memberships",
      linkNamespace: VoiceTrailShare.instantNamespace,
      onDelete: .cascade
    ),
    InstantAttribute(
      id: "v3_share_memberships/user",
      namespace: instantNamespace,
      name: "user",
      valueType: .ref,
      isRequired: true,
      isIndexed: true,
      forwardIdentity: "v3_share_memberships/user",
      reverseIdentity: "$users/shareMemberships",
      linkNamespace: VoiceTrailUser.instantNamespace
    ),
  ]

  public init(snapshot: InstantEntitySnapshot) throws {
    id = InstantID(rawValue: snapshot.id)
  }
}

public struct VoiceTrailViewerMembership: Hashable, Codable, Sendable {
  public var id: String
  public var userID: InstantID<VoiceTrailUser>
  public var role: InstantShareRole
  public var acceptedAt: Date

  public init(_ snapshot: InstantLinkedEntitySnapshot) throws {
    guard case let .string(rawRole) = snapshot.values["role"]?.first,
      let role = InstantShareRole(rawValue: rawRole),
      case let .date(acceptedAt) = snapshot.values["acceptedAt"]?.first,
      let userID = snapshot.links?["user"]?.first?.id
    else {
      throw InstantError(
        code: .decodeFailed,
        operation: "decode VoiceTrail viewer membership",
        namespace: VoiceTrailShareMembership.instantNamespace,
        localID: snapshot.id,
        message: "Expected role, acceptedAt, and one user link.",
        recovery: "Keep the app recording projection aligned with the canonical share graph."
      )
    }
    id = snapshot.id
    self.userID = InstantID(rawValue: userID)
    self.role = role
    self.acceptedAt = acceptedAt
  }
}

extension VoiceTrailRecording {
  public static func recordingsQuery(
    scope: VoiceTrailRecordingScope,
    searchText: String,
    viewerID: InstantID<VoiceTrailUser>?
  ) -> InstantQuery<Self> {
    guard let viewerID else {
      return query.where(identifier.isIn([]))
    }
    let viewerMembership = VoiceTrailShareMembership.query
      .where(VoiceTrailShareMembership.user == viewerID)
      .include(VoiceTrailShareMembership.user)
    let shareQuery = VoiceTrailShare.query
      .include(VoiceTrailShare.owner)
      .include(VoiceTrailShare.memberships, viewerMembership)
    var query = query
      .include(owner)
      .include(readers)
      .include(writers)
      .include(share, shareQuery)
      .order(title)
    switch scope {
    case .mine:
      query = query.where(owner == viewerID)
    case .shared:
      query = query.where(.any(readers == viewerID, writers == viewerID))
    }
    guard !searchText.isEmpty else { return query }
    return query.where(title.iLike("%\(searchText)%"))
  }
}

public struct VoiceTrailTranscription: Hashable, Codable, InstantEntityModel {
  public var id: InstantID<Self>
  public var recordingID: InstantID<VoiceTrailRecording>
  public var state: String

  public static let instantNamespace = "v3_capture_transcriptions"
  public static let recording = InstantAttributePath<
    Self,
    InstantID<VoiceTrailRecording>
  >("recording")
  public static let state = InstantAttributePath<Self, String>("state")
  public static let instantAttributes = [
    InstantAttribute.primaryKey(namespace: instantNamespace),
    InstantAttribute(
      id: "v3_capture_transcriptions/recording",
      namespace: instantNamespace,
      name: "recording",
      valueType: .ref,
      isRequired: true,
      isIndexed: true,
      forwardIdentity: "v3_capture_transcriptions/recording",
      reverseIdentity: "v3_capture_recordings/transcriptions",
      linkNamespace: VoiceTrailRecording.instantNamespace,
      onDelete: .cascade
    ),
    InstantAttribute(
      id: "v3_capture_transcriptions/state",
      namespace: instantNamespace,
      name: "state",
      valueType: .string,
      isIndexed: true
    ),
  ]

  public init(snapshot: InstantEntitySnapshot) throws {
    guard case let .ref(recordingID) = snapshot.values["recording"]?.first,
      case let .string(state) = snapshot.values["state"]?.first
    else {
      throw InstantError(
        code: .decodeFailed,
        operation: "decode VoiceTrail transcription",
        namespace: Self.instantNamespace,
        localID: snapshot.id,
        message: "Expected recording and state values.",
        recovery: "Keep the app transcription model aligned with the generated schema."
      )
    }
    id = InstantID(rawValue: snapshot.id)
    self.recordingID = InstantID(rawValue: recordingID)
    self.state = state
  }
}

public struct VoiceTrailRecordingCreated: Hashable, Sendable {
  public var recordingID: InstantID<VoiceTrailRecording>
  public var transcriptionID: InstantID<VoiceTrailTranscription>

  public init(
    recordingID: InstantID<VoiceTrailRecording>,
    transcriptionID: InstantID<VoiceTrailTranscription>
  ) {
    self.recordingID = recordingID
    self.transcriptionID = transcriptionID
  }
}

public struct CreateVoiceTrailRecording: InstantMessage {
  public var recordingID: InstantID<VoiceTrailRecording>
  public var transcriptionID: InstantID<VoiceTrailTranscription>
  public var ownerID: InstantID<VoiceTrailUser>
  public var deviceID: String
  public var title: String

  public init(
    recordingID: InstantID<VoiceTrailRecording>,
    transcriptionID: InstantID<VoiceTrailTranscription>,
    ownerID: InstantID<VoiceTrailUser>,
    deviceID: String,
    title: String
  ) {
    self.recordingID = recordingID
    self.transcriptionID = transcriptionID
    self.ownerID = ownerID
    self.deviceID = deviceID
    self.title = title
  }

  public func prepare(using client: InstantSwiftDataClient) async throws
    -> InstantPreparedMessage<VoiceTrailRecordingCreated>
  {
    _ = client
    return InstantPreparedMessage(
      change: VoiceTrailRecordingCreated(
        recordingID: recordingID,
        transcriptionID: transcriptionID
      )
    ) {
      VoiceTrailRecording.create(
        id: recordingID,
        VoiceTrailRecording.title.set(title),
        VoiceTrailRecording.owner.set(ownerID),
        VoiceTrailRecording.deviceID.set(deviceID),
        VoiceTrailRecording.state.set("recording"),
        VoiceTrailRecording.durationMilliseconds.set(0)
      )
      VoiceTrailTranscription.create(
        id: transcriptionID,
        VoiceTrailTranscription.recording.set(recordingID),
        VoiceTrailTranscription.state.set("processing")
      )
    }
  }
}

public struct VoiceTrailAttachment: Hashable, Codable, InstantEntityModel {
  public var id: InstantID<Self>
  public var recordingID: InstantID<VoiceTrailRecording>
  public var kind: String
  public var contents: String
  public var offsetMilliseconds: Int

  public static let instantNamespace = "v3_capture_attachments"
  public static let recording = InstantAttributePath<Self, InstantID<VoiceTrailRecording>>(
    "recording"
  )
  public static let kind = InstantAttributePath<Self, String>("kind")
  public static let contents = InstantAttributePath<Self, String>("contents")
  public static let offsetMilliseconds = InstantAttributePath<Self, Int>("offsetMilliseconds")
  public static let instantAttributes = [
    InstantAttribute.primaryKey(namespace: instantNamespace),
    InstantAttribute(
      id: "v3_capture_attachments/recording",
      namespace: instantNamespace,
      name: "recording",
      valueType: .ref,
      isRequired: true,
      isIndexed: true,
      forwardIdentity: "v3_capture_attachments/recording",
      reverseIdentity: "v3_capture_recordings/attachments",
      linkNamespace: VoiceTrailRecording.instantNamespace,
      onDelete: .cascade
    ),
    InstantAttribute(
      id: "v3_capture_attachments/kind",
      namespace: instantNamespace,
      name: "kind",
      valueType: .string,
      isIndexed: true
    ),
    InstantAttribute(
      id: "v3_capture_attachments/contents",
      namespace: instantNamespace,
      name: "contents",
      valueType: .string
    ),
    InstantAttribute(
      id: "v3_capture_attachments/offsetMilliseconds",
      namespace: instantNamespace,
      name: "offsetMilliseconds",
      valueType: .number,
      isIndexed: true
    ),
  ]

  public init(snapshot: InstantEntitySnapshot) throws {
    guard case let .ref(recordingID) = snapshot.values["recording"]?.first,
      case let .string(kind) = snapshot.values["kind"]?.first,
      case let .string(contents) = snapshot.values["contents"]?.first,
      case let .number(offset) = snapshot.values["offsetMilliseconds"]?.first,
      let offsetMilliseconds = Int(exactly: offset)
    else {
      throw InstantError(
        code: .decodeFailed,
        operation: "decode VoiceTrail attachment",
        namespace: Self.instantNamespace,
        localID: snapshot.id,
        message: "Expected recording, kind, contents, and exact offset values.",
        recovery: "Keep the app attachment model aligned with the generated VoiceTrail schema."
      )
    }
    id = InstantID(rawValue: snapshot.id)
    self.recordingID = InstantID(rawValue: recordingID)
    self.kind = kind
    self.contents = contents
    self.offsetMilliseconds = offsetMilliseconds
  }
}

public struct VoiceTrailAttachmentCreated: Hashable, Sendable {
  public var attachmentID: InstantID<VoiceTrailAttachment>

  public init(attachmentID: InstantID<VoiceTrailAttachment>) {
    self.attachmentID = attachmentID
  }
}

public struct CreateVoiceTrailAttachment: InstantMessage {
  public var attachmentID: InstantID<VoiceTrailAttachment>
  public var recordingID: InstantID<VoiceTrailRecording>
  public var kind: String
  public var contents: String
  public var offsetMilliseconds: Int

  public init(
    attachmentID: InstantID<VoiceTrailAttachment>,
    recordingID: InstantID<VoiceTrailRecording>,
    kind: String,
    contents: String,
    offsetMilliseconds: Int
  ) {
    self.attachmentID = attachmentID
    self.recordingID = recordingID
    self.kind = kind
    self.contents = contents
    self.offsetMilliseconds = offsetMilliseconds
  }

  public func prepare(using client: InstantSwiftDataClient) async throws
    -> InstantPreparedMessage<VoiceTrailAttachmentCreated>
  {
    _ = client
    return InstantPreparedMessage(
      change: VoiceTrailAttachmentCreated(attachmentID: attachmentID)
    ) {
      VoiceTrailAttachment.create(
        id: attachmentID,
        VoiceTrailAttachment.recording.set(recordingID),
        VoiceTrailAttachment.kind.set(kind),
        VoiceTrailAttachment.contents.set(contents),
        VoiceTrailAttachment.offsetMilliseconds.set(offsetMilliseconds)
      )
    }
  }
}

public struct VoiceTrailRecordingFinished: Hashable, Sendable {
  public var recordingID: InstantID<VoiceTrailRecording>
  public var durationMilliseconds: Int

  public init(
    recordingID: InstantID<VoiceTrailRecording>,
    durationMilliseconds: Int
  ) {
    self.recordingID = recordingID
    self.durationMilliseconds = durationMilliseconds
  }
}

public struct FinishVoiceTrailRecording: InstantMessage {
  public var recordingID: InstantID<VoiceTrailRecording>
  public var transcriptionID: InstantID<VoiceTrailTranscription>
  public var durationMilliseconds: Int

  public init(
    recordingID: InstantID<VoiceTrailRecording>,
    transcriptionID: InstantID<VoiceTrailTranscription>,
    durationMilliseconds: Int
  ) {
    self.recordingID = recordingID
    self.transcriptionID = transcriptionID
    self.durationMilliseconds = durationMilliseconds
  }

  public func prepare(using client: InstantSwiftDataClient) async throws
    -> InstantPreparedMessage<VoiceTrailRecordingFinished>
  {
    _ = client
    return InstantPreparedMessage(
      change: VoiceTrailRecordingFinished(
        recordingID: recordingID,
        durationMilliseconds: durationMilliseconds
      )
    ) {
      VoiceTrailRecording.updateExisting(
        id: recordingID,
        VoiceTrailRecording.state.set("finished"),
        VoiceTrailRecording.durationMilliseconds.set(durationMilliseconds)
      )
      VoiceTrailTranscription.updateExisting(
        id: transcriptionID,
        VoiceTrailTranscription.state.set("ready")
      )
    }
  }
}

public struct VoiceTrailPlaybackRoom: InstantSwiftData.InstantRoomSchema {
  public typealias Presence = VoiceTrailPlaybackPresence
  public static let roomType = "recording.playback"

  public enum Topic: String, CaseIterable, InstantRoomTopic {
    public typealias RoomSchema = VoiceTrailPlaybackRoom

    case reaction
    case commentDraft
    case commentCommitted
  }
}

public struct VoiceTrailPlaybackPresence: Codable, Equatable, Sendable {
  public var userID: InstantID<VoiceTrailUser>
  public var displayName: String
  public var isPlaying: Bool
  public var offsetSeconds: Double
  public var focusedSegmentID: String?

  public init(
    userID: InstantID<VoiceTrailUser>,
    displayName: String,
    isPlaying: Bool,
    offsetSeconds: Double,
    focusedSegmentID: String? = nil
  ) {
    self.userID = userID
    self.displayName = displayName
    self.isPlaying = isPlaying
    self.offsetSeconds = offsetSeconds
    self.focusedSegmentID = focusedSegmentID
  }
}

public struct VoiceTrailReaction: Codable, Equatable, Sendable {
  public var emoji: String
  public var offsetSeconds: Double

  public init(emoji: String, offsetSeconds: Double) {
    self.emoji = emoji
    self.offsetSeconds = offsetSeconds
  }
}

public struct VoiceTrailCommentDraft: Codable, Equatable, Sendable {
  public var text: String
  public var offsetSeconds: Double

  public init(text: String, offsetSeconds: Double) {
    self.text = text
    self.offsetSeconds = offsetSeconds
  }
}

public struct VoiceTrailCommentCommitted: Codable, Equatable, Sendable {
  public var commentID: String

  public init(commentID: String) {
    self.commentID = commentID
  }
}

public enum VoiceTrailRecordingAudio: InstantStoredFileMatcher {
  public static func matches(_ file: InstantStoredFile) -> Bool {
    file.contentType?.hasPrefix("audio/") == true
  }
}
