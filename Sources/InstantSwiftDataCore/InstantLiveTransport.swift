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

    case let .bool(value):
      try container.encode(value)

    case let .number(value):
      if value.isFinite,
        value.rounded() == value,
        value >= Double(Int64.min),
        value <= Double(Int64.max)
      {
        try container.encode(Int64(value))
      } else {
        try container.encode(value)
      }

    case let .string(value):
      try container.encode(value)

    case let .array(values):
      try container.encode(values)

    case let .object(values):
      try container.encode(values)
    }
  }

  public var stringValue: String? {
    guard case let .string(value) = self else { return nil }
    return value
  }

  public var arrayValue: [InstantLiveJSONValue]? {
    guard case let .array(value) = self else { return nil }
    return value
  }

  public var objectValue: [String: InstantLiveJSONValue]? {
    guard case let .object(value) = self else { return nil }
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

  public init(
    clientEventID: String?,
    message: String,
    status: Int? = nil,
    type: String? = nil,
    hint: InstantLiveJSONValue? = nil
  ) {
    self.clientEventID = clientEventID
    self.message = message
    self.status = status
    self.type = type
    self.hint = hint
  }
}

public enum InstantLiveServerEvent: Hashable, Sendable {
  case initOK(InstantLiveInitOK)
  case addQueryOK(InstantLiveQueryOK)
  case addQueryExists(InstantLiveQueryOK)
  case refreshOK(InstantLiveRefreshOK)
  case transactOK(InstantLiveTransactOK)
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

    case "error":
      self = .error(
        InstantLiveErrorMessage(
          clientEventID: message.clientEventID,
          message: message.fields["message"]?.stringValue ?? "Instant live transport error.",
          status: message.fields["status"]?.intValue,
          type: message.fields["type"]?.stringValue,
          hint: message.fields["hint"]
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
    case let .addQueryOK(message):
      return message.op
    case let .addQueryExists(message):
      return message.op
    case .refreshOK:
      return "refresh-ok"
    case .transactOK:
      return "transact-ok"
    case .error:
      return "error"
    case let .other(message):
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
        recovery: "Pass an Instant runtime WebSocket URI such as wss://api.instantdb.com/runtime/session."
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
  public var connect: @Sendable (InstantLiveSessionRequest) async throws
    -> InstantLiveWebSocketSession

  public init(
    connect: @escaping @Sendable (InstantLiveSessionRequest) async throws
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

private extension InstantLiveJSONValue {
  init(jsonObject: Any) throws {
    switch jsonObject {
    case _ as NSNull:
      self = .null

    case let value as Bool:
      self = .bool(value)

    case let value as Int:
      self = .number(Double(value))

    case let value as Int64:
      self = .number(Double(value))

    case let value as Double:
      self = .number(value)

    case let value as String:
      self = .string(value)

    case let values as [Any]:
      self = .array(try values.map(Self.init(jsonObject:)))

    case let values as [String: Any]:
      self = .object(try values.mapValues(Self.init(jsonObject:)))

    case let value as NSNumber:
      self = .number(value.doubleValue)

    default:
      throw InstantError(
        code: .decodeFailed,
        operation: "encode Instant live JSON value",
        message: "Unsupported JSON object in live transport payload.",
        recovery: "Ensure the live transport payload contains JSON-compatible values."
      )
    }
  }

  var intValue: Int? {
    guard case let .number(value) = self,
      value.isFinite,
      value.rounded() == value,
      value >= Double(Int.min),
      value <= Double(Int.max)
    else {
      return nil
    }
    return Int(value)
  }

  var scalarStringValue: String? {
    switch self {
    case let .string(value):
      return value
    case let .number(value):
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

private actor InstantURLSessionLiveWebSocket {
  private let urlSession: URLSession
  private let task: URLSessionWebSocketTask

  init(url: URL) throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 10
    configuration.timeoutIntervalForResource = 30
    self.urlSession = URLSession(configuration: configuration)
    self.task = urlSession.webSocketTask(with: url)
    self.task.resume()
  }

  func send(_ message: InstantLiveMessage) async throws {
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
  }

  func receive() async throws -> InstantLiveMessage {
    switch try await task.receive() {
    case let .string(string):
      guard let data = string.data(using: .utf8) else {
        throw InstantError(
          code: .decodeFailed,
          operation: "decode Instant live WebSocket string",
          message: "Received WebSocket string was not valid UTF-8.",
          recovery: "Inspect the Instant live WebSocket response payload."
        )
      }
      return try JSONDecoder().decode(InstantLiveMessage.self, from: data)

    case let .data(data):
      return try JSONDecoder().decode(InstantLiveMessage.self, from: data)

    @unknown default:
      throw InstantError(
        code: .decodeFailed,
        operation: "decode Instant live WebSocket message",
        message: "Received an unsupported WebSocket message kind.",
        recovery: "Update the live transport to handle new WebSocket message kinds."
      )
    }
  }

  func close() async {
    task.cancel(with: .normalClosure, reason: nil)
    urlSession.invalidateAndCancel()
  }
}
