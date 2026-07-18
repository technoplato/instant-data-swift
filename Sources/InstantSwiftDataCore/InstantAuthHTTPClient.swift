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
      recovery: "Verify the app ID and refresh token, then authenticate again."
    )
  }
}
