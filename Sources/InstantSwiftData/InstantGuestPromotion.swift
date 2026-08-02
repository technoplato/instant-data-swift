import Foundation

/// The identity result of exchanging a provider credential while a guest session is active.
public enum InstantGuestPromotionDisposition: Hashable, Sendable {
  /// The authenticated user ID stayed equal to the guest user ID.
  case upgradedInPlace

  /// The provider already belonged to another user, so Instant linked the guest to that user.
  ///
  /// Records owned by the guest still have the guest user ID. Applications must explicitly
  /// authorize access through Instant's linked-guest relations or perform a product-specific
  /// ownership transfer; this outcome does not imply that guest-owned records were migrated.
  case linkedToExistingUser

  /// Authentication produced a different user ID without canonical Instant-server link evidence.
  ///
  /// This is the truthful outcome for local or custom auth exchanges that do not explicitly attest
  /// that the exact guest refresh token was accepted by Instant's guest-linking endpoint.
  case identityChangedWithoutVerifiedLink
}

public struct InstantGuestPromotionResult: Hashable, Sendable {
  public var guestUserID: String
  public var session: InstantAuthSession
  public var disposition: InstantGuestPromotionDisposition

  public init(
    guestUserID: String,
    session: InstantAuthSession,
    disposition: InstantGuestPromotionDisposition
  ) {
    self.guestUserID = guestUserID
    self.session = session
    self.disposition = disposition
  }

  /// Whether the authenticated primary identity must access data through the linked guest.
  ///
  /// `nil` means that the exchange did not provide enough evidence to prove a guest link exists.
  public var requiresLinkedGuestAccess: Bool? {
    switch disposition {
    case .upgradedInPlace:
      false
    case .linkedToExistingUser:
      true
    case .identityChangedWithoutVerifiedLink:
      nil
    }
  }
}

extension InstantSwiftDataClient {
  /// Exchanges an ID token while preserving the active guest refresh token for Instant's
  /// guest-upgrade or guest-linking behavior.
  public func promoteGuestWithIDToken(
    clientName: String,
    idToken: String,
    nonce: String? = nil
  ) async throws -> InstantGuestPromotionResult {
    try await performGuestPromotionWithIDToken(
      clientName: clientName,
      idToken: idToken,
      nonce: nonce
    )
  }

  /// Exchanges an OAuth authorization code while preserving the active guest refresh token for
  /// Instant's guest-upgrade or guest-linking behavior.
  public func promoteGuestWithOAuth(
    code: String,
    codeVerifier: String? = nil
  ) async throws -> InstantGuestPromotionResult {
    try await performGuestPromotionWithOAuth(
      code: code,
      codeVerifier: codeVerifier
    )
  }
}

extension InstantGuestPromotionResult {
  init(_ result: InstantGuestPromotionExchangeResult) {
    guestUserID = result.guestUserID
    session = result.session
    switch result.disposition {
    case .upgradedInPlace:
      disposition = .upgradedInPlace
    case .linkedToExistingUser:
      disposition = .linkedToExistingUser
    case .identityChangedWithoutVerifiedLink:
      disposition = .identityChangedWithoutVerifiedLink
    }
  }
}
