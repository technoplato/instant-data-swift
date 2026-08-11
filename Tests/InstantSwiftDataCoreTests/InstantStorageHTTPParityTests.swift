import CustomDump
import Foundation
@testable import InstantSwiftDataCore
import Testing

@Suite(.serialized)
struct InstantStorageHTTPParityTests {
  @Test("Storage upload uses the canonical PUT headers, raw body, and response shape")
  func uploadMatchesCanonicalSDK() async throws {
    let recorder = StorageRequestRecorder(
      response: InstantStorageHTTPResponse(
        statusCode: 200,
        data: Data(#"{"data":{"id":"file-1"}}"#.utf8)
      )
    )
    let client = InstantStorageTransportClient.live(httpClient: recorder.client)
    let body = Data("export default function App() {}".utf8)
    let sourceURL = temporaryFileURL(name: "App.tsx")
    try body.write(to: sourceURL)
    defer { try? FileManager.default.removeItem(at: sourceURL) }

    let response = try await client.upload(
      InstantStorageUploadRequest(
        appID: "app-1",
        apiURI: try #require(URL(string: "https://api.example.test/custom")),
        path: "builds/build-1 App.tsx",
        sourceURL: sourceURL,
        byteCount: Int64(body.count),
        refreshToken: "refresh-token",
        contentType: "text/typescript",
        contentDisposition: #"inline; filename="App.tsx""#
      )
    )

    expectNoDifference(response, InstantStorageUploadResponse(id: "file-1"))
    let request = try #require(await recorder.onlyRequest())
    expectNoDifference(request.httpMethod, "PUT")
    expectNoDifference(
      request.url?.absoluteString,
      "https://api.example.test/custom/storage/upload"
    )
    expectNoDifference(request.value(forHTTPHeaderField: "app_id"), "app-1")
    expectNoDifference(request.value(forHTTPHeaderField: "path"), "builds/build-1 App.tsx")
    expectNoDifference(request.value(forHTTPHeaderField: "Authorization"), "Bearer refresh-token")
    expectNoDifference(request.value(forHTTPHeaderField: "Content-Type"), "text/typescript")
    expectNoDifference(
      request.value(forHTTPHeaderField: "Content-Disposition"),
      #"inline; filename="App.tsx""#
    )
    expectNoDifference(request.value(forHTTPHeaderField: "Content-Length"), "32")
    expectNoDifference(request.httpBody, nil)
    let uploadSourceURL = await recorder.onlyUploadSourceURL()
    expectNoDifference(uploadSourceURL, sourceURL)
  }

  @Test("Large storage upload keeps a bounded file-backed request payload")
  func largeUploadIsFileBacked() async throws {
    let recorder = StorageRequestRecorder(
      response: InstantStorageHTTPResponse(
        statusCode: 200,
        data: Data(#"{"data":{"id":"file-1"}}"#.utf8)
      )
    )
    let client = InstantStorageTransportClient.live(httpClient: recorder.client)
    let sourceURL = temporaryFileURL(name: "large-recording.wav")
    try Data().write(to: sourceURL)
    let handle = try FileHandle(forWritingTo: sourceURL)
    let byteCount: Int64 = 64 * 1_024 * 1_024
    try handle.truncate(atOffset: UInt64(byteCount))
    try handle.close()
    defer { try? FileManager.default.removeItem(at: sourceURL) }

    _ = try await client.upload(
      InstantStorageUploadRequest(
        appID: "app-1",
        apiURI: try #require(URL(string: "https://api.example.test")),
        path: "recordings/large-recording.wav",
        sourceURL: sourceURL,
        byteCount: byteCount,
        refreshToken: "refresh-token",
        contentType: "audio/wav"
      )
    )

    let request = try #require(await recorder.onlyRequest())
    expectNoDifference(request.httpBody, nil)
    expectNoDifference(request.value(forHTTPHeaderField: "Content-Length"), "67108864")
    let uploadSourceURL = await recorder.onlyUploadSourceURL()
    expectNoDifference(uploadSourceURL, sourceURL)
    let peakRetainedRequestBodyByteCount = await recorder.peakRetainedRequestBodyByteCount()
    expectNoDifference(peakRetainedRequestBodyByteCount, 0)
  }

  @Test("Storage delete uses the canonical DELETE query and bearer token")
  func deleteMatchesCanonicalSDK() async throws {
    let recorder = StorageRequestRecorder(
      response: InstantStorageHTTPResponse(
        statusCode: 200,
        data: Data(#"{"data":{"id":"file-1"}}"#.utf8)
      )
    )
    let client = InstantStorageTransportClient.live(httpClient: recorder.client)

    let response = try await client.delete(
      InstantStorageDeleteRequest(
        appID: "app-1",
        apiURI: try #require(URL(string: "https://api.example.test/custom")),
        path: "builds/build-1 App.tsx",
        refreshToken: "refresh-token"
      )
    )

    expectNoDifference(response, InstantStorageDeleteResponse(id: "file-1"))
    let request = try #require(await recorder.onlyRequest())
    expectNoDifference(request.httpMethod, "DELETE")
    expectNoDifference(
      request.url?.absoluteString,
      "https://api.example.test/custom/storage/files?app_id=app-1&filename=builds/build-1%20App.tsx"
    )
    expectNoDifference(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    expectNoDifference(request.value(forHTTPHeaderField: "Authorization"), "Bearer refresh-token")
    expectNoDifference(request.httpBody, nil)
  }

  @Test("Storage download fetches the URL discovered from the $files query")
  func downloadUsesDiscoveredURL() async throws {
    let body = Data("remote-file".utf8)
    let recorder = StorageRequestRecorder(
      response: InstantStorageHTTPResponse(statusCode: 200, data: body)
    )
    let client = InstantStorageTransportClient.live(httpClient: recorder.client)
    let url = try #require(
      URL(string: "https://instant-storage.example.test/signed/file-1?token=abc")
    )

    let downloaded = try await client.download(InstantStorageDownloadRequest(url: url))

    expectNoDifference(downloaded, body)
    let request = try #require(await recorder.onlyRequest())
    expectNoDifference(request.httpMethod, "GET")
    expectNoDifference(request.url, url)
    expectNoDifference(request.httpBody, nil)
  }

  @Test("Named storage download resolves a signed URL without a live query")
  func namedDownloadUsesAuthenticatedStorageAPI() async throws {
    let body = Data("remote-file".utf8)
    let recorder = StorageRequestRecorder(
      responses: [
        InstantStorageHTTPResponse(
          statusCode: 200,
          data: Data(
            #"{"data":"https://instant-storage.example.test/signed/file-1?token=abc"}"#.utf8
          )
        ),
        InstantStorageHTTPResponse(statusCode: 200, data: body),
      ]
    )
    let client = InstantStorageTransportClient.live(httpClient: recorder.client)

    let downloaded = try await client.downloadFile(
      InstantStorageFileDownloadRequest(
        appID: "app-1",
        apiURI: try #require(URL(string: "https://api.example.test/custom")),
        path: "scribe/recording 1/audio.wav",
        refreshToken: "refresh-token"
      )
    )

    expectNoDifference(downloaded, body)
    let requests = await recorder.recordedRequests()
    expectNoDifference(requests.count, 2)
    expectNoDifference(requests[0].httpMethod, "GET")
    expectNoDifference(
      requests[0].url?.absoluteString,
      "https://api.example.test/custom/storage/signed-download-url?app_id=app-1&filename=scribe/recording%201/audio.wav"
    )
    expectNoDifference(
      requests[0].value(forHTTPHeaderField: "Authorization"),
      "Bearer refresh-token"
    )
    expectNoDifference(
      requests[1].url?.absoluteString,
      "https://instant-storage.example.test/signed/file-1?token=abc"
    )
  }

  @Test("Storage maps authorization and malformed response failures")
  func failuresAreActionable() async throws {
    let forbiddenRecorder = StorageRequestRecorder(
      response: InstantStorageHTTPResponse(statusCode: 403, data: Data())
    )
    let forbidden = InstantStorageTransportClient.live(
      httpClient: forbiddenRecorder.client
    )
    do {
      _ = try await forbidden.upload(uploadRequest())
      Issue.record("Expected forbidden storage upload to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .permissionRejected)
      expectNoDifference(error.operation, "upload file")
    }
    let forbiddenRequests = await forbiddenRecorder.recordedRequests()
    expectNoDifference(forbiddenRequests.count, 1)

    let malformedRecorder = StorageRequestRecorder(
      response: InstantStorageHTTPResponse(statusCode: 200, data: Data(#"{}"#.utf8))
    )
    let malformed = InstantStorageTransportClient.live(
      httpClient: malformedRecorder.client
    )
    do {
      _ = try await malformed.upload(uploadRequest())
      Issue.record("Expected malformed storage upload response to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .decodeFailed)
      expectNoDifference(error.operation, "upload file")
    }
    let malformedRequests = await malformedRecorder.recordedRequests()
    expectNoDifference(malformedRequests.count, 1)
  }

  private func uploadRequest() -> InstantStorageUploadRequest {
    let sourceURL = temporaryFileURL(name: "failure.txt")
    return InstantStorageUploadRequest(
      appID: "app-1",
      apiURI: URL(string: "https://api.example.test")!,
      path: "App.tsx",
      sourceURL: sourceURL,
      byteCount: 4,
      refreshToken: "refresh-token"
    )
  }

  private func temporaryFileURL(name: String) -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("instant-storage-\(UUID().uuidString)-\(name)")
  }
}

private actor StorageRequestRecorder {
  private var requests: [URLRequest] = []
  private var uploadSourceURLs: [URL] = []
  private var peakRequestBodyByteCount = 0
  private var responses: [InstantStorageHTTPResponse]

  init(response: InstantStorageHTTPResponse) {
    self.responses = [response]
  }

  init(responses: [InstantStorageHTTPResponse]) {
    self.responses = responses
  }

  nonisolated var client: InstantStorageHTTPClient {
    InstantStorageHTTPClient(
      send: { request in
        await self.response(for: request)
      },
      uploadFile: { request, sourceURL in
        await self.response(for: request, uploadSourceURL: sourceURL)
      }
    )
  }

  func response(
    for request: URLRequest,
    uploadSourceURL: URL? = nil
  ) -> InstantStorageHTTPResponse {
    requests.append(request)
    peakRequestBodyByteCount = max(peakRequestBodyByteCount, request.httpBody?.count ?? 0)
    if let uploadSourceURL {
      uploadSourceURLs.append(uploadSourceURL)
    }
    if responses.count > 1 {
      return responses.removeFirst()
    }
    return responses[0]
  }

  func onlyRequest() -> URLRequest? {
    requests.count == 1 ? requests[0] : nil
  }

  func recordedRequests() -> [URLRequest] {
    requests
  }

  func onlyUploadSourceURL() -> URL? {
    uploadSourceURLs.count == 1 ? uploadSourceURLs[0] : nil
  }

  func peakRetainedRequestBodyByteCount() -> Int {
    peakRequestBodyByteCount
  }
}
