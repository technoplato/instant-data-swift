import Foundation

public struct InstantStorageUploadRequest: Hashable, Sendable {
  public var appID: String
  public var apiURI: URL
  public var path: String
  public var data: Data
  public var refreshToken: String
  public var contentType: String?
  public var contentDisposition: String?

  public init(
    appID: String,
    apiURI: URL,
    path: String,
    data: Data,
    refreshToken: String,
    contentType: String? = nil,
    contentDisposition: String? = nil
  ) {
    self.appID = appID
    self.apiURI = apiURI
    self.path = path
    self.data = data
    self.refreshToken = refreshToken
    self.contentType = contentType
    self.contentDisposition = contentDisposition
  }
}

public struct InstantStorageUploadResponse: Hashable, Codable, Sendable {
  public var id: String

  public init(id: String) {
    self.id = id
  }
}

public struct InstantStorageDeleteRequest: Hashable, Sendable {
  public var appID: String
  public var apiURI: URL
  public var path: String
  public var refreshToken: String

  public init(appID: String, apiURI: URL, path: String, refreshToken: String) {
    self.appID = appID
    self.apiURI = apiURI
    self.path = path
    self.refreshToken = refreshToken
  }
}

public struct InstantStorageDeleteResponse: Hashable, Codable, Sendable {
  public var id: String?

  public init(id: String?) {
    self.id = id
  }
}

public struct InstantStorageTransportClient: Sendable {
  public var upload:
    @Sendable (InstantStorageUploadRequest) async throws -> InstantStorageUploadResponse
  public var delete:
    @Sendable (InstantStorageDeleteRequest) async throws -> InstantStorageDeleteResponse

  public init(
    upload: @escaping @Sendable (InstantStorageUploadRequest) async throws
      -> InstantStorageUploadResponse,
    delete: @escaping @Sendable (InstantStorageDeleteRequest) async throws
      -> InstantStorageDeleteResponse
  ) {
    self.upload = upload
    self.delete = delete
  }
}

public struct InstantStorageHTTPResponse: Hashable, Codable, Sendable {
  public var statusCode: Int
  public var data: Data

  public init(statusCode: Int, data: Data) {
    self.statusCode = statusCode
    self.data = data
  }
}

public struct InstantStorageHTTPClient: Sendable {
  public var send: @Sendable (URLRequest) async throws -> InstantStorageHTTPResponse

  public init(
    send: @escaping @Sendable (URLRequest) async throws -> InstantStorageHTTPResponse
  ) {
    self.send = send
  }
}

extension InstantStorageHTTPClient {
  public static let live = Self { request in
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let response = response as? HTTPURLResponse else {
      throw InstantError(
        code: .networkFailed,
        operation: "perform Instant storage request",
        message: "Instant storage returned a non-HTTP response.",
        recovery: "Check the configured Instant API endpoint and network connection."
      )
    }
    return InstantStorageHTTPResponse(statusCode: response.statusCode, data: data)
  }
}

extension InstantStorageTransportClient {
  public static func live(httpClient: InstantStorageHTTPClient = .live) -> Self {
    Self(
      upload: { request in
        var urlRequest = URLRequest(
          url: request.apiURI
            .appendingPathComponent("storage")
            .appendingPathComponent("upload")
        )
        urlRequest.httpMethod = "PUT"
        urlRequest.httpBody = request.data
        urlRequest.setValue(request.appID, forHTTPHeaderField: "app_id")
        urlRequest.setValue(request.path, forHTTPHeaderField: "path")
        urlRequest.setValue(
          "Bearer \(request.refreshToken)",
          forHTTPHeaderField: "Authorization"
        )
        urlRequest.setValue(
          request.contentType ?? "application/octet-stream",
          forHTTPHeaderField: "Content-Type"
        )
        if let contentDisposition = request.contentDisposition {
          urlRequest.setValue(contentDisposition, forHTTPHeaderField: "Content-Disposition")
        }

        let response = try await httpClient.send(urlRequest)
        try validateStorageResponse(response, operation: "upload file")
        do {
          return try JSONDecoder().decode(InstantStorageUploadEnvelope.self, from: response.data)
            .data
        } catch {
          throw InstantError(
            code: .decodeFailed,
            operation: "upload file",
            message: "Instant storage returned an invalid upload response.",
            recovery: "Retry the upload and inspect the Instant storage response."
          )
        }
      },
      delete: { request in
        var components = URLComponents(
          url: request.apiURI
            .appendingPathComponent("storage")
            .appendingPathComponent("files"),
          resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
          URLQueryItem(name: "app_id", value: request.appID),
          URLQueryItem(name: "filename", value: request.path),
        ]
        guard let url = components?.url else {
          throw InstantError(
            code: .validationFailed,
            operation: "delete file",
            message: "Could not construct the Instant storage delete URL.",
            recovery: "Check the configured Instant API endpoint and file path."
          )
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "DELETE"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(
          "Bearer \(request.refreshToken)",
          forHTTPHeaderField: "Authorization"
        )

        let response = try await httpClient.send(urlRequest)
        try validateStorageResponse(response, operation: "delete file")
        do {
          return try JSONDecoder().decode(InstantStorageDeleteEnvelope.self, from: response.data)
            .data
        } catch {
          throw InstantError(
            code: .decodeFailed,
            operation: "delete file",
            message: "Instant storage returned an invalid delete response.",
            recovery: "Retry the delete and inspect the Instant storage response."
          )
        }
      }
    )
  }
}

private struct InstantStorageUploadEnvelope: Decodable {
  var data: InstantStorageUploadResponse
}

private struct InstantStorageDeleteEnvelope: Decodable {
  var data: InstantStorageDeleteResponse
}

private func validateStorageResponse(
  _ response: InstantStorageHTTPResponse,
  operation: String
) throws {
  guard (200..<300).contains(response.statusCode) else {
    throw InstantError(
      code: response.statusCode == 401 || response.statusCode == 403
        ? .permissionRejected
        : .networkFailed,
      operation: operation,
      message: "Instant storage returned HTTP \(response.statusCode).",
      recovery: "Verify the app ID, refresh token, storage permissions, and file path."
    )
  }
}
