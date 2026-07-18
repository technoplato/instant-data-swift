import Dependencies
import Foundation

public struct InstantAuthProviderID: RawRepresentable, Hashable, Codable, Sendable, Identifiable {
  public var id: String { rawValue }
  public var rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  public static let guest = Self(rawValue: "guest")
  public static let magicCode = Self(rawValue: "magic-code")
}

public enum InstantAuthProviderPresentation: String, Hashable, Codable, Sendable {
  case native
  case externalBrowser
}

public enum InstantAuthEmailSource: String, Hashable, Codable, Sendable {
  case instant
}

public struct AuthProvider: Hashable, Codable, Sendable, Identifiable {
  public enum Kind: String, Hashable, Codable, Sendable {
    case magicCode
    case idToken
    case authorizationCode
  }

  public var id: InstantAuthProviderID
  public var kind: Kind
  public var clientName: String?
  public var title: String
  public var systemImage: String
  public var presentation: InstantAuthProviderPresentation?

  public init(
    id: InstantAuthProviderID,
    kind: Kind,
    clientName: String? = nil,
    title: String,
    systemImage: String,
    presentation: InstantAuthProviderPresentation? = nil
  ) {
    self.id = id
    self.kind = kind
    self.clientName = clientName
    self.title = title
    self.systemImage = systemImage
    self.presentation = presentation
  }

  public static func magicCode<ExtraFields>(
    email _: InstantAuthEmailSource,
    extraFields _: ExtraFields.Type
  ) -> Self {
    Self(
      id: .magicCode,
      kind: .magicCode,
      title: "Email",
      systemImage: "envelope"
    )
  }

  public static func apple(
    clientName: String,
    presentation: InstantAuthProviderPresentation
  ) -> Self {
    idToken(
      id: "apple",
      clientName: clientName,
      title: "Continue with Apple",
      systemImage: "apple.logo",
      presentation: presentation
    )
  }

  public static func google(
    clientName: String,
    presentation: InstantAuthProviderPresentation
  ) -> Self {
    idToken(
      id: "google",
      clientName: clientName,
      title: "Continue with Google",
      systemImage: "g.circle",
      presentation: presentation
    )
  }

  public static func github(
    clientName: String,
    presentation: InstantAuthProviderPresentation
  ) -> Self {
    authorizationCode(
      id: "github",
      clientName: clientName,
      title: "Continue with GitHub",
      systemImage: "chevron.left.forwardslash.chevron.right",
      presentation: presentation
    )
  }

  public static func authorizationCode(
    id: String,
    clientName: String,
    title: String? = nil,
    systemImage: String = "person.badge.key",
    presentation: InstantAuthProviderPresentation = .externalBrowser
  ) -> Self {
    Self(
      id: InstantAuthProviderID(rawValue: id),
      kind: .authorizationCode,
      clientName: clientName,
      title: title ?? "Continue with \(id)",
      systemImage: systemImage,
      presentation: presentation
    )
  }

  private static func idToken(
    id: String,
    clientName: String,
    title: String,
    systemImage: String,
    presentation: InstantAuthProviderPresentation
  ) -> Self {
    Self(
      id: InstantAuthProviderID(rawValue: id),
      kind: .idToken,
      clientName: clientName,
      title: title,
      systemImage: systemImage,
      presentation: presentation
    )
  }
}

public typealias AuthProviderSelection = AuthProvider

public protocol InstantAuthProviderCatalog {
  static var all: [AuthProvider] { get }
}

public struct InstantAuthProviderCredential: Hashable, Codable, Sendable {
  public enum Payload: Hashable, Codable, Sendable {
    case idToken(value: String, nonce: String?)
    case authorizationCode(value: String, codeVerifier: String?)
  }

  public var providerID: InstantAuthProviderID
  public var payload: Payload

  public init(providerID: InstantAuthProviderID, payload: Payload) {
    self.providerID = providerID
    self.payload = payload
  }
}

public struct InstantAuthProviderAuthorizer: Sendable {
  public var authorize: @Sendable (AuthProvider) async throws -> InstantAuthProviderCredential

  public init(
    authorize: @escaping @Sendable (AuthProvider) async throws
      -> InstantAuthProviderCredential
  ) {
    self.authorize = authorize
  }
}

private enum InstantAuthProviderAuthorizerKey: TestDependencyKey {
  static let testValue = InstantAuthProviderAuthorizer { provider in
    throw InstantError(
      code: .implementationFailed,
      operation: "authorize with \(provider.id.rawValue)",
      message: "No auth provider authorizer has been configured.",
      recovery: "Install a native or browser authorizer in DependencyValues."
    )
  }
}

extension InstantAuthProviderAuthorizerKey: DependencyKey {
  static let liveValue = testValue
}

extension DependencyValues {
  public var instantAuthProviderAuthorizer: InstantAuthProviderAuthorizer {
    get { self[InstantAuthProviderAuthorizerKey.self] }
    set { self[InstantAuthProviderAuthorizerKey.self] = newValue }
  }
}
