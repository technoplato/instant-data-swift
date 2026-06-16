import Foundation

public struct LocalIntegrationValidationDetails: Codable, Equatable, Sendable {
  public var cachePath: String
  public var authUserID: String?
  public var roomType: String?
  public var roomID: String?
  public var topic: String?
  public var roomMemberIDs: [String]
  public var roomPresenceValueKeys: [String]
  public var topicMessageIDs: [String]
  public var topicPayloadKeys: [String]
  public var fileIDs: [String]
  public var fileByteCounts: [Int64]
  public var fileContentDigests: [String]
  public var streamChunkIDs: [String]
  public var activeShareIDs: [String]
  public var revokedShareIDs: [String]
  public var shareMemberUserIDs: [String]

  public init(
    cachePath: String,
    authUserID: String?,
    roomType: String? = nil,
    roomID: String? = nil,
    topic: String? = nil,
    roomMemberIDs: [String] = [],
    roomPresenceValueKeys: [String] = [],
    topicMessageIDs: [String] = [],
    topicPayloadKeys: [String] = [],
    fileIDs: [String] = [],
    fileByteCounts: [Int64] = [],
    fileContentDigests: [String] = [],
    streamChunkIDs: [String] = [],
    activeShareIDs: [String] = [],
    revokedShareIDs: [String] = [],
    shareMemberUserIDs: [String] = []
  ) {
    self.cachePath = cachePath
    self.authUserID = authUserID
    self.roomType = roomType
    self.roomID = roomID
    self.topic = topic
    self.roomMemberIDs = roomMemberIDs
    self.roomPresenceValueKeys = roomPresenceValueKeys
    self.topicMessageIDs = topicMessageIDs
    self.topicPayloadKeys = topicPayloadKeys
    self.fileIDs = fileIDs
    self.fileByteCounts = fileByteCounts
    self.fileContentDigests = fileContentDigests
    self.streamChunkIDs = streamChunkIDs
    self.activeShareIDs = activeShareIDs
    self.revokedShareIDs = revokedShareIDs
    self.shareMemberUserIDs = shareMemberUserIDs
  }
}

public struct LocalIntegrationValidationResult: Sendable {
  public var appID: String
  public var cacheURL: URL
  public var evidence: [ValidationEvidenceRow<LocalIntegrationValidationDetails>]

  public init(
    appID: String,
    cacheURL: URL,
    evidence: [ValidationEvidenceRow<LocalIntegrationValidationDetails>]
  ) {
    self.appID = appID
    self.cacheURL = cacheURL
    self.evidence = evidence
  }
}

public enum InstantSwiftDataLocalIntegrationValidation {
  public static func run(
    appID: String = "local-validation",
    cacheURL: URL? = nil,
    timestamp: @escaping @Sendable () -> InstantTimestamp = {
      InstantTimestamp(milliseconds: Int64((Date().timeIntervalSince1970 * 1000).rounded()))
    },
    makeID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() }
  ) async throws -> LocalIntegrationValidationResult {
    let cacheURL =
      cacheURL
      ?? FileManager.default.temporaryDirectory
        .appendingPathComponent("InstantSwiftDataValidation-\(makeID())", isDirectory: true)
        .appendingPathComponent("state.sqlite")
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: appID,
        persistenceURL: cacheURL,
        now: timestamp,
        makeID: makeID
      )
    )
    let room = InstantRoomHandle(type: "chat", id: "validation")
    let topic = "sendEmoji"
    let streamID = "chat/validation"
    var evidence: [ValidationEvidenceRow<LocalIntegrationValidationDetails>] = []

    let ownerSession = try await runtime.signInWithRefreshToken("owner-refresh", userID: "user-1")
    guard ownerSession.userID == "user-1" else {
      throw validationError(
        operation: "validate local integrations auth",
        message: "Expected owner auth session to use user-1."
      )
    }
    evidence.append(
      try await evidenceRow(
        event: "auth",
        runtime: runtime,
        cacheURL: cacheURL,
        room: room,
        topic: topic,
        streamID: streamID,
        timestamp: timestamp
      )
    )

    let member = try await runtime.setPresence(
      room: room,
      values: ["name": .string("Ada"), "status": .string("online")]
    )
    guard member.userID == "user-1" else {
      throw validationError(
        operation: "validate local integrations presence",
        message: "Expected room presence to use the signed-in owner."
      )
    }
    evidence.append(
      try await evidenceRow(
        event: "room-presence",
        runtime: runtime,
        cacheURL: cacheURL,
        room: room,
        topic: topic,
        streamID: streamID,
        timestamp: timestamp
      )
    )

    let message = try await runtime.publishTopicMessage(
      room: room,
      topic: topic,
      payload: .object(["emoji": .string("wave")])
    )
    guard message.userID == "user-1" else {
      throw validationError(
        operation: "validate local integrations topic",
        message: "Expected room topic message to use the signed-in owner."
      )
    }
    evidence.append(
      try await evidenceRow(
        event: "room-topic",
        runtime: runtime,
        cacheURL: cacheURL,
        room: room,
        topic: topic,
        streamID: streamID,
        timestamp: timestamp
      )
    )

    let fileData = Data("local integration file\n".utf8)
    let sourceURL = cacheURL.deletingLastPathComponent()
      .appendingPathComponent("local-integration-file.txt")
    try FileManager.default.createDirectory(
      at: sourceURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try fileData.write(to: sourceURL)
    let file = try await runtime.uploadFile(
      from: sourceURL,
      name: "integration.txt",
      contentType: "text/plain"
    )
    let contents = try await runtime.storedFileContents(id: file.id)
    guard contents.data == fileData else {
      throw validationError(
        operation: "validate local integrations file",
        message: "Expected stored file contents to match the uploaded local bytes."
      )
    }
    evidence.append(
      try await evidenceRow(
        event: "file",
        runtime: runtime,
        cacheURL: cacheURL,
        room: room,
        topic: topic,
        streamID: streamID,
        timestamp: timestamp
      )
    )

    let chunk = try await runtime.appendStreamChunk(
      streamID: streamID,
      payload: .object(["text": .string("hello stream")])
    )
    guard chunk.userID == "user-1" else {
      throw validationError(
        operation: "validate local integrations stream",
        message: "Expected stream chunk to use the signed-in owner."
      )
    }
    evidence.append(
      try await evidenceRow(
        event: "stream",
        runtime: runtime,
        cacheURL: cacheURL,
        room: room,
        topic: topic,
        streamID: streamID,
        timestamp: timestamp
      )
    )

    let createdShare = try await runtime.createShare(
      rootNamespace: "remindersLists",
      rootID: "list-1"
    )
    guard createdShare.memberships.map(\.userID) == ["user-1"] else {
      throw validationError(
        operation: "validate local integrations share create",
        message: "Expected share creation to record the owner membership."
      )
    }
    evidence.append(
      try await evidenceRow(
        event: "share-create",
        runtime: runtime,
        cacheURL: cacheURL,
        room: room,
        topic: topic,
        streamID: streamID,
        timestamp: timestamp
      )
    )

    _ = try await runtime.signInWithRefreshToken("invitee-refresh", userID: "user-2")
    let acceptedShare = try await runtime.acceptShare(token: createdShare.share.token)
    guard acceptedShare.memberships.map(\.userID).sorted() == ["user-1", "user-2"] else {
      throw validationError(
        operation: "validate local integrations share accept",
        message: "Expected accepted share to include owner and invitee memberships."
      )
    }
    evidence.append(
      try await evidenceRow(
        event: "share-accept",
        runtime: runtime,
        cacheURL: cacheURL,
        room: room,
        topic: topic,
        streamID: streamID,
        timestamp: timestamp
      )
    )

    _ = try await runtime.signInWithRefreshToken("owner-refresh", userID: "user-1")
    let revokedShare = try await runtime.revokeShare(id: createdShare.share.id)
    guard revokedShare.share.isRevoked else {
      throw validationError(
        operation: "validate local integrations share revoke",
        message: "Expected owner revoke to mark the share revoked."
      )
    }
    evidence.append(
      try await evidenceRow(
        event: "share-revoke",
        runtime: runtime,
        cacheURL: cacheURL,
        room: room,
        topic: topic,
        streamID: streamID,
        timestamp: timestamp,
        revokedShares: [revokedShare]
      )
    )

    let relaunchedRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: appID,
        persistenceURL: cacheURL,
        now: timestamp,
        makeID: makeID
      )
    )
    guard try await relaunchedRuntime.authSession()?.userID == "user-1" else {
      throw validationError(
        operation: "validate local integrations relaunch",
        message: "Expected auth session to persist across relaunch."
      )
    }
    evidence.append(
      try await evidenceRow(
        event: "relaunch",
        runtime: relaunchedRuntime,
        cacheURL: cacheURL,
        room: room,
        topic: topic,
        streamID: streamID,
        timestamp: timestamp
      )
    )

    return LocalIntegrationValidationResult(appID: appID, cacheURL: cacheURL, evidence: evidence)
  }

  private static func evidenceRow(
    event: String,
    runtime: InstantRuntime,
    cacheURL: URL,
    room: InstantRoomHandle,
    topic: String,
    streamID: String,
    timestamp: @escaping @Sendable () -> InstantTimestamp,
    revokedShares: [InstantShareSnapshot] = []
  ) async throws -> ValidationEvidenceRow<LocalIntegrationValidationDetails> {
    let session = try await runtime.authSession()
    let presence = try await runtime.roomPresence(room: room)
    let topicMessages = try await runtime.roomTopicMessages(room: room, topic: topic)
    let files = try await runtime.storedFiles()
    var fileContents: [InstantStoredFileContents] = []
    for file in files {
      fileContents.append(try await runtime.storedFileContents(id: file.id))
    }
    let chunks = try await runtime.streamChunks(streamID: streamID)
    let activeShares = try await runtime.shares()
    let allShareMemberships = (activeShares + revokedShares).flatMap(\.memberships)

    return ValidationEvidenceRow(
      caseID: "validation.local.integrations",
      side: "swift",
      event: event,
      appID: runtime.configuration.appID,
      timestampMs: timestamp().milliseconds,
      ok: true,
      details: LocalIntegrationValidationDetails(
        cachePath: cacheURL.path,
        authUserID: session?.userID,
        roomType: room.type,
        roomID: room.id,
        topic: topic,
        roomMemberIDs: presence.map(\.userID).sorted(),
        roomPresenceValueKeys: sortedObjectKeys(in: presence.map(\.values)),
        topicMessageIDs: topicMessages.map(\.id),
        topicPayloadKeys: sortedObjectKeys(in: topicMessages.map(\.payload)),
        fileIDs: files.map(\.id),
        fileByteCounts: fileContents.map(\.byteCount),
        fileContentDigests: fileContents.map { contentDigest($0.data) },
        streamChunkIDs: chunks.map(\.id),
        activeShareIDs: activeShares.map(\.share.id),
        revokedShareIDs: revokedShares.map(\.share.id),
        shareMemberUserIDs: Array(Set(allShareMemberships.map(\.userID))).sorted()
      )
    )
  }

  private static func sortedObjectKeys(in objects: [[String: JSONValue]]) -> [String] {
    Array(Set(objects.flatMap(\.keys))).sorted()
  }

  private static func sortedObjectKeys(in values: [JSONValue]) -> [String] {
    Array(
      Set(
        values.flatMap { value -> [String] in
          guard case let .object(object) = value else { return [] }
          return Array(object.keys)
        }
      )
    )
    .sorted()
  }

  private static func contentDigest(_ data: Data) -> String {
    var hash: UInt64 = 0xcbf29ce484222325
    for byte in data {
      hash ^= UInt64(byte)
      hash &*= 0x100000001b3
    }
    let hex = String(hash, radix: 16)
    return "fnv1a64:" + String(repeating: "0", count: max(0, 16 - hex.count)) + hex
  }

  private static func validationError(operation: String, message: String) -> InstantError {
    InstantError(
      code: .validationFailed,
      operation: operation,
      message: message,
      recovery: "Inspect the local integration validation runtime step that emitted the failure."
    )
  }
}
