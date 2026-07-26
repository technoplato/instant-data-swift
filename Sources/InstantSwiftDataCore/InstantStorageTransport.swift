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

public struct InstantStorageDownloadRequest: Hashable, Sendable {
  public var url: URL

  public init(url: URL) {
    self.url = url
  }
}

public struct InstantStorageFileDownloadRequest: Hashable, Sendable {
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

public final class InstantStorageTransportClient: Sendable {
  public let upload:
    @Sendable (InstantStorageUploadRequest) async throws -> InstantStorageUploadResponse
  public let delete:
    @Sendable (InstantStorageDeleteRequest) async throws -> InstantStorageDeleteResponse
  public let download:
    @Sendable (InstantStorageDownloadRequest) async throws -> Data
  public let downloadFile:
    @Sendable (InstantStorageFileDownloadRequest) async throws -> Data

  public init(
    upload: @escaping @Sendable (InstantStorageUploadRequest) async throws
      -> InstantStorageUploadResponse,
    delete: @escaping @Sendable (InstantStorageDeleteRequest) async throws
      -> InstantStorageDeleteResponse
  ) {
    self.upload = upload
    self.delete = delete
    self.download = { _ in
      throw InstantError(
        code: .networkFailed,
        operation: "download file",
        message: "No remote storage download transport is configured.",
        recovery: "Configure InstantStorageTransportClient.live() before downloading remote files."
      )
    }
    self.downloadFile = { _ in
      throw InstantError(
        code: .networkFailed,
        operation: "download file",
        message: "No authenticated storage file download transport is configured.",
        recovery: "Configure InstantStorageTransportClient.live() before downloading remote files."
      )
    }
  }

  public init(
    upload: @escaping @Sendable (InstantStorageUploadRequest) async throws
      -> InstantStorageUploadResponse,
    delete: @escaping @Sendable (InstantStorageDeleteRequest) async throws
      -> InstantStorageDeleteResponse,
    download: @escaping @Sendable (InstantStorageDownloadRequest) async throws -> Data
  ) {
    self.upload = upload
    self.delete = delete
    self.download = download
    self.downloadFile = { _ in
      throw InstantError(
        code: .networkFailed,
        operation: "download file",
        message: "No authenticated storage file download transport is configured.",
        recovery: "Configure InstantStorageTransportClient.live() before downloading remote files."
      )
    }
  }

  public init(
    upload: @escaping @Sendable (InstantStorageUploadRequest) async throws
      -> InstantStorageUploadResponse,
    delete: @escaping @Sendable (InstantStorageDeleteRequest) async throws
      -> InstantStorageDeleteResponse,
    downloadFile: @escaping @Sendable (InstantStorageFileDownloadRequest) async throws -> Data
  ) {
    self.upload = upload
    self.delete = delete
    self.download = { _ in
      throw InstantError(
        code: .networkFailed,
        operation: "download file",
        message: "No remote storage URL download transport is configured.",
        recovery: "Configure InstantStorageTransportClient.live() before downloading remote files."
      )
    }
    self.downloadFile = downloadFile
  }

  public init(
    upload: @escaping @Sendable (InstantStorageUploadRequest) async throws
      -> InstantStorageUploadResponse,
    delete: @escaping @Sendable (InstantStorageDeleteRequest) async throws
      -> InstantStorageDeleteResponse,
    download: @escaping @Sendable (InstantStorageDownloadRequest) async throws -> Data,
    downloadFile: @escaping @Sendable (InstantStorageFileDownloadRequest) async throws -> Data
  ) {
    self.upload = upload
    self.delete = delete
    self.download = download
    self.downloadFile = downloadFile
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
      },
      download: { request in
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = "GET"
        let response = try await httpClient.send(urlRequest)
        try validateStorageResponse(response, operation: "download file")
        return response.data
      },
      downloadFile: { request in
        var components = URLComponents(
          url: request.apiURI
            .appendingPathComponent("storage")
            .appendingPathComponent("signed-download-url"),
          resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
          URLQueryItem(name: "app_id", value: request.appID),
          URLQueryItem(name: "filename", value: request.path),
        ]
        guard let signedURLRequestURL = components?.url else {
          throw InstantError(
            code: .validationFailed,
            operation: "download file",
            message: "Could not construct the Instant storage download URL.",
            recovery: "Check the configured Instant API endpoint and file path."
          )
        }
        var signedURLRequest = URLRequest(url: signedURLRequestURL)
        signedURLRequest.httpMethod = "GET"
        signedURLRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        signedURLRequest.setValue(
          "Bearer \(request.refreshToken)",
          forHTTPHeaderField: "Authorization"
        )
        let signedURLResponse = try await httpClient.send(signedURLRequest)
        try validateStorageResponse(signedURLResponse, operation: "download file")
        let envelope: InstantStorageSignedDownloadEnvelope
        do {
          envelope = try JSONDecoder().decode(
            InstantStorageSignedDownloadEnvelope.self,
            from: signedURLResponse.data
          )
        } catch {
          throw InstantError(
            code: .decodeFailed,
            operation: "download file",
            message: "Instant storage returned an invalid download URL response.",
            recovery: "Retry the download and inspect the Instant storage response."
          )
        }
        guard let downloadURL = URL(string: envelope.data) else {
          throw InstantError(
            code: .decodeFailed,
            operation: "download file",
            message: "Instant storage returned an invalid signed download URL.",
            recovery: "Retry the download and inspect the Instant storage response."
          )
        }
        var downloadRequest = URLRequest(url: downloadURL)
        downloadRequest.httpMethod = "GET"
        let downloadResponse = try await httpClient.send(downloadRequest)
        try validateStorageResponse(downloadResponse, operation: "download file")
        return downloadResponse.data
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

private struct InstantStorageSignedDownloadEnvelope: Decodable {
  var data: String
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
