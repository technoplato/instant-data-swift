import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

public enum InstantLiveJSONValue: Hashable, Codable, Sendable {
  case null
  case bool(Bool)
  case number(Double)
  case string(String)
  case array([InstantLiveJSONValue])
  case object([String: InstantLiveJSONValue])

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()

    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Int.self) {
      self = .number(Double(value))
    } else if let value = try? container.decode(Double.self) {
      self = .number(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([InstantLiveJSONValue].self) {
      self = .array(value)
    } else if let value = try? container.decode([String: InstantLiveJSONValue].self) {
      self = .object(value)
    } else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Unsupported Instant live JSON value."
      )
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .null:
      try container.encodeNil()

    case .bool(let value):
      try container.encode(value)

    case .number(let value):
      if value.isFinite,
        value.rounded() == value,
        value >= Double(Int64.min),
        value <= Double(Int64.max)
      {
        try container.encode(Int64(value))
      } else {
        try container.encode(value)
      }

    case .string(let value):
      try container.encode(value)

    case .array(let values):
      try container.encode(values)

    case .object(let values):
      try container.encode(values)
    }
  }

  public var stringValue: String? {
    guard case .string(let value) = self else { return nil }
    return value
  }

  public var arrayValue: [InstantLiveJSONValue]? {
    guard case .array(let value) = self else { return nil }
    return value
  }

  public var objectValue: [String: InstantLiveJSONValue]? {
    guard case .object(let value) = self else { return nil }
    return value
  }
}

public struct InstantLiveMessage: Hashable, Codable, Sendable {
  public var op: String
  public var clientEventID: String?
  public var fields: [String: InstantLiveJSONValue]

  public init(
    op: String,
    clientEventID: String? = nil,
    fields: [String: InstantLiveJSONValue] = [:]
  ) {
    self.op = op
    self.clientEventID = clientEventID
    self.fields = fields
  }

  private enum CodingKeys: String, CodingKey {
    case op
    case clientEventID = "client-event-id"
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let op = try container.decode(String.self, forKey: .op)
    let clientEventID = try container.decodeIfPresent(String.self, forKey: .clientEventID)

    let dynamicContainer = try decoder.container(keyedBy: InstantLiveDynamicCodingKey.self)
    var fields: [String: InstantLiveJSONValue] = [:]
    for key in dynamicContainer.allKeys {
      guard key.stringValue != CodingKeys.op.rawValue,
        key.stringValue != CodingKeys.clientEventID.rawValue
      else {
        continue
      }
      fields[key.stringValue] = try dynamicContainer.decode(InstantLiveJSONValue.self, forKey: key)
    }

    self.init(op: op, clientEventID: clientEventID, fields: fields)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(op, forKey: .op)
    try container.encodeIfPresent(clientEventID, forKey: .clientEventID)

    var dynamicContainer = encoder.container(keyedBy: InstantLiveDynamicCodingKey.self)
    for key in fields.keys.sorted() {
      try dynamicContainer.encode(
        fields[key],
        forKey: InstantLiveDynamicCodingKey(stringValue: key)
      )
    }
  }
}

extension InstantLiveMessage {
  public static func initMessage(
    appID: String,
    refreshToken: String? = nil,
    adminToken: String? = nil,
    clientEventID: String,
    versions: [String: String] = ["InstantDB-Swift": "0.1.0"]
  ) -> Self {
    var fields: [String: InstantLiveJSONValue] = [
      "app-id": .string(appID),
      "versions": .object(versions.mapValues(InstantLiveJSONValue.string)),
    ]
    if let refreshToken, !refreshToken.isEmpty {
      fields["refresh-token"] = .string(refreshToken)
    }
    if let adminToken, !adminToken.isEmpty {
      fields["__admin-token"] = .string(adminToken)
    }
    return Self(op: "init", clientEventID: clientEventID, fields: fields)
  }

  public static func addQuery(
    _ query: InstantLiveJSONValue,
    clientEventID: String
  ) -> Self {
    Self(
      op: "add-query",
      clientEventID: clientEventID,
      fields: ["q": query]
    )
  }

  public static func removeQuery(
    _ query: InstantLiveJSONValue,
    clientEventID: String
  ) -> Self {
    Self(
      op: "remove-query",
      clientEventID: clientEventID,
      fields: ["q": query]
    )
  }

  public static func transact(
    _ txSteps: [InstantTransportStep],
    clientEventID: String
  ) throws -> Self {
    let data = try JSONEncoder().encode(txSteps)
    let jsonObject = try JSONSerialization.jsonObject(with: data)
    return Self(
      op: "transact",
      clientEventID: clientEventID,
      fields: ["tx-steps": try InstantLiveJSONValue(jsonObject: jsonObject)]
    )
  }

  public static func joinRoom(
    _ room: InstantRoomHandle,
    presence: [String: JSONValue]? = nil,
    clientEventID: String
  ) -> Self {
    var fields: [String: InstantLiveJSONValue] = [
      "room-id": .string(room.id),
      "room-type": .string(room.type),
    ]
    if let presence {
      fields["data"] = .object(presence.mapValues(InstantLiveJSONValue.init))
    }
    return Self(op: "join-room", clientEventID: clientEventID, fields: fields)
  }

  public static func leaveRoom(
    _ room: InstantRoomHandle,
    clientEventID: String
  ) -> Self {
    Self(
      op: "leave-room",
      clientEventID: clientEventID,
      fields: ["room-id": .string(room.id)]
    )
  }

  public static func setPresence(
    room: InstantRoomHandle,
    values: [String: JSONValue],
    clientEventID: String
  ) -> Self {
    Self(
      op: "set-presence",
      clientEventID: clientEventID,
      fields: [
        "data": .object(values.mapValues(InstantLiveJSONValue.init)),
        "room-id": .string(room.id),
      ]
    )
  }

  public static func clientBroadcast(
    room: InstantRoomHandle,
    topic: String,
    payload: JSONValue,
    clientEventID: String
  ) -> Self {
    Self(
      op: "client-broadcast",
      clientEventID: clientEventID,
      fields: [
        "data": InstantLiveJSONValue(payload),
        "room-id": .string(room.id),
        "roomType": .string(room.type),
        "topic": .string(topic),
      ]
    )
  }
}

public struct InstantLiveInitOK: Hashable, Sendable {
  public var clientEventID: String?
  public var sessionID: String
  public var attrs: [InstantLiveJSONValue]
  public var auth: InstantLiveJSONValue?

  public init(
    clientEventID: String?,
    sessionID: String,
    attrs: [InstantLiveJSONValue],
    auth: InstantLiveJSONValue? = nil
  ) {
    self.clientEventID = clientEventID
    self.sessionID = sessionID
    self.attrs = attrs
    self.auth = auth
  }
}

public struct InstantLiveQueryOK: Hashable, Sendable {
  public var op: String
  public var clientEventID: String?
  public var query: InstantLiveJSONValue?
  public var result: [InstantLiveJSONValue]
  public var processedTransactionID: String?

  public init(
    op: String,
    clientEventID: String?,
    query: InstantLiveJSONValue?,
    result: [InstantLiveJSONValue],
    processedTransactionID: String? = nil
  ) {
    self.op = op
    self.clientEventID = clientEventID
    self.query = query
    self.result = result
    self.processedTransactionID = processedTransactionID
  }
}

public struct InstantLiveRefreshOK: Hashable, Sendable {
  public var clientEventID: String?
  public var processedTransactionID: String?
  public var attrs: [InstantLiveJSONValue]
  public var computations: [InstantLiveJSONValue]

  public init(
    clientEventID: String?,
    processedTransactionID: String?,
    attrs: [InstantLiveJSONValue],
    computations: [InstantLiveJSONValue]
  ) {
    self.clientEventID = clientEventID
    self.processedTransactionID = processedTransactionID
    self.attrs = attrs
    self.computations = computations
  }
}

public struct InstantLiveTransactOK: Hashable, Sendable {
  public var clientEventID: String?
  public var transactionID: String?
  public var isn: String?

  public init(clientEventID: String?, transactionID: String?, isn: String? = nil) {
    self.clientEventID = clientEventID
    self.transactionID = transactionID
    self.isn = isn
  }
}

public struct InstantLiveErrorMessage: Hashable, Sendable {
  public var clientEventID: String?
  public var message: String
  public var status: Int?
  public var type: String?
  public var hint: InstantLiveJSONValue?
  public var originalEvent: InstantLiveMessage?

  public init(
    clientEventID: String?,
    message: String,
    status: Int? = nil,
    type: String? = nil,
    hint: InstantLiveJSONValue? = nil,
    originalEvent: InstantLiveMessage? = nil
  ) {
    self.clientEventID = clientEventID
    self.message = message
    self.status = status
    self.type = type
    self.hint = hint
    self.originalEvent = originalEvent
  }
}

public struct InstantLiveRoomOK: Hashable, Sendable {
  public var op: String
  public var clientEventID: String?
  public var roomID: String

  public init(op: String, clientEventID: String?, roomID: String) {
    self.op = op
    self.clientEventID = clientEventID
    self.roomID = roomID
  }
}

public struct InstantLivePresenceRefresh: Hashable, Sendable {
  public var clientEventID: String?
  public var roomID: String
  public var sessions: [String: InstantLiveJSONValue]

  public init(
    clientEventID: String?,
    roomID: String,
    sessions: [String: InstantLiveJSONValue]
  ) {
    self.clientEventID = clientEventID
    self.roomID = roomID
    self.sessions = sessions
  }
}

public struct InstantLivePresencePatch: Hashable, Sendable {
  public var clientEventID: String?
  public var roomID: String
  public var edits: [InstantLiveJSONValue]

  public init(
    clientEventID: String?,
    roomID: String,
    edits: [InstantLiveJSONValue]
  ) {
    self.clientEventID = clientEventID
    self.roomID = roomID
    self.edits = edits
  }
}

public struct InstantLiveServerBroadcast: Hashable, Sendable {
  public var clientEventID: String?
  public var roomID: String
  public var topic: String
  public var envelope: InstantLiveJSONValue?

  public init(
    clientEventID: String?,
    roomID: String,
    topic: String,
    envelope: InstantLiveJSONValue?
  ) {
    self.clientEventID = clientEventID
    self.roomID = roomID
    self.topic = topic
    self.envelope = envelope
  }
}

public struct InstantLiveStreamFile: Hashable, Sendable {
  public var url: String
  public var size: Int64

  public init(url: String, size: Int64) {
    self.url = url
    self.size = size
  }
}

public struct InstantLiveStreamAppend: Hashable, Sendable {
  public var clientEventID: String?
  public var streamID: String
  public var clientID: String?
  public var files: [InstantLiveStreamFile]
  public var done: Bool
  public var abortReason: String?
  public var offset: Int64
  public var error: String?
  public var retry: Bool
  public var content: String?

  public init(
    clientEventID: String?,
    streamID: String,
    clientID: String? = nil,
    files: [InstantLiveStreamFile] = [],
    done: Bool = false,
    abortReason: String? = nil,
    offset: Int64,
    error: String? = nil,
    retry: Bool = false,
    content: String? = nil
  ) {
    self.clientEventID = clientEventID
    self.streamID = streamID
    self.clientID = clientID
    self.files = files
    self.done = done
    self.abortReason = abortReason
    self.offset = offset
    self.error = error
    self.retry = retry
    self.content = content
  }
}

public struct InstantLiveStartStreamOK: Hashable, Sendable {
  public var clientEventID: String?
  public var streamID: String
  public var clientID: String
  public var offset: Int64

  public init(clientEventID: String?, streamID: String, clientID: String, offset: Int64) {
    self.clientEventID = clientEventID
    self.streamID = streamID
    self.clientID = clientID
    self.offset = offset
  }
}

public struct InstantLiveStreamFlushed: Hashable, Sendable {
  public var streamID: String
  public var offset: Int64
  public var done: Bool

  public init(streamID: String, offset: Int64, done: Bool) {
    self.streamID = streamID
    self.offset = offset
    self.done = done
  }
}

public struct InstantLiveAppendFailed: Hashable, Sendable {
  public var streamID: String

  public init(streamID: String) {
    self.streamID = streamID
  }
}

public enum InstantLiveServerEvent: Hashable, Sendable {
  case initOK(InstantLiveInitOK)
  case addQueryOK(InstantLiveQueryOK)
  case addQueryExists(InstantLiveQueryOK)
  case refreshOK(InstantLiveRefreshOK)
  case transactOK(InstantLiveTransactOK)
  case joinRoomOK(InstantLiveRoomOK)
  case leaveRoomOK(InstantLiveRoomOK)
  case refreshPresence(InstantLivePresenceRefresh)
  case patchPresence(InstantLivePresencePatch)
  case serverBroadcast(InstantLiveServerBroadcast)
  case startStreamOK(InstantLiveStartStreamOK)
  case streamFlushed(InstantLiveStreamFlushed)
  case appendFailed(InstantLiveAppendFailed)
  case streamAppend(InstantLiveStreamAppend)
  case error(InstantLiveErrorMessage)
  case other(InstantLiveMessage)

  public init(message: InstantLiveMessage) {
    switch message.op {
    case "init-ok":
      self = .initOK(
        InstantLiveInitOK(
          clientEventID: message.clientEventID,
          sessionID: message.fields["session-id"]?.stringValue ?? "",
          attrs: message.fields["attrs"]?.arrayValue ?? [],
          auth: message.fields["auth"]
        )
      )

    case "add-query-ok":
      self = .addQueryOK(
        InstantLiveQueryOK(
          op: message.op,
          clientEventID: message.clientEventID,
          query: message.fields["q"],
          result: message.fields["result"]?.arrayValue ?? [],
          processedTransactionID: message.fields["processed-tx-id"]?.scalarStringValue
        )
      )

    case "add-query-exists":
      self = .addQueryExists(
        InstantLiveQueryOK(
          op: message.op,
          clientEventID: message.clientEventID,
          query: message.fields["q"],
          result: message.fields["result"]?.arrayValue ?? [],
          processedTransactionID: message.fields["processed-tx-id"]?.scalarStringValue
        )
      )

    case "refresh-ok":
      self = .refreshOK(
        InstantLiveRefreshOK(
          clientEventID: message.clientEventID,
          processedTransactionID: message.fields["processed-tx-id"]?.scalarStringValue,
          attrs: message.fields["attrs"]?.arrayValue ?? [],
          computations: message.fields["computations"]?.arrayValue ?? []
        )
      )

    case "transact-ok":
      self = .transactOK(
        InstantLiveTransactOK(
          clientEventID: message.clientEventID,
          transactionID: message.fields["tx-id"]?.scalarStringValue,
          isn: message.fields["isn"]?.scalarStringValue
        )
      )

    case "join-room-ok", "leave-room-ok":
      let room = InstantLiveRoomOK(
        op: message.op,
        clientEventID: message.clientEventID,
        roomID: message.fields["room-id"]?.stringValue ?? ""
      )
      self = message.op == "join-room-ok" ? .joinRoomOK(room) : .leaveRoomOK(room)

    case "refresh-presence":
      self = .refreshPresence(
        InstantLivePresenceRefresh(
          clientEventID: message.clientEventID,
          roomID: message.fields["room-id"]?.stringValue ?? "",
          sessions: message.fields["data"]?.objectValue ?? [:]
        )
      )

    case "patch-presence":
      self = .patchPresence(
        InstantLivePresencePatch(
          clientEventID: message.clientEventID,
          roomID: message.fields["room-id"]?.stringValue ?? "",
          edits: message.fields["edits"]?.arrayValue ?? []
        )
      )

    case "server-broadcast":
      self = .serverBroadcast(
        InstantLiveServerBroadcast(
          clientEventID: message.clientEventID,
          roomID: message.fields["room-id"]?.stringValue ?? "",
          topic: message.fields["topic"]?.stringValue ?? "",
          envelope: message.fields["data"]
        )
      )

    case "start-stream-ok":
      self = .startStreamOK(
        InstantLiveStartStreamOK(
          clientEventID: message.clientEventID,
          streamID: message.fields["stream-id"]?.stringValue ?? "",
          clientID: message.fields["client-id"]?.stringValue ?? "",
          offset: Int64(message.fields["offset"]?.intValue ?? 0)
        )
      )

    case "stream-flushed":
      self = .streamFlushed(
        InstantLiveStreamFlushed(
          streamID: message.fields["stream-id"]?.stringValue ?? "",
          offset: Int64(message.fields["offset"]?.intValue ?? 0),
          done: message.fields["done"]?.booleanValue ?? false
        )
      )

    case "append-failed":
      self = .appendFailed(
        InstantLiveAppendFailed(
          streamID: message.fields["stream-id"]?.stringValue ?? ""
        )
      )

    case "stream-append":
      let files: [InstantLiveStreamFile] =
        (message.fields["files"]?.arrayValue ?? []).compactMap { value in
          guard let object = value.objectValue,
            let url = object["url"]?.stringValue,
            let size = object["size"]?.intValue
          else {
            return nil
          }
          return InstantLiveStreamFile(url: url, size: Int64(size))
        }
      self = .streamAppend(
        InstantLiveStreamAppend(
          clientEventID: message.clientEventID,
          streamID: message.fields["stream-id"]?.stringValue ?? "",
          clientID: message.fields["client-id"]?.stringValue,
          files: files,
          done: message.fields["done"] == .bool(true),
          abortReason: message.fields["abort-reason"]?.stringValue,
          offset: Int64(message.fields["offset"]?.intValue ?? 0),
          error: message.fields["error"]?.stringValue,
          retry: message.fields["retry"] == .bool(true),
          content: message.fields["content"]?.stringValue
        )
      )

    case "error":
      let originalEvent = message.fields["original-event"]?.objectValue.flatMap {
        object -> InstantLiveMessage? in
        guard let op = object["op"]?.stringValue else { return nil }
        var fields = object
        fields["op"] = nil
        let clientEventID = fields.removeValue(forKey: "client-event-id")?.stringValue
        return InstantLiveMessage(op: op, clientEventID: clientEventID, fields: fields)
      }
      self = .error(
        InstantLiveErrorMessage(
          clientEventID: message.clientEventID,
          message: message.fields["message"]?.stringValue ?? "Instant live transport error.",
          status: message.fields["status"]?.intValue,
          type: message.fields["type"]?.stringValue,
          hint: message.fields["hint"],
          originalEvent: originalEvent
        )
      )

    default:
      self = .other(message)
    }
  }

  public var op: String {
    switch self {
    case .initOK:
      return "init-ok"
    case .addQueryOK(let message):
      return message.op
    case .addQueryExists(let message):
      return message.op
    case .refreshOK:
      return "refresh-ok"
    case .transactOK:
      return "transact-ok"
    case .joinRoomOK(let message):
      return message.op
    case .leaveRoomOK(let message):
      return message.op
    case .refreshPresence:
      return "refresh-presence"
    case .patchPresence:
      return "patch-presence"
    case .serverBroadcast:
      return "server-broadcast"
    case .startStreamOK:
      return "start-stream-ok"
    case .streamFlushed:
      return "stream-flushed"
    case .appendFailed:
      return "append-failed"
    case .streamAppend:
      return "stream-append"
    case .error:
      return "error"
    case .other(let message):
      return message.op
    }
  }
}

public struct InstantLiveSessionRequest: Hashable, Sendable {
  public var appID: String
  public var websocketURI: URL
  public var refreshToken: String?
  public var adminToken: String?
  public var versions: [String: String]

  public init(
    appID: String,
    websocketURI: URL = InstantRuntimeConfiguration.defaultWebSocketURI,
    refreshToken: String? = nil,
    adminToken: String? = nil,
    versions: [String: String] = ["InstantDB-Swift": "0.1.0"]
  ) {
    self.appID = appID
    self.websocketURI = websocketURI
    self.refreshToken = refreshToken
    self.adminToken = adminToken
    self.versions = versions
  }

  public func sessionURL() throws -> URL {
    guard var components = URLComponents(url: websocketURI, resolvingAgainstBaseURL: false),
      components.host?.isEmpty == false
    else {
      throw InstantError(
        code: .validationFailed,
        operation: "build Instant live WebSocket URL",
        path: "websocketURI",
        message: "The WebSocket URI must be absolute and include a host.",
        recovery:
          "Pass an Instant runtime WebSocket URI such as wss://api.instantdb.com/runtime/session."
      )
    }
    var queryItems = components.queryItems ?? []
    queryItems.removeAll { $0.name == "app_id" }
    queryItems.append(URLQueryItem(name: "app_id", value: appID))
    components.queryItems = queryItems
    guard let url = components.url else {
      throw InstantError(
        code: .validationFailed,
        operation: "build Instant live WebSocket URL",
        path: "websocketURI",
        message: "The WebSocket URI could not be encoded with an app_id query item.",
        recovery: "Check the app id and WebSocket URI before opening the live session."
      )
    }
    return url
  }

  public func initMessage(clientEventID: String) -> InstantLiveMessage {
    .initMessage(
      appID: appID,
      refreshToken: refreshToken,
      adminToken: adminToken,
      clientEventID: clientEventID,
      versions: versions
    )
  }
}

public struct InstantLiveWebSocketSession: Sendable {
  public var send: @Sendable (InstantLiveMessage) async throws -> Void
  public var receive: @Sendable () async throws -> InstantLiveMessage
  public var close: @Sendable () async -> Void

  public init(
    send: @escaping @Sendable (InstantLiveMessage) async throws -> Void,
    receive: @escaping @Sendable () async throws -> InstantLiveMessage,
    close: @escaping @Sendable () async -> Void
  ) {
    self.send = send
    self.receive = receive
    self.close = close
  }
}

public struct InstantLiveTransportClient: Sendable {
  public var connect:
    @Sendable (InstantLiveSessionRequest) async throws
      -> InstantLiveWebSocketSession

  public init(
    connect:
      @escaping @Sendable (InstantLiveSessionRequest) async throws
      -> InstantLiveWebSocketSession
  ) {
    self.connect = connect
  }
}

func instantLiveWithTimeout<Value: Sendable>(
  operation: String,
  timeoutMilliseconds: UInt64,
  _ work: @escaping @Sendable () async throws -> Value
) async throws -> Value {
  guard timeoutMilliseconds > 0 else {
    return try await work()
  }
  return try await withThrowingTaskGroup(of: Value.self) { group in
    group.addTask {
      try await work()
    }
    group.addTask {
      try await Task.sleep(nanoseconds: timeoutMilliseconds * 1_000_000)
      throw InstantError(
        code: .networkFailed,
        operation: operation,
        message: "Timed out after \(timeoutMilliseconds)ms waiting for Instant live transport.",
        recovery: "Check the Instant WebSocket endpoint, credentials, and server response."
      )
    }
    guard let result = try await group.next() else {
      throw InstantError(
        code: .networkFailed,
        operation: operation,
        message: "Instant live transport finished without a result.",
        recovery: "Open a new live session and retry the operation."
      )
    }
    group.cancelAll()
    return result
  }
}

extension InstantLiveTransportClient {
  public static let local = Self { request in
    let session = InstantLocalLiveSession(appID: request.appID)
    return InstantLiveWebSocketSession(
      send: { message in
        await session.send(message)
      },
      receive: {
        try await session.receive()
      },
      close: {
        await session.close()
      }
    )
  }

  public static let live = Self { request in
    let socket = try InstantURLSessionLiveWebSocket(url: request.sessionURL())
    return InstantLiveWebSocketSession(
      send: { message in
        try await socket.send(message)
      },
      receive: {
        try await socket.receive()
      },
      close: {
        await socket.close()
      }
    )
  }
}

private struct InstantLiveDynamicCodingKey: CodingKey {
  var stringValue: String
  var intValue: Int?

  init(stringValue: String) {
    self.stringValue = stringValue
    self.intValue = nil
  }

  init(intValue: Int) {
    self.stringValue = String(intValue)
    self.intValue = intValue
  }
}

extension InstantLiveJSONValue {
  fileprivate init(_ value: JSONValue) {
    switch value {
    case .null:
      self = .null
    case .bool(let value):
      self = .bool(value)
    case .number(let value):
      self = .number(value)
    case .string(let value):
      self = .string(value)
    case .array(let values):
      self = .array(values.map(Self.init))
    case .object(let values):
      self = .object(values.mapValues(Self.init))
    }
  }

  fileprivate init(jsonObject: Any) throws {
    switch jsonObject {
    case _ as NSNull:
      self = .null

    case let value as NSNumber:
      if CFGetTypeID(value) == CFBooleanGetTypeID() {
        self = .bool(value.boolValue)
      } else {
        self = .number(value.doubleValue)
      }

    case let value as String:
      self = .string(value)

    case let values as [Any]:
      self = .array(try values.map(Self.init(jsonObject:)))

    case let values as [String: Any]:
      self = .object(try values.mapValues(Self.init(jsonObject:)))

    default:
      throw InstantError(
        code: .decodeFailed,
        operation: "encode Instant live JSON value",
        message: "Unsupported JSON object in live transport payload.",
        recovery: "Ensure the live transport payload contains JSON-compatible values."
      )
    }
  }

  fileprivate var intValue: Int? {
    guard case .number(let value) = self,
      value.isFinite,
      value.rounded() == value,
      value >= Double(Int.min),
      value <= Double(Int.max)
    else {
      return nil
    }
    return Int(value)
  }

  fileprivate var booleanValue: Bool? {
    guard case .bool(let value) = self else { return nil }
    return value
  }

  fileprivate var scalarStringValue: String? {
    switch self {
    case .string(let value):
      return value
    case .number(let value):
      guard value.isFinite else { return nil }
      if value.rounded() == value,
        value >= Double(Int64.min),
        value <= Double(Int64.max)
      {
        return String(Int64(value))
      }
      return String(value)
    default:
      return nil
    }
  }
}

extension InstantLiveJSONValue {
  var jsonValue: JSONValue {
    switch self {
    case .null:
      return .null
    case .bool(let value):
      return .bool(value)
    case .number(let value):
      return .number(value)
    case .string(let value):
      return .string(value)
    case .array(let values):
      return .array(values.map(\.jsonValue))
    case .object(let values):
      return .object(values.mapValues(\.jsonValue))
    }
  }
}

private actor InstantLocalLiveSession {
  private let appID: String
  private var pending: [InstantLiveMessage] = []
  private var isClosed = false
  private var hasQuery = false

  init(appID: String) {
    self.appID = appID
  }

  func send(_ message: InstantLiveMessage) {
    guard !isClosed else { return }
    switch message.op {
    case "init":
      pending.append(
        InstantLiveMessage(
          op: "init-ok",
          clientEventID: message.clientEventID,
          fields: [
            "attrs": .array([]),
            "auth": .null,
            "session-id": .string("local-session-\(appID)"),
          ]
        )
      )

    case "add-query":
      hasQuery = true
      pending.append(
        InstantLiveMessage(
          op: "add-query-ok",
          clientEventID: message.clientEventID,
          fields: [
            "q": message.fields["q"] ?? .object([:]),
            "result": .array([]),
          ]
        )
      )

    case "remove-query":
      hasQuery = false

    case "transact":
      let transactionID = "local-\(message.clientEventID ?? "transaction")"
      pending.append(
        InstantLiveMessage(
          op: "transact-ok",
          clientEventID: message.clientEventID,
          fields: [
            "isn": .string("local-isn-\(message.clientEventID ?? "transaction")"),
            "tx-id": .string(transactionID),
          ]
        )
      )
      if hasQuery {
        pending.append(
          InstantLiveMessage(
            op: "refresh-ok",
            clientEventID: message.clientEventID,
            fields: [
              "attrs": .array([]),
              "computations": .array([]),
              "processed-tx-id": .string(transactionID),
            ]
          )
        )
      }

    default:
      pending.append(
        InstantLiveMessage(
          op: "error",
          clientEventID: message.clientEventID,
          fields: [
            "message": .string("Unsupported local Instant live op '\(message.op)'."),
            "type": .string("unsupported-op"),
          ]
        )
      )
    }
  }

  func receive() throws -> InstantLiveMessage {
    guard !isClosed else {
      throw InstantError(
        code: .networkFailed,
        operation: "receive local Instant live message",
        message: "The local Instant live session is closed.",
        recovery: "Open a new live session before receiving messages."
      )
    }
    guard !pending.isEmpty else {
      throw InstantError(
        code: .networkFailed,
        operation: "receive local Instant live message",
        message: "No local Instant live messages are pending.",
        recovery: "Send an init or add-query message before awaiting a local response."
      )
    }
    return pending.removeFirst()
  }

  func close() {
    isClosed = true
    pending.removeAll()
  }
}

actor InstantURLSessionLiveWebSocket {
  private static let maximumMessageSize = 16 * 1_024 * 1_024
  private static let sharedURLSession: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.waitsForConnectivity = true
    configuration.timeoutIntervalForRequest = 10
    // A WebSocket is a long-lived resource. A short resource timeout closes an
    // otherwise healthy, idle room and silently drops presence/topic updates.
    configuration.timeoutIntervalForResource = 7 * 24 * 60 * 60
    return URLSession(configuration: configuration)
  }()

  private let task: URLSessionWebSocketTask
  private var isClosed = false

  var urlSessionIdentity: ObjectIdentifier {
    ObjectIdentifier(Self.sharedURLSession)
  }

  var waitsForConnectivity: Bool {
    Self.sharedURLSession.configuration.waitsForConnectivity
  }

  init(url: URL) throws {
    let task = Self.sharedURLSession.webSocketTask(with: url)
    task.maximumMessageSize = Self.maximumMessageSize
    self.task = task
    task.resume()
    InstantDiagnostics.shared.record(
      .debug,
      subsystem: "instant-swift-data-core",
      category: "network",
      event: "urlsession-websocket.resumed",
      message: "URLSession WebSocket task resumed.",
      metadata: [
        "host": url.host ?? "unknown",
        "maximumMessageSize": String(Self.maximumMessageSize),
        "scheme": url.scheme ?? "unknown",
      ]
    )
  }

  func send(_ message: InstantLiveMessage) async throws {
    do {
      let data = try JSONEncoder().encode(message)
      guard let string = String(data: data, encoding: .utf8) else {
        throw InstantError(
          code: .decodeFailed,
          operation: "send Instant live WebSocket message",
          message: "Encoded WebSocket message was not valid UTF-8.",
          recovery: "Inspect the live WebSocket message encoder."
        )
      }
      try await task.send(.string(string))
      InstantDiagnostics.shared.record(
        .trace,
        subsystem: "instant-swift-data-core",
        category: "network",
        event: "urlsession-websocket.frame-sent",
        message: "URLSession sent a WebSocket text frame.",
        metadata: [
          "op": message.op,
          "byteCount": String(data.count),
        ],
        correlationID: message.clientEventID
      )
    } catch {
      InstantDiagnostics.shared.record(
        error: error,
        subsystem: "instant-swift-data-core",
        category: "network",
        event: "urlsession-websocket.send-failed",
        message: "URLSession failed to send a WebSocket frame.",
        metadata: ["op": message.op],
        correlationID: message.clientEventID
      )
      throw error
    }
  }

  func receive() async throws -> InstantLiveMessage {
    do {
      let message: InstantLiveMessage
      let byteCount: Int
      switch try await task.receive() {
      case .string(let string):
        guard let data = string.data(using: .utf8) else {
          throw InstantError(
            code: .decodeFailed,
            operation: "decode Instant live WebSocket string",
            message: "Received WebSocket string was not valid UTF-8.",
            recovery: "Inspect the Instant live WebSocket response payload."
          )
        }
        byteCount = data.count
        message = try JSONDecoder().decode(InstantLiveMessage.self, from: data)

      case .data(let data):
        byteCount = data.count
        message = try JSONDecoder().decode(InstantLiveMessage.self, from: data)

      @unknown default:
        throw InstantError(
          code: .decodeFailed,
          operation: "decode Instant live WebSocket message",
          message: "Received an unsupported WebSocket message kind.",
          recovery: "Update the live transport to handle new WebSocket message kinds."
        )
      }
      InstantDiagnostics.shared.record(
        .trace,
        subsystem: "instant-swift-data-core",
        category: "network",
        event: "urlsession-websocket.frame-received",
        message: "URLSession received and decoded a WebSocket frame.",
        metadata: [
          "op": message.op,
          "byteCount": String(byteCount),
        ],
        correlationID: message.clientEventID
      )
      return message
    } catch {
      if isClosed || error is CancellationError {
        InstantDiagnostics.shared.record(
          .debug,
          subsystem: "instant-swift-data-core",
          category: "network",
          event: "urlsession-websocket.receive-ended-after-close",
          message: "The pending URLSession WebSocket receive ended after the session closed."
        )
      } else {
        InstantDiagnostics.shared.record(
          error: error,
          subsystem: "instant-swift-data-core",
          category: "network",
          event: "urlsession-websocket.receive-failed",
          message: "URLSession failed to receive or decode a WebSocket frame."
        )
      }
      throw error
    }
  }

  func close() async {
    guard !isClosed else { return }
    isClosed = true
    InstantDiagnostics.shared.record(
      .debug,
      subsystem: "instant-swift-data-core",
      category: "network",
      event: "urlsession-websocket.closing",
      message: "Closing the URLSession WebSocket task."
    )
    task.cancel()
  }
}
