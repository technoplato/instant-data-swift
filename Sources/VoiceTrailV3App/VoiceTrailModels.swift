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

  public static let instantNamespace = "v3_capture_recordings"
  public static let title = InstantAttributePath<Self, String>("title")
  public static let owner = InstantAttributePath<Self, InstantID<VoiceTrailUser>>("owner")
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

  public init(recordingID: InstantID<VoiceTrailRecording>) {
    self.recordingID = recordingID
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
      change: VoiceTrailRecordingCreated(recordingID: recordingID)
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

public struct VoiceTrailPlaybackRoom: InstantSwiftData.InstantRoomSchema {
  public typealias Presence = VoiceTrailPlaybackPresence

  public enum Topic: String, InstantRoomTopic {
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

public enum VoiceTrailRecordingAudio: InstantStoredFileMatcher {
  public static func matches(_ file: InstantStoredFile) -> Bool {
    file.contentType?.hasPrefix("audio/") == true
  }
}
