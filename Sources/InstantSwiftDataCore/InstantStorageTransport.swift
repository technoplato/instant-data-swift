import Foundation

/// A file-backed storage upload request.
///
/// Keep `sourceURL` readable and unchanged until `upload` returns. `byteCount`
/// is the exact regular-file size sent as the request's content length.
public struct InstantStorageUploadRequest: Hashable, Sendable {
  public var appID: String
  public var apiURI: URL
  public var path: String
  public var sourceURL: URL
  public var byteCount: Int64
  public var refreshToken: String
  public var contentType: String?
  public var contentDisposition: String?

  public init(
    appID: String,
    apiURI: URL,
    path: String,
    sourceURL: URL,
    byteCount: Int64,
    refreshToken: String,
    contentType: String? = nil,
    contentDisposition: String? = nil
  ) {
    self.appID = appID
    self.apiURI = apiURI
    self.path = path
    self.sourceURL = sourceURL
    self.byteCount = byteCount
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

public typealias InstantStorageTransportOperation<Value: Sendable> =
  InstantAbortableOperation<Value>

public final class InstantStorageTransportClient: Sendable {
  public let upload:
    @Sendable (InstantStorageUploadRequest) async throws -> InstantStorageUploadResponse
  public let delete:
    @Sendable (InstantStorageDeleteRequest) async throws -> InstantStorageDeleteResponse
  public let download:
    @Sendable (InstantStorageDownloadRequest) async throws -> Data
  public let downloadFile:
    @Sendable (InstantStorageFileDownloadRequest) async throws -> Data
  let prepareUploadOperation:
    @Sendable (InstantStorageUploadRequest)
      -> InstantStorageTransportOperation<InstantStorageUploadResponse>
  let prepareDeleteOperation:
    @Sendable (InstantStorageDeleteRequest)
      -> InstantStorageTransportOperation<InstantStorageDeleteResponse>

  public init(
    upload: @escaping @Sendable (InstantStorageUploadRequest) async throws
      -> InstantStorageUploadResponse,
    delete: @escaping @Sendable (InstantStorageDeleteRequest) async throws
      -> InstantStorageDeleteResponse
  ) {
    self.upload = upload
    self.delete = delete
    self.prepareUploadOperation = Self.cooperativeOperation(upload)
    self.prepareDeleteOperation = Self.cooperativeOperation(delete)
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
    self.prepareUploadOperation = Self.cooperativeOperation(upload)
    self.prepareDeleteOperation = Self.cooperativeOperation(delete)
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
    self.prepareUploadOperation = Self.cooperativeOperation(upload)
    self.prepareDeleteOperation = Self.cooperativeOperation(delete)
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
    self.prepareUploadOperation = Self.cooperativeOperation(upload)
    self.prepareDeleteOperation = Self.cooperativeOperation(delete)
    self.download = download
    self.downloadFile = downloadFile
  }

  private init(
    prepareUploadOperation:
      @escaping @Sendable (InstantStorageUploadRequest)
        -> InstantStorageTransportOperation<InstantStorageUploadResponse>,
    prepareDeleteOperation:
      @escaping @Sendable (InstantStorageDeleteRequest)
        -> InstantStorageTransportOperation<InstantStorageDeleteResponse>,
    download: @escaping @Sendable (InstantStorageDownloadRequest) async throws -> Data,
    downloadFile:
      @escaping @Sendable (InstantStorageFileDownloadRequest) async throws -> Data
  ) {
    self.prepareUploadOperation = prepareUploadOperation
    self.prepareDeleteOperation = prepareDeleteOperation
    self.upload = { request in
      let operation = prepareUploadOperation(request)
      return try await withTaskCancellationHandler {
        try await operation.run()
      } onCancel: {
        operation.abort()
      }
    }
    self.delete = { request in
      let operation = prepareDeleteOperation(request)
      return try await withTaskCancellationHandler {
        try await operation.run()
      } onCancel: {
        operation.abort()
      }
    }
    self.download = download
    self.downloadFile = downloadFile
  }

  private static func cooperativeOperation<Request: Sendable, Response: Sendable>(
    _ operation: @escaping @Sendable (Request) async throws -> Response
  ) -> @Sendable (Request) -> InstantStorageTransportOperation<Response> {
    { request in
      InstantStorageTransportOperation(
        run: { try await operation(request) },
        abort: {}
      )
    }
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
  public var uploadFile: @Sendable (URLRequest, URL) async throws -> InstantStorageHTTPResponse {
    didSet {
      let uploadFile = self.uploadFile
      prepareUploadFileOperation = Self.cooperativeUploadOperation(uploadFile)
    }
  }
  fileprivate var prepareUploadFileOperation:
    @Sendable (URLRequest, URL) -> InstantStorageTransportOperation<InstantStorageHTTPResponse>

  public init(
    send: @escaping @Sendable (URLRequest) async throws -> InstantStorageHTTPResponse
  ) {
    self.send = send
    let uploadFile: @Sendable (URLRequest, URL) async throws
      -> InstantStorageHTTPResponse = { _, _ in
      throw InstantError(
        code: .networkFailed,
        operation: "upload file",
        message: "No file-backed Instant storage HTTP transport is configured.",
        recovery: "Provide InstantStorageHTTPClient.uploadFile or use the live client."
      )
    }
    self.uploadFile = uploadFile
    self.prepareUploadFileOperation = Self.cooperativeUploadOperation(uploadFile)
  }

  public init(
    send: @escaping @Sendable (URLRequest) async throws -> InstantStorageHTTPResponse,
    uploadFile: @escaping @Sendable (URLRequest, URL) async throws
      -> InstantStorageHTTPResponse
  ) {
    self.send = send
    self.uploadFile = uploadFile
    self.prepareUploadFileOperation = Self.cooperativeUploadOperation(uploadFile)
  }

  fileprivate init(
    send: @escaping @Sendable (URLRequest) async throws -> InstantStorageHTTPResponse,
    prepareUploadFileOperation:
      @escaping @Sendable (URLRequest, URL)
        -> InstantStorageTransportOperation<InstantStorageHTTPResponse>
  ) {
    self.send = send
    self.prepareUploadFileOperation = prepareUploadFileOperation
    self.uploadFile = { request, sourceURL in
      let operation = prepareUploadFileOperation(request, sourceURL)
      return try await withTaskCancellationHandler {
        try await operation.run()
      } onCancel: {
        operation.abort()
      }
    }
  }

  private static func cooperativeUploadOperation(
    _ uploadFile:
      @escaping @Sendable (URLRequest, URL) async throws -> InstantStorageHTTPResponse
  ) -> @Sendable (URLRequest, URL)
    -> InstantStorageTransportOperation<InstantStorageHTTPResponse> {
    { request, sourceURL in
      InstantStorageTransportOperation(
        run: { try await uploadFile(request, sourceURL) },
        abort: {}
      )
    }
  }
}

// SAFETY: `lock` protects the single URLSession completion result and the
// single waiter. Completion may race with `run()` installing its waiter.
private final class InstantStorageHTTPCompletion: @unchecked Sendable {
  private let lock = NSLock()
  private var result: Result<InstantStorageHTTPResponse, Error>?
  private var continuation:
    CheckedContinuation<InstantStorageHTTPResponse, Error>?

  func complete(_ result: Result<InstantStorageHTTPResponse, Error>) {
    let continuation = lock.withLock {
      () -> CheckedContinuation<InstantStorageHTTPResponse, Error>? in
      if let continuation = self.continuation {
        self.continuation = nil
        return continuation
      }
      self.result = result
      return nil
    }
    continuation?.resume(with: result)
  }

  func value() async throws -> InstantStorageHTTPResponse {
    try await withCheckedThrowingContinuation { continuation in
      let pending = lock.withLock { () -> Result<InstantStorageHTTPResponse, Error>? in
        if let existing = self.result {
          self.result = nil
          return existing
        }
        self.continuation = continuation
        return nil
      }
      if let pending {
        continuation.resume(with: pending)
      }
    }
  }
}

private func liveStorageUploadOperation(
  request: URLRequest,
  sourceURL: URL
) -> InstantStorageTransportOperation<InstantStorageHTTPResponse> {
  let completion = InstantStorageHTTPCompletion()
  let task = URLSession.shared.uploadTask(
    with: request,
    fromFile: sourceURL
  ) { data, response, error in
    if let error {
      completion.complete(.failure(error))
      return
    }
    do {
      guard let response else {
        throw InstantError(
          code: .networkFailed,
          operation: "upload file",
          message: "Instant storage returned no HTTP response.",
          recovery: "Check the configured Instant API endpoint and network connection."
        )
      }
      completion.complete(
        .success(try httpResponse(data: data ?? Data(), response: response))
      )
    } catch {
      completion.complete(.failure(error))
    }
  }
  return InstantStorageTransportOperation(
    run: {
      task.resume()
      return try await completion.value()
    },
    abort: {
      task.cancel()
    }
  )
}

extension InstantStorageHTTPClient {
  public static let live = Self(
    send: { request in
      let (data, response) = try await URLSession.shared.data(for: request)
      return try httpResponse(data: data, response: response)
    },
    prepareUploadFileOperation: { request, sourceURL in
      // Upstream StorageAPI uploads a File/Blob directly. A suspended
      // URLSession upload task is the Swift file-backed equivalent and gives
      // cancellation a synchronous task-level abort before asynchronous work.
      liveStorageUploadOperation(request: request, sourceURL: sourceURL)
    }
  )
}

extension InstantStorageTransportClient {
  /// Builds a storage transport that exposes a fresh abortable operation for
  /// every upload and delete request.
  public static func preparedOperations(
    upload:
      @escaping @Sendable (InstantStorageUploadRequest)
        -> InstantStorageTransportOperation<InstantStorageUploadResponse>,
    delete:
      @escaping @Sendable (InstantStorageDeleteRequest)
        -> InstantStorageTransportOperation<InstantStorageDeleteResponse>
  ) -> Self {
    Self(
      prepareUploadOperation: upload,
      prepareDeleteOperation: delete,
      download: { _ in
        throw InstantError(
          code: .networkFailed,
          operation: "download file",
          message: "No remote storage download transport is configured.",
          recovery: "Configure InstantStorageTransportClient.live() before downloading remote files."
        )
      },
      downloadFile: { _ in
        throw InstantError(
          code: .networkFailed,
          operation: "download file",
          message: "No authenticated storage file download transport is configured.",
          recovery: "Configure InstantStorageTransportClient.live() before downloading remote files."
        )
      }
    )
  }

  public static func live(httpClient: InstantStorageHTTPClient = .live) -> Self {
    Self(
      prepareUploadOperation: { request in
        guard request.sourceURL.isFileURL, request.byteCount >= 0 else {
          return InstantStorageTransportOperation(
            run: {
              throw InstantError(
                code: .validationFailed,
                operation: "upload file",
                message: "Instant storage uploads require a file URL and nonnegative byte count.",
                recovery: "Write the upload to a regular local file and pass its exact byte count."
              )
            },
            abort: {}
          )
        }
        var urlRequest = URLRequest(
          url: request.apiURI
            .appendingPathComponent("storage")
            .appendingPathComponent("upload")
        )
        urlRequest.httpMethod = "PUT"
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
        urlRequest.setValue(
          String(request.byteCount),
          forHTTPHeaderField: "Content-Length"
        )
        if let contentDisposition = request.contentDisposition {
          urlRequest.setValue(contentDisposition, forHTTPHeaderField: "Content-Disposition")
        }

        let upload = httpClient.prepareUploadFileOperation(urlRequest, request.sourceURL)
        return InstantStorageTransportOperation(
          run: {
            let response = try await upload.run()
            try validateStorageResponse(response, operation: "upload file")
            do {
              return try JSONDecoder().decode(
                InstantStorageUploadEnvelope.self,
                from: response.data
              ).data
            } catch {
              throw InstantError(
                code: .decodeFailed,
                operation: "upload file",
                message: "Instant storage returned an invalid upload response.",
                recovery: "Retry the upload and inspect the Instant storage response."
              )
            }
          },
          abort: {
            upload.abort()
          }
        )
      },
      prepareDeleteOperation: { request in
        InstantStorageTransportOperation(
          run: {
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
              return try JSONDecoder().decode(
                InstantStorageDeleteEnvelope.self,
                from: response.data
              ).data
            } catch {
              throw InstantError(
                code: .decodeFailed,
                operation: "delete file",
                message: "Instant storage returned an invalid delete response.",
                recovery: "Retry the delete and inspect the Instant storage response."
              )
            }
          },
          abort: {
            // Custom HTTP clients expose only an async delete call today.
          }
        )
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

private func httpResponse(
  data: Data,
  response: URLResponse
) throws -> InstantStorageHTTPResponse {
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
