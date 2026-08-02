import Foundation

/// Evidence supplied by an auth exchange that can prove how Instant processed a guest token.
public enum InstantGuestPromotionLinkEvidence: String, Hashable, Codable, Sendable {
  /// The canonical Instant auth endpoint accepted the exact refresh token from the guest session.
  case instantServerAcceptedGuestToken
}

/// The identity outcome produced by an atomic guest credential exchange.
public enum InstantGuestPromotionExchangeDisposition: Hashable, Sendable {
  case upgradedInPlace
  case linkedToExistingUser
  case identityChangedWithoutVerifiedLink
}

/// A guest promotion result committed by the runtime after its local auth compare-and-swap passed.
public struct InstantGuestPromotionExchangeResult: Hashable, Sendable {
  public var guestUserID: String
  public var session: InstantAuthSession
  public var disposition: InstantGuestPromotionExchangeDisposition

  public init(
    guestUserID: String,
    session: InstantAuthSession,
    disposition: InstantGuestPromotionExchangeDisposition
  ) {
    self.guestUserID = guestUserID
    self.session = session
    self.disposition = disposition
  }
}
