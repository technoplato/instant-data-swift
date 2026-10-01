import Foundation

/// A second identity of the same Instant app, signed in on a temporary client beside the app's primary client.
///
/// An Instant client keeps one auth session per store, and signing in replaces it. A provider sign-in on the primary
/// client therefore promotes or links the primary identity instead of proving that the person controls another one:
/// like Instant's TypeScript client, the runtime sends a guest's refresh token with magic-code and OAuth exchanges, and
/// any current refresh token with ID-token exchanges. A second sign-in has its own temporary store and its own
/// connection to Instant, and it starts with no session. Its exchanges carry no refresh token, and nothing it does
/// touches the primary's session, store, or outbox.
///
/// ```swift
/// let second = try await InstantSecondSignIn.open(beside: client)
/// do {
///   _ = try await second.signIn(with: credential, provider: provider)
///   try await second.transactAwaitingServer(join, operation: "the join")
/// } catch {
///   await second.close()
///   throw error
/// }
/// await second.close()
/// ```
///
/// Call ``close()`` on every path. It revokes only a refresh token this sign-in minted, closes the connection, and
/// deletes the temporary store. ``InstantAccountLinks`` uses second sign-ins to link one person's identities.
public actor InstantSecondSignIn {
  /// The temporary client. Its store and its connection belong to this second sign-in alone.
  public nonisolated let client: InstantSwiftDataClient

  private nonisolated let storeURL: URL
  /// Every refresh token this sign-in's own exchanges minted, recorded where they return it.
  private nonisolated let mintedTokens: InstantMintedRefreshTokens
  private var isSigningIn = false
  private var isClosing = false
  private var closing: Task<Void, Never>?

  private init(
    client: InstantSwiftDataClient,
    storeURL: URL,
    mintedTokens: InstantMintedRefreshTokens
  ) {
    self.client = client
    self.storeURL = storeURL
    self.mintedTokens = mintedTokens
  }

  // MARK: Opening

  /// Opens a temporary client of `primary`'s app with no session.
  ///
  /// The temporary client copies the primary's endpoints, auth exchanges, and live transport. It stores its data in
  /// its own file under the temporary directory and connects to Instant on its own. It never syncs the first-party
  /// cookie, which names the device's signed-in user.
  ///
  /// - Parameters:
  ///   - primary: The app's client. Nothing about it changes.
  ///   - attributes: Schema the temporary store needs and the primary does not declare, such as
  ///     ``InstantAccountLinks/attributes``. An id the primary already declares keeps the primary's declaration.
  /// - Throws: An ``InstantError`` when `primary` has no runtime or no connection to Instant.
  public static func open(
    beside primary: InstantSwiftDataClient,
    registering attributes: [InstantAttribute] = []
  ) async throws -> InstantSecondSignIn {
    let mintedTokens = InstantMintedRefreshTokens()
    let configuration = try temporaryConfiguration(
      beside: primary,
      registering: attributes,
      recordingMintedTokensIn: mintedTokens
    )
    let runtime: InstantRuntime
    do {
      runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    } catch {
      _ = deleteStore(at: configuration.persistenceURL)
      throw error
    }
    record(
      .info,
      "second-sign-in.opened",
      "Opened a second sign-in beside the primary Instant client.",
      [
        "appID": configuration.appID,
        "store": configuration.persistenceURL.lastPathComponent,
        "registeredAttributeCount": String(configuration.initialAttributes.count),
      ]
    )
    return InstantSecondSignIn(
      client: InstantSwiftDataClient(runtime: runtime),
      storeURL: configuration.persistenceURL,
      mintedTokens: mintedTokens
    )
  }

  /// Opens a temporary client signed in as `primary`'s own identity.
  ///
  /// The temporary client adopts the primary's refresh token once Instant verifies it
  /// (`/runtime/auth/verify_refresh_token`). Verifying mints nothing, so ``close()`` never revokes the token. Writes
  /// through this client reach Instant at once instead of queueing behind the primary's outbox.
  ///
  /// - Throws: An ``InstantError`` when `primary` is not signed in, has no refresh token, or has no connection to
  ///   Instant, or when Instant refuses the token.
  public static func open(
    sharingSessionOf primary: InstantSwiftDataClient,
    registering attributes: [InstantAttribute] = []
  ) async throws -> InstantSecondSignIn {
    guard let session = try await primary.authSession() else {
      throw InstantError(
        code: .authFailed,
        operation: "share the primary Instant session",
        message: "The primary client is not signed in, so there is no session to share.",
        recovery: "Sign in on the primary client first."
      )
    }
    guard let refreshToken = session.refreshToken?.trimmingCharacters(in: .whitespacesAndNewlines),
      !refreshToken.isEmpty
    else {
      throw InstantError(
        code: .authFailed,
        operation: "share the primary Instant session",
        message: "The primary session has no refresh token to share.",
        recovery: "Sign in again on the primary client online, so Instant issues a refresh token."
      )
    }
    let signIn = try await open(beside: primary, registering: attributes)
    do {
      _ = try await signIn.adopt(
        refreshToken: refreshToken,
        userID: session.userID,
        method: "primary-session"
      )
    } catch {
      await signIn.close()
      throw error
    }
    return signIn
  }

  // MARK: Signing in

  /// The temporary client's session, or `nil` before a sign-in.
  public func session() async throws -> InstantAuthSession? {
    try await client.authSession()
  }

  /// Sends a magic code to `email` for ``signInWithMagicCode(email:code:)``.
  ///
  /// - Throws: An ``InstantError`` when this second sign-in already has a session or is closed.
  public func sendMagicCode(email: String) async throws -> InstantMagicCodeChallenge {
    try await beginSignIn(operation: "send a magic code")
    defer { isSigningIn = false }
    return try await client.sendMagicCode(email: email)
  }

  /// Signs in with the magic code Instant sent to `email`. The exchange mints a refresh token that ``close()`` revokes.
  public func signInWithMagicCode(email: String, code: String) async throws -> InstantAuthSession {
    try await signIn(method: "magic-code", mints: true) { client in
      try await client.signInWithMagicCode(email: email, code: code)
    }
  }

  /// Signs in with a provider's ID token, such as Sign in with Apple's. The exchange sends no refresh token and mints
  /// one that ``close()`` revokes.
  public func signInWithIDToken(
    clientName: String,
    idToken: String,
    nonce: String? = nil
  ) async throws -> InstantAuthSession {
    try await signIn(method: "id-token", mints: true) { client in
      try await client.signInWithIDToken(clientName: clientName, idToken: idToken, nonce: nonce)
    }
  }

  /// Signs in with an OAuth authorization code, such as Google's browser sign-in returns. The exchange sends no
  /// refresh token and mints one that ``close()`` revokes.
  public func signInWithOAuth(
    code: String,
    codeVerifier: String? = nil
  ) async throws -> InstantAuthSession {
    try await signIn(method: "oauth", mints: true) { client in
      try await client.signInWithOAuth(code: code, codeVerifier: codeVerifier)
    }
  }

  /// Signs in with the credential an ``InstantAuthProviderAuthorizer`` returned for `provider`: an ID token through
  /// ``signInWithIDToken(clientName:idToken:nonce:)``, or an authorization code through
  /// ``signInWithOAuth(code:codeVerifier:)``.
  public func signIn(
    with credential: InstantAuthProviderCredential,
    provider: AuthProvider
  ) async throws -> InstantAuthSession {
    let operation = "sign in with \(provider.id.rawValue)"
    guard credential.providerID == provider.id else {
      throw InstantError(
        code: .authFailed,
        operation: operation,
        message:
          "The credential is for '\(credential.providerID.rawValue)', not '\(provider.id.rawValue)'.",
        recovery: "Pass the credential that the provider's authorizer returned."
      )
    }
    switch (provider.kind, credential.payload) {
    case (.idToken, .idToken(let value, let nonce)):
      guard let clientName = provider.clientName?.trimmingCharacters(in: .whitespacesAndNewlines),
        !clientName.isEmpty
      else {
        throw InstantError(
          code: .validationFailed,
          operation: operation,
          message: "The ID-token provider has no Instant client name.",
          recovery: "Declare the provider with the client name configured in Instant."
        )
      }
      return try await signInWithIDToken(clientName: clientName, idToken: value, nonce: nonce)

    case (.authorizationCode, .authorizationCode(let value, let codeVerifier)):
      return try await signInWithOAuth(code: value, codeVerifier: codeVerifier)

    default:
      throw InstantError(
        code: .authFailed,
        operation: operation,
        message: "The credential payload does not match the provider's kind.",
        recovery:
          "Return an ID token for an ID-token provider, or an authorization code for an authorization-code provider."
      )
    }
  }

  /// Signs in with a refresh token this device already holds, such as a CLI's stored credential.
  ///
  /// Instant verifies the token and the temporary client adopts it. Verifying mints nothing, so ``close()`` never
  /// revokes it.
  public func adoptRefreshToken(_ refreshToken: String) async throws -> InstantAuthSession {
    try await adopt(refreshToken: refreshToken, userID: nil, method: "refresh-token")
  }

  private func adopt(
    refreshToken: String,
    userID: String?,
    method: String
  ) async throws -> InstantAuthSession {
    try await signIn(method: method, mints: false) { client in
      try await client.signInWithRefreshToken(refreshToken, userID: userID)
    }
  }

  private func signIn(
    method: String,
    mints: Bool,
    _ exchange: @Sendable (InstantSwiftDataClient) async throws -> InstantAuthSession
  ) async throws -> InstantAuthSession {
    try await beginSignIn(operation: "sign in")
    defer { isSigningIn = false }
    let session: InstantAuthSession
    do {
      session = try await exchange(client)
    } catch {
      guard !isClosing else {
        // The exchange may have minted a token before the deleted store refused the session.
        throw await endSignInAfterClose(method: method)
      }
      Self.record(
        .warning,
        "second-sign-in.sign-in-failed",
        "A second sign-in's exchange failed.",
        appMetadata.merging(["method": method]) { $1 }.merging(Self.summary(of: error)) { $1 }
      )
      throw error
    }
    guard !isClosing else {
      throw await endSignInAfterClose(method: method)
    }
    Self.record(
      .info,
      "second-sign-in.signed-in",
      "A second sign-in signed in.",
      appMetadata.merging(
        [
          "method": method,
          "minted": String(mints),
          "userID": session.userID,
          "isGuest": String(session.isGuest),
        ]
      ) { $1 }
    )
    return session
  }

  /// `close()` ran while an exchange was in flight. Revokes whatever that exchange minted, and returns the cancellation
  /// the sign-in throws.
  private func endSignInAfterClose(method: String) async -> CancellationError {
    let revocation = await revokeMintedTokens()
    try? await client.signOut(invalidateToken: false)
    Self.record(
      .notice,
      "second-sign-in.signed-in-after-close",
      "A second sign-in finished after it was closed, so its session ended at once.",
      appMetadata.merging(["method": method, "revocation": revocation]) { $1 }
    )
    return CancellationError()
  }

  private func beginSignIn(operation: String) async throws {
    try refuseIfClosed(operation: operation)
    guard !isSigningIn else {
      throw InstantError(
        code: .authFailed,
        operation: operation,
        message: "This second sign-in is already signing in.",
        recovery: "Wait for the current sign-in to finish, or close this second sign-in and open another."
      )
    }
    isSigningIn = true
    do {
      if let session = try await client.authSession() {
        throw InstantError(
          code: .authFailed,
          operation: operation,
          message:
            "This second sign-in is already signed in as \(session.userID), and it holds one identity.",
          recovery: "Close it and open another second sign-in for a different identity."
        )
      }
    } catch {
      isSigningIn = false
      throw error
    }
  }

  // MARK: Reading and writing as the second identity

  /// Writes `transaction` as this second identity and returns once Instant accepts it.
  ///
  /// An ordinary `transact` returns after the local commit. This waits for the server, because the next step of a flow
  /// such as account linking needs the write on the server first. It connects when the temporary client is not
  /// connected, then waits up to `timeout` for Instant's answer. Five seconds is the codebase-wide bound for a server
  /// wait.
  ///
  /// ```swift
  /// try await second.transactAwaitingServer(join, operation: "the join")
  /// ```
  ///
  /// - Parameters:
  ///   - transaction: The write. Instant answers for `transaction.id`.
  ///   - operation: A short noun phrase that names the write in errors, such as `"the invite"`.
  ///   - timeout: How long to wait for Instant's answer.
  /// - Throws: An ``InstantError`` carrying Instant's refusal, or one that says how long it waited for Instant to
  ///   accept `operation`. Either way the write stays only in the temporary store, which ``close()`` deletes.
  public func transactAwaitingServer(
    _ transaction: InstantStoreTransaction,
    operation: String,
    timeout: Duration = .seconds(5)
  ) async throws {
    let waitOperation = "wait for Instant to accept \(operation)"
    try refuseIfClosed(operation: waitOperation)
    try Self.validate(timeout, operation: waitOperation)
    guard let runtime = client.runtime else {
      throw InstantError(
        code: .implementationFailed,
        operation: waitOperation,
        message: "The temporary client has no runtime.",
        recovery: "Open the second sign-in beside a runtime-backed client."
      )
    }
    guard let session = try await client.authSession() else {
      throw InstantError(
        code: .authFailed,
        operation: waitOperation,
        message: "This second sign-in has no session, so it cannot write as a second identity.",
        recovery: "Sign the second identity in before writing."
      )
    }
    try await connectIfNeeded()
    let metadata = appMetadata.merging(
      ["operation": operation, "transactionID": transaction.id, "userID": session.userID]
    ) { $1 }
    do {
      try await runtime.withAutomaticMutationRetrySuspended(id: transaction.id) {
        let lifecycle = try await runtime.observeMutationLifecycle(id: transaction.id)
        _ = try await runtime.transact(transaction)
        let answer = try await Self.serverAnswer(
          lifecycle,
          transactionID: transaction.id,
          operation: operation,
          timeout: timeout
        )
        switch answer {
        case .serverAccepted:
          return

        case .failed(let mutation):
          throw mutation.rejectionError(
            operation: waitOperation,
            recovery: "Check the app's permission rules for this write, then try again."
          )

        case .waiting:
          throw InstantError(
            code: .implementationFailed,
            operation: waitOperation,
            localID: transaction.id,
            message: "The mutation lifecycle returned a waiting event as its answer.",
            recovery: "Report this as an Instant Swift Data bug."
          )
        }
      }
    } catch let error as InstantError {
      Self.record(
        error: error,
        error.code == .networkFailed ? "second-sign-in.write-timed-out" : "second-sign-in.write-refused",
        "Instant did not accept a second sign-in's write.",
        metadata
      )
      throw error
    }
    Self.record(.info, "second-sign-in.write-accepted", "Instant accepted a second sign-in's write.", metadata)
  }

  /// Reads `plan` from Instant as this second identity.
  ///
  /// It connects when the temporary client is not connected, and the answer comes from the server, not from a cache.
  /// It waits up to `timeout` for that answer.
  ///
  /// - Throws: An ``InstantError`` when Instant refuses the read, or one that says how long it waited.
  public func queryServer(
    _ plan: InstantQueryPlan,
    timeout: Duration = .seconds(5)
  ) async throws -> [InstantEntitySnapshot] {
    let operation = "read \(plan.namespace) from Instant"
    try refuseIfClosed(operation: operation)
    try Self.validate(timeout, operation: operation)
    try await connectIfNeeded()
    let client = client
    let emission = try await Self.withDeadline(
      timeout,
      timedOut: {
        InstantError(
          code: .networkFailed,
          operation: operation,
          message: "Waited \(Self.waitDescription(timeout)) for Instant to answer a read of \(plan.namespace).",
          recovery: "Check this device's connection to Instant, then try again."
        )
      },
      { try await client.queryOnce(plan) }
    )
    return emission.values
  }

  private func connectIfNeeded() async throws {
    switch try await client.connectionStatus().state {
    case .opened, .authenticated:
      return
    case .connecting, .closed, .errored:
      _ = try await client.connect()
    }
  }

  // MARK: Closing

  /// Ends this second sign-in. It is safe to call more than once, and it never throws.
  ///
  /// Closing closes the temporary client's connection, revokes every refresh token this sign-in's exchanges minted,
  /// and deletes the temporary store. An adopted token, such as the primary's or a stored credential, is only signed
  /// out locally, never revoked. A sign-in still in flight revokes its token when it finishes. Writes Instant has not
  /// accepted are deleted with the store.
  public func close() async {
    if let closing {
      await closing.value
      return
    }
    isClosing = true
    let task = Task { await self.finishClosing() }
    closing = task
    await task.value
  }

  private func finishClosing() async {
    var metadata = appMetadata
    do {
      _ = try await client.closeConnection()
      metadata["connectionClosed"] = "true"
    } catch {
      metadata["connectionClosed"] = "false"
      metadata.merge(Self.summary(of: error)) { $1 }
    }
    metadata["revocation"] = await revokeMintedTokens()
    if let session = try? await client.authSession() {
      metadata["userID"] = session.userID
      try? await client.signOut(invalidateToken: false)
    }
    let storeDeleted = Self.deleteStore(at: storeURL)
    metadata["storeDeleted"] = String(storeDeleted)
    Self.record(
      storeDeleted ? .info : .warning,
      "second-sign-in.closed",
      storeDeleted
        ? "Closed a second sign-in and deleted its temporary store."
        : "Closed a second sign-in, but its temporary store could not be deleted.",
      metadata
    )
  }

  /// Revokes each minted token that nothing has revoked yet, once: `none`, `revoked`, or `revoke-failed`.
  ///
  /// The ledger, not the session, decides: an exchange can mint a token that the store never saves (the store was
  /// deleted, or the save failed), and an adopted token was never minted here.
  private func revokeMintedTokens() async -> String {
    let tokens = mintedTokens.claimUnrevoked()
    guard !tokens.isEmpty else { return "none" }
    var allRevoked = true
    for token in tokens {
      let revoked = await revoke(token)
      allRevoked = allRevoked && revoked
    }
    return allRevoked ? "revoked" : "revoke-failed"
  }

  /// Revokes `refreshToken` through `/runtime/signout`. `signOut(invalidateToken: true)` would also revoke it, but it
  /// hides a failed revocation; a minted token left valid must be reported.
  private func revoke(_ refreshToken: String) async -> Bool {
    guard let configuration = client.runtime?.configuration else { return false }
    let request = InstantAuthTokenInvalidationRequest(
      appID: configuration.appID,
      apiURI: configuration.apiURI,
      refreshToken: refreshToken,
      signedOutAt: configuration.now()
    )
    do {
      try await Self.withDeadline(
        .seconds(5),
        timedOut: {
          InstantError(
            code: .networkFailed,
            operation: "revoke a second sign-in's refresh token",
            message: "Waited 5 seconds for Instant to revoke the refresh token.",
            recovery: "The token stays valid until it expires. Check this device's connection to Instant."
          )
        },
        { try await configuration.authTokenInvalidator.invalidate(request) }
      )
      return true
    } catch {
      Self.record(
        .error,
        "second-sign-in.revoke-failed",
        "Could not revoke the refresh token a second sign-in minted. It stays valid until it expires.",
        appMetadata.merging(Self.summary(of: error)) { $1 }
      )
      return false
    }
  }

  private func refuseIfClosed(operation: String) throws {
    guard !isClosing else {
      throw InstantError(
        code: .validationFailed,
        operation: operation,
        message: "This second sign-in is closed.",
        recovery: "Open a new second sign-in."
      )
    }
  }

  // MARK: Helpers

  private nonisolated var appMetadata: [String: String] {
    [
      "appID": client.runtime?.configuration.appID ?? "",
      "store": storeURL.lastPathComponent,
    ]
  }

  /// A new transaction or entity id from the temporary client's id source.
  nonisolated func makeID() -> String {
    client.runtime?.configuration.makeID() ?? UUID().uuidString.lowercased()
  }

  /// The directory that holds every second sign-in's temporary store.
  static var storeDirectory: URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(
      "InstantSecondSignIn",
      isDirectory: true
    )
  }

  private static func temporaryConfiguration(
    beside primary: InstantSwiftDataClient,
    registering attributes: [InstantAttribute],
    recordingMintedTokensIn mintedTokens: InstantMintedRefreshTokens
  ) throws -> InstantRuntimeConfiguration {
    guard let runtime = primary.runtime else {
      throw InstantError(
        code: .implementationFailed,
        operation: "open a second sign-in",
        message: "This Instant client has no runtime, so a second sign-in cannot copy its configuration.",
        recovery: "Open the second sign-in beside a runtime-backed client."
      )
    }
    var configuration = runtime.configuration
    guard configuration.liveTransport != nil, !configuration.isLocalOnly else {
      throw InstantError(
        code: .validationFailed,
        operation: "open a second sign-in",
        message: "Linking another sign-in needs a connection to Instant, and this client is local-only.",
        recovery: "Open the second sign-in beside a client bootstrapped with a live transport."
      )
    }
    configuration.persistenceURL = storeDirectory.appendingPathComponent(
      "\(storeName(appID: configuration.appID))-\(UUID().uuidString.lowercased()).sqlite"
    )
    // A temporary client connects whenever it has something to send or read, whatever the primary chose.
    configuration.autoConnectLiveTransport = true
    // The first-party cookie names the device's signed-in user. A temporary identity must never replace it.
    configuration.firstPartyURL = nil
    configuration.startupTrace = .disabled
    configuration.actorHopRecorder = nil
    configuration.localPersistenceMigrations = []
    let declared = Set(configuration.initialAttributes.map(\.id))
    configuration.initialAttributes += attributes.filter { !declared.contains($0.id) }
    // Record every token the exchanges mint where they return it, before the runtime tries to save the session.
    let magicCodeExchange = configuration.magicCodeExchange
    configuration.magicCodeExchange = InstantMagicCodeExchange(
      send: magicCodeExchange.send,
      verify: { request in
        let verification = try await magicCodeExchange.verify(request)
        mintedTokens.record(verification.refreshToken)
        return verification
      }
    )
    let idTokenExchange = configuration.idTokenExchange
    configuration.idTokenExchange = InstantIDTokenExchange { request in
      let verification = try await idTokenExchange.signIn(request)
      mintedTokens.record(verification.refreshToken)
      return verification
    }
    let oauthExchange = configuration.oauthExchange
    configuration.oauthExchange = InstantOAuthExchange { request in
      let verification = try await oauthExchange.signIn(request)
      mintedTokens.record(verification.refreshToken)
      return verification
    }
    let guestAuthenticator = configuration.guestAuthenticator
    configuration.guestAuthenticator = InstantGuestAuthenticator { request in
      let verification = try await guestAuthenticator.signIn(request)
      mintedTokens.record(verification.refreshToken)
      return verification
    }
    return configuration
  }

  private static func storeName(appID: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
    let name = String(
      appID.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
    )
    .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    return name.isEmpty ? "app" : name
  }

  /// Deletes the store file and its SQLite companions. Returns whether none remains.
  static func deleteStore(at url: URL) -> Bool {
    let fileManager = FileManager.default
    var deletedAll = true
    for path in [url.path, url.path + "-wal", url.path + "-shm", url.path + "-journal"]
    where fileManager.fileExists(atPath: path) {
      do {
        try fileManager.removeItem(atPath: path)
      } catch {
        deletedAll = false
      }
    }
    return deletedAll
  }

  private static func serverAnswer(
    _ lifecycle: AsyncStream<InstantMutationLifecycleEvent>,
    transactionID: String,
    operation: String,
    timeout: Duration
  ) async throws -> InstantMutationLifecycleEvent {
    try await withDeadline(
      timeout,
      timedOut: {
        InstantError(
          code: .networkFailed,
          operation: "wait for Instant to accept \(operation)",
          localID: transactionID,
          message: "Waited \(waitDescription(timeout)) for Instant to accept \(operation).",
          recovery:
            "Check this device's connection to Instant, then try again. The write stays only in the temporary store, which closing the second sign-in deletes."
        )
      },
      {
        for await event in lifecycle {
          switch event {
          case .waiting:
            continue
          case .serverAccepted, .failed:
            return event
          }
        }
        try Task.checkCancellation()
        throw InstantError(
          code: .implementationFailed,
          operation: "wait for Instant to accept \(operation)",
          localID: transactionID,
          message: "The mutation lifecycle ended before Instant answered.",
          recovery: "Report this as an Instant Swift Data bug."
        )
      }
    )
  }

  /// Runs `operation`, or throws `timedOut()` once `timeout` passes first.
  static func withDeadline<Value: Sendable>(
    _ timeout: Duration,
    timedOut: @escaping @Sendable () -> InstantError,
    _ operation: @escaping @Sendable () async throws -> Value
  ) async throws -> Value {
    try await withThrowingTaskGroup(of: Value.self) { group in
      group.addTask { try await operation() }
      group.addTask {
        try await Task.sleep(for: timeout)
        throw timedOut()
      }
      defer { group.cancelAll() }
      guard let value = try await group.next() else { throw CancellationError() }
      return value
    }
  }

  private static func validate(_ timeout: Duration, operation: String) throws {
    guard timeout >= .zero else {
      throw InstantError(
        code: .validationFailed,
        operation: operation,
        message: "The server wait must not be negative.",
        recovery: "Pass a timeout of zero or more. The codebase-wide bound is five seconds."
      )
    }
  }

  /// `5 seconds`, `1 second`, or `200 milliseconds`.
  static func waitDescription(_ duration: Duration) -> String {
    let (seconds, attoseconds) = duration.components
    if attoseconds == 0 {
      return seconds == 1 ? "1 second" : "\(seconds) seconds"
    }
    let milliseconds = seconds * 1_000 + attoseconds / 1_000_000_000_000_000
    return milliseconds == 1 ? "1 millisecond" : "\(milliseconds) milliseconds"
  }

  /// The error's code and operation, plus the server's status and type, without its message. Auth messages can echo
  /// the email address a sign-in used.
  private static func summary(of error: Error) -> [String: String] {
    guard let error = error as? InstantError else {
      return ["errorType": String(reflecting: type(of: error))]
    }
    var summary = ["errorCode": error.code.rawValue, "errorOperation": error.operation]
    summary["serverStatus"] = error.serverStatus.map(String.init)
    summary["serverType"] = error.serverType
    return summary
  }

  private static func record(
    _ level: InstantDiagnosticLevel,
    _ event: String,
    _ message: String,
    _ metadata: [String: String]
  ) {
    InstantDiagnostics.shared.record(
      level,
      subsystem: "instant-swift-data",
      category: "auth",
      event: event,
      message: message,
      metadata: metadata
    )
  }

  private static func record(
    error: InstantError,
    _ event: String,
    _ message: String,
    _ metadata: [String: String]
  ) {
    InstantDiagnostics.shared.record(
      error: error,
      subsystem: "instant-swift-data",
      category: "auth",
      event: event,
      message: message,
      metadata: metadata
    )
  }
}

/// The refresh tokens a second sign-in's exchanges minted, each revoked at most once.
// SAFETY: `lock` protects `minted` and `claimed`; no lock is held across an await.
final class InstantMintedRefreshTokens: @unchecked Sendable {
  private let lock = NSLock()
  private var minted: [String] = []
  private var claimed: Set<String> = []

  func record(_ refreshToken: String?) {
    guard let refreshToken, !refreshToken.isEmpty else { return }
    lock.withLock {
      if !minted.contains(refreshToken) {
        minted.append(refreshToken)
      }
    }
  }

  /// The minted tokens nothing has claimed yet, now claimed for revocation by the caller.
  func claimUnrevoked() -> [String] {
    lock.withLock {
      let unclaimed = minted.filter { !claimed.contains($0) }
      claimed.formUnion(unclaimed)
      return unclaimed
    }
  }
}
