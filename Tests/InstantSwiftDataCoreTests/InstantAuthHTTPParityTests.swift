import CustomDump
import Foundation
@testable import InstantSwiftDataCore
import Testing

@Suite(.serialized)
struct InstantAuthHTTPParityTests {
  @Test("Instant authAPI.verifyRefreshToken posts canonical body and decodes user")
  func verifyRefreshTokenRequestMatchesCanonicalSDK() async throws {
    let recorder = AuthRequestRecorder()
    let client = InstantAuthHTTPClient { request in
      await recorder.record(request)
      return InstantAuthHTTPResponse(
        statusCode: 200,
        data: Data(
          #"{"user":{"id":"user-1","refresh_token":"verified-token","email":"user@example.com"}}"#.utf8
        )
      )
    }
    let verifier = InstantRefreshTokenVerifier.live(
      apiURI: try #require(URL(string: "https://api.example.test/custom")),
      httpClient: client
    )

    let verification = try await verifier.verify(
      InstantRefreshTokenVerificationRequest(
        appID: "app-1",
        refreshToken: "refresh-token",
        userID: "untrusted-local-user",
        signedInAt: InstantTimestamp(milliseconds: 1_700_000_000_000),
        makeID: { "unused-id" }
      )
    )

    expectNoDifference(
      verification,
      InstantRefreshTokenVerification(userID: "user-1", refreshToken: "verified-token")
    )
    let request = try #require(await recorder.onlyRequest())
    expectNoDifference(request.httpMethod, "POST")
    expectNoDifference(
      request.url?.absoluteString,
      "https://api.example.test/custom/runtime/auth/verify_refresh_token"
    )
    expectNoDifference(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    expectNoDifference(
      try requestJSONObject(request),
      ["app-id": "app-1", "refresh-token": "refresh-token"]
    )
  }

  @Test("Instant authAPI.signOut posts canonical body")
  func signOutRequestMatchesCanonicalSDK() async throws {
    let recorder = AuthRequestRecorder()
    let client = InstantAuthHTTPClient { request in
      await recorder.record(request)
      return InstantAuthHTTPResponse(statusCode: 200, data: Data(#"{}"#.utf8))
    }
    let invalidator = InstantAuthTokenInvalidator.live(
      apiURI: try #require(URL(string: "https://api.example.test/custom")),
      httpClient: client
    )

    try await invalidator.invalidate(
      InstantAuthTokenInvalidationRequest(
        appID: "app-1",
        refreshToken: "refresh-token",
        signedOutAt: InstantTimestamp(milliseconds: 1_700_000_000_000)
      )
    )

    let request = try #require(await recorder.onlyRequest())
    expectNoDifference(request.httpMethod, "POST")
    expectNoDifference(
      request.url?.absoluteString,
      "https://api.example.test/custom/runtime/signout"
    )
    expectNoDifference(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    expectNoDifference(
      try requestJSONObject(request),
      ["app_id": "app-1", "refresh_token": "refresh-token"]
    )
  }
}

private actor AuthRequestRecorder {
  private var requests: [URLRequest] = []

  func record(_ request: URLRequest) {
    requests.append(request)
  }

  func onlyRequest() -> URLRequest? {
    requests.count == 1 ? requests[0] : nil
  }
}

private func requestJSONObject(_ request: URLRequest) throws -> [String: String] {
  let data = try #require(request.httpBody)
  return try #require(JSONSerialization.jsonObject(with: data) as? [String: String])
}
