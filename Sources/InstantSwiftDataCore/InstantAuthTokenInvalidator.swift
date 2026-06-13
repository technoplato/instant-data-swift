import Foundation

public struct InstantAuthTokenInvalidationRequest: Sendable {
  public var appID: String
  public var refreshToken: String
  public var signedOutAt: InstantTimestamp

  public init(
    appID: String,
    refreshToken: String,
    signedOutAt: InstantTimestamp
  ) {
    self.appID = appID
    self.refreshToken = refreshToken
    self.signedOutAt = signedOutAt
  }
}

public struct InstantAuthTokenInvalidator: Sendable {
  public var invalidate:
    @Sendable (InstantAuthTokenInvalidationRequest) async throws -> Void

  public init(
    invalidate: @escaping @Sendable (InstantAuthTokenInvalidationRequest) async throws -> Void
  ) {
    self.invalidate = invalidate
  }
}

extension InstantAuthTokenInvalidator {
  public static let local = Self(
    invalidate: { _ in }
  )
}
