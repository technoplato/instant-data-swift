import Foundation
import InstantSwiftData

public struct AuthV3User: Hashable, Codable, InstantEntityModel {
  public struct Signup: Sendable {}

  public var id: InstantID<Self>
  public var email: String?
  public var displayName: String?
  public var username: String?
  public var imageURL: String?
  public var type: InstantAuthUserType?

  public static let instantNamespace = "$users"
  public static let identifier = InstantAttributePath<Self, String>("id")
  public static let email = InstantAttributePath<Self, String?>("email")
  public static let displayName = InstantAttributePath<Self, String?>("displayName")
  public static let username = InstantAttributePath<Self, String?>("username")
  public static let imageURL = InstantAttributePath<Self, String?>("imageURL")
  public static let type = InstantAttributePath<Self, String?>("type")
  public static let instantAttributes = [
    InstantAttribute(
      id: "$users/email",
      namespace: instantNamespace,
      name: "email",
      valueType: .string,
      isRequired: false,
      isIndexed: true,
      isUnique: true
    ),
    InstantAttribute(
      id: "$users/displayName",
      namespace: instantNamespace,
      name: "displayName",
      valueType: .string,
      isRequired: false,
      isIndexed: true
    ),
    InstantAttribute(
      id: "$users/username",
      namespace: instantNamespace,
      name: "username",
      valueType: .string,
      isRequired: false,
      isIndexed: true
    ),
    InstantAttribute(
      id: "$users/imageURL",
      namespace: instantNamespace,
      name: "imageURL",
      valueType: .string,
      isRequired: false
    ),
    InstantAttribute(
      id: "$users/type",
      namespace: instantNamespace,
      name: "type",
      valueType: .string,
      isRequired: false
    ),
  ]

  public init(
    id: InstantID<Self>,
    email: String? = nil,
    displayName: String? = nil,
    username: String? = nil,
    imageURL: String? = nil,
    type: InstantAuthUserType? = nil
  ) {
    self.id = id
    self.email = email
    self.displayName = displayName
    self.username = username
    self.imageURL = imageURL
    self.type = type
  }

  public init(snapshot: InstantEntitySnapshot) throws {
    id = InstantID(rawValue: snapshot.id)
    email = Self.optionalString("email", from: snapshot)
    displayName = Self.optionalString("displayName", from: snapshot)
    username = Self.optionalString("username", from: snapshot)
    imageURL = Self.optionalString("imageURL", from: snapshot)
    type = Self.optionalString("type", from: snapshot).flatMap(InstantAuthUserType.init(rawValue:))
  }

  private static func optionalString(
    _ name: String,
    from snapshot: InstantEntitySnapshot
  ) -> String? {
    guard case let .string(value) = snapshot.values[name]?.first else { return nil }
    return value
  }
}

public enum AuthV3Providers: InstantAuthProviderCatalog {
  public static let magicCode = AuthProvider.magicCode(
    email: .instant,
    extraFields: AuthV3User.Signup.self
  )
  public static let apple = AuthProvider.apple(
    clientName: "apple",
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

  public static let all = [magicCode, apple]
}
