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

#if canImport(AuthenticationServices)
import AuthenticationServices
#endif
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

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
  static let liveValue = InstantAuthProviderAuthorizer { provider in
    @Dependency(\.defaultInstantSwiftData) var client

    if provider.presentation == .externalBrowser || provider.kind == .authorizationCode {
      #if canImport(AuthenticationServices)
      guard let clientName = provider.clientName else {
        throw InstantError(
          code: .validationFailed,
          operation: "authorize with browser",
          message: "Provider missing clientName.",
          recovery: "Set clientName on AuthProvider."
        )
      }
      return try await BrowserOAuthAuthorizer.shared.authorize(
        clientName: clientName,
        providerID: provider.id,
        client: client
      )
      #endif
    }

    if provider.id.rawValue == "apple" {
      #if canImport(AuthenticationServices)
      do {
        return try await AppleIDAuthorizer.shared.authorize(provider: provider)
      } catch {
        let nsError = error as NSError
        if nsError.domain == ASAuthorizationError.errorDomain && nsError.code == 1000 {
          let clientName = provider.clientName ?? "apple"
          return try await BrowserOAuthAuthorizer.shared.authorize(
            clientName: clientName,
            providerID: provider.id,
            client: client
          )
        }
        throw error
      }
      #else
      throw InstantError(
        code: .implementationFailed,
        operation: "authorize with apple",
        message: "AuthenticationServices is not available on this platform.",
        recovery: "Run on iOS or macOS."
      )
      #endif
    }

    return try await testValue.authorize(provider)
  }
}

extension DependencyValues {
  public var instantAuthProviderAuthorizer: InstantAuthProviderAuthorizer {
    get { self[InstantAuthProviderAuthorizerKey.self] }
    set { self[InstantAuthProviderAuthorizerKey.self] = newValue }
  }
}

#if canImport(AuthenticationServices)
@MainActor
public final class BrowserOAuthAuthorizer: NSObject, ASWebAuthenticationPresentationContextProviding {
  public static let shared = BrowserOAuthAuthorizer()

  public func authorize(
    clientName: String,
    providerID: InstantAuthProviderID,
    client: InstantSwiftDataClient
  ) async throws -> InstantAuthProviderCredential {
    let callbackScheme = "instantauth"
    guard let redirectURL = URL(string: "\(callbackScheme)://oauth-callback") else {
      throw InstantError(
        code: .validationFailed,
        operation: "authorize with browser",
        message: "Failed to construct callback URL.",
        recovery: "Check callback scheme format."
      )
    }
    let authURL = try client.oauthAuthorizationURL(clientName: clientName, redirectURL: redirectURL)

    return try await withCheckedThrowingContinuation { continuation in
      let session = ASWebAuthenticationSession(
        url: authURL,
        callbackURLScheme: callbackScheme
      ) { callbackURL, error in
        if let error = error {
          continuation.resume(throwing: error)
          return
        }
        guard let callbackURL = callbackURL,
              let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
          continuation.resume(throwing: InstantError(
            code: .authFailed,
            operation: "authorize with browser",
            message: "No authorization code returned from OAuth callback URL.",
            recovery: "Complete authentication in the browser window."
          ))
          return
        }
        let credential = InstantAuthProviderCredential(
          providerID: providerID,
          payload: .authorizationCode(value: code, codeVerifier: nil)
        )
        continuation.resume(returning: credential)
      }
      session.presentationContextProvider = self
      session.prefersEphemeralWebBrowserSession = false
      session.start()
    }
  }

  public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
    #if os(macOS)
    return NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? NSWindow()
    #elseif os(iOS)
    return UIApplication.shared.windows.first { $0.isKeyWindow } ?? UIApplication.shared.windows.first ?? UIWindow()
    #else
    fatalError("Unsupported OS")
    #endif
  }
}

@MainActor
public final class AppleIDAuthorizer: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
  public static let shared = AppleIDAuthorizer()

  private var continuation: CheckedContinuation<InstantAuthProviderCredential, Error>?

  public func authorize(provider: AuthProvider) async throws -> InstantAuthProviderCredential {
    return try await withCheckedThrowingContinuation { continuation in
      self.continuation = continuation
      let appleIDProvider = ASAuthorizationAppleIDProvider()
      let request = appleIDProvider.createRequest()
      request.requestedScopes = [.fullName, .email]

      let controller = ASAuthorizationController(authorizationRequests: [request])
      controller.delegate = self
      controller.presentationContextProvider = self
      controller.performRequests()
    }
  }

  public nonisolated func authorizationController(
    controller: ASAuthorizationController,
    didCompleteWithAuthorization authorization: ASAuthorization
  ) {
    Task { @MainActor in
      if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
         let identityTokenData = appleIDCredential.identityToken,
         let identityToken = String(data: identityTokenData, encoding: .utf8) {
        let credential = InstantAuthProviderCredential(
          providerID: InstantAuthProviderID(rawValue: "apple"),
          payload: .idToken(value: identityToken, nonce: nil)
        )
        self.continuation?.resume(returning: credential)
        self.continuation = nil
      } else {
        self.continuation?.resume(throwing: InstantError(
          code: .implementationFailed,
          operation: "authorize with apple",
          message: "Failed to extract identity token from Apple credential.",
          recovery: "Try signing in with Apple again or verify system settings."
        ))
        self.continuation = nil
      }
    }
  }

  public nonisolated func authorizationController(
    controller: ASAuthorizationController,
    didCompleteWithError error: Error
  ) {
    Task { @MainActor in
      self.continuation?.resume(throwing: error)
      self.continuation = nil
    }
  }

  public func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
    #if os(macOS)
    return NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? NSWindow()
    #elseif os(iOS)
    return UIApplication.shared.windows.first { $0.isKeyWindow } ?? UIApplication.shared.windows.first ?? UIWindow()
    #else
    fatalError("Unsupported OS")
    #endif
  }
}
#endif


