import Dependencies
import Foundation

public enum InstantAuthMode: Hashable, Sendable {
  case enteringEmail
  case sendingMagicCode(email: String)
  case magicCodeSent(email: String)
  case verifyingMagicCode(email: String)
  case signingIn(providerID: InstantAuthProviderID)
  case signingOut
}

public enum InstantAuthStatus: Hashable, Sendable {
  case signedOut
  case working
  case signedIn(InstantAuthSession)
  case failed(InstantError)
}

public struct InstantAuthSignedInEvent: Hashable, Sendable {
  public var session: InstantAuthSession
  public var providerID: InstantAuthProviderID

  public init(session: InstantAuthSession, providerID: InstantAuthProviderID) {
    self.session = session
    self.providerID = providerID
  }
}

public struct InstantAuthUser<Entity: InstantEntityModel>: Hashable, Sendable {
  public var id: InstantID<Entity>
  public var session: InstantAuthSession

  public init(id: InstantID<Entity>, session: InstantAuthSession) {
    self.id = id
    self.session = session
  }
}

#if canImport(SwiftUI)
  import SwiftUI

  @MainActor
  public final class InstantAuthState<User: InstantEntityModel>: ObservableObject {
    @Published public var email = ""
    @Published public var magicCode = ""
    @Published public private(set) var mode: InstantAuthMode = .enteringEmail
    @Published public private(set) var status: InstantAuthStatus = .signedOut
    @Published public private(set) var session: InstantAuthSession?

    public let providers: [AuthProvider]

    public var user: InstantAuthUser<User>? {
      session.map {
        InstantAuthUser(
          id: InstantID(rawValue: $0.userID),
          session: $0
        )
      }
    }

    public var isBusy: Bool {
      status == .working
    }

    private var actionGeneration = 0
    private var activeAction: Task<Void, Never>?
    private var observationTask: Task<Void, Never>?

    public init(providers: [AuthProvider]) {
      self.providers = providers.filter { $0.kind != .magicCode }
    }

    public func startObservationIfNeeded() {
      @Dependency(\.defaultInstantSwiftData) var client
      startObservationIfNeeded(using: client)
    }

    public func startObservationIfNeeded(using client: InstantSwiftDataClient) {
      guard observationTask == nil else { return }
      observationTask = Task { @MainActor [weak self] in
        do {
          let subscription = try await client.subscribeAuthSession()
          for try await session in subscription {
            try Task.checkCancellation()
            guard let self else { return }
            self.session = session
            if !self.isBusy {
              self.status = session.map(InstantAuthStatus.signedIn) ?? .signedOut
            }
          }
        } catch is CancellationError {
        } catch {
          guard let self else { return }
          self.status = .failed(Self.authError(error, operation: "observe Instant auth"))
        }
        self?.observationTask = nil
      }
    }

    public func stopObservation() {
      observationTask?.cancel()
      observationTask = nil
    }

    public func resetMagicCode() {
      cancelActiveAction()
      magicCode = ""
      mode = .enteringEmail
      status = session.map(InstantAuthStatus.signedIn) ?? .signedOut
    }

    @discardableResult
    public func sendMagicCode(
      onChallengeSent: @escaping @MainActor @Sendable (InstantMagicCodeChallenge) -> Void = { _ in
      },
      onFailure: @escaping @MainActor @Sendable (InstantError) -> Void = { _ in }
    ) -> Task<Void, Never> {
      @Dependency(\.defaultInstantSwiftData) var client
      return sendMagicCode(
        using: client,
        onChallengeSent: onChallengeSent,
        onFailure: onFailure
      )
    }

    @discardableResult
    public func sendMagicCode(
      using client: InstantSwiftDataClient,
      onChallengeSent: @escaping @MainActor @Sendable (InstantMagicCodeChallenge) -> Void = { _ in
      },
      onFailure: @escaping @MainActor @Sendable (InstantError) -> Void = { _ in }
    ) -> Task<Void, Never> {
      let targetEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
      let generation = beginAction(mode: .sendingMagicCode(email: targetEmail))
      let task = Task { @MainActor [weak self] in
        do {
          let challenge = try await client.sendMagicCode(email: targetEmail)
          try Task.checkCancellation()
          guard let self, self.actionGeneration == generation else { return }
          self.email = challenge.email
          self.mode = .magicCodeSent(email: challenge.email)
          self.status = self.session.map(InstantAuthStatus.signedIn) ?? .signedOut
          self.activeAction = nil
          onChallengeSent(challenge)
        } catch is CancellationError {
          self?.finishCancellation(generation: generation)
        } catch {
          guard let self, self.actionGeneration == generation else { return }
          let error = Self.authError(error, operation: "send magic code")
          self.mode = .enteringEmail
          self.status = .failed(error)
          self.activeAction = nil
          onFailure(error)
        }
      }
      activeAction = task
      return task
    }

    @discardableResult
    public func verifyMagicCode(
      onSignedIn: @escaping @MainActor @Sendable (InstantAuthSignedInEvent) -> Void = { _ in },
      onFailure: @escaping @MainActor @Sendable (InstantError) -> Void = { _ in }
    ) -> Task<Void, Never> {
      @Dependency(\.defaultInstantSwiftData) var client
      return verifyMagicCode(using: client, onSignedIn: onSignedIn, onFailure: onFailure)
    }

    @discardableResult
    public func verifyMagicCode(
      using client: InstantSwiftDataClient,
      onSignedIn: @escaping @MainActor @Sendable (InstantAuthSignedInEvent) -> Void = { _ in },
      onFailure: @escaping @MainActor @Sendable (InstantError) -> Void = { _ in }
    ) -> Task<Void, Never> {
      let targetEmail: String
      switch mode {
      case .magicCodeSent(let email), .verifyingMagicCode(let email):
        targetEmail = email
      default:
        targetEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
      }
      let code = magicCode.trimmingCharacters(in: .whitespacesAndNewlines)
      let generation = beginAction(mode: .verifyingMagicCode(email: targetEmail))
      let task = Task { @MainActor [weak self] in
        do {
          let session = try await client.signInWithMagicCode(email: targetEmail, code: code)
          try Task.checkCancellation()
          guard let self, self.actionGeneration == generation else { return }
          let event = InstantAuthSignedInEvent(session: session, providerID: .magicCode)
          self.finishSignedIn(event, generation: generation)
          onSignedIn(event)
        } catch is CancellationError {
          self?.finishCancellation(generation: generation)
        } catch {
          guard let self, self.actionGeneration == generation else { return }
          let error = Self.authError(error, operation: "verify magic code")
          self.mode = .magicCodeSent(email: targetEmail)
          self.status = .failed(error)
          self.activeAction = nil
          onFailure(error)
        }
      }
      activeAction = task
      return task
    }

    @discardableResult
    public func signInAsGuest(
      onSignedIn: @escaping @MainActor @Sendable (InstantAuthSignedInEvent) -> Void = { _ in },
      onFailure: @escaping @MainActor @Sendable (InstantError) -> Void = { _ in }
    ) -> Task<Void, Never> {
      @Dependency(\.defaultInstantSwiftData) var client
      return signInAsGuest(using: client, onSignedIn: onSignedIn, onFailure: onFailure)
    }

    @discardableResult
    public func signInAsGuest(
      using client: InstantSwiftDataClient,
      onSignedIn: @escaping @MainActor @Sendable (InstantAuthSignedInEvent) -> Void = { _ in },
      onFailure: @escaping @MainActor @Sendable (InstantError) -> Void = { _ in }
    ) -> Task<Void, Never> {
      let generation = beginAction(mode: .signingIn(providerID: .guest))
      let task = Task { @MainActor [weak self] in
        do {
          let session = try await client.signInAsGuest()
          try Task.checkCancellation()
          guard let self, self.actionGeneration == generation else { return }
          let event = InstantAuthSignedInEvent(session: session, providerID: .guest)
          self.finishSignedIn(event, generation: generation)
          onSignedIn(event)
        } catch is CancellationError {
          self?.finishCancellation(generation: generation)
        } catch {
          self?.finishFailure(
            error,
            operation: "sign in as guest",
            generation: generation,
            onFailure: onFailure
          )
        }
      }
      activeAction = task
      return task
    }

    @discardableResult
    public func signOut(
      invalidateToken: Bool = true,
      onSignedOut: @escaping @MainActor @Sendable () -> Void = {},
      onFailure: @escaping @MainActor @Sendable (InstantError) -> Void = { _ in }
    ) -> Task<Void, Never> {
      @Dependency(\.defaultInstantSwiftData) var client
      return signOut(
        using: client,
        invalidateToken: invalidateToken,
        onSignedOut: onSignedOut,
        onFailure: onFailure
      )
    }

    @discardableResult
    public func signOut(
      using client: InstantSwiftDataClient,
      invalidateToken: Bool = true,
      onSignedOut: @escaping @MainActor @Sendable () -> Void = {},
      onFailure: @escaping @MainActor @Sendable (InstantError) -> Void = { _ in }
    ) -> Task<Void, Never> {
      let generation = beginAction(mode: .signingOut)
      let task = Task { @MainActor [weak self] in
        do {
          try await client.signOut(invalidateToken: invalidateToken)
          try Task.checkCancellation()
          guard let self, self.actionGeneration == generation else { return }
          self.session = nil
          self.status = .signedOut
          self.mode = .enteringEmail
          self.email = ""
          self.magicCode = ""
          self.activeAction = nil
          onSignedOut()
        } catch is CancellationError {
          self?.finishCancellation(generation: generation)
        } catch {
          self?.finishFailure(
            error,
            operation: "sign out",
            generation: generation,
            onFailure: onFailure
          )
        }
      }
      activeAction = task
      return task
    }

    @discardableResult
    public func signIn(
      _ provider: AuthProviderSelection,
      onProviderCompleted: @escaping @MainActor @Sendable (InstantAuthProviderCredential) -> Void =
        { _ in },
      onSignedIn: @escaping @MainActor @Sendable (InstantAuthSignedInEvent) -> Void = { _ in },
      onFailure: @escaping @MainActor @Sendable (InstantError) -> Void = { _ in }
    ) -> Task<Void, Never> {
      @Dependency(\.defaultInstantSwiftData) var client
      @Dependency(\.instantAuthProviderAuthorizer) var authorizer
      return signIn(
        provider,
        using: client,
        authorizer: authorizer,
        onProviderCompleted: onProviderCompleted,
        onSignedIn: onSignedIn,
        onFailure: onFailure
      )
    }

    @discardableResult
    public func signIn(
      _ provider: AuthProviderSelection,
      using client: InstantSwiftDataClient,
      authorizer: InstantAuthProviderAuthorizer,
      onProviderCompleted: @escaping @MainActor @Sendable (InstantAuthProviderCredential) -> Void =
        { _ in },
      onSignedIn: @escaping @MainActor @Sendable (InstantAuthSignedInEvent) -> Void = { _ in },
      onFailure: @escaping @MainActor @Sendable (InstantError) -> Void = { _ in }
    ) -> Task<Void, Never> {
      let generation = beginAction(mode: .signingIn(providerID: provider.id))
      let task = Task { @MainActor [weak self] in
        do {
          guard provider.kind != .magicCode else {
            throw InstantError(
              code: .validationFailed,
              operation: "sign in with auth provider",
              message: "Magic-code auth uses sendMagicCode and verifyMagicCode.",
              recovery: "Call the dedicated magic-code actions for the email provider."
            )
          }
          let credential = try await authorizer.authorize(provider)
          try Task.checkCancellation()
          guard credential.providerID == provider.id else {
            throw InstantError(
              code: .authFailed,
              operation: "sign in with auth provider",
              message: "The credential provider did not match the selected provider.",
              recovery: "Return credentials for '\(provider.id.rawValue)' from the authorizer."
            )
          }
          onProviderCompleted(credential)
          let session = try await Self.exchange(
            credential,
            provider: provider,
            using: client
          )
          try Task.checkCancellation()
          guard let self, self.actionGeneration == generation else { return }
          let event = InstantAuthSignedInEvent(session: session, providerID: provider.id)
          self.finishSignedIn(event, generation: generation)
          onSignedIn(event)
        } catch is CancellationError {
          self?.finishCancellation(generation: generation)
        } catch {
          self?.finishFailure(
            error,
            operation: "sign in with \(provider.id.rawValue)",
            generation: generation,
            onFailure: onFailure
          )
        }
      }
      activeAction = task
      return task
    }

    public func cancelActiveAction() {
      actionGeneration += 1
      activeAction?.cancel()
      activeAction = nil
      mode = .enteringEmail
      status = session.map(InstantAuthStatus.signedIn) ?? .signedOut
    }

    private func beginAction(mode: InstantAuthMode) -> Int {
      actionGeneration += 1
      activeAction?.cancel()
      activeAction = nil
      self.mode = mode
      status = .working
      return actionGeneration
    }

    private func finishSignedIn(
      _ event: InstantAuthSignedInEvent,
      generation: Int
    ) {
      guard actionGeneration == generation else { return }
      session = event.session
      status = .signedIn(event.session)
      mode = .enteringEmail
      magicCode = ""
      activeAction = nil
    }

    private func finishFailure(
      _ rawError: Error,
      operation: String,
      generation: Int,
      onFailure: @MainActor @Sendable (InstantError) -> Void
    ) {
      guard actionGeneration == generation else { return }
      let error = Self.authError(rawError, operation: operation)
      status = .failed(error)
      mode = .enteringEmail
      activeAction = nil
      onFailure(error)
    }

    private func finishCancellation(generation: Int) {
      guard actionGeneration == generation else { return }
      status = session.map(InstantAuthStatus.signedIn) ?? .signedOut
      mode = .enteringEmail
      activeAction = nil
    }

    private static func exchange(
      _ credential: InstantAuthProviderCredential,
      provider: AuthProvider,
      using client: InstantSwiftDataClient
    ) async throws -> InstantAuthSession {
      switch (provider.kind, credential.payload) {
      case (.idToken, .idToken(let value, let nonce)):
        guard let clientName = provider.clientName, !clientName.isEmpty else {
          throw InstantError(
            code: .validationFailed,
            operation: "exchange auth provider credential",
            message: "The ID-token provider is missing a client name.",
            recovery: "Declare the provider with its configured Instant client name."
          )
        }
        return try await client.signInWithIDToken(
          clientName: clientName,
          idToken: value,
          nonce: nonce
        )

      case (.authorizationCode, .authorizationCode(let value, let codeVerifier)):
        return try await client.signInWithOAuth(code: value, codeVerifier: codeVerifier)

      default:
        throw InstantError(
          code: .authFailed,
          operation: "exchange auth provider credential",
          message: "The credential payload did not match the selected provider kind.",
          recovery: "Return an ID token or authorization code matching the provider declaration."
        )
      }
    }

    private static func authError(_ error: Error, operation: String) -> InstantError {
      if let error = error as? InstantError { return error }
      return InstantError(
        code: .authFailed,
        operation: operation,
        message: String(describing: error),
        recovery: "Inspect the auth provider configuration and retry the action."
      )
    }
  }

  @dynamicMemberLookup
  @MainActor
  public struct InstantAuthProjection<User: InstantEntityModel> {
    fileprivate let state: InstantAuthState<User>

    public subscript<Value>(
      dynamicMember keyPath: ReferenceWritableKeyPath<InstantAuthState<User>, Value>
    ) -> Binding<Value> {
      Binding(
        get: { state[keyPath: keyPath] },
        set: { state[keyPath: keyPath] = $0 }
      )
    }
  }

  @MainActor
  @propertyWrapper
  public struct InstantAuth<User: InstantEntityModel, Providers: InstantAuthProviderCatalog>:
    DynamicProperty
  {
    @StateObject private var state: InstantAuthState<User>

    public init(_ user: User.Type, providers: Providers.Type) {
      _ = user
      _state = StateObject(
        wrappedValue: InstantAuthState<User>(providers: providers.all)
      )
    }

    public var wrappedValue: InstantAuthState<User> {
      state
    }

    public var projectedValue: InstantAuthProjection<User> {
      InstantAuthProjection(state: state)
    }

    public mutating func update() {
      state.startObservationIfNeeded()
    }
  }
#endif
