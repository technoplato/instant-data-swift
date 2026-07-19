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

    let response = try await client.upload(
      InstantStorageUploadRequest(
        appID: "app-1",
        apiURI: try #require(URL(string: "https://api.example.test/custom")),
        path: "builds/build-1 App.tsx",
        data: body,
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
    expectNoDifference(request.httpBody, body)
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

  @Test("Storage maps authorization and malformed response failures")
  func failuresAreActionable() async throws {
    let forbidden = InstantStorageTransportClient.live(
      httpClient: StorageRequestRecorder(
        response: InstantStorageHTTPResponse(statusCode: 403, data: Data())
      ).client
    )
    do {
      _ = try await forbidden.upload(uploadRequest())
      Issue.record("Expected forbidden storage upload to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .permissionRejected)
      expectNoDifference(error.operation, "upload file")
    }

    let malformed = InstantStorageTransportClient.live(
      httpClient: StorageRequestRecorder(
        response: InstantStorageHTTPResponse(statusCode: 200, data: Data(#"{}"#.utf8))
      ).client
    )
    do {
      _ = try await malformed.upload(uploadRequest())
      Issue.record("Expected malformed storage upload response to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .decodeFailed)
      expectNoDifference(error.operation, "upload file")
    }
  }

  private func uploadRequest() -> InstantStorageUploadRequest {
    InstantStorageUploadRequest(
      appID: "app-1",
      apiURI: URL(string: "https://api.example.test")!,
      path: "App.tsx",
      data: Data("code".utf8),
      refreshToken: "refresh-token"
    )
  }
}

private actor StorageRequestRecorder {
  private var requests: [URLRequest] = []
  private let response: InstantStorageHTTPResponse

  init(response: InstantStorageHTTPResponse) {
    self.response = response
  }

  nonisolated var client: InstantStorageHTTPClient {
    InstantStorageHTTPClient { request in
      await self.record(request)
      return self.response
    }
  }

  func record(_ request: URLRequest) {
    requests.append(request)
  }

  func onlyRequest() -> URLRequest? {
    requests.count == 1 ? requests[0] : nil
  }
}
