import Foundation

public struct InstantAuthHTTPResponse: Hashable, Codable, Sendable {
  public var statusCode: Int
  public var data: Data

  public init(statusCode: Int, data: Data) {
    self.statusCode = statusCode
    self.data = data
  }
}

public struct InstantAuthHTTPClient: Sendable {
  public var send: @Sendable (URLRequest) async throws -> InstantAuthHTTPResponse

  public init(
    send: @escaping @Sendable (URLRequest) async throws -> InstantAuthHTTPResponse
  ) {
    self.send = send
  }
}

extension InstantAuthHTTPClient {
  public static let live = Self { request in
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let response = response as? HTTPURLResponse else {
      throw InstantError(
        code: .networkFailed,
        operation: "perform Instant auth request",
        message: "Instant auth returned a non-HTTP response.",
        recovery: "Check the configured Instant API endpoint and network connection."
      )
    }
    return InstantAuthHTTPResponse(statusCode: response.statusCode, data: data)
  }
}

struct InstantVerifyRefreshTokenBody: Encodable {
  var appID: String
  var refreshToken: String

  private enum CodingKeys: String, CodingKey {
    case appID = "app-id"
    case refreshToken = "refresh-token"
  }
}

struct InstantSignOutBody: Encodable {
  var appID: String
  var refreshToken: String

  private enum CodingKeys: String, CodingKey {
    case appID = "app_id"
    case refreshToken = "refresh_token"
  }
}

struct InstantSendMagicCodeBody: Encodable {
  var appID: String
  var email: String

  private enum CodingKeys: String, CodingKey {
    case appID = "app-id"
    case email
  }
}

struct InstantVerifyMagicCodeBody: Encodable {
  var appID: String
  var email: String
  var code: String
  var refreshToken: String?
  var extraFields: [String: InstantValue]

  private enum CodingKeys: String, CodingKey {
    case appID = "app-id"
    case email
    case code
    case refreshToken = "refresh-token"
    case extraFields = "extra-fields"
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(appID, forKey: .appID)
    try container.encode(email, forKey: .email)
    try container.encode(code, forKey: .code)
    try container.encodeIfPresent(refreshToken, forKey: .refreshToken)
    if !extraFields.isEmpty {
      try container.encode(
        extraFields.mapValues(InstantAuthJSONValue.init),
        forKey: .extraFields
      )
    }
  }
}

struct InstantIDTokenBody: Encodable {
  var appID: String
  var nonce: String?
  var idToken: String
  var clientName: String
  var refreshToken: String?

  private enum CodingKeys: String, CodingKey {
    case appID = "app_id"
    case nonce
    case idToken = "id_token"
    case clientName = "client_name"
    case refreshToken = "refresh_token"
  }
}

struct InstantOAuthTokenBody: Encodable {
  var appID: String
  var code: String
  var codeVerifier: String?
  var refreshToken: String?

  private enum CodingKeys: String, CodingKey {
    case appID = "app_id"
    case code
    case codeVerifier = "code_verifier"
    case refreshToken = "refresh_token"
  }
}

private indirect enum InstantAuthJSONValue: Encodable {
  case null
  case string(String)
  case number(Double)
  case bool(Bool)
  case array([InstantAuthJSONValue])
  case object([String: InstantAuthJSONValue])

  init(_ value: InstantValue) {
    switch value {
    case .null:
      self = .null
    case let .string(value), let .ref(value):
      self = .string(value)
    case let .number(value):
      self = .number(value)
    case let .bool(value):
      self = .bool(value)
    case let .date(value):
      self = .string(ISO8601DateFormatter().string(from: value))
    case let .json(value):
      self.init(value)
    case let .lookupRef(value):
      self = .string(value.description)
    }
  }

  init(_ value: JSONValue) {
    switch value {
    case .null:
      self = .null
    case let .string(value):
      self = .string(value)
    case let .number(value):
      self = .number(value)
    case let .bool(value):
      self = .bool(value)
    case let .array(values):
      self = .array(values.map(Self.init))
    case let .object(values):
      self = .object(values.mapValues(Self.init))
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .null:
      try container.encodeNil()
    case let .string(value):
      try container.encode(value)
    case let .number(value):
      try container.encode(value)
    case let .bool(value):
      try container.encode(value)
    case let .array(value):
      try container.encode(value)
    case let .object(value):
      try container.encode(value)
    }
  }
}

struct InstantVerifyRefreshTokenResponse: Decodable {
  struct User: Decodable {
    var id: String
    var refreshToken: String

    private enum CodingKeys: String, CodingKey {
      case id
      case refreshToken = "refresh_token"
    }
  }

  var user: User
}

struct InstantAuthUserResponse: Decodable {
  struct User: Decodable {
    var id: String
    var refreshToken: String?

    private enum CodingKeys: String, CodingKey {
      case id
      case refreshToken = "refresh_token"
    }
  }

  var user: User
  var created: Bool?
}

func decodeInstantAuthUserResponse(
  _ data: Data,
  operation: String
) throws -> InstantAuthUserResponse {
  do {
    return try JSONDecoder().decode(InstantAuthUserResponse.self, from: data)
  } catch {
    throw InstantError(
      code: .decodeFailed,
      operation: operation,
      message: "Instant auth returned an invalid user response.",
      recovery: "Inspect the canonical Instant auth response shape."
    )
  }
}

func instantAuthRequest<Body: Encodable>(
  apiURI: URL,
  path: [String],
  body: Body
) throws -> URLRequest {
  let url = path.reduce(apiURI) { url, component in
    url.appendingPathComponent(component)
  }
  var request = URLRequest(url: url)
  request.httpMethod = "POST"
  request.httpBody = try JSONEncoder().encode(body)
  request.setValue("application/json", forHTTPHeaderField: "Content-Type")
  return request
}

func validateInstantAuthResponse(
  _ response: InstantAuthHTTPResponse,
  operation: String
) throws {
  guard (200..<300).contains(response.statusCode) else {
    throw InstantError(
      code: .authFailed,
      operation: operation,
      message: "Instant auth returned HTTP \(response.statusCode).",
      recovery: "Verify the app ID and authentication credentials, then try again."
    )
  }
}
