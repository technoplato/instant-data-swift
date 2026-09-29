import CustomDump
import Foundation
import InstantSwiftData
import Testing

/// An auth session carries the refresh token that authenticates the account, so every way Swift
/// prints or reflects a session, or a value that contains one, must leave the token and the email
/// address out. Apps log these values: AuthV3App posts `String(describing: event.identityTransition)`
/// in a notification for host loggers.
@Suite
struct InstantAuthSessionRedactionTests {
  private static let refreshToken = "secret-refresh-token-7f3a"
  private static let email = "person@example.com"
  private static let imageURL = "https://example.com/avatar.png"
  private static let signedInAt = InstantTimestamp(milliseconds: 1_700_000_000_000)

  private static let session = InstantAuthSession(
    appID: "app-1",
    userID: "user-1",
    refreshToken: refreshToken,
    isGuest: false,
    createdAt: signedInAt,
    updatedAt: signedInAt,
    email: email,
    imageURL: imageURL,
    type: .user
  )

  @Test("a session prints its identity with the refresh token and email redacted")
  func descriptionRedactsRefreshTokenAndEmail() {
    expectNoDifference(
      String(describing: Self.session),
      #"InstantAuthSession(appID: "app-1", userID: "user-1", isGuest: false, email: <present>, refreshToken: <redacted>)"#
    )
    expectNoDifference(String(reflecting: Self.session), String(describing: Self.session))
  }

  @Test("a session without a refresh token or email prints nil for both")
  func descriptionPrintsNilForMissingValues() {
    let guest = InstantAuthSession(
      appID: "app-1",
      userID: "guest-1",
      isGuest: true,
      createdAt: Self.signedInAt,
      updatedAt: Self.signedInAt
    )

    expectNoDifference(
      String(describing: guest),
      #"InstantAuthSession(appID: "app-1", userID: "guest-1", isGuest: true, email: nil, refreshToken: nil)"#
    )
  }

  @Test("custom dumps show every field, with credentials and personal data as presence markers")
  func customDumpRedactsRefreshTokenAndPersonalData() {
    expectNoDifference(
      String(customDumping: Self.session),
      """
      InstantAuthSession(
        appID: "app-1",
        userID: "user-1",
        refreshToken: <redacted>,
        email: <present>,
        imageURL: <present>,
        type: .user,
        isGuest: false,
        createdAt: InstantTimestamp(milliseconds: 1700000000000),
        updatedAt: InstantTimestamp(milliseconds: 1700000000000)
      )
      """
    )
  }

  @Test("no rendering of a session, or of a value that carries one, contains the token or email")
  func everyRenderingOfEveryCarrierRedacts() {
    let promotion = InstantGuestPromotionResult(
      guestUserID: "guest-1",
      session: Self.session,
      disposition: .linkedToExistingUser
    )
    let carriers: [(name: String, value: Any)] = [
      ("session", Self.session),
      ("optional session", Optional(Self.session) as Any),
      ("session array", [Self.session]),
      ("guest promotion result", promotion),
      ("identity transition", InstantAuthIdentityTransition.guestPromoted(promotion)),
      (
        "signed-in event",
        InstantAuthSignedInEvent(
          session: Self.session,
          providerID: InstantAuthProviderID(rawValue: "google"),
          identityTransition: .guestPromoted(promotion)
        )
      ),
      ("auth status", InstantAuthStatus.signedIn(Self.session)),
      (
        "guest promotion exchange result",
        InstantGuestPromotionExchangeResult(
          guestUserID: "guest-1",
          session: Self.session,
          disposition: .linkedToExistingUser
        )
      ),
      ("magic-code sign-in result", InstantMagicCodeSignInResult(session: Self.session, created: false)),
    ]

    for carrier in carriers {
      var dumped = ""
      dump(carrier.value, to: &dumped)
      var customDumped = ""
      customDump(carrier.value, to: &customDumped)
      let renderings = [
        ("interpolation", "\(carrier.value)"),
        ("describing", String(describing: carrier.value)),
        ("reflecting", String(reflecting: carrier.value)),
        ("dump", dumped),
        ("customDump", customDumped),
      ]
      for (method, rendering) in renderings {
        #expect(!rendering.contains(Self.refreshToken), "\(carrier.name) via \(method)")
        #expect(!rendering.contains(Self.email), "\(carrier.name) via \(method)")
        #expect(!rendering.contains(Self.imageURL), "\(carrier.name) via \(method)")
        #expect(rendering.contains("user-1"), "\(carrier.name) via \(method)")
      }
    }
  }

  @Test("persistence, equality, and hashing still use the refresh token")
  func codableEquatableAndHashableKeepTheRefreshToken() throws {
    let data = try JSONEncoder().encode(Self.session)
    #expect(String(decoding: data, as: UTF8.self).contains(Self.refreshToken))
    let decoded = try JSONDecoder().decode(InstantAuthSession.self, from: data)
    expectNoDifference(decoded.refreshToken, Self.refreshToken)
    expectNoDifference(decoded.email, Self.email)
    #expect(decoded == Self.session)

    var rotated = Self.session
    rotated.refreshToken = "rotated-refresh-token"
    #expect(rotated != Self.session)
    #expect(Set([Self.session, rotated]).count == 2)
  }
}
