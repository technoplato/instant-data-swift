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

/// Where ``InstantAuthState``'s account linking is. Linking never changes the session.
public enum InstantAccountLinkingStatus: Hashable, Sendable {
  /// Nothing is in progress.
  case idle
  /// The other identity is signing in with this provider on a second sign-in.
  case signingInSecond(InstantAuthProviderID)
  /// A link code is on its way to `email`.
  case sendingCode(email: String)
  /// A link code was sent to `email`. Verifying it links that identity.
  case codeSent(email: String)
  /// The two identities are writing the link.
  case linking
  /// The identity `userID` is being removed from the link.
  case unlinking(userID: String)
  /// The last linking action failed.
  case failed(InstantError)
}

public enum InstantAuthIdentityTransition: Hashable, Sendable {
  case signedIn
  case guestPromoted(InstantGuestPromotionResult)
}

public struct InstantAuthSignedInEvent: Hashable, Sendable {
  public var session: InstantAuthSession
  public var providerID: InstantAuthProviderID
  public var identityTransition: InstantAuthIdentityTransition

  public init(
    session: InstantAuthSession,
    providerID: InstantAuthProviderID,
    identityTransition: InstantAuthIdentityTransition = .signedIn
  ) {
    self.session = session
    self.providerID = providerID
    self.identityTransition = identityTransition
  }
}

public struct InstantAuthUser<Entity: InstantEntityModel>: Hashable, Sendable {
  public var id: InstantID<Entity>
  public var session: InstantAuthSession

  public init(id: InstantID<Entity>, session: InstantAuthSession) {
    self.id = id
    self.session = session
  }

  public var email: String? { session.email }
  public var imageURL: String? { session.imageURL }
  public var type: InstantAuthUserType { session.type ?? (session.isGuest ? .guest : .user) }
  public var isGuest: Bool { session.isGuest }
}

#if canImport(SwiftUI)
  import SwiftUI

  @MainActor
  public final class InstantAuthState<User: InstantEntityModel>: ObservableObject {
    @Published public var email = ""
    @Published public var magicCode = ""
    @Published public private(set) var mode: InstantAuthMode = .enteringEmail
    @Published public private(set) var status: InstantAuthStatus = .signedOut
    @Published public private(set) var session: InstantAuthSession? {
      didSet {
        guard oldValue?.userID != session?.userID else { return }
        // The link belongs to the previous user; a pending link code would link into the wrong account.
        accountLink = nil
        if oldValue != nil {
          cancelLinking()
        }
      }
    }

    public let providers: [AuthProvider]

    /// Providers that complete through an external credential exchange.
    ///
    /// Magic code remains available through `sendMagicCode` and `verifyMagicCode`, but it should
    /// not be rendered as a provider button that calls `signIn(_:)`.
    public var credentialProviders: [AuthProvider] {
      providers.filter { $0.kind != .magicCode }
    }

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
          let event = try await Self.exchange(
            credential,
            provider: provider,
            using: client
          )
          try Task.checkCancellation()
          guard let self, self.actionGeneration == generation else { return }
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

    // MARK: Account linking

    /// The account link of this session's identity, as the last read, link, or unlink returned it.
    ///
    /// `nil` before ``refreshAccountLink(using:links:onFailure:)`` reads it, when the identity is in no link, and after
    /// the session changes to another user.
    @Published public private(set) var accountLink: InstantAccountLink?

    /// Where account linking is. Linking never changes ``session``.
    @Published public private(set) var linking: InstantAccountLinkingStatus = .idle

    /// The email address a link code was sent to, while that code can still be entered.
    ///
    /// A wrong code keeps it, so the code can be entered again. Linking, ``cancelLinking()``, and a new link action
    /// clear it.
    @Published public private(set) var linkCodeEmail: String?

    private var linkingGeneration = 0
    private var linkingTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    /// The second sign-in a link code was sent from, held until the code is verified or linking is cancelled.
    private var heldLinkSignIn: InstantSecondSignIn?

    /// Reads ``accountLink`` from Instant through a temporary twin of the session.
    @discardableResult
    public func refreshAccountLink(
      links: InstantAccountLinks = .default,
      onFailure: @escaping @MainActor @Sendable (InstantError) -> Void = { _ in }
    ) -> Task<Void, Never> {
      @Dependency(\.defaultInstantSwiftData) var client
      return refreshAccountLink(using: client, links: links, onFailure: onFailure)
    }

    /// Reads ``accountLink`` from Instant through a temporary twin of `client`'s session.
    ///
    /// A failure leaves ``accountLink`` as it was and, unless a linking action is in progress, sets ``linking`` to
    /// ``InstantAccountLinkingStatus/failed(_:)``.
    @discardableResult
    public func refreshAccountLink(
      using client: InstantSwiftDataClient,
      links: InstantAccountLinks = .default,
      onFailure: @escaping @MainActor @Sendable (InstantError) -> Void = { _ in }
    ) -> Task<Void, Never> {
      refreshTask?.cancel()
      let task = Task { @MainActor [weak self] in
        do {
          guard try await client.authSession() != nil else {
            self?.accountLink = nil
            return
          }
          let link = try await links.accountLink(sharingSessionOf: client)
          try Task.checkCancellation()
          self?.accountLink = link
        } catch is CancellationError {
        } catch {
          guard let self else { return }
          let error = Self.authError(error, operation: "read the linked sign-ins")
          if self.linking == .idle {
            self.linking = .failed(error)
          }
          onFailure(error)
        }
      }
      refreshTask = task
      return task
    }

    /// Signs another identity in with `provider` and links it with this session's identity.
    @discardableResult
    public func linkAnotherSignIn(
      _ provider: AuthProviderSelection,
      links: InstantAccountLinks = .default,
      deviceName: String? = nil,
      onLinked: @escaping @MainActor @Sendable (InstantAccountLink) -> Void = { _ in },
      onFailure: @escaping @MainActor @Sendable (InstantError) -> Void = { _ in }
    ) -> Task<Void, Never> {
      @Dependency(\.defaultInstantSwiftData) var client
      @Dependency(\.instantAuthProviderAuthorizer) var authorizer
      return linkAnotherSignIn(
        provider,
        using: client,
        authorizer: authorizer,
        links: links,
        deviceName: deviceName,
        onLinked: onLinked,
        onFailure: onFailure
      )
    }

    /// Signs another identity in with `provider` and links it with `client`'s identity.
    ///
    /// The other identity signs in on a second sign-in beside `client` (``InstantSecondSignIn``), so `client`'s session
    /// never changes. ``InstantAccountLinks/link(primary:second:secondProvider:deviceName:now:)`` then links the two,
    /// and the second sign-in closes on every path. ``linking`` moves from
    /// ``InstantAccountLinkingStatus/signingInSecond(_:)`` to ``InstantAccountLinkingStatus/linking`` and back to
    /// ``InstantAccountLinkingStatus/idle``, or to ``InstantAccountLinkingStatus/failed(_:)``. Cancelling the provider's
    /// sign-in returns to ``InstantAccountLinkingStatus/idle`` without a failure.
    @discardableResult
    public func linkAnotherSignIn(
      _ provider: AuthProviderSelection,
      using client: InstantSwiftDataClient,
      authorizer: InstantAuthProviderAuthorizer,
      links: InstantAccountLinks = .default,
      deviceName: String? = nil,
      onLinked: @escaping @MainActor @Sendable (InstantAccountLink) -> Void = { _ in },
      onFailure: @escaping @MainActor @Sendable (InstantError) -> Void = { _ in }
    ) -> Task<Void, Never> {
      let previous = takeHeldLinkSignIn()
      let generation = beginLinking(.signingInSecond(provider.id))
      let task = Task { @MainActor [weak self] in
        await previous?.close()
        var opened: InstantSecondSignIn?
        do {
          guard provider.kind != .magicCode else {
            throw InstantError(
              code: .validationFailed,
              operation: "link another sign-in",
              message: "Email codes link through sendLinkMagicCode and verifyLinkMagicCode.",
              recovery: "Call the link-code actions for an email sign-in."
            )
          }
          let second = try await InstantSecondSignIn.open(beside: client, registering: links.attributes)
          opened = second
          let credential = try await authorizer.authorize(provider)
          try Task.checkCancellation()
          _ = try await second.signIn(with: credential, provider: provider)
          try Task.checkCancellation()
          self?.continueLinking(.linking, generation: generation)
          let link = try await links.link(
            primary: client,
            second: second,
            secondProvider: InstantAccountLinkProvider(providerID: provider.id),
            deviceName: deviceName
          )
          await second.close()
          self?.finishLinking(link, generation: generation, onLinked: onLinked)
        } catch {
          await opened?.close()
          self?.failLinking(
            error,
            operation: "link another sign-in with \(provider.id.rawValue)",
            generation: generation,
            onFailure: onFailure
          )
        }
      }
      linkingTask = task
      return task
    }

    /// Sends a link code to `email` from a new second sign-in, and holds that sign-in for
    /// ``verifyLinkMagicCode(email:code:links:deviceName:onLinked:onFailure:)``.
    @discardableResult
    public func sendLinkMagicCode(
      email: String,
      links: InstantAccountLinks = .default,
      onCodeSent: @escaping @MainActor @Sendable (InstantMagicCodeChallenge) -> Void = { _ in },
      onFailure: @escaping @MainActor @Sendable (InstantError) -> Void = { _ in }
    ) -> Task<Void, Never> {
      @Dependency(\.defaultInstantSwiftData) var client
      return sendLinkMagicCode(
        email: email,
        using: client,
        links: links,
        onCodeSent: onCodeSent,
        onFailure: onFailure
      )
    }

    /// Sends a link code to `email` from a new second sign-in beside `client`, and holds that sign-in until the code is
    /// verified or ``cancelLinking()`` closes it. A code sent earlier is discarded.
    @discardableResult
    public func sendLinkMagicCode(
      email rawEmail: String,
      using client: InstantSwiftDataClient,
      links: InstantAccountLinks = .default,
      onCodeSent: @escaping @MainActor @Sendable (InstantMagicCodeChallenge) -> Void = { _ in },
      onFailure: @escaping @MainActor @Sendable (InstantError) -> Void = { _ in }
    ) -> Task<Void, Never> {
      let email = rawEmail.trimmingCharacters(in: .whitespacesAndNewlines)
      let previous = takeHeldLinkSignIn()
      let generation = beginLinking(.sendingCode(email: email))
      let task = Task { @MainActor [weak self] in
        await previous?.close()
        var opened: InstantSecondSignIn?
        do {
          let second = try await InstantSecondSignIn.open(beside: client, registering: links.attributes)
          opened = second
          let challenge = try await second.sendMagicCode(email: email)
          try Task.checkCancellation()
          guard let self, self.linkingGeneration == generation else {
            await second.close()
            return
          }
          self.heldLinkSignIn = second
          self.linkCodeEmail = challenge.email
          self.linking = .codeSent(email: challenge.email)
          self.linkingTask = nil
          onCodeSent(challenge)
        } catch {
          await opened?.close()
          self?.failLinking(
            error,
            operation: "send a link code",
            generation: generation,
            onFailure: onFailure
          )
        }
      }
      linkingTask = task
      return task
    }

    /// Verifies a link code and links that identity with this session's identity.
    @discardableResult
    public func verifyLinkMagicCode(
      email: String,
      code: String,
      links: InstantAccountLinks = .default,
      deviceName: String? = nil,
      onLinked: @escaping @MainActor @Sendable (InstantAccountLink) -> Void = { _ in },
      onFailure: @escaping @MainActor @Sendable (InstantError) -> Void = { _ in }
    ) -> Task<Void, Never> {
      @Dependency(\.defaultInstantSwiftData) var client
      return verifyLinkMagicCode(
        email: email,
        code: code,
        using: client,
        links: links,
        deviceName: deviceName,
        onLinked: onLinked,
        onFailure: onFailure
      )
    }

    /// Verifies the link code on the held second sign-in, then links that identity with `client`'s identity.
    ///
    /// A wrong code keeps the held sign-in, so the code can be entered again. Once the code signs in, the held sign-in
    /// closes when linking ends, whether linking succeeds or fails.
    @discardableResult
    public func verifyLinkMagicCode(
      email rawEmail: String,
      code rawCode: String,
      using client: InstantSwiftDataClient,
      links: InstantAccountLinks = .default,
      deviceName: String? = nil,
      onLinked: @escaping @MainActor @Sendable (InstantAccountLink) -> Void = { _ in },
      onFailure: @escaping @MainActor @Sendable (InstantError) -> Void = { _ in }
    ) -> Task<Void, Never> {
      let email = rawEmail.trimmingCharacters(in: .whitespacesAndNewlines)
      let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
      let held = heldLinkSignIn
      let generation = beginLinking(.signingInSecond(.magicCode))
      let task = Task { @MainActor [weak self] in
        guard let held else {
          self?.failLinking(
            InstantError(
              code: .validationFailed,
              operation: "verify a link code",
              message: "No link code is waiting to be verified.",
              recovery: "Send a code to the other sign-in's email address first."
            ),
            operation: "verify a link code",
            generation: generation,
            onFailure: onFailure
          )
          return
        }
        do {
          _ = try await held.signInWithMagicCode(email: email, code: code)
          try Task.checkCancellation()
        } catch {
          self?.failLinking(
            error,
            operation: "verify a link code",
            generation: generation,
            onFailure: onFailure
          )
          return
        }
        self?.releaseHeldLinkSignIn(held)
        self?.continueLinking(.linking, generation: generation)
        do {
          let link = try await links.link(
            primary: client,
            second: held,
            secondProvider: .magicCode,
            deviceName: deviceName
          )
          await held.close()
          self?.finishLinking(link, generation: generation, onLinked: onLinked)
        } catch {
          await held.close()
          self?.failLinking(
            error,
            operation: "link another sign-in by email code",
            generation: generation,
            onFailure: onFailure
          )
        }
      }
      linkingTask = task
      return task
    }

    /// Stops any linking action and closes a held second sign-in. The returned task finishes once that sign-in is
    /// closed.
    @discardableResult
    public func cancelLinking() -> Task<Void, Never> {
      linkingGeneration += 1
      linkingTask?.cancel()
      linkingTask = nil
      linking = .idle
      let held = takeHeldLinkSignIn()
      return Task { await held?.close() }
    }

    /// Removes `memberUserID` from this session's account link.
    @discardableResult
    public func unlink(
      memberUserID: String,
      links: InstantAccountLinks = .default,
      onUnlinked: @escaping @MainActor @Sendable (InstantAccountLink?) -> Void = { _ in },
      onFailure: @escaping @MainActor @Sendable (InstantError) -> Void = { _ in }
    ) -> Task<Void, Never> {
      @Dependency(\.defaultInstantSwiftData) var client
      return unlink(
        memberUserID: memberUserID,
        using: client,
        links: links,
        onUnlinked: onUnlinked,
        onFailure: onFailure
      )
    }

    /// Removes `memberUserID` from `client`'s account link through a temporary twin of its session, and sets
    /// ``accountLink`` to what remains (`nil` when the link is gone).
    @discardableResult
    public func unlink(
      memberUserID: String,
      using client: InstantSwiftDataClient,
      links: InstantAccountLinks = .default,
      onUnlinked: @escaping @MainActor @Sendable (InstantAccountLink?) -> Void = { _ in },
      onFailure: @escaping @MainActor @Sendable (InstantError) -> Void = { _ in }
    ) -> Task<Void, Never> {
      let previous = takeHeldLinkSignIn()
      let generation = beginLinking(.unlinking(userID: memberUserID))
      let task = Task { @MainActor [weak self] in
        await previous?.close()
        do {
          let remaining = try await links.unlink(memberUserID: memberUserID, primary: client)
          guard let self else { return }
          self.accountLink = remaining
          guard self.linkingGeneration == generation else { return }
          self.linking = .idle
          self.linkingTask = nil
          onUnlinked(remaining)
        } catch {
          self?.failLinking(
            error,
            operation: "unlink a sign-in",
            generation: generation,
            onFailure: onFailure
          )
        }
      }
      linkingTask = task
      return task
    }

    private func beginLinking(_ status: InstantAccountLinkingStatus) -> Int {
      linkingGeneration += 1
      linkingTask?.cancel()
      linkingTask = nil
      linking = status
      return linkingGeneration
    }

    private func continueLinking(_ status: InstantAccountLinkingStatus, generation: Int) {
      guard linkingGeneration == generation else { return }
      linking = status
    }

    private func finishLinking(
      _ link: InstantAccountLink,
      generation: Int,
      onLinked: @MainActor @Sendable (InstantAccountLink) -> Void
    ) {
      // The link exists on the server whether or not this action was superseded.
      accountLink = link
      guard linkingGeneration == generation else { return }
      linking = .idle
      linkingTask = nil
      onLinked(link)
    }

    private func failLinking(
      _ rawError: Error,
      operation: String,
      generation: Int,
      onFailure: @MainActor @Sendable (InstantError) -> Void
    ) {
      guard linkingGeneration == generation else { return }
      linkingTask = nil
      guard !(rawError is CancellationError) else {
        linking = .idle
        return
      }
      let error = Self.authError(rawError, operation: operation)
      linking = .failed(error)
      onFailure(error)
    }

    private func takeHeldLinkSignIn() -> InstantSecondSignIn? {
      let held = heldLinkSignIn
      heldLinkSignIn = nil
      linkCodeEmail = nil
      return held
    }

    private func releaseHeldLinkSignIn(_ signIn: InstantSecondSignIn) {
      guard heldLinkSignIn === signIn else { return }
      heldLinkSignIn = nil
      linkCodeEmail = nil
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
    ) async throws -> InstantAuthSignedInEvent {
      let isPromotingGuest = try await client.authSession()?.isGuest == true
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
        if isPromotingGuest {
          let result = try await client.promoteGuestWithIDToken(
            clientName: clientName,
            idToken: value,
            nonce: nonce
          )
          return InstantAuthSignedInEvent(
            session: result.session,
            providerID: provider.id,
            identityTransition: .guestPromoted(result)
          )
        } else {
          let session = try await client.signInWithIDToken(
            clientName: clientName,
            idToken: value,
            nonce: nonce
          )
          return InstantAuthSignedInEvent(session: session, providerID: provider.id)
        }

      case (.authorizationCode, .authorizationCode(let value, let codeVerifier)):
        if isPromotingGuest {
          let result = try await client.promoteGuestWithOAuth(
            code: value,
            codeVerifier: codeVerifier
          )
          return InstantAuthSignedInEvent(
            session: result.session,
            providerID: provider.id,
            identityTransition: .guestPromoted(result)
          )
        } else {
          let session = try await client.signInWithOAuth(
            code: value,
            codeVerifier: codeVerifier
          )
          return InstantAuthSignedInEvent(session: session, providerID: provider.id)
        }

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
