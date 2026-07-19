import Foundation
import InstantSwiftData

public struct AuthV3User: Hashable, Codable, InstantEntityModel {
  public struct Signup: Sendable {}

  public var id: InstantID<Self>
  public var email: String?

  public static let instantNamespace = "$users"
  public static let email = InstantAttributePath<Self, String?>("email")
  public static let instantAttributes = [
    InstantAttribute(
      id: "$users/email",
      namespace: instantNamespace,
      name: "email",
      valueType: .string,
      isRequired: false,
      isIndexed: true,
      isUnique: true
    )
  ]

  public init(snapshot: InstantEntitySnapshot) throws {
    id = InstantID(rawValue: snapshot.id)
    if case let .string(email) = snapshot.values["email"]?.first {
      self.email = email
    } else {
      self.email = nil
    }
  }
}

public enum AuthV3Providers: InstantAuthProviderCatalog {
  public static let magicCode = AuthProvider.magicCode(
    email: .instant,
    extraFields: AuthV3User.Signup.self
  )
  public static let apple = AuthProvider.apple(
    clientName: "apple-ios",
    presentation: .native
  )
  public static let google = AuthProvider.google(
    clientName: "google-ios",
    presentation: .native
  )
  public static let github = AuthProvider.github(
    clientName: "github-web",
    presentation: .externalBrowser
  )
  public static let enterprise = AuthProvider.authorizationCode(
    id: "enterprise-oidc",
    clientName: "enterprise-oidc"
  )

  public static let all = [magicCode, apple, google, github, enterprise]
}
