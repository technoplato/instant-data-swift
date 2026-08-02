import Dependencies
import Foundation

#if canImport(CryptoKit)
  import CryptoKit
#endif

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
  public var redirectURL: URL?

  public init(
    id: InstantAuthProviderID,
    kind: Kind,
    clientName: String? = nil,
    title: String,
    systemImage: String,
    presentation: InstantAuthProviderPresentation? = nil,
    redirectURL: URL? = nil
  ) {
    self.id = id
    self.kind = kind
    self.clientName = clientName
    self.title = title
    self.systemImage = systemImage
    self.presentation = presentation
    self.redirectURL = redirectURL
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
    presentation: InstantAuthProviderPresentation,
    redirectURL: URL? = nil
  ) -> Self {
    switch presentation {
    case .native:
      idToken(
        id: "apple",
        clientName: clientName,
        title: "Continue with Apple",
        systemImage: "apple.logo",
        presentation: presentation
      )
    case .externalBrowser:
      authorizationCode(
        id: "apple",
        clientName: clientName,
        title: "Continue with Apple",
        systemImage: "apple.logo",
        presentation: presentation,
        redirectURL: redirectURL
      )
    }
  }

  public static func google(
    clientName: String,
    presentation: InstantAuthProviderPresentation,
    redirectURL: URL? = nil
  ) -> Self {
    switch presentation {
    case .native:
      idToken(
        id: "google",
        clientName: clientName,
        title: "Continue with Google",
        systemImage: "g.circle.fill",
        presentation: presentation
      )
    case .externalBrowser:
      authorizationCode(
        id: "google",
        clientName: clientName,
        title: "Continue with Google",
        systemImage: "g.circle.fill",
        presentation: presentation,
        redirectURL: redirectURL
      )
    }
  }

  public static func github(
    clientName: String,
    presentation: InstantAuthProviderPresentation,
    redirectURL: URL? = nil
  ) -> Self {
    authorizationCode(
      id: "github",
      clientName: clientName,
      title: "Continue with GitHub",
      systemImage: "chevron.left.forwardslash.chevron.right",
      presentation: presentation,
      redirectURL: redirectURL
    )
  }

  public static func authorizationCode(
    id: String,
    clientName: String,
    title: String? = nil,
    systemImage: String = "person.badge.key",
    presentation: InstantAuthProviderPresentation = .externalBrowser,
    redirectURL: URL? = nil
  ) -> Self {
    Self(
      id: InstantAuthProviderID(rawValue: id),
      kind: .authorizationCode,
      clientName: clientName,
      title: title ?? "Continue with \(id)",
      systemImage: systemImage,
      presentation: presentation,
      redirectURL: redirectURL
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
    authorize:
      @escaping @Sendable (AuthProvider) async throws
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
  static var testValue: InstantAuthProviderAuthorizer {
    InstantAuthProviderAuthorizer { provider in
      throw InstantError(
        code: .implementationFailed,
        operation: "authorize with \(provider.id.rawValue)",
        message: "No auth provider authorizer has been configured.",
        recovery: "Install a native or browser authorizer in DependencyValues."
      )
    }
  }
}

extension InstantAuthProviderAuthorizerKey: DependencyKey {
  static var liveValue: InstantAuthProviderAuthorizer {
    InstantAuthProviderAuthorizer { provider in
      @Dependency(\.defaultInstantSwiftData) var client

      switch provider.kind {
      case .authorizationCode:
        guard provider.presentation == .externalBrowser else {
          throw InstantError(
            code: .validationFailed,
            operation: "authorize with \(provider.id.rawValue)",
            message: "Authorization-code providers must use external-browser presentation.",
            recovery: "Declare '\(provider.id.rawValue)' with presentation: .externalBrowser."
          )
        }
        #if canImport(AuthenticationServices) && canImport(CryptoKit) && (canImport(AppKit) || canImport(UIKit))
          return try await BrowserOAuthAuthorizer.shared.authorize(
            provider: provider,
            client: client
          )
        #else
          throw InstantError(
            code: .implementationFailed,
            operation: "authorize with \(provider.id.rawValue)",
            message: "Browser authentication is unavailable on this platform.",
            recovery:
              "Use an Apple platform with AuthenticationServices or inject a provider authorizer."
          )
        #endif

      case .idToken:
        guard provider.presentation == .native else {
          throw InstantError(
            code: .validationFailed,
            operation: "authorize with \(provider.id.rawValue)",
            message: "ID-token providers must use native presentation.",
            recovery:
              "Use .native with a token-producing authorizer, or declare an external-browser authorization-code provider."
          )
        }
        guard provider.id.rawValue == "apple" else {
          throw InstantError(
            code: .implementationFailed,
            operation: "authorize with \(provider.id.rawValue)",
            message: "No native \(provider.id.rawValue) token authorizer is installed.",
            recovery:
              "Inject InstantAuthProviderAuthorizer from the provider SDK, or configure this provider for external-browser OAuth."
          )
        }
        #if canImport(AuthenticationServices) && canImport(CryptoKit) && (canImport(AppKit) || canImport(UIKit))
          return try await AppleIDAuthorizer.shared.authorize(provider: provider)
        #else
          throw InstantError(
            code: .implementationFailed,
            operation: "authorize with Apple",
            message: "Native Sign in with Apple is unavailable on this platform.",
            recovery:
              "Run on a supported Apple platform or configure Apple for external-browser OAuth."
          )
        #endif

      case .magicCode:
        throw InstantError(
          code: .validationFailed,
          operation: "authorize with magic code",
          message: "Magic-code auth does not use a provider authorizer.",
          recovery: "Call sendMagicCode and verifyMagicCode instead."
        )
      }
    }
  }
}

extension DependencyValues {
  public var instantAuthProviderAuthorizer: InstantAuthProviderAuthorizer {
    get { self[InstantAuthProviderAuthorizerKey.self] }
    set { self[InstantAuthProviderAuthorizerKey.self] = newValue }
  }
}

#if canImport(CryptoKit)
  struct InstantOAuthPKCE: Hashable, Sendable {
    let verifier: String
    let challenge: String

    init(verifier: String) throws {
      let allowedCharacters = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"
      )
      guard
        (43...128).contains(verifier.utf8.count),
        verifier.unicodeScalars.allSatisfy(allowedCharacters.contains)
      else {
        throw InstantError(
          code: .validationFailed,
          operation: "create OAuth PKCE challenge",
          message: "The PKCE verifier must contain 43 to 128 unreserved ASCII characters.",
          recovery: "Generate a fresh high-entropy verifier before starting browser authentication."
        )
      }
      self.verifier = verifier
      self.challenge = Self.base64URLEncoded(
        Data(SHA256.hash(data: Data(verifier.utf8)))
      )
    }

    static func generate() throws -> Self {
      try Self(
        verifier: (UUID().uuidString + UUID().uuidString)
          .replacingOccurrences(of: "-", with: "")
      )
    }

    func appendingChallenge(to url: URL) throws -> URL {
      guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
        throw InstantError(
          code: .validationFailed,
          operation: "create OAuth PKCE challenge",
          message: "The OAuth authorization URL could not be parsed.",
          recovery: "Check the Instant API URL and OAuth client configuration."
        )
      }
      var queryItems = components.queryItems ?? []
      queryItems.removeAll {
        $0.name == "code_challenge" || $0.name == "code_challenge_method"
      }
      queryItems.append(URLQueryItem(name: "code_challenge", value: challenge))
      queryItems.append(URLQueryItem(name: "code_challenge_method", value: "S256"))
      components.queryItems = queryItems
      guard let url = components.url else {
        throw InstantError(
          code: .validationFailed,
          operation: "create OAuth PKCE challenge",
          message: "The OAuth authorization URL could not encode its PKCE challenge.",
          recovery: "Check the Instant API URL and OAuth client configuration."
        )
      }
      return url
    }

    fileprivate static func base64URLEncoded(_ data: Data) -> String {
      data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
    }
  }
#endif

struct InstantAuthAttemptTracker: Sendable {
  private var activeID: UUID?

  var isActive: Bool { activeID != nil }
  var currentID: UUID? { activeID }

  mutating func begin() throws -> UUID {
    guard activeID == nil else {
      throw InstantError(
        code: .authFailed,
        operation: "begin auth attempt",
        message: "Another authentication request is already in progress.",
        recovery: "Finish or cancel the current request before starting another one."
      )
    }
    let id = UUID()
    activeID = id
    return id
  }

  func matches(_ id: UUID) -> Bool {
    activeID == id
  }

  @discardableResult
  mutating func finish(_ id: UUID) -> Bool {
    guard activeID == id else { return false }
    activeID = nil
    return true
  }
}

enum InstantOAuthCallbackValue: Hashable, Sendable {
  case authorizationCode(String)
  case providerError(String)
}

struct InstantOAuthCallbackValidator {
  static func validate(
    _ callbackURL: URL,
    redirectURL: URL,
    expectedState: String
  ) throws -> InstantOAuthCallbackValue {
    guard matches(callbackURL, redirectURL) else {
      throw callbackError(
        "The provider returned an unexpected OAuth callback URL.",
        recovery: "Verify the app callback scheme and Instant authorized redirect origin."
      )
    }
    guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
      throw callbackError(
        "The OAuth callback URL could not be parsed.",
        recovery: "Retry sign-in and inspect the configured redirect URL if the problem continues."
      )
    }

    let query = Dictionary(grouping: components.queryItems ?? [], by: \.name)
    let returnedStates = query["state"] ?? []
    guard returnedStates.count <= 1 else {
      throw callbackError(
        "The OAuth callback contained a duplicate 'state' field.",
        recovery: "Close the sign-in window and begin a fresh authentication request."
      )
    }
    guard
      let returnedState = returnedStates.only?.value,
      returnedState == expectedState
    else {
      throw callbackError(
        "The OAuth callback state did not match the request.",
        recovery: "Close the sign-in window and begin a fresh authentication request."
      )
    }
    for name in ["code", "error"] where (query[name]?.count ?? 0) > 1 {
      throw callbackError(
        "The OAuth callback contained a duplicate '\(name)' field.",
        recovery: "Close the sign-in window and begin a fresh authentication request."
      )
    }
    if query["code"] != nil, query["error"] != nil {
      throw callbackError(
        "The OAuth callback contained both an authorization code and an error.",
        recovery: "Close the sign-in window and begin a fresh authentication request."
      )
    }
    if let providerError = query["error"]?.only?.value {
      let description = query["error_description"]?.first?.value ?? providerError
      return .providerError(description)
    }
    guard
      let code = query["code"]?.only?.value?.trimmingCharacters(in: .whitespacesAndNewlines),
      !code.isEmpty
    else {
      throw callbackError(
        "The OAuth callback did not contain an authorization code.",
        recovery: "Complete authentication in the provider window and retry."
      )
    }
    return .authorizationCode(code)
  }

  private static func matches(_ callbackURL: URL, _ redirectURL: URL) -> Bool {
    callbackURL.scheme?.caseInsensitiveCompare(redirectURL.scheme ?? "") == .orderedSame
      && (callbackURL.host ?? "").caseInsensitiveCompare(redirectURL.host ?? "") == .orderedSame
      && callbackURL.path == redirectURL.path
  }

  private static func callbackError(_ message: String, recovery: String) -> InstantError {
    InstantError(
      code: .authFailed,
      operation: "authorize with browser",
      message: message,
      recovery: recovery
    )
  }
}

extension Collection {
  fileprivate var only: Element? {
    count == 1 ? first : nil
  }
}

#if canImport(AuthenticationServices) && canImport(CryptoKit) && (canImport(AppKit) || canImport(UIKit))
  @MainActor
  private func instantAuthPresentationAnchor() -> ASPresentationAnchor? {
    #if canImport(AppKit) && !targetEnvironment(macCatalyst)
      return NSApplication.shared.keyWindow
        ?? NSApplication.shared.windows.first(where: \.isVisible)
    #elseif canImport(UIKit)
      let windows = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap(\.windows)
      return windows.first(where: \.isKeyWindow) ?? windows.first(where: { !$0.isHidden })
    #else
      return nil
    #endif
  }

  @MainActor
  public final class BrowserOAuthAuthorizer: NSObject,
    ASWebAuthenticationPresentationContextProviding
  {
    public static let shared = BrowserOAuthAuthorizer()

    private var continuation: CheckedContinuation<InstantAuthProviderCredential, Error>?
    private var session: ASWebAuthenticationSession?
    private var presentationWindow: ASPresentationAnchor?
    private var providerID: InstantAuthProviderID?
    private var redirectURL: URL?
    private var pkce: InstantOAuthPKCE?
    private var state: String?
    private var attempts = InstantAuthAttemptTracker()

    public func authorize(
      provider: AuthProvider,
      client: InstantSwiftDataClient
    ) async throws -> InstantAuthProviderCredential {
      guard continuation == nil, !attempts.isActive else {
        throw InstantError(
          code: .authFailed,
          operation: "authorize with \(provider.id.rawValue)",
          message: "Another browser authentication request is already in progress.",
          recovery: "Finish or cancel the current sign-in before starting another one."
        )
      }
      guard provider.kind == .authorizationCode, provider.presentation == .externalBrowser else {
        throw InstantError(
          code: .validationFailed,
          operation: "authorize with \(provider.id.rawValue)",
          message: "Browser authentication requires an authorization-code provider.",
          recovery: "Declare the provider with presentation: .externalBrowser."
        )
      }
      guard
        let clientName = provider.clientName?.trimmingCharacters(in: .whitespacesAndNewlines),
        !clientName.isEmpty
      else {
        throw InstantError(
          code: .validationFailed,
          operation: "authorize with \(provider.id.rawValue)",
          message: "The browser provider is missing its Instant client name.",
          recovery: "Set clientName to the OAuth client configured in the Instant dashboard."
        )
      }
      guard
        let redirectURL = provider.redirectURL,
        let callbackScheme = redirectURL.scheme?.lowercased(),
        !callbackScheme.isEmpty,
        callbackScheme != "http",
        callbackScheme != "https"
      else {
        throw InstantError(
          code: .validationFailed,
          operation: "authorize with \(provider.id.rawValue)",
          message: "Browser authentication requires an app-owned custom-scheme callback URL.",
          recovery:
            "Set redirectURL to a registered callback such as 'my-app://oauth-callback' and authorize its origin in Instant."
        )
      }
      guard let presentationWindow = instantAuthPresentationAnchor() else {
        throw InstantError(
          code: .authFailed,
          operation: "authorize with \(provider.id.rawValue)",
          message: "No active application window can present browser authentication.",
          recovery: "Make the app active and retry sign-in from a visible window."
        )
      }

      let pkce = try InstantOAuthPKCE.generate()
      let state = UUID().uuidString.replacingOccurrences(of: "-", with: "")
      let baseURL = try client.oauthAuthorizationURL(
        clientName: clientName,
        redirectURL: redirectURL
      )
      let authorizationURL = try Self.appending(
        URLQueryItem(name: "state", value: state),
        to: pkce.appendingChallenge(to: baseURL)
      )
      let attemptID = try attempts.begin()

      self.providerID = provider.id
      self.redirectURL = redirectURL
      self.pkce = pkce
      self.state = state
      self.presentationWindow = presentationWindow

      return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
          self.continuation = continuation
          let session = ASWebAuthenticationSession(
            url: authorizationURL,
            callbackURLScheme: callbackScheme
          ) { [weak self] callbackURL, error in
            Task { @MainActor in
              self?.complete(attemptID: attemptID, callbackURL: callbackURL, error: error)
            }
          }
          session.presentationContextProvider = self
          session.prefersEphemeralWebBrowserSession = false
          self.session = session
          guard session.start() else {
            finish(
              attemptID: attemptID,
              throwing: InstantError(
                code: .authFailed,
                operation: "authorize with \(provider.id.rawValue)",
                message: "The system browser authentication session could not start.",
                recovery: "Make the app active, verify the callback URL, and retry sign-in."
              )
            )
            return
          }
        }
      } onCancel: {
        Task { @MainActor [weak self] in
          self?.cancel(attemptID: attemptID)
        }
      }
    }

    @available(
      *,
      deprecated,
      message:
        "Construct AuthProvider with an explicit redirectURL and call authorize(provider:client:)."
    )
    public func authorize(
      clientName: String,
      providerID: InstantAuthProviderID,
      client: InstantSwiftDataClient
    ) async throws -> InstantAuthProviderCredential {
      guard let redirectURL = URL(string: "instantauth://oauth-callback") else {
        throw InstantError(
          code: .validationFailed,
          operation: "authorize with browser",
          message: "The compatibility callback URL could not be constructed.",
          recovery: "Migrate to authorize(provider:client:) with an explicit redirect URL."
        )
      }
      return try await authorize(
        provider: .authorizationCode(
          id: providerID.rawValue,
          clientName: clientName,
          redirectURL: redirectURL
        ),
        client: client
      )
    }

    public func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
      guard let presentationWindow else {
        preconditionFailure("Browser authentication started without a presentation window.")
      }
      return presentationWindow
    }

    private func complete(attemptID: UUID, callbackURL: URL?, error: Error?) {
      guard attempts.matches(attemptID) else { return }
      if let error {
        let nsError = error as NSError
        if nsError.domain == ASWebAuthenticationSessionError.errorDomain,
          nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue
        {
          finish(attemptID: attemptID, throwing: CancellationError())
        } else {
          finish(
            attemptID: attemptID,
            throwing: InstantError(
              code: .authFailed,
              operation: "authorize with browser",
              message: String(describing: error),
              recovery: "Check the provider configuration and retry browser sign-in."
            )
          )
        }
        return
      }
      guard
        let callbackURL,
        let expectedRedirectURL = redirectURL,
        let state
      else {
        finish(
          attemptID: attemptID,
          throwing: InstantError(
            code: .authFailed,
            operation: "authorize with browser",
            message: "The browser authentication callback was incomplete.",
            recovery: "Close the sign-in window and begin a fresh authentication request."
          )
        )
        return
      }
      do {
        switch try InstantOAuthCallbackValidator.validate(
          callbackURL,
          redirectURL: expectedRedirectURL,
          expectedState: state
        ) {
        case .authorizationCode(let code):
          guard let providerID, let pkce else {
            throw InstantError(
              code: .authFailed,
              operation: "authorize with browser",
              message: "The browser authentication attempt lost its provider or PKCE verifier.",
              recovery: "Close the sign-in window and begin a fresh authentication request."
            )
          }
          finish(
            attemptID: attemptID,
            returning: InstantAuthProviderCredential(
              providerID: providerID,
              payload: .authorizationCode(value: code, codeVerifier: pkce.verifier)
            )
          )
        case .providerError(let description):
          finish(
            attemptID: attemptID,
            throwing: InstantError(
              code: .authFailed,
              operation: "authorize with browser",
              message: "The provider rejected authentication: \(description)",
              recovery: "Review the provider consent or account state, then retry sign-in."
            )
          )
        }
      } catch {
        finish(attemptID: attemptID, throwing: error)
      }
    }

    private func cancel(attemptID: UUID) {
      guard attempts.matches(attemptID) else { return }
      session?.cancel()
      finish(attemptID: attemptID, throwing: CancellationError())
    }

    private func finish(
      attemptID: UUID,
      returning credential: InstantAuthProviderCredential
    ) {
      let continuation = clear(attemptID: attemptID)
      continuation?.resume(returning: credential)
    }

    private func finish(attemptID: UUID, throwing error: Error) {
      let continuation = clear(attemptID: attemptID)
      continuation?.resume(throwing: error)
    }

    private func clear(
      attemptID: UUID
    ) -> CheckedContinuation<InstantAuthProviderCredential, Error>? {
      guard attempts.finish(attemptID) else { return nil }
      let continuation = continuation
      self.continuation = nil
      session = nil
      presentationWindow = nil
      providerID = nil
      redirectURL = nil
      pkce = nil
      state = nil
      return continuation
    }

    private static func appending(_ item: URLQueryItem, to url: URL) throws -> URL {
      guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
        throw InstantError(
          code: .validationFailed,
          operation: "create OAuth authorization URL",
          message: "The OAuth authorization URL could not be parsed.",
          recovery: "Check the Instant API URL and OAuth client configuration."
        )
      }
      var queryItems = components.queryItems ?? []
      queryItems.removeAll { $0.name == item.name }
      queryItems.append(item)
      components.queryItems = queryItems
      guard let url = components.url else {
        throw InstantError(
          code: .validationFailed,
          operation: "create OAuth authorization URL",
          message: "The OAuth authorization URL could not encode its request state.",
          recovery: "Check the Instant API URL and OAuth client configuration."
        )
      }
      return url
    }

  }

  @MainActor
  public final class AppleIDAuthorizer: NSObject, ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding
  {
    public static let shared = AppleIDAuthorizer()

    private var continuation: CheckedContinuation<InstantAuthProviderCredential, Error>?
    private var controller: ASAuthorizationController?
    private var presentationWindow: ASPresentationAnchor?
    private var providerID: InstantAuthProviderID?
    private var nonce: String?
    private var activeControllerID: ObjectIdentifier?
    private var attempts = InstantAuthAttemptTracker()

    public func authorize(provider: AuthProvider) async throws -> InstantAuthProviderCredential {
      guard continuation == nil, !attempts.isActive else {
        throw InstantError(
          code: .authFailed,
          operation: "authorize with Apple",
          message: "Another Sign in with Apple request is already in progress.",
          recovery: "Finish or cancel the current sign-in before starting another one."
        )
      }
      guard
        provider.id.rawValue == "apple",
        provider.kind == .idToken,
        provider.presentation == .native
      else {
        throw InstantError(
          code: .validationFailed,
          operation: "authorize with Apple",
          message: "Native Sign in with Apple requires an Apple ID-token provider.",
          recovery: "Declare Apple with presentation: .native."
        )
      }
      guard let presentationWindow = instantAuthPresentationAnchor() else {
        throw InstantError(
          code: .authFailed,
          operation: "authorize with Apple",
          message: "No active application window can present Sign in with Apple.",
          recovery: "Make the app active and retry sign-in from a visible window."
        )
      }

      let nonce = try InstantOAuthPKCE.generate().verifier
      let request = ASAuthorizationAppleIDProvider().createRequest()
      request.requestedScopes = [.fullName, .email]
      request.nonce = Self.sha256Hex(nonce)

      let controller = ASAuthorizationController(authorizationRequests: [request])
      controller.delegate = self
      controller.presentationContextProvider = self
      let attemptID = try attempts.begin()
      self.controller = controller
      self.activeControllerID = ObjectIdentifier(controller)
      self.presentationWindow = presentationWindow
      self.providerID = provider.id
      self.nonce = nonce

      return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
          self.continuation = continuation
          controller.performRequests()
        }
      } onCancel: {
        Task { @MainActor [weak self] in
          self?.cancel(attemptID: attemptID)
        }
      }
    }

    public nonisolated func authorizationController(
      controller: ASAuthorizationController,
      didCompleteWithAuthorization authorization: ASAuthorization
    ) {
      let controllerID = ObjectIdentifier(controller)
      let credential = authorization.credential as? ASAuthorizationAppleIDCredential
      let tokenData = credential?.identityToken
      Task { @MainActor [weak self] in
        guard
          let self,
          self.activeControllerID == controllerID,
          let attemptID = self.attempts.currentID
        else { return }
        guard
          let tokenData,
          let identityToken = String(data: tokenData, encoding: .utf8),
          !identityToken.isEmpty,
          let providerID = self.providerID,
          let nonce = self.nonce
        else {
          self.finish(
            attemptID: attemptID,
            throwing: InstantError(
              code: .authFailed,
              operation: "authorize with Apple",
              message: "Apple completed authentication without a usable identity token.",
              recovery: "Verify the Sign in with Apple capability and retry."
            )
          )
          return
        }
        self.finish(
          attemptID: attemptID,
          returning: InstantAuthProviderCredential(
            providerID: providerID,
            payload: .idToken(value: identityToken, nonce: nonce)
          )
        )
      }
    }

    public nonisolated func authorizationController(
      controller: ASAuthorizationController,
      didCompleteWithError error: Error
    ) {
      let controllerID = ObjectIdentifier(controller)
      let nsError = error as NSError
      Task { @MainActor [weak self] in
        guard
          let self,
          self.activeControllerID == controllerID,
          let attemptID = self.attempts.currentID
        else { return }
        if nsError.domain == ASAuthorizationError.errorDomain,
          nsError.code == ASAuthorizationError.canceled.rawValue
        {
          self.finish(attemptID: attemptID, throwing: CancellationError())
        } else {
          self.finish(
            attemptID: attemptID,
            throwing: InstantError(
              code: .authFailed,
              operation: "authorize with Apple",
              message: String(describing: error),
              recovery:
                "Verify the Sign in with Apple capability, client name, and account state, then retry."
            )
          )
        }
      }
    }

    public func presentationAnchor(for _: ASAuthorizationController) -> ASPresentationAnchor {
      guard let presentationWindow else {
        preconditionFailure("Sign in with Apple started without a presentation window.")
      }
      return presentationWindow
    }

    private func cancel(attemptID: UUID) {
      guard attempts.matches(attemptID) else { return }
      if #available(iOS 16, macCatalyst 16, tvOS 16, watchOS 9, *) {
        controller?.cancel()
      }
      finish(attemptID: attemptID, throwing: CancellationError())
    }

    private func finish(
      attemptID: UUID,
      returning credential: InstantAuthProviderCredential
    ) {
      let continuation = clear(attemptID: attemptID)
      continuation?.resume(returning: credential)
    }

    private func finish(attemptID: UUID, throwing error: Error) {
      let continuation = clear(attemptID: attemptID)
      continuation?.resume(throwing: error)
    }

    private func clear(
      attemptID: UUID
    ) -> CheckedContinuation<InstantAuthProviderCredential, Error>? {
      guard attempts.finish(attemptID) else { return nil }
      let continuation = continuation
      self.continuation = nil
      controller = nil
      activeControllerID = nil
      presentationWindow = nil
      providerID = nil
      nonce = nil
      return continuation
    }

    private static func sha256Hex(_ value: String) -> String {
      SHA256.hash(data: Data(value.utf8))
        .map { String(format: "%02x", $0) }
        .joined()
    }
  }
#endif
