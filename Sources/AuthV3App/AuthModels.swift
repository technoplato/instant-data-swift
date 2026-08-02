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
    guard case .string(let value) = snapshot.values[name]?.first else { return nil }
    return value
  }
}

public struct AuthV3ProviderConfiguration: Hashable, Sendable {
  public var appleClientName: String
  public var applePresentation: InstantAuthProviderPresentation
  public var googleClientName: String
  public var googlePresentation: InstantAuthProviderPresentation
  public var browserRedirectURL: URL?

  public init(
    appleClientName: String = "apple",
    applePresentation: InstantAuthProviderPresentation = .native,
    googleClientName: String = "google",
    googlePresentation: InstantAuthProviderPresentation = .externalBrowser,
    browserRedirectURL: URL? = URL(string: "auth-v3://oauth-callback")
  ) {
    self.appleClientName = appleClientName
    self.applePresentation = applePresentation
    self.googleClientName = googleClientName
    self.googlePresentation = googlePresentation
    self.browserRedirectURL = browserRedirectURL
  }

  public static func environment(
    _ environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> Self {
    let defaults = Self()
    return Self(
      appleClientName: nonEmpty(environment["INSTANT_APPLE_AUTH_CLIENT_NAME"])
        ?? defaults.appleClientName,
      applePresentation: presentation(
        environment["INSTANT_APPLE_AUTH_PRESENTATION"],
        default: defaults.applePresentation
      ),
      googleClientName: nonEmpty(environment["INSTANT_GOOGLE_AUTH_CLIENT_NAME"])
        ?? defaults.googleClientName,
      googlePresentation: presentation(
        environment["INSTANT_GOOGLE_AUTH_PRESENTATION"],
        default: defaults.googlePresentation
      ),
      browserRedirectURL: nonEmpty(environment["INSTANT_OAUTH_REDIRECT_URL"])
        .flatMap(URL.init(string:))
        ?? defaults.browserRedirectURL
    )
  }

  private static func nonEmpty(_ rawValue: String?) -> String? {
    guard let value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty
    else { return nil }
    return value
  }

  private static func presentation(
    _ rawValue: String?,
    default defaultValue: InstantAuthProviderPresentation
  ) -> InstantAuthProviderPresentation {
    nonEmpty(rawValue).flatMap(InstantAuthProviderPresentation.init(rawValue:)) ?? defaultValue
  }
}

public enum AuthV3Providers: InstantAuthProviderCatalog {
  public static let magicCode = AuthProvider.magicCode(
    email: .instant,
    extraFields: AuthV3User.Signup.self
  )

  @available(*, deprecated, message: "Use providers(configuration:) for app-owned settings.")
  public static let apple = AuthProvider.apple(
    clientName: "apple",
    presentation: .native
  )

  @available(*, deprecated, message: "Use providers(configuration:) for app-owned settings.")
  public static let google = AuthProvider.google(
    clientName: "google-ios",
    presentation: .native
  )

  @available(*, deprecated, message: "Use providers(configuration:) for app-owned settings.")
  public static let github = AuthProvider.github(
    clientName: "github-web",
    presentation: .externalBrowser
  )

  @available(*, deprecated, message: "Use providers(configuration:) for app-owned settings.")
  public static let enterprise = AuthProvider.authorizationCode(
    id: "enterprise-oidc",
    clientName: "enterprise-oidc"
  )

  public static var all: [AuthProvider] {
    providers(configuration: .environment())
  }

  public static func providers(
    configuration: AuthV3ProviderConfiguration
  ) -> [AuthProvider] {
    [
      magicCode,
      .apple(
        clientName: configuration.appleClientName,
        presentation: configuration.applePresentation,
        redirectURL: configuration.browserRedirectURL
      ),
      .google(
        clientName: configuration.googleClientName,
        presentation: configuration.googlePresentation,
        redirectURL: configuration.browserRedirectURL
      ),
    ]
  }
}
