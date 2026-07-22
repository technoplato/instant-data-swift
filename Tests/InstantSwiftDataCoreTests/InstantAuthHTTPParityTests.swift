import CustomDump
import Foundation
@testable import InstantSwiftDataCore
import Testing

@Suite(.serialized)
struct InstantAuthHTTPParityTests {
  @Test("Instant authAPI magic-code calls use canonical endpoints and bodies")
  func magicCodeRequestsMatchCanonicalSDK() async throws {
    let sendRecorder = AuthRequestRecorder()
    let exchange = InstantMagicCodeExchange.live(
      httpClient: InstantAuthHTTPClient { request in
        await sendRecorder.record(request)
        return InstantAuthHTTPResponse(statusCode: 200, data: Data(#"{"sent":true}"#.utf8))
      }
    )
    let apiURI = try #require(URL(string: "https://api.example.test/custom"))
    let challenge = try await exchange.send(
      InstantMagicCodeSendRequest(
        appID: "app-1",
        apiURI: apiURI,
        email: "user@example.com",
        sentAt: InstantTimestamp(milliseconds: 1_700_000_000_000),
        makeID: { "unused" }
      )
    )
    let sendRequest = try #require(await sendRecorder.onlyRequest())
    expectNoDifference(
      sendRequest.url?.absoluteString,
      "https://api.example.test/custom/runtime/auth/send_magic_code"
    )
    expectNoDifference(
      try requestJSONObject(sendRequest),
      ["app-id": "app-1", "email": "user@example.com"]
    )
    expectNoDifference(challenge.code, "")

    let verifyRecorder = AuthRequestRecorder()
    let verifier = InstantMagicCodeExchange.live(
      httpClient: InstantAuthHTTPClient { request in
        await verifyRecorder.record(request)
        return InstantAuthHTTPResponse(
          statusCode: 200,
          data: Data(
            #"{"user":{"id":"user-1","refresh_token":"token-2","email":"user@example.com","imageURL":"https://example.com/avatar.png","type":"user"},"created":true}"#.utf8
          )
        )
      }
    )
    let verification = try await verifier.verify(
      InstantMagicCodeVerifyRequest(
        appID: "app-1",
        apiURI: apiURI,
        email: "user@example.com",
        code: "123456",
        challenge: challenge,
        refreshToken: "token-1",
        extraFields: ["displayName": .string("Sample User")],
        verifiedAt: InstantTimestamp(milliseconds: 1_700_000_001_000)
      )
    )
    expectNoDifference(
      verification,
      InstantMagicCodeVerification(
        userID: "user-1",
        refreshToken: "token-2",
        created: true,
        email: "user@example.com",
        imageURL: "https://example.com/avatar.png",
        type: .user
      )
    )
    let verifyRequest = try #require(await verifyRecorder.onlyRequest())
    expectNoDifference(
      verifyRequest.url?.absoluteString,
      "https://api.example.test/custom/runtime/auth/verify_magic_code"
    )
    let verifyRequestBody = try #require(verifyRequest.httpBody)
    let body = try #require(
      JSONSerialization.jsonObject(with: verifyRequestBody) as? [String: Any]
    )
    expectNoDifference(body["app-id"] as? String, "app-1")
    expectNoDifference(body["refresh-token"] as? String, "token-1")
    expectNoDifference(
      (body["extra-fields"] as? [String: String])?["displayName"],
      "Sample User"
    )
  }

  @Test("Instant authAPI ID-token and OAuth calls use canonical endpoints and bodies")
  func oauthRequestsMatchCanonicalSDK() async throws {
    let apiURI = try #require(URL(string: "https://api.example.test/custom"))
    let idRecorder = AuthRequestRecorder()
    let idExchange = InstantIDTokenExchange.live(
      httpClient: InstantAuthHTTPClient { request in
        await idRecorder.record(request)
        return InstantAuthHTTPResponse(
          statusCode: 200,
          data: Data(
            #"{"user":{"id":"id-user","refresh_token":"id-refresh","email":"id@example.com","type":"user"},"created":false}"#.utf8
          )
        )
      }
    )
    let idVerification = try await idExchange.signIn(
      InstantIDTokenSignInRequest(
        appID: "app-1",
        apiURI: apiURI,
        clientName: "google-ios",
        idToken: "jwt",
        nonce: "nonce",
        refreshToken: "existing",
        signedInAt: InstantTimestamp(milliseconds: 1),
        makeID: { "unused" }
      )
    )
    expectNoDifference(idVerification.email, "id@example.com")
    expectNoDifference(idVerification.type, .user)
    let idRequest = try #require(await idRecorder.onlyRequest())
    expectNoDifference(
      idRequest.url?.absoluteString,
      "https://api.example.test/custom/runtime/oauth/id_token"
    )
    let idRequestBody = try #require(idRequest.httpBody)
    let idBody = try #require(
      JSONSerialization.jsonObject(with: idRequestBody) as? [String: String]
    )
    expectNoDifference(
      idBody,
      [
        "app_id": "app-1", "client_name": "google-ios", "id_token": "jwt",
        "nonce": "nonce", "refresh_token": "existing",
      ]
    )

    let oauthRecorder = AuthRequestRecorder()
    let oauthExchange = InstantOAuthExchange.live(
      httpClient: InstantAuthHTTPClient { request in
        await oauthRecorder.record(request)
        return InstantAuthHTTPResponse(
          statusCode: 200,
          data: Data(
            #"{"user":{"id":"oauth-user","refresh_token":"oauth-refresh","email":"oauth@example.com","type":"user"},"created":true}"#.utf8
          )
        )
      }
    )
    let oauthVerification = try await oauthExchange.signIn(
      InstantOAuthSignInRequest(
        appID: "app-1",
        apiURI: apiURI,
        code: "auth-code",
        codeVerifier: "verifier",
        refreshToken: "existing",
        signedInAt: InstantTimestamp(milliseconds: 1),
        makeID: { "unused" }
      )
    )
    expectNoDifference(oauthVerification.email, "oauth@example.com")
    expectNoDifference(oauthVerification.type, .user)
    let oauthRequest = try #require(await oauthRecorder.onlyRequest())
    expectNoDifference(
      oauthRequest.url?.absoluteString,
      "https://api.example.test/custom/runtime/oauth/token"
    )
    expectNoDifference(
      try requestJSONObject(oauthRequest),
      [
        "app_id": "app-1", "code": "auth-code", "code_verifier": "verifier",
        "refresh_token": "existing",
      ]
    )
  }

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
    let verifier = InstantRefreshTokenVerifier.live(httpClient: client)

    let verification = try await verifier.verify(
      InstantRefreshTokenVerificationRequest(
        appID: "app-1",
        apiURI: try #require(URL(string: "https://api.example.test/custom")),
        refreshToken: "refresh-token",
        userID: "untrusted-local-user",
        signedInAt: InstantTimestamp(milliseconds: 1_700_000_000_000),
        makeID: { "unused-id" }
      )
    )

    expectNoDifference(
      verification,
      InstantRefreshTokenVerification(
        userID: "user-1",
        refreshToken: "verified-token",
        email: "user@example.com"
      )
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
    let invalidator = InstantAuthTokenInvalidator.live(httpClient: client)

    try await invalidator.invalidate(
      InstantAuthTokenInvalidationRequest(
        appID: "app-1",
        apiURI: try #require(URL(string: "https://api.example.test/custom")),
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
