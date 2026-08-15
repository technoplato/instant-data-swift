import Foundation
import IssueReporting

package struct InstantLiveInfiniteQueryChunkObservation: Sendable {
  package var stream: AsyncStream<InstantQueryEmission>
  package var cancel: @Sendable () async -> Void
}

package struct InstantQueryObservationLease: Sendable {
  package var stream: AsyncStream<InstantQueryEmission>
  package var cancel: @Sendable () async -> Void

  package init(
    stream: AsyncStream<InstantQueryEmission>,
    cancel: @escaping @Sendable () async -> Void
  ) {
    self.stream = stream
    self.cancel = cancel
  }

  package static func finished() -> Self {
    let finished = AsyncStream<InstantQueryEmission>.makeStream(
      bufferingPolicy: .bufferingNewest(1)
    )
    finished.continuation.finish()
    return Self(stream: finished.stream, cancel: {})
  }
}

/// One late-installable, exact asynchronous termination boundary.
///
/// Setup code creates this owner before its first suspension. Cancellation can
/// therefore win before a resource exists; installing that resource later
/// starts its cleanup immediately. Natural completion also starts cleanup, but
/// does not masquerade as caller cancellation at the `completeSetup` handoff.
/// Cleanup never runs while the state lock is held.
// SAFETY: `lock` protects every mutable setup, operation, cancellation, and
// waiter field.
package final class InstantAsyncCancellationOwner: @unchecked Sendable {
  // SAFETY: each box is captured and mutated by exactly one cleanup Task; that
  // task serializes access across executor hops.
  private final class OperationBox: @unchecked Sendable {
    private var operation: (@Sendable () async -> Void)?

    init(_ operation: @escaping @Sendable () async -> Void) {
      self.operation = operation
    }

    func run() async {
      var operation = self.operation
      self.operation = nil
      await operation?()
      operation = nil
    }
  }

  private let lock = NSLock()
  private var operation: (@Sendable () async -> Void)?
  private var didInstallOperation = false
  private var isCleanupRequested = false
  private var isExplicitCancellationRequested = false
  private var activeOperationCount = 0
  private var didStartCleanup = false
  private var didFinishCleanup = false
  private var didCompleteSetup = false
  private var continuations: [CheckedContinuation<Void, Never>] = []

  package init() {}

  package init(cancelAndWait operation: @escaping @Sendable () async -> Void) {
    self.operation = operation
    self.didInstallOperation = true
  }

  package func install(cancelAndWait operation: @escaping @Sendable () async -> Void) {
    let operationToStart = lock.withLock { () -> (@Sendable () async -> Void)? in
      precondition(!didInstallOperation, "Cancellation cleanup can only be installed once.")
      didInstallOperation = true
      self.operation = operation
      return takeCleanupOperationIfReady()
    }
    if let operationToStart { start(operationToStart) }
  }

  package func completeSetup() -> Bool {
    lock.withLock {
      precondition(!didCompleteSetup, "Cancellation setup can only complete once.")
      didCompleteSetup = true
      return isExplicitCancellationRequested
    }
  }

  package func cancel() {
    requestCancellation(unlessSetupCompleted: false)
  }

  /// Cancels setup only while this owner still owns the resource handoff.
  /// `completeSetup` and this operation linearize under the same lock: once
  /// setup completes, ordinary resource cancellation belongs to the returned
  /// lease rather than the setup task's cancellation handler.
  package func cancelBeforeSetupCompletes() {
    requestCancellation(unlessSetupCompleted: true)
  }

  private func requestCancellation(unlessSetupCompleted: Bool) {
    let operation = lock.withLock { () -> (@Sendable () async -> Void)? in
      if unlessSetupCompleted, didCompleteSetup { return nil }
      isExplicitCancellationRequested = true
      isCleanupRequested = true
      return takeCleanupOperationIfReady()
    }
    if let operation { start(operation) }
  }

  /// Finishes exact cleanup without converting a successfully built finite
  /// observation into a caller-cancelled setup result.
  package func finish() {
    let operation = lock.withLock { () -> (@Sendable () async -> Void)? in
      isCleanupRequested = true
      return takeCleanupOperationIfReady()
    }
    if let operation { start(operation) }
  }

  package func unlessCancelled(_ action: @Sendable () -> Void) {
    let shouldRun = lock.withLock {
      guard !isCleanupRequested else { return false }
      activeOperationCount += 1
      return true
    }
    guard shouldRun else { return }
    action()
    finishOperation()
  }

  package func wait() async {
    await withCheckedContinuation { continuation in
      let shouldResume = lock.withLock {
        if didFinishCleanup { return true }
        continuations.append(continuation)
        return false
      }
      if shouldResume { continuation.resume() }
    }
  }

  private func finishOperation() {
    let operation = lock.withLock { () -> (@Sendable () async -> Void)? in
      activeOperationCount -= 1
      return takeCleanupOperationIfReady()
    }
    if let operation { start(operation) }
  }

  private func takeCleanupOperationIfReady() -> (@Sendable () async -> Void)? {
    guard
      isCleanupRequested,
      didInstallOperation,
      activeOperationCount == 0,
      !didStartCleanup,
      let operation
    else { return nil }
    didStartCleanup = true
    self.operation = nil
    return operation
  }

  private func start(_ operation: @escaping @Sendable () async -> Void) {
    let operationBox = OperationBox(operation)
    Task { [self, operationBox] in
      await operationBox.run()
      finishCleanup()
    }
  }

  private func finishCleanup() {
    let continuations: [CheckedContinuation<Void, Never>] = lock.withLock {
      guard !didFinishCleanup else { return [] }
      didFinishCleanup = true
      let continuations = self.continuations
      self.continuations.removeAll()
      return continuations
    }
    for continuation in continuations {
      continuation.resume()
    }
  }
}

/// Owns one restartable asynchronous service through its exact completion.
///
/// A stop request latches the owner before it cancels the current task and
/// returns a stable handle to that exact task. Natural completion clears only
/// the matching token, so an older task can never erase a replacement. The
/// owner retains no completed task or operation closure.
// SAFETY: `lock` protects the token, suspension, and task fields. A Task handle
// is safe to copy across concurrency domains and its value is awaited without
// holding the lock.
package enum InstantStandardQuerySetupCheckpoint: Equatable, Sendable {
  case localObservationInstalled
}

package enum InstantLiveInfiniteQuerySetupCheckpoint: Equatable, Sendable {
  case beforePersistedPageInfoLoad
  case localObservationInstalled
}

private struct InstantLiveInfiniteQueryChunkObservationLease<Element: Sendable>: Sendable {
  var stream: AsyncStream<Element>
  var cancel: @Sendable () async -> Void
}

private final class InstantLiveObservationTermination: Sendable {
  private let owner: InstantAsyncCancellationOwner

  init(_ action: @escaping @Sendable () async -> Void) {
    self.owner = InstantAsyncCancellationOwner(cancelAndWait: action)
  }

  func run() async {
    owner.cancel()
    await owner.wait()
  }
}

public struct InstantRuntimeConfiguration: Sendable {
  public static let defaultAPIURI = URL(string: "https://api.instantdb.com")!
  public static let defaultWebSocketURI = URL(
    string: "wss://api.instantdb.com/runtime/session"
  )!

  public var appID: String
  public var apiURI: URL
  public var websocketURI: URL
  public var firstPartyURL: URL?
  public var persistenceURL: URL
  public var initialAttributes: [InstantAttribute]
  public var deferredValueResidency: InstantDeferredValueResidencyPolicy
  public var now: @Sendable () -> InstantTimestamp
  public var makeID: @Sendable () -> String
  public var refreshTokenVerifier: InstantRefreshTokenVerifier
  public var guestAuthenticator: InstantGuestAuthenticator
  public var magicCodeExchange: InstantMagicCodeExchange
  public var idTokenExchange: InstantIDTokenExchange
  public var oauthExchange: InstantOAuthExchange
  public var authTokenInvalidator: InstantAuthTokenInvalidator
  public var mutationTransport: InstantMutationTransportClient
  public var liveTransport: InstantLiveTransportClient?
  public var autoConnectLiveTransport: Bool
  public var liveShareContract: InstantLiveShareContract?
  public var userCookieSyncClient: InstantUserCookieSyncClient
  public var platformAppClient: InstantPlatformAppClient
  public var appBuilderCodeGenerator: AppBuilderCodeGeneratorClient
  public var startupTrace: InstantStartupTrace = .disabled
  package var actorHopRecorder: InstantActorHopRecorder?
  package var isLocalOnly: Bool
  var queryCachePruningPolicy = InstantQueryCachePruningPolicy(
    maxAgeMilliseconds: 1_000 * 60 * 60 * 24 * 7 * 52,
    maxEntries: 1_000,
    maxEncodedJSONBytes: 1_000_000
  )
  var queryCachePruningWriteInterval = 64
  var liveQueryResultPruningPolicy = InstantLiveQueryResultPruningPolicy(
    maxAgeMilliseconds: 1_000 * 60 * 60 * 24 * 7 * 52,
    maxEntries: 1_000,
    maxTripleCount: 1_000_000
  )
  var liveQueryResultPruningWriteInterval = 64
  var liveReconnectSleep: @Sendable (UInt64) async throws -> Void =
    instantLiveDefaultTimeoutSleep
  var liveMutationDeadlineSleep: @Sendable (UInt64) async throws -> Void =
    instantLiveDefaultTimeoutSleep
  package var explicitMutationTransportDeadlineSleep:
    @Sendable (UInt64) async throws -> Void = instantLiveDefaultTimeoutSleep
  package var explicitMutationClaimRenewalSleep:
    @Sendable (UInt64) async throws -> Void = instantLiveDefaultTimeoutSleep
  package var explicitMutationCleanupWatchdogSleep:
    @Sendable (UInt64) async throws -> Void = instantLiveDefaultTimeoutSleep
  package var exactCloseWatchdogSleep: @Sendable (UInt64) async throws -> Void =
    instantLiveDefaultTimeoutSleep
  var onLiveQueryResultPruneActiveKeysCapturedForTesting:
    (@Sendable (Set<String>) async -> Void)? = nil
  package var onLiveInfiniteQuerySetupCheckpointForTesting:
    (@Sendable (InstantLiveInfiniteQuerySetupCheckpoint) async -> Void)? = nil
  package var onStandardQuerySetupCheckpointForTesting:
    (@Sendable (InstantStandardQuerySetupCheckpoint) async throws -> Void)? = nil
  package var onStandardQueryObservationCleanupStartedForTesting:
    (@Sendable () async -> Void)? = nil
  package var onStoredFilesRemoteSnapshotMergedForTesting:
    (@Sendable (_ fileCount: Int) async -> Void)? = nil
  package var onStoredFilesRemoteSnapshotPublishedForTesting:
    (@Sendable (_ fileCount: Int) -> Void)? = nil
  package var onLocalInfiniteQueryObservationInstalledForTesting:
    (@Sendable () async -> Void)? = nil
  package var onLiveInfiniteQueryPreBootstrapPayloadAcquiredForTesting:
    (@Sendable (_ valueCount: Int) async throws -> Void)? = nil
  package var onLiveInfiniteQueryDeferredHydrationAcquiredForTesting:
    (@Sendable (_ valueCount: Int) async -> Void)? = nil
  package var liveInfiniteQueryRetirementWatchdogSleep:
    @Sendable (UInt64) async throws -> Void = instantLiveDefaultTimeoutSleep
  package var onLiveInfiniteQueryRetirementCleanupStartedForTesting:
    (@Sendable (_ subscriptionID: Int) async -> Void)? = nil
  package var onLocalInfiniteQueryNavigationRequestAcquiredForTesting:
    (@Sendable (_ valueCount: Int) async throws -> Void)? = nil
  package var onLocalInfiniteQueryHydrationRequestAcquiredForTesting:
    (@Sendable (_ sequence: Int64, _ valueCount: Int) async throws -> Void)? = nil
  package var onLocalInfiniteQueryTerminalPublishedBeforeObservationCleanupForTesting:
    (@Sendable () async -> Void)? = nil
  package var onAutomaticMutationPumpRetryWindowCompletedForTesting:
    (@Sendable () async -> Void)? = nil
  package var onAutomaticLiveConnectionTaskStartedForTesting:
    (@Sendable () async -> Void)? = nil
  package var onStartupCookieSyncTaskStartedForTesting:
    (@Sendable () async -> Void)? = nil
  package var onLiveReceiverEventAcquiredForTesting:
    (@Sendable () async -> Void)? = nil
  package var onLiveQueryOnceAcknowledgedForTesting:
    (@Sendable () async throws -> Void)? = nil
  var onLocalMutationSupersessionPreparedForTesting:
    (@Sendable (_ predecessorID: String, _ newcomerID: String) async -> Void)? = nil
  var onLocalMutationPersistedBeforeStorePublicationForTesting:
    (@Sendable (_ transactionID: String) async -> Void)? = nil
  var onServerApplyPreparedBeforeCommitForTesting:
    (@Sendable (_ planID: String) async -> Void)? = nil

  public init(
    appID: String,
    persistenceURL: URL,
    initialAttributes: [InstantAttribute] = [],
    deferredValueResidency: InstantDeferredValueResidencyPolicy = .none,
    now: @escaping @Sendable () -> InstantTimestamp = {
      InstantTimestamp(milliseconds: Int64((Date().timeIntervalSince1970 * 1000).rounded()))
    },
    makeID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() },
    refreshTokenVerifier: InstantRefreshTokenVerifier = .local,
    guestAuthenticator: InstantGuestAuthenticator = .local,
    magicCodeExchange: InstantMagicCodeExchange = .local,
    idTokenExchange: InstantIDTokenExchange = .local,
    oauthExchange: InstantOAuthExchange = .local,
    authTokenInvalidator: InstantAuthTokenInvalidator = .local,
    platformAppClient: InstantPlatformAppClient = .local,
    appBuilderCodeGenerator: AppBuilderCodeGeneratorClient = .local
  ) {
    self.init(
      appID: appID,
      apiURI: Self.defaultAPIURI,
      websocketURI: Self.defaultWebSocketURI,
      persistenceURL: persistenceURL,
      initialAttributes: initialAttributes,
      deferredValueResidency: deferredValueResidency,
      now: now,
      makeID: makeID,
      refreshTokenVerifier: refreshTokenVerifier,
      guestAuthenticator: guestAuthenticator,
      magicCodeExchange: magicCodeExchange,
      idTokenExchange: idTokenExchange,
      oauthExchange: oauthExchange,
      authTokenInvalidator: authTokenInvalidator,
      mutationTransport: .local,
      liveTransport: nil,
      liveShareContract: nil,
      platformAppClient: platformAppClient,
      appBuilderCodeGenerator: appBuilderCodeGenerator
    )
  }

  public init(
    appID: String,
    persistenceURL: URL,
    initialAttributes: [InstantAttribute],
    now: @escaping @Sendable () -> InstantTimestamp,
    makeID: @escaping @Sendable () -> String,
    refreshTokenVerifier: InstantRefreshTokenVerifier,
    guestAuthenticator: InstantGuestAuthenticator,
    magicCodeExchange: InstantMagicCodeExchange,
    idTokenExchange: InstantIDTokenExchange,
    oauthExchange: InstantOAuthExchange,
    authTokenInvalidator: InstantAuthTokenInvalidator,
    platformAppClient: InstantPlatformAppClient,
    appBuilderCodeGenerator: AppBuilderCodeGeneratorClient
  ) {
    self.init(
      appID: appID,
      persistenceURL: persistenceURL,
      initialAttributes: initialAttributes,
      deferredValueResidency: .none,
      now: now,
      makeID: makeID,
      refreshTokenVerifier: refreshTokenVerifier,
      guestAuthenticator: guestAuthenticator,
      magicCodeExchange: magicCodeExchange,
      idTokenExchange: idTokenExchange,
      oauthExchange: oauthExchange,
      authTokenInvalidator: authTokenInvalidator,
      platformAppClient: platformAppClient,
      appBuilderCodeGenerator: appBuilderCodeGenerator
    )
  }

  public init(
    appID: String,
    persistenceURL: URL,
    initialAttributes: [InstantAttribute],
    deferredValueResidency: InstantDeferredValueResidencyPolicy = .none,
    now: @escaping @Sendable () -> InstantTimestamp,
    makeID: @escaping @Sendable () -> String,
    refreshTokenVerifier: InstantRefreshTokenVerifier,
    magicCodeExchange: InstantMagicCodeExchange,
    idTokenExchange: InstantIDTokenExchange,
    oauthExchange: InstantOAuthExchange,
    authTokenInvalidator: InstantAuthTokenInvalidator,
    platformAppClient: InstantPlatformAppClient,
    appBuilderCodeGenerator: AppBuilderCodeGeneratorClient
  ) {
    self.init(
      appID: appID,
      persistenceURL: persistenceURL,
      initialAttributes: initialAttributes,
      deferredValueResidency: deferredValueResidency,
      now: now,
      makeID: makeID,
      refreshTokenVerifier: refreshTokenVerifier,
      guestAuthenticator: .local,
      magicCodeExchange: magicCodeExchange,
      idTokenExchange: idTokenExchange,
      oauthExchange: oauthExchange,
      authTokenInvalidator: authTokenInvalidator,
      platformAppClient: platformAppClient,
      appBuilderCodeGenerator: appBuilderCodeGenerator
    )
  }

  public init(
    appID: String,
    persistenceURL: URL,
    initialAttributes: [InstantAttribute] = [],
    deferredValueResidency: InstantDeferredValueResidencyPolicy = .none,
    now: @escaping @Sendable () -> InstantTimestamp = {
      InstantTimestamp(milliseconds: Int64((Date().timeIntervalSince1970 * 1_000).rounded()))
    },
    makeID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() },
    refreshTokenVerifier: InstantRefreshTokenVerifier = .local,
    guestAuthenticator: InstantGuestAuthenticator = .local,
    magicCodeExchange: InstantMagicCodeExchange = .local,
    idTokenExchange: InstantIDTokenExchange = .local,
    oauthExchange: InstantOAuthExchange = .local,
    authTokenInvalidator: InstantAuthTokenInvalidator = .local,
    liveShareContract: InstantLiveShareContract?,
    platformAppClient: InstantPlatformAppClient = .local,
    appBuilderCodeGenerator: AppBuilderCodeGeneratorClient = .local
  ) {
    self.init(
      appID: appID,
      apiURI: Self.defaultAPIURI,
      websocketURI: Self.defaultWebSocketURI,
      persistenceURL: persistenceURL,
      initialAttributes: initialAttributes,
      deferredValueResidency: deferredValueResidency,
      now: now,
      makeID: makeID,
      refreshTokenVerifier: refreshTokenVerifier,
      guestAuthenticator: guestAuthenticator,
      magicCodeExchange: magicCodeExchange,
      idTokenExchange: idTokenExchange,
      oauthExchange: oauthExchange,
      authTokenInvalidator: authTokenInvalidator,
      mutationTransport: .local,
      liveTransport: nil,
      liveShareContract: liveShareContract,
      platformAppClient: platformAppClient,
      appBuilderCodeGenerator: appBuilderCodeGenerator
    )
  }

  public init(
    appID: String,
    apiURI: URL = Self.defaultAPIURI,
    websocketURI: URL = Self.defaultWebSocketURI,
    firstPartyURL: URL? = nil,
    persistenceURL: URL,
    initialAttributes: [InstantAttribute] = [],
    deferredValueResidency: InstantDeferredValueResidencyPolicy = .none,
    now: @escaping @Sendable () -> InstantTimestamp = {
      InstantTimestamp(milliseconds: Int64((Date().timeIntervalSince1970 * 1000).rounded()))
    },
    makeID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() },
    refreshTokenVerifier: InstantRefreshTokenVerifier = .local,
    guestAuthenticator: InstantGuestAuthenticator = .local,
    magicCodeExchange: InstantMagicCodeExchange = .local,
    idTokenExchange: InstantIDTokenExchange = .local,
    oauthExchange: InstantOAuthExchange = .local,
    authTokenInvalidator: InstantAuthTokenInvalidator = .local,
    mutationTransport: InstantMutationTransportClient = .local,
    liveTransport: InstantLiveTransportClient? = nil,
    liveShareContract: InstantLiveShareContract? = nil,
    userCookieSyncClient: InstantUserCookieSyncClient = .live,
    platformAppClient: InstantPlatformAppClient = .local,
    appBuilderCodeGenerator: AppBuilderCodeGeneratorClient = .local
  ) {
    self.appID = appID
    self.apiURI = apiURI
    self.websocketURI = websocketURI
    self.firstPartyURL = firstPartyURL
    self.persistenceURL = persistenceURL
    self.initialAttributes = initialAttributes
    self.deferredValueResidency = deferredValueResidency
    self.now = now
    self.makeID = makeID
    self.refreshTokenVerifier = refreshTokenVerifier
    self.guestAuthenticator = guestAuthenticator
    self.magicCodeExchange = magicCodeExchange
    self.idTokenExchange = idTokenExchange
    self.oauthExchange = oauthExchange
    self.authTokenInvalidator = authTokenInvalidator
    self.mutationTransport = mutationTransport
    self.liveTransport = liveTransport
    self.autoConnectLiveTransport = false
    self.liveShareContract = liveShareContract
    self.userCookieSyncClient = userCookieSyncClient
    self.platformAppClient = platformAppClient
    self.appBuilderCodeGenerator = appBuilderCodeGenerator
    self.actorHopRecorder = nil
    self.isLocalOnly = false
  }

  public static func isValidAPIURI(_ url: URL) -> Bool {
    isValidEndpointURI(url, allowedSchemes: ["http", "https"])
  }

  public static func isValidWebSocketURI(_ url: URL) -> Bool {
    isValidEndpointURI(url, allowedSchemes: ["ws", "wss"])
  }

  private static func isValidEndpointURI(_ url: URL, allowedSchemes: Set<String>) -> Bool {
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
      let scheme = components.scheme?.lowercased(),
      allowedSchemes.contains(scheme),
      components.host?.isEmpty == false,
      components.query == nil,
      components.fragment == nil
    else {
      return false
    }
    return true
  }
}

private actor InstantAuthSessionObservers {
  private var continuations: [UUID: AsyncStream<InstantAuthSession?>.Continuation] = [:]

  func observe(current session: InstantAuthSession?) -> AsyncStream<InstantAuthSession?> {
    let id = UUID()
    let stream = AsyncStream<InstantAuthSession?>.makeStream(bufferingPolicy: .bufferingNewest(1))
    continuations[id] = stream.continuation
    stream.continuation.yield(session)
    stream.continuation.onTermination = { @Sendable _ in
      Task { await self.cancel(id: id) }
    }
    return stream.stream
  }

  func yield(_ session: InstantAuthSession?) {
    for continuation in continuations.values {
      continuation.yield(session)
    }
  }

  private func cancel(id: UUID) {
    continuations[id] = nil
  }
}

// SAFETY: upload cancellation state is protected by `lock`.
private final class InstantFileUploadProgressCancellation: @unchecked Sendable {
  private let lock = NSLock()
  private var isCancelled = false
  private var isFinished = false

  func cancel() {
    lock.withLock {
      guard !isFinished else { return }
      isCancelled = true
    }
  }

  func check() throws {
    if lock.withLock({ isCancelled }) {
      throw CancellationError()
    }
  }

  /// Linearizes one terminal publication against cancellation.
  func claimTerminalPublication() -> Bool {
    lock.withLock {
      guard !isCancelled, !isFinished else { return false }
      isFinished = true
      return true
    }
  }
}

private actor InstantRuntimeLiveRoomPresenceState {
  private var sessionsByRoom: [InstantRoomHandle: JSONValue] = [:]

  func replace(
    room: InstantRoomHandle,
    sessions: [String: InstantLiveJSONValue],
    excludingSessionID: String?,
    appID: String,
    updatedAt: InstantTimestamp
  ) -> [InstantRoomPresenceMember] {
    var value = JSONValue.object(sessions.mapValues(\.jsonValue))
    if let excludingSessionID {
      value.dissocIn([.key(excludingSessionID)])
    }
    sessionsByRoom[room] = value
    return members(
      room: room,
      sessions: value,
      excludingSessionID: excludingSessionID,
      appID: appID,
      updatedAt: updatedAt
    )
  }

  func patch(
    room: InstantRoomHandle,
    edits: [InstantLiveJSONValue],
    excludingSessionID: String?,
    appID: String,
    updatedAt: InstantTimestamp
  ) throws -> [InstantRoomPresenceMember] {
    var sessions = sessionsByRoom[room] ?? .object([:])
    for (index, edit) in edits.enumerated() {
      guard case let .array(parts) = edit,
        parts.count >= 2,
        case let .array(rawPath) = parts[0],
        let operation = parts[1].stringValue
      else {
        throw malformedPatch(index: index)
      }
      let path = try rawPath.map { component -> JSONValuePathComponent in
        guard let key = component.stringValue else {
          throw malformedPatch(index: index)
        }
        return .key(key)
      }
      switch operation {
      case "+":
        guard parts.count == 3 else { throw malformedPatch(index: index) }
        sessions.insertIn(path, parts[2].jsonValue)
      case "r":
        guard parts.count == 3 else { throw malformedPatch(index: index) }
        sessions.assocIn(path, parts[2].jsonValue)
      case "-":
        guard parts.count == 2 else { throw malformedPatch(index: index) }
        sessions.dissocIn(path)
      default:
        throw malformedPatch(index: index)
      }
    }
    if let excludingSessionID {
      sessions.dissocIn([.key(excludingSessionID)])
    }
    sessionsByRoom[room] = sessions
    return members(
      room: room,
      sessions: sessions,
      excludingSessionID: excludingSessionID,
      appID: appID,
      updatedAt: updatedAt
    )
  }

  func current(
    room: InstantRoomHandle,
    excludingSessionID: String?,
    appID: String,
    updatedAt: InstantTimestamp
  ) -> [InstantRoomPresenceMember] {
    members(
      room: room,
      sessions: sessionsByRoom[room] ?? .object([:]),
      excludingSessionID: excludingSessionID,
      appID: appID,
      updatedAt: updatedAt
    )
  }

  func remove(room: InstantRoomHandle) {
    sessionsByRoom[room] = nil
  }

  private func members(
    room: InstantRoomHandle,
    sessions: JSONValue,
    excludingSessionID: String?,
    appID: String,
    updatedAt: InstantTimestamp
  ) -> [InstantRoomPresenceMember] {
    guard case let .object(sessionValues) = sessions else { return [] }
    return sessionValues.compactMap { sessionID, rawEnvelope in
      guard sessionID != excludingSessionID,
        case let .object(envelope) = rawEnvelope,
        case let .object(values)? = envelope["data"]
      else {
        return nil
      }
      let peerID: String
      if case let .string(value)? = envelope["peer-id"] {
        peerID = value
      } else {
        peerID = sessionID
      }
      let userID: String
      if case let .object(user)? = envelope["user"],
        case let .string(value)? = user["id"]
      {
        userID = value
      } else {
        userID = peerID
      }
      return InstantRoomPresenceMember(
        appID: appID,
        room: room,
        userID: userID,
        values: values,
        updatedAt: updatedAt
      )
    }
    .sorted { $0.id < $1.id }
  }

  private func malformedPatch(index: Int) -> InstantError {
    InstantError(
      code: .decodeFailed,
      operation: "apply Instant live presence patch",
      path: "edits[\(index)]",
      message: "Instant patch-presence contained a malformed edit.",
      recovery: "Inspect the canonical Instant patch-presence payload."
    )
  }
}

private actor InstantRuntimeActiveRoomPresenceState {
  private var userIDsByRoom: [InstantRoomHandle: Set<String>] = [:]

  func activate(userID: String, in room: InstantRoomHandle) {
    userIDsByRoom[room, default: []].insert(userID)
  }

  func deactivate(userID: String, in room: InstantRoomHandle) {
    userIDsByRoom[room]?.remove(userID)
    if userIDsByRoom[room]?.isEmpty == true {
      userIDsByRoom[room] = nil
    }
  }

  func removeAll(in room: InstantRoomHandle) {
    userIDsByRoom[room] = nil
  }

  func activeMembers(
    _ members: [InstantRoomPresenceMember],
    in room: InstantRoomHandle
  ) -> [InstantRoomPresenceMember] {
    guard let activeUserIDs = userIDsByRoom[room] else { return [] }
    return members.filter { activeUserIDs.contains($0.userID) }
  }
}

private actor InstantRuntimeReconnectController {
  private let taskOwner = InstantRuntimeExactTaskOwner()
  private var lifecycleGeneration = 0
  private var acceptsStarts = true

  func start(
    sleep: @escaping @Sendable (UInt64) async throws -> Void,
    reconnect: @escaping @Sendable () async throws -> Void
  ) {
    guard acceptsStarts else { return }
    _ = taskOwner.start(restartIfRunning: true) { [weak self] in
      await self?.run(sleep: sleep, reconnect: reconnect)
    }
  }

  func cancelAndWait() async {
    lifecycleGeneration += 1
    let lifecycleGeneration = lifecycleGeneration
    acceptsStarts = false
    let handle = taskOwner.requestStop()
    await handle.wait()
    guard lifecycleGeneration == self.lifecycleGeneration else { return }
    taskOwner.resume()
    acceptsStarts = true
  }

  func requestStop() -> InstantRuntimeExactTaskOwner.Handle {
    lifecycleGeneration += 1
    acceptsStarts = false
    return taskOwner.requestStop()
  }

  func isIdleForTesting() -> Bool {
    taskOwner.isIdle
  }

  private func run(
    sleep: @escaping @Sendable (UInt64) async throws -> Void,
    reconnect: @escaping @Sendable () async throws -> Void
  ) async {
    var attempt: UInt64 = 0
    while !Task.isCancelled {
      let delay = min(attempt * 1_000, 10_000)
      do {
        try await sleep(delay)
        try Task.checkCancellation()
        try await reconnect()
        return
      } catch is CancellationError {
        return
      } catch {
        attempt += 1
      }
    }
  }
}

/// Coalesces failed-mutation retry and local-write delivery requests into one
/// fair live-session pump.
///
/// Speech can commit several open-segment updates while one SQLite hydration
/// and WebSocket send is in flight. A task per write used to queue redundant
/// full-outbox hydrations behind the operation gate, delaying the next local
/// commit and temporarily retaining duplicate encoded transaction graphs. A
/// pump turn now admits at most one retry window and one delivery window before
/// yielding, so reconnect latency does not scale with durable queue depth.
private enum InstantRuntimeMutationDeliveryPumpPassResult: Sendable {
  case finished
  case continueImmediately
  case retryAfterFailure
}

private actor InstantRuntimeMutationDeliveryPump {
  private var isSuspended = false
  private var task: Task<Void, Never>?
  private var needsAnotherPass = false

  func isIdleForTesting() -> Bool {
    task == nil && !needsAnotherPass
  }

  func isSuspendedForTesting() -> Bool {
    isSuspended
  }

  func resume() {
    isSuspended = false
  }

  func request(
    sleep: @escaping @Sendable (UInt64) async throws -> Void,
    _ deliver: @escaping @Sendable () async -> InstantRuntimeMutationDeliveryPumpPassResult
  ) {
    guard !isSuspended else { return }
    needsAnotherPass = true
    guard task == nil else { return }

    task = Task { [weak self] in
      await self?.run(sleep: sleep, deliver)
    }
  }

  func suspend() {
    isSuspended = true
    needsAnotherPass = false
    task?.cancel()
  }

  func waitUntilStopped() async {
    let task = task
    await task?.value
    self.task = nil
    needsAnotherPass = false
  }

  private func run(
    sleep: @escaping @Sendable (UInt64) async throws -> Void,
    _ deliver: @escaping @Sendable () async -> InstantRuntimeMutationDeliveryPumpPassResult
  ) async {
    var localFailureAttempt: UInt64 = 0
    pump: while !Task.isCancelled, !isSuspended, needsAnotherPass {
      needsAnotherPass = false
      switch await deliver() {
      case .finished:
        localFailureAttempt = 0

      case .continueImmediately:
        localFailureAttempt = 0
        needsAnotherPass = true
        await Task.yield()

      case .retryAfterFailure:
        // A local SQLite window failure is neither an empty outbox nor a socket
        // failure. Keep the healthy session open and retry this pump, with a
        // five-second maximum delay so failures stay loud and bounded.
        let delay: UInt64 = min(250 << min(localFailureAttempt, 4), 5_000)
        localFailureAttempt += 1
        do {
          try Task.checkCancellation()
          try await sleep(delay)
          needsAnotherPass = true
        } catch {
          break pump
        }
      }
    }
    task = nil
    if isSuspended {
      needsAnotherPass = false
    }
  }
}

private enum InstantExplicitMutationTransportOutcome: Sendable {
  case response(InstantMutationTransportResponse)
  case failure(InstantError)
  case cancelled
}

private enum InstantExplicitMutationTransportRaceEvent: Sendable {
  case completed
  case timedOut
  case cancelled
  case renewalFailed(InstantError)
}

// SAFETY: `lock` protects the one-shot event and continuation. Resolution is
// synchronous so a close or caller cancellation can wake the exact operation
// in the same boundary that invokes the transport's synchronous abort handle.
private final class InstantExplicitMutationTransportRace: @unchecked Sendable {
  private let lock = NSLock()
  private var event: InstantExplicitMutationTransportRaceEvent?
  private var continuation:
    CheckedContinuation<InstantExplicitMutationTransportRaceEvent, Never>?

  func resolve(_ event: InstantExplicitMutationTransportRaceEvent) {
    let continuation = lock.withLock {
      () -> CheckedContinuation<InstantExplicitMutationTransportRaceEvent, Never>? in
      guard self.event == nil else { return nil }
      self.event = event
      defer { self.continuation = nil }
      return self.continuation
    }
    continuation?.resume(returning: event)
  }

  func firstEvent() async -> InstantExplicitMutationTransportRaceEvent {
    return await withCheckedContinuation { continuation in
      let pending = lock.withLock { () -> InstantExplicitMutationTransportRaceEvent? in
        if let existing = self.event {
          return existing
        }
        self.continuation = continuation
        return nil
      }
      if let pending {
        continuation.resume(returning: pending)
      }
    }
  }
}

// SAFETY: `lock` orders close/caller cancellation against late child-task
// installation. The transport abort is already idempotent, and no task handle
// is canceled while the lock is held.
private final class InstantExplicitMutationOperationCancellation: @unchecked Sendable {
  private let lock = NSLock()
  private let operation: InstantMutationTransportOperation
  private let race: InstantExplicitMutationTransportRace
  private var didCancel = false
  private var transportTask: Task<InstantExplicitMutationTransportOutcome, Never>?
  private var deadlineTask: Task<Void, Never>?

  init(
    operation: InstantMutationTransportOperation,
    race: InstantExplicitMutationTransportRace
  ) {
    self.operation = operation
    self.race = race
  }

  func installTransportTask(
    _ task: Task<InstantExplicitMutationTransportOutcome, Never>
  ) {
    let cancel = lock.withLock {
      transportTask = task
      return didCancel
    }
    if cancel { task.cancel() }
  }

  func installDeadlineTask(_ task: Task<Void, Never>) {
    let cancel = lock.withLock {
      deadlineTask = task
      return didCancel
    }
    if cancel { task.cancel() }
  }

  func cancel() {
    let tasks = lock.withLock { () -> (
      transport: Task<InstantExplicitMutationTransportOutcome, Never>?,
      deadline: Task<Void, Never>?
    )? in
      guard !didCancel else { return nil }
      didCancel = true
      return (transportTask, deadlineTask)
    }
    guard let tasks else { return }
    operation.abort()
    tasks.transport?.cancel()
    tasks.deadline?.cancel()
    race.resolve(.cancelled)
  }
}

private enum InstantExplicitMutationFlushCompletion: Sendable {
  case success(InstantMutationTransportFlushResult)
  case failure(InstantError)
  case cancelled
}

private enum InstantExplicitMutationDisposition: Sendable {
  case success(InstantMutationTransportFlushResult)
  case responseFailure(InstantError)
  case transportFailure(InstantError)
  case transportCancelled
}

/// Owns one public explicit flush independently from its waiting caller.
///
/// Cancellation latches before invoking the installed synchronous abort, and
/// a late installation immediately observes that latch. The owner retains the
/// task until transport, renewal, deadline, and exact-token disposition have
/// all completed.
// SAFETY: `lock` protects every mutable field and no closure or Task handle is
// invoked or awaited while the lock is held.
private final class InstantExplicitMutationFlushOwner: @unchecked Sendable {
  struct Handle: Sendable {
    fileprivate var token: UInt64?
    fileprivate var task: Task<InstantExplicitMutationFlushCompletion, Never>?

    func wait() async {
      _ = await task?.value
    }

    func completion() async -> InstantExplicitMutationFlushCompletion? {
      await task?.value
    }
  }

  private let lock = NSLock()
  private var nextToken: UInt64 = 0
  private var isSuspended = false
  private var running: Handle?
  private var didRequestCancellation = false
  private var cancellationOperation: (@Sendable () -> Void)?

  func start(
    _ operation: @escaping @Sendable (_ token: UInt64) async throws
      -> InstantMutationTransportFlushResult
  ) -> Handle? {
    lock.withLock {
      guard !isSuspended, running == nil else { return nil }
      nextToken &+= 1
      let token = nextToken
      let task = Task { [weak self] in
        let completion: InstantExplicitMutationFlushCompletion
        do {
          completion = .success(try await operation(token))
        } catch is CancellationError {
          completion = .cancelled
        } catch let error as InstantError {
          completion = .failure(error)
        } catch {
          completion = .failure(
            InstantError(
              code: .networkFailed,
              operation: "flush Instant mutation transport",
              message: String(describing: error),
              recovery: "Inspect the configured mutation transport and retry the bounded durable outbox window."
            )
          )
        }
        self?.finish(token: token)
        return completion
      }
      let handle = Handle(token: token, task: task)
      running = handle
      didRequestCancellation = false
      cancellationOperation = nil
      return handle
    }
  }

  func installCancellation(
    token: UInt64,
    _ operation: @escaping @Sendable () -> Void
  ) {
    let operationToRun = lock.withLock { () -> (@Sendable () -> Void)? in
      guard running?.token == token else { return operation }
      if didRequestCancellation { return operation }
      cancellationOperation = operation
      return nil
    }
    operationToRun?()
  }

  func cancel(_ handle: Handle) {
    cancel(token: handle.token, suspending: false)
  }

  func requestStop() -> Handle {
    let handle = lock.withLock {
      isSuspended = true
      return running ?? Handle(token: nil, task: nil)
    }
    cancel(token: handle.token, suspending: true)
    return handle
  }

  func resume() {
    lock.withLock { isSuspended = false }
  }

  var isIdle: Bool {
    lock.withLock { running == nil }
  }

  private func cancel(token: UInt64?, suspending: Bool) {
    let cancellation = lock.withLock { () -> (
      operation: (@Sendable () -> Void)?, task: Task<InstantExplicitMutationFlushCompletion, Never>?
    ) in
      if suspending { isSuspended = true }
      guard let token, running?.token == token else { return (nil, nil) }
      didRequestCancellation = true
      let operation = cancellationOperation
      cancellationOperation = nil
      return (operation, running?.task)
    }
    cancellation.operation?()
    cancellation.task?.cancel()
  }

  private func finish(token: UInt64) {
    lock.withLock {
      guard running?.token == token else { return }
      running = nil
      didRequestCancellation = false
      cancellationOperation = nil
    }
  }
}

private actor InstantRuntimeMutationDeadlineWake {
  private var task: Task<Void, Never>?
  private var deadlineMilliseconds: Int64?
  private var generation = 0

  func request(
    deadlineMilliseconds: Int64?,
    now: @escaping @Sendable () -> InstantTimestamp,
    sleep: @escaping @Sendable (UInt64) async throws -> Void,
    wake: @escaping @Sendable () async -> Void
  ) {
    guard let deadlineMilliseconds else {
      generation += 1
      self.deadlineMilliseconds = nil
      task?.cancel()
      task = nil
      return
    }
    if let scheduled = self.deadlineMilliseconds,
      scheduled <= deadlineMilliseconds,
      task != nil
    {
      return
    }
    generation += 1
    let generation = generation
    self.deadlineMilliseconds = deadlineMilliseconds
    task?.cancel()
    task = Task { [weak self] in
      do {
        let remaining = max(0, deadlineMilliseconds - now().milliseconds)
        try await sleep(UInt64(remaining))
        try Task.checkCancellation()
      } catch {
        _ = await self?.finish(generation: generation)
        return
      }
      guard await self?.finish(generation: generation) == true else { return }
      await wake()
    }
  }

  private func finish(generation: Int) -> Bool {
    guard generation == self.generation else { return false }
    task = nil
    deadlineMilliseconds = nil
    return true
  }
}

private struct InstantSharedRootWriteTarget: Hashable, Sendable {
  var namespace: String?
  var id: String
}

private struct InstantAppliedServerTransaction: Sendable {
  var transaction: InstantStoreTransaction
  var application: InstantServerTransactionApplicationResult
  var confirmedMutation: PendingMutation?
  var mergedAttributeCount: Int
}

private actor InstantLiveQueryAcknowledgementState {
  private enum Outcome: Sendable {
    case acknowledged
    case rejected(InstantError)
  }

  private var revisions: [String: Int] = [:]
  private var outcomes: [String: (revision: Int, outcome: Outcome)] = [:]
  private var waiters: [String: [UUID: AsyncThrowingStream<Void, Error>.Continuation]] = [:]

  func revision(for key: String) -> Int {
    revisions[key, default: 0]
  }

  func record(key: String) {
    revisions[key, default: 0] += 1
    outcomes[key] = (revisions[key, default: 0], .acknowledged)
    let continuations = waiters.removeValue(forKey: key).map { Array($0.values) } ?? []
    for continuation in continuations {
      continuation.yield(())
      continuation.finish()
    }
  }

  func reject(key: String, error: InstantError) {
    revisions[key, default: 0] += 1
    outcomes[key] = (revisions[key, default: 0], .rejected(error))
    let continuations = waiters.removeValue(forKey: key).map { Array($0.values) } ?? []
    for continuation in continuations {
      continuation.finish(throwing: error)
    }
  }

  func wait(for key: String, after observedRevision: Int) async throws {
    if revisions[key, default: 0] > observedRevision {
      if let outcome = outcomes[key], outcome.revision > observedRevision {
        try resolve(outcome.outcome)
      }
      return
    }
    let id = UUID()
    let stream = AsyncThrowingStream<Void, Error>(bufferingPolicy: .bufferingNewest(1)) {
      continuation in
      if revisions[key, default: 0] > observedRevision {
        if let outcome = outcomes[key], outcome.revision > observedRevision {
          switch outcome.outcome {
          case .acknowledged:
            continuation.yield(())
            continuation.finish()
          case let .rejected(error):
            continuation.finish(throwing: error)
          }
        } else {
          continuation.yield(())
          continuation.finish()
        }
      } else {
        waiters[key, default: [:]][id] = continuation
        continuation.onTermination = { @Sendable _ in
          Task {
            await self.cancelWaiter(key: key, id: id)
          }
        }
      }
    }
    var iterator = stream.makeAsyncIterator()
    _ = try await iterator.next()
  }

  private func resolve(_ outcome: Outcome) throws {
    if case let .rejected(error) = outcome {
      throw error
    }
  }

  private func cancelWaiter(key: String, id: UUID) {
    waiters[key]?[id] = nil
    if waiters[key]?.isEmpty == true {
      waiters[key] = nil
    }
  }
}

// SAFETY: `lock` protects every read and write of the cadence counter.
private final class InstantQueryCachePruningCadence: @unchecked Sendable {
  private let lock = NSLock()
  private var writesSinceLastPrune = 0

  func shouldPrune(afterSuccessfulWriteWithInterval interval: Int) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    let interval = max(1, interval)
    if writesSinceLastPrune >= interval - 1 {
      writesSinceLastPrune = 0
      return true
    }
    writesSinceLastPrune += 1
    return false
  }
}

// SAFETY: `lock` protects every access to the mutable replacement counter.
private final class InstantRuntimeStoreAdoptionMetrics: @unchecked Sendable {
  private let lock = NSLock()
  private var storeSnapshotReplacementCount = 0

  func reset() {
    lock.lock()
    storeSnapshotReplacementCount = 0
    lock.unlock()
  }

  func recordStoreSnapshotReplacement() {
    lock.lock()
    storeSnapshotReplacementCount += 1
    lock.unlock()
  }

  func currentStoreSnapshotReplacementCount() -> Int {
    lock.lock()
    defer { lock.unlock() }
    return storeSnapshotReplacementCount
  }
}

// SAFETY: `lock` protects every access to the revisions installed in the hot
// `InstantStore` actor. The scalar pair lets persistence distinguish its own
// memory-cache revision from the revision this runtime has actually adopted.
private final class InstantRuntimeInstalledStoreRevisions: @unchecked Sendable {
  private let lock = NSLock()
  private var storeRevision: Int64
  private var attributeRevision: Int64

  init(storeRevision: Int64, attributeRevision: Int64) {
    self.storeRevision = storeRevision
    self.attributeRevision = attributeRevision
  }

  func snapshot() -> (store: Int64, attributes: Int64) {
    lock.lock()
    defer { lock.unlock() }
    return (storeRevision, attributeRevision)
  }

  func install(storeRevision: Int64, attributeRevision: Int64) {
    lock.lock()
    self.storeRevision = storeRevision
    self.attributeRevision = attributeRevision
    lock.unlock()
  }
}

private actor InstantAutomaticMutationRetryReservations {
  private var ownerCountsByMutationID: [String: Int] = [:]

  func reserve(_ mutationID: String) {
    ownerCountsByMutationID[mutationID, default: 0] += 1
  }

  func release(_ mutationID: String) {
    guard let ownerCount = ownerCountsByMutationID[mutationID] else { return }
    if ownerCount == 1 {
      ownerCountsByMutationID[mutationID] = nil
    } else {
      ownerCountsByMutationID[mutationID] = ownerCount - 1
    }
  }

  func contains(_ mutationID: String) -> Bool {
    ownerCountsByMutationID[mutationID] != nil
  }

  func snapshot() -> Set<String> {
    Set(ownerCountsByMutationID.keys)
  }
}

public final class InstantRuntime: Sendable {
  public static let selectedAppIDMetadataKey = "cli.selected_app_id"
  public static let cookieSyncLastUpdatedMetadataKey = "lastSyncedUserCookie"
  public static let cookieSyncIntervalMilliseconds: Int64 = 24 * 60 * 60 * 1000
  private static let authUsersNamespace = "$users"
  public let configuration: InstantRuntimeConfiguration
  public let store: InstantStore
  public let persistence: SQLitePersistenceStore
  let outbox: InstantOutbox
  private let authSessionObservers = InstantAuthSessionObservers()
  private let connectionStatusObservers =
    InstantSnapshotObservers<String, InstantConnectionStatus>()
  private let mutationLifecycleObservers =
    InstantSnapshotObservers<String, InstantMutationLifecycleEvent>()
  private let roomPresenceObservers =
    InstantSnapshotObservers<InstantRoomPresenceObservationKey, [InstantRoomPresenceMember]>()
  private let roomTopicObservers =
    InstantSnapshotObservers<InstantRoomTopicObservationKey, [InstantRoomTopicMessage]>()
  private let storedFilesObservers =
    InstantSnapshotObservers<InstantStoredFilesObservationKey, [InstantStoredFile]>()
  private let storageTransport: InstantStorageTransportClient?
  private let streamFileTransport: InstantStreamFileTransportClient
  private let streamChunksObservers =
    InstantSnapshotObservers<InstantStreamChunksObservationKey, [InstantStreamChunk]>()
  private let streamContentObservers = InstantStreamContentObservers()
  private let sharesObservers =
    InstantSnapshotObservers<InstantSharesObservationKey, [InstantShareSnapshot]>()
  private let operationGate = AsyncSerialGate(label: "operation")
  private let authPromotionGate = AsyncSerialGate(label: "auth-promotion")
  private let connectionGate = AsyncSerialGate(label: "connection")
  private let mutationFlushGate = AsyncSerialGate(label: "mutation-flush")
  private let queryCachePruningCadence = InstantQueryCachePruningCadence()
  private let liveQueryResultPruningCadence = InstantQueryCachePruningCadence()
  private let liveSession = InstantRuntimeLiveSession()
  private let liveQueryResultState = InstantLiveQueryResultState()
  private let liveQueryAcknowledgements = InstantLiveQueryAcknowledgementState()
  private let liveRoomPresenceState = InstantRuntimeLiveRoomPresenceState()
  private let activeRoomPresenceState = InstantRuntimeActiveRoomPresenceState()
  private let automaticLiveConnectionTaskOwner = InstantRuntimeExactTaskOwner()
  private let startupCookieSyncTaskOwner = InstantRuntimeExactTaskOwner()
  private let reconnectController = InstantRuntimeReconnectController()
  private let mutationDeliveryPump = InstantRuntimeMutationDeliveryPump()
  private let explicitMutationFlushOwner = InstantExplicitMutationFlushOwner()
  private let mutationDeadlineWake = InstantRuntimeMutationDeadlineWake()
  private let automaticDeliveryClaimantID = UUID().uuidString.lowercased()
  private let automaticMutationRetryReservations = InstantAutomaticMutationRetryReservations()
  private let storeAdoptionMetrics = InstantRuntimeStoreAdoptionMetrics()
  private let installedStoreRevisions: InstantRuntimeInstalledStoreRevisions

  private init(
    configuration: InstantRuntimeConfiguration,
    store: InstantStore,
    outbox: InstantOutbox,
    persistence: SQLitePersistenceStore,
    storageTransport: InstantStorageTransportClient?,
    streamFileTransport: InstantStreamFileTransportClient,
    storeRevision: Int64,
    attributeRevision: Int64
  ) {
    self.configuration = configuration
    self.store = store
    self.outbox = outbox
    self.persistence = persistence
    self.storageTransport = storageTransport
    self.streamFileTransport = streamFileTransport
    self.installedStoreRevisions = InstantRuntimeInstalledStoreRevisions(
      storeRevision: storeRevision,
      attributeRevision: attributeRevision
    )
  }

  package func resetPersistenceCacheResidencyMetricsForTesting() async {
    storeAdoptionMetrics.reset()
    await persistence.resetCacheResidencyMetricsForTesting()
  }

  package func persistenceCacheResidencyMetricsForTesting() async
    -> InstantPersistenceCacheResidencyMetrics
  {
    var metrics = await persistence.cacheResidencyMetricsForTesting()
    metrics.storeSnapshotReplacementCount =
      storeAdoptionMetrics.currentStoreSnapshotReplacementCount()
    return metrics
  }

  public static func bootstrap(configuration: InstantRuntimeConfiguration) async throws -> Self {
    try await bootstrap(
      configuration: configuration,
      storageTransport: nil,
      streamFileTransport: .live
    )
  }

  public static func bootstrap(
    configuration: InstantRuntimeConfiguration,
    storageTransport: InstantStorageTransportClient?
  ) async throws -> Self {
    try await bootstrap(
      configuration: configuration,
      storageTransport: storageTransport,
      streamFileTransport: .live
    )
  }

  public static func bootstrap(
    configuration: InstantRuntimeConfiguration,
    storageTransport: InstantStorageTransportClient?,
    streamFileTransport: InstantStreamFileTransportClient
  ) async throws -> Self {
    let startupTrace = configuration.startupTrace
    let runtimeStopwatch = startupTrace.started(
      "runtime.bootstrap",
      metadata: [
        "appID": configuration.appID,
        "attributeCount": String(configuration.initialAttributes.count),
        "hasLiveTransport": String(configuration.liveTransport != nil),
      ]
    )
    let startedAt = Date()
    InstantDiagnostics.shared.record(
      .info,
      subsystem: "instant-swift-data-core",
      category: "runtime",
      event: "runtime.bootstrap-started",
      message: "Bootstrapping the Instant runtime.",
      metadata: [
        "appID": configuration.appID,
        "persistencePath": configuration.persistenceURL.path,
        "attributeCount": String(configuration.initialAttributes.count),
        "hasLiveTransport": String(configuration.liveTransport != nil),
        "autoConnect": String(configuration.autoConnectLiveTransport),
        "hasStorageTransport": String(storageTransport != nil),
      ]
    )
    do {
      let validationStopwatch = startupTrace.stopwatch()
      try validateEndpoints(configuration)
      try validateInitialAttributes(configuration.initialAttributes)
      if !configuration.initialAttributes.isEmpty {
        try configuration.deferredValueResidency.validate(
          attributes: configuration.initialAttributes
        )
      }
      startupTrace.completed("runtime.validation", since: validationStopwatch)

      let persistence = try SQLitePersistenceStore(
        fileURL: configuration.persistenceURL,
        startupTrace: startupTrace,
        deferredValueResidency: configuration.deferredValueResidency,
        declaredAttributes: configuration.initialAttributes
      )
      configuration.actorHopRecorder?.record(.persistence)
      let bootstrapPruningResult = try await persistence.bootstrap(
        queryCachePruningPolicy: configuration.queryCachePruningPolicy,
        now: configuration.now()
      )
      if let bootstrapPruningResult,
        !bootstrapPruningResult.removedCacheKeys.isEmpty
      {
        InstantDiagnostics.shared.record(
          .debug,
          subsystem: "instant-swift-data-core",
          category: "query",
          event: "query-cache.pruned-at-bootstrap",
          message: "Pruned unloaded persisted query results during runtime bootstrap.",
          metadata: [
            "remainingCount": String(bootstrapPruningResult.remainingEntryCount),
            "removedCount": String(bootstrapPruningResult.removedCacheKeys.count),
          ]
        )
      }
      configuration.actorHopRecorder?.record(.persistence)
      var state = try await persistence.loadCompactState()
      let storeMaterializationStopwatch = startupTrace.stopwatch()
      let store = InstantStore(
        snapshot: state.snapshot.store,
        deferredValueResidency: configuration.deferredValueResidency
      )
      let outbox = InstantOutbox(mutations: state.snapshot.outbox)
      startupTrace.completed(
        "runtime.store-materialization",
        since: storeMaterializationStopwatch,
        metadata: [
          "attributeCount": String(state.snapshot.store.attributes.count),
          "tripleCount": String(state.snapshot.store.triples.count),
          "outboxCount": String(state.snapshot.outbox.count),
        ]
      )

      let attributeMergeStopwatch = startupTrace.stopwatch()
      var didChangeAttributes = false
      if !configuration.initialAttributes.isEmpty {
        var didBootstrapAttributes = false
        for attempt in 1...5 {
          configuration.actorHopRecorder?.record(.store)
          // Capture the durable diff base before mutating the hot store. On a
          // fresh database both the durable and hot triple arrays are empty;
          // taking this snapshot after the merge makes the new attributes look
          // unchanged and leaves SQLite without schema/cardinality metadata.
          let previousForDiff = state.snapshot.store
          let storeMergeStopwatch = startupTrace.stopwatch()
          let storeSnapshot = await store.mergeAttributesIfChanged(configuration.initialAttributes)
          startupTrace.completed(
            "runtime.attribute-store-merge",
            since: storeMergeStopwatch,
            metadata: [
              "attempt": String(attempt),
              "changed": String(storeSnapshot != nil),
            ]
          )
          guard let storeSnapshot else {
            didBootstrapAttributes = true
            break
          }
          configuration.actorHopRecorder?.record(.persistence)
          let didSave = try await persistence.saveStoreSnapshot(
            storeSnapshot,
            replacing: previousForDiff,
            expectedStoreRevision: state.storeRevision,
            expectedOutboxRevision: state.outboxRevision,
            expectedAttributeRevision: state.attributeRevision
          )
          if didSave {
            didChangeAttributes = true
            let triplesChanged = storeSnapshot.triples != previousForDiff.triples
            let attributesChanged = storeSnapshot.attributes != previousForDiff.attributes
            state = InstantPersistenceState(
              snapshot: InstantPersistenceSnapshot(
                store: storeSnapshot,
                outbox: state.snapshot.outbox
              ),
              storeRevision: state.storeRevision + (triplesChanged ? 1 : 0),
              outboxRevision: state.outboxRevision,
              attributeRevision: state.attributeRevision + (attributesChanged ? 1 : 0),
              queryResultRevision: state.queryResultRevision
            )
            didBootstrapAttributes = true
            break
          }
          configuration.actorHopRecorder?.record(.persistence)
          let reloaded = try await persistence.loadStateWithSource()
          state = reloaded.state
          switch reloaded.storeAdoption {
          case .none:
            break
          case let .attributes(attributes):
            configuration.actorHopRecorder?.record(.store)
            _ = await store.replaceAttributes(attributes)
          case let .snapshot(snapshot):
            configuration.actorHopRecorder?.record(.store)
            await store.replaceSnapshot(snapshot)
          }
          configuration.actorHopRecorder?.record(.outbox)
          await outbox.replace(with: state.snapshot.outbox)
        }
        guard didBootstrapAttributes else {
          throw InstantError(
            code: .persistenceFailed,
            operation: "bootstrap attributes",
            message: "The local Instant cache changed repeatedly while bootstrapping schema attributes.",
            recovery: "Retry launch after other writers finish updating the shared cache."
          )
        }
      } else {
        startupTrace.completed(
          "runtime.attribute-store-merge",
          durationMilliseconds: 0,
          metadata: ["skipped": "true"]
        )
      }
      startupTrace.completed(
        "runtime.attribute-merge",
        since: attributeMergeStopwatch,
        metadata: [
          "changed": String(didChangeAttributes),
          "requestedAttributeCount": String(configuration.initialAttributes.count),
          "storedAttributeCount": String(state.snapshot.store.attributes.count),
        ]
      )

      let runtime = Self(
        configuration: configuration,
        store: store,
        outbox: outbox,
        persistence: persistence,
        storageTransport: storageTransport,
        streamFileTransport: streamFileTransport,
        storeRevision: state.storeRevision,
        attributeRevision: state.attributeRevision
      )

      do {
        configuration.actorHopRecorder?.record(.persistence)
        let pruning = try await persistence.pruneLiveQueryResults(
          policy: configuration.liveQueryResultPruningPolicy,
          now: configuration.now(),
          currentStoreSnapshot: state.snapshot.store
        )
        if !pruning.result.removedQueryKeys.isEmpty {
          state = pruning.state
          if pruning.result.removedOrphanedTripleCount > 0 {
            configuration.actorHopRecorder?.record(.store)
            await store.replaceSnapshot(state.snapshot.store)
            runtime.installedStoreRevisions.install(
              storeRevision: state.storeRevision,
              attributeRevision: state.attributeRevision
            )
          }
          configuration.actorHopRecorder?.record(.outbox)
          await outbox.replace(with: state.snapshot.outbox)
          InstantDiagnostics.shared.record(
            .debug,
            subsystem: "instant-swift-data-core",
            category: "query",
            event: "live-query-results.pruned-at-bootstrap",
            message: "Pruned unloaded persisted live query results during runtime bootstrap.",
            metadata: [
              "remainingCount": String(pruning.result.remainingEntryCount),
              "remainingTripleCount": String(pruning.result.remainingTripleCount),
              "removedCount": String(pruning.result.removedQueryKeys.count),
              "removedOrphanedTripleCount": String(
                pruning.result.removedOrphanedTripleCount
              ),
            ]
          )
        }
      } catch {
        InstantDiagnostics.shared.record(
          error: error,
          subsystem: "instant-swift-data-core",
          category: "query",
          event: "live-query-results.bootstrap-prune-failed",
          message: "Could not prune persisted live query results during runtime bootstrap."
        )
      }

      runtime.startUserCookieSyncOnStartup()
      runtime.startAutomaticLiveConnectionIfNeeded()
      startupTrace.completed(
        "runtime.services-scheduled",
        durationMilliseconds: 0,
        metadata: [
          "autoConnect": String(configuration.autoConnectLiveTransport),
          "cookieSyncScheduled": "true",
        ]
      )
      InstantDiagnostics.shared.record(
        .notice,
        subsystem: "instant-swift-data-core",
        category: "runtime",
        event: "runtime.bootstrap-completed",
        message: "Instant runtime bootstrap completed.",
        metadata: [
          "appID": configuration.appID,
          "durationMilliseconds": String(
            Int64((Date().timeIntervalSince(startedAt) * 1_000).rounded())
          ),
          "storedAttributeCount": String(state.snapshot.store.attributes.count),
          "storedTripleCount": String(state.snapshot.store.triples.count),
          "outboxCount": String(state.snapshot.outbox.count),
        ]
      )
      startupTrace.completed(
        "runtime.bootstrap",
        since: runtimeStopwatch,
        metadata: [
          "storedAttributeCount": String(state.snapshot.store.attributes.count),
          "storedTripleCount": String(state.snapshot.store.triples.count),
          "outboxCount": String(state.snapshot.outbox.count),
        ]
      )
      return runtime
    } catch {
      startupTrace.failed("runtime.bootstrap", error: error, since: runtimeStopwatch)
      InstantDiagnostics.shared.record(
        error: error,
        subsystem: "instant-swift-data-core",
        category: "runtime",
        event: "runtime.bootstrap-failed",
        message: "Instant runtime bootstrap failed.",
        metadata: [
          "appID": configuration.appID,
          "persistencePath": configuration.persistenceURL.path,
          "durationMilliseconds": String(
            Int64((Date().timeIntervalSince(startedAt) * 1_000).rounded())
          ),
        ]
      )
      throw error
    }
  }

  private static func validateInitialAttributes(_ attributes: [InstantAttribute]) throws {
    if let attribute = attributes.first(where: {
      $0.name == InstantQueryOrder.serverCreatedAtField
    }) {
      throw InstantError(
        code: .validationFailed,
        operation: "bootstrap attributes",
        namespace: attribute.namespace,
        path: attribute.name,
        localID: attribute.id,
        message: "'\(InstantQueryOrder.serverCreatedAtField)' is reserved for order-only metadata.",
        recovery:
          "Rename the schema field, and use InstantQueryOrder.serverCreatedAt when ordering by "
          + "server creation time."
      )
    }
  }

  private static func validateEndpoints(_ configuration: InstantRuntimeConfiguration) throws {
    guard InstantRuntimeConfiguration.isValidAPIURI(configuration.apiURI) else {
      throw Self.endpointValidationFailed(
        name: "apiURI",
        requirement: "an absolute http or https URL with a host and no query or fragment"
      )
    }
    guard InstantRuntimeConfiguration.isValidWebSocketURI(configuration.websocketURI) else {
      throw endpointValidationFailed(
        name: "websocketURI",
        requirement: "an absolute ws or wss URL with a host and no query or fragment"
      )
    }
    if let firstPartyURL = configuration.firstPartyURL {
      guard InstantRuntimeConfiguration.isValidAPIURI(firstPartyURL) else {
        throw endpointValidationFailed(
          name: "firstPartyURL",
          requirement: "an absolute http or https URL with a host and no query or fragment"
        )
      }
    }
  }

  private static func endpointValidationFailed(name: String, requirement: String) -> InstantError {
    InstantError(
      code: .validationFailed,
      operation: "bootstrap endpoint configuration",
      path: name,
      message: "\(name) must be \(requirement).",
      recovery: "Check the Instant runtime endpoint configuration before bootstrapping."
    )
  }

  private static func cookieSyncISOString(from timestamp: InstantTimestamp) -> String {
    let date = Date(timeIntervalSince1970: Double(timestamp.milliseconds) / 1000)
    return cookieSyncDateFormatter().string(from: date)
  }

  private static func cookieSyncMilliseconds(from value: String) -> Int64? {
    for formatter in cookieSyncDateFormatters() {
      guard let date = formatter.date(from: value) else { continue }
      return Int64((date.timeIntervalSince1970 * 1000).rounded())
    }
    return nil
  }

  private static func cookieSyncDateFormatter() -> ISO8601DateFormatter {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }

  private static func cookieSyncDateFormatters() -> [ISO8601DateFormatter] {
    let internetDateTimeFormatter = ISO8601DateFormatter()
    internetDateTimeFormatter.formatOptions = [.withInternetDateTime]
    return [cookieSyncDateFormatter(), internetDateTimeFormatter]
  }

  @discardableResult
  public func transact(
    operations: [InstantTripleOperation],
    source: String = "local"
  ) async throws -> InstantStoreMutationResult {
    let transactionID = configuration.makeID()
    return try await transact(
      InstantStoreTransaction(id: transactionID, operations: operations),
      createdAt: configuration.now(),
      source: source
    )
  }

  @discardableResult
  public func transact(
    _ transaction: InstantStoreTransaction,
    createdAt: InstantTimestamp? = nil,
    source: String = "local"
  ) async throws -> InstantStoreMutationResult {
    let startedAt = Date()
    InstantDiagnostics.shared.record(
      .debug,
      subsystem: "instant-swift-data-core",
      category: "mutation",
      event: "transaction.started",
      message: "Started an Instant transaction.",
      metadata: [
        "appID": configuration.appID,
        "operationCount": String(transaction.operations.count),
        "source": source,
      ],
      correlationID: transaction.id
    )
    var enteredOperationGate = false
    do {
      // A cancelled caller must not keep a queue slot and then run the write
      // anyway. Cancellation is honored only before acquisition, so a
      // transaction that has already started still commits atomically.
      try await enterOperationGateUnlessCancelled()
      enteredOperationGate = true
      let result = try await performTransact(transaction, createdAt: createdAt, source: source)
      await leaveOperationGate()
      enteredOperationGate = false
      // Local-first (Instant JS pushOps): return after durable optimistic commit.
      // Do not await websocket delivery here — that couples every increment/send to
      // RTT and makes onOptimisticCommit fire only after the wire send. Admit the
      // work to the one owned delivery pump (the same helper used while connecting).
      await startLiveMutationDeliveryIfNeeded()
      InstantDiagnostics.shared.record(
        .debug,
        subsystem: "instant-swift-data-core",
        category: "mutation",
        event: "transaction.optimistic-commit",
        message: "Transaction committed to the local cache and entered sync processing.",
        metadata: [
          "appID": configuration.appID,
          "changedEntityCount": String(result.changedEntityIDs.count),
          "emissionCount": String(result.emissions.count),
          "tripleCount": String(result.tripleCount),
          "durationMilliseconds": String(
            Int64((Date().timeIntervalSince(startedAt) * 1_000).rounded())
          ),
        ],
        correlationID: transaction.id
      )
      return result
    } catch {
      if enteredOperationGate {
        await leaveOperationGate()
      }
      InstantDiagnostics.shared.record(
        error: error,
        subsystem: "instant-swift-data-core",
        category: "mutation",
        event: "transaction.failed",
        message: "Instant transaction failed.",
        metadata: [
          "appID": configuration.appID,
          "operationCount": String(transaction.operations.count),
          "source": source,
          "durationMilliseconds": String(
            Int64((Date().timeIntervalSince(startedAt) * 1_000).rounded())
          ),
        ],
        correlationID: transaction.id
      )
      throw error
    }
  }

  private func performTransact(
    _ transaction: InstantStoreTransaction,
    createdAt: InstantTimestamp?,
    source: String
  ) async throws -> InstantStoreMutationResult {
    var mutation: PendingMutation?

    for _ in 0..<5 {
      recordActorHop(.persistence)
      let state = try await loadCompactStateSynchronizingStore()
      if transaction.operations.isEmpty {
        return InstantStoreMutationResult(
          transactionID: transaction.id,
          changedEntityIDs: [],
          tripleCount: await store.currentTripleCount(),
          emissions: []
        )
      }
      let storeSnapshotForAuth = await authoritativeStoreSnapshot(from: state)
      try await authorizeSharedRootWrites(transaction: transaction, snapshot: storeSnapshotForAuth)
      guard let hydrated = try await persistence.loadOutboxMutations(
        statuses: [.pending, .confirmed, .failed],
        ids: [transaction.id],
        limit: 1,
        expectedStoreRevision: state.storeRevision,
        expectedOutboxRevision: state.outboxRevision
      ) else { continue }
      if let existingMutation = hydrated.first {
        recordActorHop(.outbox)
        await outbox.replace(existingMutation)
        guard existingMutation.status == .pending else {
          throw validationFailed(
            operation: "transact",
            localID: transaction.id,
            message:
              "Mutation '\(transaction.id)' already exists in the local outbox with status '\(existingMutation.status.rawValue)'.",
            recovery:
              "Use a new transaction id, or retry the existing outbox mutation before sending it again."
          )
        }
        guard Self.hasSameWireIntent(existingMutation, transaction) else {
          throw validationFailed(
            operation: "transact",
            localID: transaction.id,
            message:
              "Mutation '\(transaction.id)' is already pending with different operations.",
            recovery:
              "Reuse the same prepared transaction when retrying, or generate a new transaction id."
          )
        }
        return InstantStoreMutationResult(
          transactionID: transaction.id,
          changedEntityIDs: [],
          tripleCount: await store.currentTripleCount(),
          emissions: []
        )
      }
      let aliasReplay = try await persistence.loadOutboxAliasReplay(
        id: transaction.id,
        expectedStoreRevision: state.storeRevision,
        expectedOutboxRevision: state.outboxRevision
      )
      guard aliasReplay.matchesRevisions else { continue }
      if let alias = aliasReplay.alias {
        throw validationFailed(
          operation: "transact",
          localID: transaction.id,
          message:
            "Mutation '\(transaction.id)' is permanently reserved by an outbox supersession lifecycle whose \(alias.isPending ? "pending" : "completed") survivor is '\(alias.currentMutationID)'.",
          recovery:
            "Observe the existing transaction lifecycle, or use a new transaction id for a new write."
        )
      }
      let creationCursor = try await persistence.latestOutboxCreationTimestamp(
        expectedOutboxRevision: state.outboxRevision
      )
      guard creationCursor.matchesRevision else { continue }
      var pendingMutation: PendingMutation
      if var existingDraft = mutation {
        if createdAt == nil {
          existingDraft.createdAt = Self.monotonicOutboxTimestamp(
            existingDraft.createdAt,
            after: creationCursor.timestamp
          )
          mutation = existingDraft
        }
        pendingMutation = existingDraft
      } else {
        let newMutation = PendingMutation(
          id: transaction.id,
          createdAt: createdAt
            ?? Self.monotonicOutboxTimestamp(
              configuration.now(),
              after: creationCursor.timestamp
            ),
          transaction: transaction
        )
        mutation = newMutation
        pendingMutation = newMutation
      }
      let immediateTail: InstantOutboxImmediateTailLoad
      if OutboxSameEntitySupersession.isEligibleImmediateTailNewcomer(
        pendingMutation,
        attributes: state.snapshot.store.attributes
      ) {
        immediateTail = try await persistence.loadImmediateSupersessionTail(
          expectedStoreRevision: state.storeRevision,
          expectedOutboxRevision: state.outboxRevision
        )
        guard immediateTail.matchesRevisions else { continue }
      } else {
        // The final save still compares both revisions atomically. Skipping
        // this read is safe and keeps partial/reference writes off the tail
        // body path entirely.
        immediateTail = InstantOutboxImmediateTailLoad(
          matchesRevisions: true,
          mutation: nil
        )
      }
      recordActorHop(.store)
      // `loadCompactStateSynchronizingStore` installs every SQLite-source snapshot, including an
      // authoritative empty one. The hot indexes are therefore the single preparation source for
      // both cache hits and cross-runtime revision changes.
      let supersededTail: PendingMutation? = immediateTail.mutation.flatMap { predecessor in
        guard predecessor.rollbackTransaction != nil,
          OutboxSameEntitySupersession.canReplaceImmediateTail(
            predecessor,
            with: pendingMutation,
            attributes: state.snapshot.store.attributes
          )
        else { return nil }
        return predecessor
      }
      let deferredTriples = try await deferredValuesForPreparing(transaction)
      let prepared: PreparedStoreMutation
      if let supersededTail, let rollback = supersededTail.rollbackTransaction {
        // The current store includes the predecessor overlay. Peel exactly that
        // layer and apply the newcomer on the pre-predecessor baseline. The
        // generated newcomer rollback therefore restores authoritative state
        // directly, regardless of how many earlier ids alias this survivor.
        prepared = try await store.prepare(
          peelingOverlays: [rollback],
          thenApplying: transaction,
          hydratingDeferredValues: deferredTriples
        )
      } else {
        prepared = try await store.prepareCurrent(
          transaction,
          hydratingDeferredValues: deferredTriples
        )
      }
      pendingMutation.rollbackTransaction = Self.rollbackTransaction(
        mutationID: pendingMutation.id,
        prepared: prepared
      )
      mutation = pendingMutation
      try InstantAutomaticOutboxAdmission.validateNewMutation(pendingMutation)
      if let supersededTail {
        await configuration.onLocalMutationSupersessionPreparedForTesting?(
          supersededTail.id,
          pendingMutation.id
        )
      }
      recordActorHop(.persistence)
      let didSave = try await persistence.saveLocalMutation(
        changedEntityTriples: prepared.changedEntityTriples,
        pendingMutation: pendingMutation,
        supersedingImmediateTail: supersededTail,
        expectedStoreRevision: state.storeRevision,
        expectedAttributeRevision: state.attributeRevision,
        expectedOutboxRevision: state.outboxRevision
      )
      if didSave {
        await configuration.onLocalMutationPersistedBeforeStorePublicationForTesting?(
          transaction.id
        )
        recordActorHop(.store)
        let committed = await store.commitAndPublish(prepared)
        installedStoreRevisions.install(
          storeRevision: state.storeRevision + 1,
          attributeRevision: state.attributeRevision
        )
        _ = try? await publishConnectionStatusWithGateHeld()
        return committed.result
      }
    }

    throw transactionChangedDuringPersistence(id: transaction.id)
  }

  private func deferredValuesForPreparing(
    _ transaction: InstantStoreTransaction
  ) async throws -> [InstantTriple] {
    try await deferredValuesForPreparing([transaction])
  }

  private func deferredValuesForPreparing(
    _ transactions: [InstantStoreTransaction]
  ) async throws -> [InstantTriple] {
    // Upstream applies deep merges and optimistic rebases against one complete store. Load only
    // the entities these transactions can touch into the throwaway prepared indexes; commit strips
    // the configured payload attributes before installing the next hot store.
    let policy = configuration.deferredValueResidency
    guard policy.isEnabled, !transactions.isEmpty else { return [] }
    recordActorHop(.store)
    var entityIDs: Set<String> = []
    for transaction in transactions {
      entityIDs.formUnion(policy.directEntityIDs(in: transaction))
      entityIDs.formUnion(try await store.resolvedMutationEntityIDs(in: transaction))
      if policy.requiresEntityDiscovery(in: transaction),
        let preview = try? await store.prepareCurrent(transaction)
      {
        entityIDs.formUnion(preview.result.changedEntityIDs)
      }
    }
    guard !entityIDs.isEmpty else { return [] }
    recordActorHop(.persistence)
    return try await persistence.loadDeferredValues(
      attributeIDs: policy.attributeIDs,
      entityIDs: entityIDs
    )
  }

  private static func monotonicOutboxTimestamp(
    _ requested: InstantTimestamp,
    after mutations: [PendingMutation]
  ) -> InstantTimestamp {
    guard
      let latest = mutations.map(\.createdAt).max(),
      requested <= latest,
      latest.milliseconds < Int64.max
    else { return requested }
    return InstantTimestamp(milliseconds: latest.milliseconds + 1)
  }

  private static func monotonicOutboxTimestamp(
    _ requested: InstantTimestamp,
    after latest: InstantTimestamp?
  ) -> InstantTimestamp {
    guard let latest, requested <= latest, latest.milliseconds < Int64.max else {
      return requested
    }
    return InstantTimestamp(milliseconds: latest.milliseconds + 1)
  }

  /// A replayed pending mutation may have newer internal write timestamps than the caller's
  /// original transaction. Those timestamps keep the durable body aligned with its optimistic
  /// overlay, but they are not part of the transaction's server-visible intent.
  private static func hasSameWireIntent(
    _ existingMutation: PendingMutation,
    _ transaction: InstantStoreTransaction
  ) -> Bool {
    guard existingMutation.transaction.id == transaction.id else { return false }
    let existing = InstantTransportMutation(existingMutation)
    let replay = InstantTransportMutation(
      PendingMutation(
        id: transaction.id,
        createdAt: existingMutation.createdAt,
        transaction: transaction
      )
    )
    return existing.preconditions == replay.preconditions
      && existing.txSteps == replay.txSteps
  }

  /// Keep the durable transaction and its replayed overlay on the same logical timestamp.
  /// Delivery compares these timestamps to suppress genuinely stale writes; rebasing only the
  /// overlay makes the mutation suppress its own wire operations after a refresh or rejection.
  private static func rebaseDurableTransaction(
    in mutation: inout PendingMutation,
    at timestamp: InstantTimestamp
  ) -> [InstantTripleOperation] {
    mutation.transaction.operations = mutation.transaction.operations.map {
      $0.rebased(at: timestamp)
    }
    return mutation.transaction.operations.filter(\.isRebasedLocalWrite)
  }

  /// Upstream Instant keeps server query stores separate and reapplies pending mutations as an
  /// optimistic overlay (`Reactor.dataForQuery` / `_applyOptimisticUpdates`). Swift persists one
  /// materialized store, so it records the exact inverse of this optimistic layer instead.
  static func rollbackTransaction(
    mutationID: String,
    prepared: PreparedStoreMutation
  ) -> InstantStoreTransaction? {
    let changedEntityTriples = prepared.changedEntityTriples
    var operations: [InstantTripleOperation] = []
    for entityID in prepared.result.changedEntityIDs.sorted() {
      let before = prepared.previousChangedEntityTriples[entityID, default: []]
      let after = changedEntityTriples[entityID, default: []]
      // Pure create: one deleteEntity replaces N retract triples (publishGate seed
      // outbox floor — autoresearch #044). Semantics: remove all attrs on entity.
      if before.isEmpty, !after.isEmpty {
        operations.append(.deleteEntity(entityID))
        continue
      }
      let beforeSet = Set(before)
      let afterSet = Set(after)
      operations.append(
        contentsOf:
          after
          .filter { !beforeSet.contains($0) }
          .map(InstantTripleOperation.retract)
      )
      operations.append(
        contentsOf:
          before
          .filter { !afterSet.contains($0) }
          .map(InstantTripleOperation.insert)
      )
    }
    guard !operations.isEmpty else { return nil }
    return InstantStoreTransaction(
      id: "rollback-\(mutationID)",
      operations: operations
    )
  }

  @discardableResult
  public func applyServerTransaction(
    _ transaction: InstantStoreTransaction,
    processedTransactionID: String? = nil,
    receivedAt: InstantTimestamp? = nil
  ) async throws -> InstantServerTransactionApplicationResult {
    await enterOperationGate()
    do {
      let result = try await performApplyServerTransaction(
        transaction,
        processedTransactionID: processedTransactionID,
        receivedAt: receivedAt
      )
      await leaveOperationGate()
      return result.application
    } catch {
      await leaveOperationGate()
      throw error
    }
  }

  private func performApplyServerTransaction(
    _ transaction: InstantStoreTransaction,
    processedTransactionID: String?,
    receivedAt: InstantTimestamp?,
    confirmingMutationID: String? = nil,
    mergingAttributes attributesToMerge: [InstantAttribute] = [],
    liveQueryResultReplacements: [InstantLiveQueryResultReplacement] = []
  ) async throws -> InstantAppliedServerTransaction {
    let processedTransactionID = (processedTransactionID ?? transaction.id)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !processedTransactionID.isEmpty else {
      throw validationFailed(
        operation: "apply server transaction",
        message: "Processed transaction id must not be empty.",
        recovery: "Pass the Instant transaction id that has been fully received from the server."
      )
    }
    let transactionID = transaction.id.trimmingCharacters(in: .whitespacesAndNewlines)
    var baseAuthoritativeTransaction = transaction
    baseAuthoritativeTransaction.id = transactionID.isEmpty
      ? processedTransactionID
      : transactionID
    let metadataUpdatedAt = receivedAt ?? configuration.now()
    let confirmingMutationID = confirmingMutationID?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .nilIfEmpty
    let persistedLiveQueryResults = liveQueryResultReplacements.map {
      InstantPersistedLiveQueryResult(replacement: $0, updatedAt: metadataUpdatedAt)
    }

    applyAttempts: for _ in 0..<5 {
      recordActorHop(.persistence)
      let compactState = try await loadCompactStateSynchronizingStore()
      var authoritativeTransaction = baseAuthoritativeTransaction
      if !liveQueryResultReplacements.isEmpty {
        recordActorHop(.persistence)
        guard let retractions = try await persistence.liveQueryReplacementRetractions(
          for: liveQueryResultReplacements,
          expectedQueryResultRevision: compactState.queryResultRevision
        ) else { continue applyAttempts }
        guard let protectedRetractions = try await persistence.protectingServerRetractions(
          retractions,
          expectedOutboxRevision: compactState.outboxRevision
        ) else { continue applyAttempts }
        authoritativeTransaction.operations.insert(contentsOf: protectedRetractions, at: 0)
      }
      let footprint = Self.serverApplyFootprint(
        operations: authoritativeTransaction.operations
      )
      let changedMergedAttributes: [InstantAttribute]
      if attributesToMerge.isEmpty {
        changedMergedAttributes = []
      } else {
        let currentAttributes = compactState.snapshot.store.attributes
        let previousAttributes = Dictionary(
          uniqueKeysWithValues: currentAttributes.map { ($0.id, $0) }
        )
        var mergedAttributeStore = AttributeStore(attributes: currentAttributes)
        mergedAttributeStore.merge(attributesToMerge)
        changedMergedAttributes = mergedAttributeStore.attributes.filter {
          previousAttributes[$0.id] != $0
        }
      }
      let mergedAttributeCount = changedMergedAttributes.count
      let planID = "server-apply-\(configuration.makeID())"
      let plan: InstantServerApplyPlan
      normalization: while true {
        let load = try await persistence.beginServerApplyPlan(
          id: planID,
          footprint: footprint,
          hasServerOperations: !authoritativeTransaction.operations.isEmpty,
          processedTransactionID: processedTransactionID,
          confirmingMutationID: confirmingMutationID
        )
        switch load {
        case let .ready(readyPlan):
          plan = readyPlan
          break normalization

        case let .normalizationRequired(firstMutationID):
          let normalized = try await persistence.normalizeOptimisticEffectMetadata(
            startingAtMutationID: firstMutationID
          )
          if !normalized.normalizedMutationIDs.isEmpty { continue normalization }
          if normalized.blockedMutationID == firstMutationID,
            try await persistence.isolateLegacyFailedUnknownServerApplyMutation(
              id: firstMutationID
            )
          {
            continue normalization
          }
          let error = unknownOptimisticOverlayState(
            id: normalized.blockedMutationID ?? firstMutationID,
            operation: "apply server transaction"
          )
          reportIssue("\(error)")
          throw error
        }
      }
      guard
        plan.expectedStoreRevision == compactState.storeRevision,
        plan.expectedAttributeRevision == compactState.attributeRevision,
        plan.expectedOutboxRevision == compactState.outboxRevision,
        plan.expectedQueryResultRevision == compactState.queryResultRevision
      else {
        try? await persistence.finishServerApplyPlan(id: plan.id)
        continue applyAttempts
      }

      do {
        // Upstream Reactor rebuilds a server store and then applies optimistic
        // mutations in creation order. Swift's one-store representation first
        // peels only the indexed connected components in reverse order. The
        // durable bodies are copied to SQLite temp staging one bounded page at
        // a time; no component-sized Swift array exists.
        recordActorHop(.store)
        var prepared = try await store.prepare(
          peelingOverlays: [],
          thenApplying: InstantStoreTransaction(
            id: "\(authoritativeTransaction.id)-bounded-base",
            operations: []
          ),
          mergingAttributes: attributesToMerge
        )
        var changedEntityIDs: Set<String> = []
        var reversePosition: InstantOutboxDeliveryPosition?
        var stalePlan = false
        while true {
          recordActorHop(.persistence)
          let page = try await persistence.loadServerApplyBodyPage(
            planID: plan.id,
            direction: .reverse,
            after: reversePosition
          )
          if page.isStale {
            stalePlan = true
            break
          }
          guard !page.entries.isEmpty else { break }
          for entry in page.entries where entry.isComponentBody {
            let mutation = entry.mutation
            guard mutation.optimisticOverlayState != .removed else { continue }
            guard let rollback = mutation.rollbackTransaction else {
              let effect = InstantOptimisticEffectFootprint.normalized(for: mutation)
              guard effect?.entityIDs.isEmpty == true, effect?.isGlobal == false else {
                throw InstantError(
                  code: .persistenceFailed,
                  operation: "apply server transaction",
                  localID: mutation.id,
                  message:
                    "Active optimistic mutation '\(mutation.id)' has no durable rollback.",
                  recovery:
                    "Preserve the row and run an authoritative recovery instead of guessing its inverse."
                )
              }
              continue
            }
            prepared = try await hydrateDeferredValuesForServerApply(
              [rollback],
              over: prepared,
              planID: plan.id
            )
            let peeled = try await store.prepare(rollback, applyingTo: prepared)
            changedEntityIDs.formUnion(peeled.result.changedEntityIDs)
            prepared = peeled
          }
          reversePosition = page.nextPosition
        }
        if stalePlan {
          try? await persistence.finishServerApplyPlan(id: plan.id)
          continue applyAttempts
        }

        var authoritativeCoverage: InstantAuthoritativeWriteCoverage?
        if !authoritativeTransaction.operations.isEmpty {
          prepared = try await hydrateDeferredValuesForServerApply(
            [authoritativeTransaction],
            over: prepared,
            planID: plan.id
          )
          let appliedServer = try await store.prepare(
            authoritativeTransaction,
            applyingTo: prepared
          )
          changedEntityIDs.formUnion(appliedServer.result.changedEntityIDs)
          authoritativeCoverage = InstantAuthoritativeWriteCoverage(
            operations: authoritativeTransaction.operations,
            attributes: appliedServer.attributes,
            previousChangedEntityTriples: appliedServer.previousChangedEntityTriples,
            changedEntityTriples: appliedServer.changedEntityTriples
          )
          prepared = appliedServer
        }

        var confirmedMutation: PendingMutation?
        var forwardPosition: InstantOutboxDeliveryPosition?
        while true {
          recordActorHop(.persistence)
          let page = try await persistence.loadServerApplyBodyPage(
            planID: plan.id,
            direction: .forward,
            after: forwardPosition
          )
          if page.isStale {
            stalePlan = true
            break
          }
          guard !page.entries.isEmpty else { break }
          var dispositions: [InstantServerApplyStagedDisposition] = []
          dispositions.reserveCapacity(page.entries.count)
          for entry in page.entries {
            var mutation = entry.mutation
            if entry.shouldPruneAtWatermark {
              dispositions.append(.remove(mutationID: mutation.id))
              continue
            }
            if entry.shouldConfirm {
              mutation.status = .confirmed
              mutation.failureMessage = nil
              mutation.failure = nil
              mutation.confirmationSource = .manual
              confirmedMutation = mutation
            }
            guard entry.isComponentBody else {
              dispositions.append(.update(mutation))
              continue
            }
            if mutation.status == .failed {
              mutation.rollbackTransaction = nil
              mutation.optimisticOverlayState = .removed
              dispositions.append(.update(mutation))
              continue
            }
            if mutation.status == .confirmed,
              mutation.confirmationSource == .serverTransport,
              mutation.serverTransactionID == nil,
              authoritativeCoverage?.covers(mutation.transaction.operations) == true
            {
              dispositions.append(.remove(mutationID: mutation.id))
              continue
            }

            let newestServerTimestamp =
              prepared.indexes.newestTransactionTimeMilliseconds ?? 0
            let optimisticTimestamp = InstantTimestamp(
              milliseconds: newestServerTimestamp == Int64.max
                ? newestServerTimestamp
                : newestServerTimestamp + 1
            )
            let operations = Self.rebaseDurableTransaction(
              in: &mutation,
              at: optimisticTimestamp
            )
            mutation.rollbackTransaction = nil
            mutation.optimisticOverlayState = .applied
            if !operations.isEmpty {
              let replayTransaction = InstantStoreTransaction(
                id: mutation.transaction.id,
                operations: operations
              )
              prepared = try await hydrateDeferredValuesForServerApply(
                [replayTransaction],
                over: prepared,
                planID: plan.id
              )
              let replay = try await store.prepare(
                replayTransaction,
                applyingTo: prepared
              )
              changedEntityIDs.formUnion(replay.result.changedEntityIDs)
              mutation.rollbackTransaction = Self.rollbackTransaction(
                mutationID: mutation.id,
                prepared: replay
              )
              prepared = replay
            }
            dispositions.append(.update(mutation))
          }
          try await persistence.stageServerApplyBodyPage(
            planID: plan.id,
            dispositions: dispositions
          )
          forwardPosition = page.nextPosition
        }
        if stalePlan {
          try? await persistence.finishServerApplyPlan(id: plan.id)
          continue applyAttempts
        }

        let preparedForCommit = PreparedStoreMutation(
          result: InstantStoreMutationResult(
            transactionID: authoritativeTransaction.id,
            changedEntityIDs: changedEntityIDs,
            tripleCount: prepared.indexes.tripleCount,
            emissions: []
          ),
          sequence: prepared.sequence,
          attributes: prepared.attributes,
          indexes: prepared.indexes
        )
        await configuration.onServerApplyPreparedBeforeCommitForTesting?(plan.id)
        recordActorHop(.persistence)
        guard let commit = try await persistence.commitServerApplyPlan(
          planID: plan.id,
          changedEntityTriples: preparedForCommit.changedEntityTriples,
          mergingAttributes: changedMergedAttributes,
          queryResults: persistedLiveQueryResults,
          storeChanged: !authoritativeTransaction.operations.isEmpty || mergedAttributeCount > 0,
          metadataKey: processedTransactionIDMetadataKey,
          metadataValue: processedTransactionID,
          metadataUpdatedAt: metadataUpdatedAt
        ) else {
          try? await persistence.finishServerApplyPlan(id: plan.id)
          continue applyAttempts
        }

        recordActorHop(.store)
        let changesMaterializedStore =
          !authoritativeTransaction.operations.isEmpty || mergedAttributeCount > 0
        let committedResult: InstantStoreMutationResult
        if changesMaterializedStore {
          await store.installLiveQueryPageInfo(
            liveQueryResultReplacements,
            publishing: false
          )
          committedResult = await store.commitAndPublish(preparedForCommit).result
          installedStoreRevisions.install(
            storeRevision: commit.expectedStoreRevision + (commit.didChangeStore ? 1 : 0),
            attributeRevision: commit.expectedAttributeRevision
              + (commit.didChangeAttributes ? 1 : 0)
          )
        } else {
          await store.installLiveQueryPageInfo(
            liveQueryResultReplacements,
            publishing: true
          )
          committedResult = preparedForCommit.result
        }

        var patchPosition: InstantOutboxDeliveryPosition?
        while true {
          recordActorHop(.persistence)
          let patch = try await persistence.loadServerApplyResidentPatchPage(
            planID: plan.id,
            after: patchPosition
          )
          guard !patch.removedMutationIDs.isEmpty || !patch.replacementMutations.isEmpty
          else { break }
          recordActorHop(.outbox)
          for mutationID in patch.removedMutationIDs {
            await outbox.remove(id: mutationID)
          }
          for mutation in patch.replacementMutations {
            await outbox.replaceIfPresent(mutation)
          }
          patchPosition = patch.nextPosition
        }
        try await persistence.finishServerApplyPlan(id: plan.id)
        _ = try? await publishConnectionStatusWithGateHeld(
          pendingMutationCount: commit.pendingMutationCount
        )
        if let confirmedMutation {
          await publishMutationLifecycle(confirmedMutation)
        }
        let application = InstantServerTransactionApplicationResult(
          mutation: committedResult,
          syncState: InstantSyncState(processedTransactionID: processedTransactionID),
          pendingMutationCount: commit.pendingMutationCount
        )
        return InstantAppliedServerTransaction(
          transaction: authoritativeTransaction,
          application: application,
          confirmedMutation: confirmedMutation,
          mergedAttributeCount: mergedAttributeCount
        )
      } catch {
        try? await persistence.finishServerApplyPlan(id: plan.id)
        throw error
      }
    }

    throw serverTransactionChangedDuringPersistence(id: processedTransactionID)
  }

  private static func serverApplyFootprint(
    operations: [InstantTripleOperation]
  ) -> InstantServerApplyFootprint {
    var entityIDs: Set<String> = []
    var isGlobal = false
    for operation in operations {
      switch operation {
      case let .merge(triple), let .insert(triple), let .retract(triple):
        entityIDs.insert(triple.entityID)
        switch triple.value {
        case let .ref(targetEntityID):
          entityIDs.insert(targetEntityID)
        case .lookupRef:
          isGlobal = true
        case .null, .string, .number, .bool, .date, .json:
          break
        }

      case let .deleteEntity(entityID), let .deleteEntityInNamespace(entityID, _),
        let .requireEntityMissing(entityID, _), let .requireEntityExists(entityID, _):
        entityIDs.insert(entityID)

      case let .requireTripleExists(entityID, _, value):
        entityIDs.insert(entityID)
        if case let .ref(targetEntityID) = value {
          entityIDs.insert(targetEntityID)
        } else if case .lookupRef = value {
          isGlobal = true
        }

      case .mergeByLookup, .insertByLookup, .retractByLookup,
        .deleteEntityByLookup, .requireEntityMissingByLookup,
        .requireEntityExistsByLookup, .ruleParams, .ruleParamsByLookup:
        isGlobal = true
      }
    }
    return InstantServerApplyFootprint(entityIDs: entityIDs, isGlobal: isGlobal)
  }

  private func hydrateDeferredValuesForServerApply(
    _ transactions: [InstantStoreTransaction],
    over prepared: PreparedStoreMutation,
    planID: String
  ) async throws -> PreparedStoreMutation {
    let policy = configuration.deferredValueResidency
    guard policy.isEnabled, !transactions.isEmpty else { return prepared }
    var entityIDs: Set<String> = []
    for transaction in transactions {
      entityIDs.formUnion(policy.directEntityIDs(in: transaction))
      for operation in transaction.operations {
        for lookup in Self.serverApplyLookupRefs(in: operation) {
          guard let lookupAttribute = prepared.attributes.lookupAttribute(id: lookup.attributeID)
          else { continue }
          entityIDs.formUnion(
            prepared.indexes.entityIDs(
              matching: lookup,
              lookupAttribute: lookupAttribute
            )
          )
        }
      }
      if policy.requiresEntityDiscovery(in: transaction) {
        let preview = try await store.prepare(transaction, applyingTo: prepared)
        entityIDs.formUnion(preview.result.changedEntityIDs)
      }
    }
    guard !entityIDs.isEmpty else { return prepared }
    recordActorHop(.persistence)
    let deferredTriples = try await persistence.loadDeferredValues(
      attributeIDs: policy.attributeIDs,
      entityIDs: entityIDs
    )
    guard !deferredTriples.isEmpty else { return prepared }
    recordActorHop(.store)
    return try await store.prepare(
      InstantStoreTransaction(
        id: "\(planID)-deferred-hydration",
        operations: deferredTriples.map(InstantTripleOperation.insert)
      ),
      applyingTo: prepared
    )
  }

  private static func serverApplyLookupRefs(
    in operation: InstantTripleOperation
  ) -> [InstantLookupRef] {
    switch operation {
    case let .mergeByLookup(entity, _, value, _, _),
      let .insertByLookup(entity, _, value, _, _),
      let .retractByLookup(entity, _, value, _, _):
      var lookups = [entity]
      if case let .lookupRef(valueLookup) = value { lookups.append(valueLookup) }
      return lookups
    case let .deleteEntityByLookup(entity),
      let .requireEntityMissingByLookup(entity, _),
      let .requireEntityExistsByLookup(entity, _),
      let .ruleParamsByLookup(entity, _, _):
      return [entity]
    case let .merge(triple), let .insert(triple), let .retract(triple):
      if case let .lookupRef(lookup) = triple.value { return [lookup] }
      return []
    case let .requireTripleExists(_, _, value):
      if case let .lookupRef(lookup) = value { return [lookup] }
      return []
    case .requireEntityMissing, .requireEntityExists,
      .deleteEntity, .deleteEntityInNamespace, .ruleParams:
      return []
    }
  }

  @discardableResult
  public func applyLiveRefresh(
    _ refreshOK: InstantLiveRefreshOK,
    receivedAt: InstantTimestamp? = nil
  ) async throws -> InstantLiveRefreshApplicationResult {
    let receivedAt = receivedAt ?? configuration.now()
    await enterOperationGate()
    do {
      recordActorHop(.persistence)
      let state = try await loadCompactStateSynchronizingStore()
      let translated = try InstantLiveRefreshTranslator.translate(
        refreshOK,
        existingAttributes: state.snapshot.store.attributes,
        receivedAt: receivedAt
      )
      let applied = try await performApplyServerTransaction(
        translated.transaction,
        processedTransactionID: translated.processedTransactionID,
        receivedAt: receivedAt,
        confirmingMutationID: translated.confirmationMutationID,
        mergingAttributes: translated.attributesToMerge,
        liveQueryResultReplacements: translated.queryResultReplacements
      )
      await liveQueryResultState.record(translated.queryResultReplacements)
      if !translated.queryResultReplacements.isEmpty,
        liveQueryResultPruningCadence.shouldPrune(
          afterSuccessfulWriteWithInterval: configuration.liveQueryResultPruningWriteInterval
        )
      {
        do {
          _ = try await performPruneLiveQueryResults(
            policy: configuration.liveQueryResultPruningPolicy,
            now: configuration.now()
          )
        } catch {
          InstantDiagnostics.shared.record(
            error: error,
            subsystem: "instant-swift-data-core",
            category: "query",
            event: "live-query-results.prune-failed",
            message: "Could not prune unloaded persisted live query results."
          )
        }
      }

      await leaveOperationGate()
      return InstantLiveRefreshApplicationResult(
        transaction: applied.transaction,
        application: applied.application,
        confirmedMutation: applied.confirmedMutation,
        insertedTripleCount: translated.transaction.operations.count,
        mergedAttributeCount: applied.mergedAttributeCount
      )
    } catch {
      await leaveOperationGate()
      throw error
    }
  }

  @discardableResult
  public func confirmMutationIfPresent(id: String) async throws -> PendingMutation? {
    await enterOperationGate()
    do {
      let result = try await performConfirmMutationIfPresent(id: id)
      await leaveOperationGate()
      InstantDiagnostics.shared.record(
        result.mutation == nil ? .debug : .notice,
        subsystem: "instant-swift-data-core",
        category: "mutation",
        event: result.mutation == nil
          ? "transaction.confirmation-not-found"
          : "transaction.local-confirmed",
        message: result.mutation == nil
          ? "A caller's local confirmation did not match an outbox mutation."
          : "A caller locally confirmed an outbox mutation without server-acceptance proof.",
        metadata: ["pendingMutationCount": String(result.pendingMutationCount)],
        correlationID: id
      )
      return result.mutation
    } catch {
      await leaveOperationGate()
      InstantDiagnostics.shared.record(
        error: error,
        subsystem: "instant-swift-data-core",
        category: "mutation",
        event: "transaction.confirmation-failed",
        message: "Failed to apply a local outbox confirmation.",
        correlationID: id
      )
      throw error
    }
  }

  package func acceptMutationIfPresent(
    id: String,
    serverTransactionID: String
  ) async throws -> PendingMutation? {
    await enterOperationGate()
    do {
      let result = try await performAcceptMutationIfPresent(
        id: id,
        serverTransactionID: serverTransactionID
      )
      await scheduleLiveMutationDeadlineWake(
        at: result.nextClaimDeadlineMilliseconds
      )
      await leaveOperationGate()
      let diagnosticLevel: InstantDiagnosticLevel
      let diagnosticEvent: String
      let diagnosticMessage: String
      if result.mutation == nil {
        diagnosticLevel = .debug
        diagnosticEvent = "transaction.acceptance-not-found"
        diagnosticMessage = "Server acceptance did not match a local outbox mutation."
      } else if result.didChange {
        diagnosticLevel = .notice
        diagnosticEvent = "transaction.server-accepted"
        diagnosticMessage = "Instant accepted an outbox mutation and retained its optimistic overlay until the server watermark catches up."
      } else {
        diagnosticLevel = .debug
        diagnosticEvent = "transaction.acceptance-already-recorded"
        diagnosticMessage = "Instant ignored a duplicate server acceptance after the first server transaction proof was recorded."
      }
      InstantDiagnostics.shared.record(
        diagnosticLevel,
        subsystem: "instant-swift-data-core",
        category: "mutation",
        event: diagnosticEvent,
        message: diagnosticMessage,
        metadata: [
          "recordedServerTransactionID": result.mutation?.serverTransactionID ?? "none",
          "pendingMutationCount": String(result.pendingMutationCount),
          "receivedServerTransactionID": serverTransactionID,
        ],
        correlationID: id
      )
      return result.mutation
    } catch {
      await leaveOperationGate()
      InstantDiagnostics.shared.record(
        error: error,
        subsystem: "instant-swift-data-core",
        category: "mutation",
        event: "transaction.acceptance-failed",
        message: "Failed to retain an accepted Instant mutation until its server watermark.",
        correlationID: id
      )
      throw error
    }
  }

  private func performAcceptMutationIfPresent(
    id: String,
    serverTransactionID: String
  ) async throws -> (
    mutation: PendingMutation?,
    pendingMutationCount: Int,
    didChange: Bool,
    nextClaimDeadlineMilliseconds: Int64?
  ) {
    for _ in 0..<5 {
      recordActorHop(.persistence)
      let outboxRevision = try await persistence.currentOutboxRevision()
      guard let acceptance = try await persistence.acceptOutboxMutation(
        id: id,
        serverTransactionID: serverTransactionID,
        expectedOutboxRevision: outboxRevision
      ) else { continue }
      guard let mutation = acceptance.mutation else {
        recordActorHop(.outbox)
        await outbox.remove(id: id)
        return (
          mutation: nil,
          pendingMutationCount: acceptance.pendingMutationCount,
          didChange: false,
          nextClaimDeadlineMilliseconds: acceptance.nextClaimDeadlineMilliseconds
        )
      }
      if acceptance.didChange {
        _ = try? await publishConnectionStatusWithGateHeld(
          pendingMutationCount: acceptance.pendingMutationCount
        )
        await publishMutationLifecycle(mutation)
      }
      recordActorHop(.outbox)
      await outbox.remove(id: mutation.id)
      return (
        mutation: mutation,
        pendingMutationCount: acceptance.pendingMutationCount,
        didChange: acceptance.didChange,
        nextClaimDeadlineMilliseconds: acceptance.nextClaimDeadlineMilliseconds
      )
    }

    throw outboxChangedDuringStatusUpdate(id: id)
  }

  private func performConfirmMutationIfPresent(
    id: String
  ) async throws -> (mutation: PendingMutation?, pendingMutationCount: Int) {
    for _ in 0..<5 {
      recordActorHop(.persistence)
      let outboxRevision = try await persistence.currentOutboxRevision()
      guard let confirmation = try await persistence.confirmOutboxMutationIfPresent(
        id: id,
        expectedOutboxRevision: outboxRevision
      ) else { continue }
      guard let mutation = confirmation.mutation else {
        await outbox.remove(id: id)
        return (nil, confirmation.pendingMutationCount)
      }
      recordActorHop(.outbox)
      await outbox.remove(id: mutation.id)
      _ = try? await publishConnectionStatusWithGateHeld(
        pendingMutationCount: confirmation.pendingMutationCount
      )
      await publishMutationLifecycle(mutation)
      return (mutation, confirmation.pendingMutationCount)
    }

    throw outboxChangedDuringStatusUpdate(id: id)
  }

  private func mergeLiveRefreshAttributes(
    _ attributes: [InstantAttribute],
    into snapshot: inout InstantStoreSnapshot
  ) -> Int {
    guard !attributes.isEmpty else { return 0 }
    let previousAttributes = Dictionary(
      uniqueKeysWithValues: snapshot.attributes.map { ($0.id, $0) }
    )
    var attributeStore = AttributeStore(attributes: snapshot.attributes)
    attributeStore.merge(attributes)
    snapshot.attributes = attributeStore.attributes
    return snapshot.attributes.filter { previousAttributes[$0.id] != $0 }.count
  }

  /// The attributes this device holds durably, as opposed to the ones a live session happens to
  /// be holding in memory.
  package func persistedStoreAttributes() async throws -> [InstantAttribute] {
    await enterOperationGate()
    do {
      recordActorHop(.persistence)
      let attributes = try await loadCompactStateSynchronizingStore().snapshot.store.attributes
      await leaveOperationGate()
      return attributes
    } catch {
      await leaveOperationGate()
      throw error
    }
  }

  /// Writes the server's attribute set into the local cache.
  ///
  /// Instant models attributes as data: a device can only materialize namespaces it holds
  /// attributes for, and query observation refuses to subscribe to a namespace it cannot
  /// validate. A device that keeps the server's attribute set in memory only therefore goes
  /// permanently blind to every namespace added to the schema after its last sync — it never
  /// subscribes, so it never receives the payload that would have taught it the namespace.
  ///
  /// Upstream applies the set on every `init-ok`
  /// (`upstream/instant/client/packages/core/src/Reactor.js` line 640, `this._setAttrs(msg.attrs)`).
  /// Upstream replaces its whole in-memory attr store there and keeps locally minted attributes
  /// separately in `optimisticAttrs()`; this client persists a single attribute set, so it
  /// merges instead — a namespace/name pair the device already holds keeps its local attribute
  /// id, because local triples and pending mutations reference that id.
  ///
  /// The caller must already hold the operation gate.
  @discardableResult
  private func applyServerAttributesWithGateHeld(
    _ serverAttributes: [InstantLiveJSONValue]
  ) async throws -> Int {
    guard !serverAttributes.isEmpty else { return 0 }
    for _ in 0..<5 {
      recordActorHop(.persistence)
      let state = try await loadCompactStateSynchronizingStore()
      let attributesToMerge = try InstantLiveRefreshTranslator.attributesToMerge(
        serverAttributes: serverAttributes,
        existingAttributes: state.snapshot.store.attributes
      )
      guard !attributesToMerge.isEmpty else { return 0 }
      var storeSnapshot = await authoritativeStoreSnapshot(from: state)
      let previousStoreSnapshot = storeSnapshot
      let mergedCount = mergeLiveRefreshAttributes(attributesToMerge, into: &storeSnapshot)
      guard mergedCount > 0 else { return 0 }
      recordActorHop(.persistence)
      let didSave = try await persistence.saveStoreSnapshot(
        storeSnapshot,
        replacing: previousStoreSnapshot,
        expectedStoreRevision: state.storeRevision,
        expectedOutboxRevision: state.outboxRevision,
        expectedAttributeRevision: state.attributeRevision
      )
      if didSave {
        // Merge into the live store rather than replacing its snapshot: the persisted triples
        // are the ones this loop read, and the in-memory store may already carry newer
        // optimistic ones.
        recordActorHop(.store)
        _ = await store.mergeAttributesIfChanged(attributesToMerge)
        installedStoreRevisions.install(
          storeRevision: state.storeRevision,
          attributeRevision: state.attributeRevision + 1
        )
        InstantDiagnostics.shared.record(
          .notice,
          subsystem: "instant-swift-data-core",
          category: "connection",
          event: "connection.server-attributes-applied",
          message: "Stored attributes the server sent for namespaces this device did not have.",
          metadata: [
            "appID": configuration.appID,
            "mergedAttributeCount": String(mergedCount),
            "serverAttributeCount": String(serverAttributes.count),
            "namespaces": Set(attributesToMerge.map(\.namespace)).sorted()
              .joined(separator: ","),
          ]
        )
        return mergedCount
      }
      recordActorHop(.persistence)
      _ = try await loadCompactStateSynchronizingStore()
    }
    throw InstantError(
      code: .persistenceFailed,
      operation: "apply server attributes",
      message: "The local Instant cache changed repeatedly while storing the server's attributes.",
      recovery: "Retry the connection after other writers finish updating the shared cache."
    )
  }

  @discardableResult
  package func migrateLocalPersistenceSnapshot(
    name: String,
    transform: @Sendable (InstantPersistenceSnapshot) throws -> InstantPersistenceSnapshot
  ) async throws -> Bool {
    await enterOperationGate()
    do {
      for _ in 0..<5 {
        recordActorHop(.persistence)
        let state = try await persistence.loadState()
        let nextSnapshot = try transform(state.snapshot)
        if nextSnapshot == state.snapshot {
          recordActorHop(.store)
          await replaceStoreSnapshot(state.snapshot.store)
          installedStoreRevisions.install(
            storeRevision: state.storeRevision,
            attributeRevision: state.attributeRevision
          )
          recordActorHop(.outbox)
          await outbox.replace(with: state.snapshot.outbox)
          await leaveOperationGate()
          return false
        }
        recordActorHop(.persistence)
        let didSave = try await persistence.saveSnapshot(
          nextSnapshot,
          replacing: state.snapshot,
          expectedStoreRevision: state.storeRevision,
          expectedAttributeRevision: state.attributeRevision,
          expectedOutboxRevision: state.outboxRevision
        )
        if didSave {
          recordActorHop(.store)
          await replaceStoreSnapshot(nextSnapshot.store)
          installedStoreRevisions.install(
            storeRevision: state.storeRevision + 1,
            attributeRevision: state.attributeRevision + 1
          )
          recordActorHop(.outbox)
          await outbox.replace(with: nextSnapshot.outbox)
          await leaveOperationGate()
          return true
        }
      }

      throw persistenceChangedDuringMigration(name: name)
    } catch {
      await leaveOperationGate()
      throw error
    }
  }

  public func observe(
    _ plan: InstantQueryPlan,
    remotePageInfo: InstantQueryRemotePageInfo? = nil
  ) async -> AsyncStream<InstantQueryEmission> {
    await observeQueryLease(
      plan,
      remotePageInfo: remotePageInfo
    ).stream
  }

  package func observeQueryLease(
    _ plan: InstantQueryPlan,
    remotePageInfo: InstantQueryRemotePageInfo? = nil
  ) async -> InstantQueryObservationLease {
    await observe(
      plan,
      remotePageInfo: remotePageInfo,
      connectsToLiveTransport: true
    )
  }

  package func observeLocally(
    _ plan: InstantQueryPlan
  ) async -> AsyncStream<InstantQueryEmission> {
    await observeLocallyLease(plan).stream
  }

  package func observeLocallyLease(
    _ plan: InstantQueryPlan
  ) async -> InstantQueryObservationLease {
    await observe(
      plan,
      remotePageInfo: nil,
      connectsToLiveTransport: false
    )
  }

  private func observe(
    _ plan: InstantQueryPlan,
    remotePageInfo: InstantQueryRemotePageInfo?,
    connectsToLiveTransport: Bool
  ) async -> InstantQueryObservationLease {
    let cancellation = InstantAsyncCancellationOwner()
    if Task.isCancelled { cancellation.cancelBeforeSetupCompletes() }
    return await withTaskCancellationHandler {
      let observation = await prepareObservation(
        plan,
        remotePageInfo: remotePageInfo,
        connectsToLiveTransport: connectsToLiveTransport
      )
      cancellation.install(cancelAndWait: observation.cancel)
      let lease = InstantQueryObservationLease(
        stream: observation.stream,
        cancel: {
          cancellation.cancel()
          await cancellation.wait()
        }
      )
      if cancellation.completeSetup() {
        await cancellation.wait()
        return .finished()
      }
      return lease
    } onCancel: {
      cancellation.cancelBeforeSetupCompletes()
    }
  }

  private func prepareObservation(
    _ plan: InstantQueryPlan,
    remotePageInfo: InstantQueryRemotePageInfo?,
    connectsToLiveTransport: Bool
  ) async -> InstantQueryObservationLease {
    let startupStopwatch = configuration.startupTrace.started(
      "query.observe",
      metadata: ["namespace": plan.namespace]
    )
    InstantDiagnostics.shared.record(
      .info,
      subsystem: "instant-swift-data-core",
      category: "query",
      event: "query-observation.started",
      message: "Started observing an Instant query.",
      metadata: [
        "appID": configuration.appID,
        "namespace": plan.namespace,
        "transport": connectsToLiveTransport && configuration.liveTransport != nil
          ? "websocket" : "local-cache",
      ],
      correlationID: plan.id
    )
    guard !Task.isCancelled else {
      return Self.finishedQueryObservationLease()
    }
    // Bootstrap hydrates the in-memory store once. Query declarations must not reread the whole
    // SQLite file or wait for connection/authentication work; subsequent local and remote
    // mutations update this actor-isolated store directly.
    recordActorHop(.store)
    let schemaSnapshotStopwatch = configuration.startupTrace.stopwatch()
    let attributes = await store.attributeSnapshot()
    guard !Task.isCancelled else {
      return Self.finishedQueryObservationLease()
    }
    configuration.startupTrace.completed(
      "query.schema-snapshot",
      since: schemaSnapshotStopwatch,
      metadata: ["namespace": plan.namespace]
    )
    if let issue = TripleIndexes.validate(
      plan,
      attributes: AttributeStore(attributes: attributes)
    ) {
      InstantDiagnostics.shared.record(
        .warning,
        subsystem: "instant-swift-data-core",
        category: "query",
        event: "query-observation.validation-failed",
        message: "Query observation failed schema validation and will emit no values.",
        metadata: ["namespace": plan.namespace],
        correlationID: plan.id
      )
      // A stream that stays empty forever reads exactly like a namespace with no rows, which is
      // how a device kept serving stale data for weeks without anyone noticing. Say it out loud.
      reportIssue(
        """
        Instant will emit nothing for the '\(plan.namespace)' query '\(plan.id)'.

        \(issue.message)

        \(issue.recovery)
        """
      )
      return InstantQueryObservationLease(
        stream: Self.emptyObservation(plan),
        cancel: {}
      )
    }
    let usesLiveTransport = connectsToLiveTransport && configuration.liveTransport != nil
    let liveRegistration: (query: InstantLiveJSONValue, key: String)?
    if usesLiveTransport {
      do {
        let query = try InstantLiveQueryEncoder.encode(plan)
        liveRegistration = (
          query: query,
          key: try InstantLiveQueryEncoder.registrationKey(for: query)
        )
      } catch {
        liveRegistration = nil
        await recordConnectionError(error)
        InstantDiagnostics.shared.record(
          error: error,
          subsystem: "instant-swift-data-core",
          category: "query",
          event: "query-observation.encoding-failed",
          message: "Could not encode a live query observation.",
          metadata: ["namespace": plan.namespace],
          correlationID: plan.id
        )
      }
    } else {
      liveRegistration = nil
    }

    if liveRegistration != nil {
      do {
        try await enterOperationGateUnlessCancelled(
          operation: "observe standard live query"
        )
      } catch {
        return Self.finishedQueryObservationLease()
      }
      guard !Task.isCancelled else {
        await leaveOperationGate()
        return Self.finishedQueryObservationLease()
      }
    }
    recordActorHop(.store)
    let localRegistrationStopwatch = configuration.startupTrace.stopwatch()
    let storeObservation = await store.observeQueryLease(
      plan,
      remotePageInfo: remotePageInfo,
      onCancellationStarted:
        configuration.onStandardQueryObservationCleanupStartedForTesting
    )
    configuration.startupTrace.completed(
      "query.local-registration",
      since: localRegistrationStopwatch,
      metadata: ["namespace": plan.namespace]
    )
    configuration.startupTrace.completed(
      "query.local-observer",
      since: startupStopwatch,
      metadata: ["namespace": plan.namespace]
    )
    if Task.isCancelled {
      if liveRegistration != nil {
        await leaveOperationGate()
      }
      await storeObservation.cancel()
      return Self.finishedQueryObservationLease()
    }
    guard let liveRegistration else {
      if !usesLiveTransport {
        InstantDiagnostics.shared.record(
          .debug,
          subsystem: "instant-swift-data-core",
          category: "query",
          event: "query-observation.local-registered",
          message: "Registered a local-cache query observation.",
          metadata: ["namespace": plan.namespace],
          correlationID: plan.id
        )
      }
      let localObservation = Self.liveObservationLease(storeObservation.stream) {
        await storeObservation.cancel()
      }
      let hydration = hydratingDeferredValues(
        in: localObservation.stream,
        plan: plan,
        attributes: attributes
      )
      let observation = Self.liveObservationLease(hydration.stream) {
        async let cancelHydration: Void = hydration.cancel()
        async let cancelLocalObservation: Void = localObservation.cancel()
        _ = await (cancelHydration, cancelLocalObservation)
      }
      let lease = Self.queryObservationLease(observation)
      if Task.isCancelled {
        await lease.cancel()
        return Self.finishedQueryObservationLease()
      }
      return lease
    }
    let query = liveRegistration.query
    let registrationKey = liveRegistration.key
    do {
      try await instantLiveWithTimeout(
        operation: "install standard live query local observation",
        timeoutMilliseconds: 5_000
      ) {
        try await self.configuration.onStandardQuerySetupCheckpointForTesting?(
          .localObservationInstalled
        )
        try Task.checkCancellation()
      }
      try Task.checkCancellation()
    } catch {
      await leaveOperationGate()
      await storeObservation.cancel()
      return Self.finishedQueryObservationLease()
    }
    await liveQueryResultState.retain(key: registrationKey)
    if Task.isCancelled {
      await leaveOperationGate()
      async let cancelStore: Void = storeObservation.cancel()
      async let releaseResult: Void = liveQueryResultState.release(key: registrationKey)
      _ = await (cancelStore, releaseResult)
      return Self.finishedQueryObservationLease()
    }

    let liveObservation = Self.liveObservationLease(storeObservation.stream) { [weak self] in
      await storeObservation.cancel()
      guard let self else { return }
      await self.liveQueryResultState.release(key: registrationKey)
      do {
        _ = try await self.liveSession.unregisterQuery(
          key: registrationKey,
          clientEventID: self.configuration.makeID()
        )
        InstantDiagnostics.shared.record(
          .debug,
          subsystem: "instant-swift-data-core",
          category: "query",
          event: "query-observation.live-unregistered",
          message: "Unregistered a live Instant query observation.",
          metadata: ["registrationKey": registrationKey],
          correlationID: plan.id
        )
      } catch {
        await self.recordConnectionError(error)
        InstantDiagnostics.shared.record(
          error: error,
          subsystem: "instant-swift-data-core",
          category: "query",
          event: "query-observation.unregister-failed",
          message: "Could not unregister a live Instant query observation.",
          correlationID: plan.id
        )
      }
    }

    do {
      try await liveSession.registerQuery(
        query,
        key: registrationKey,
        clientEventID: configuration.makeID()
      )
      try Task.checkCancellation()
      await leaveOperationGate()
      let isLiveSessionOpen = await liveSession.isOpen
      configuration.startupTrace.milestone(
        "query.live-registration",
        metadata: [
          "namespace": plan.namespace,
          "state": isLiveSessionOpen ? "registered" : "pending",
        ]
      )
      InstantDiagnostics.shared.record(
        isLiveSessionOpen ? .notice : .debug,
        subsystem: "instant-swift-data-core",
        category: "query",
        event: isLiveSessionOpen
          ? "query-observation.live-registered"
          : "query-observation.live-pending",
        message: isLiveSessionOpen
          ? "Registered a live Instant query observation."
          : "The live query will register automatically when the WebSocket session opens.",
        metadata: [
          "namespace": plan.namespace,
          "registrationKey": registrationKey,
          "autoConnect": String(configuration.autoConnectLiveTransport),
          "liveSessionOpen": String(isLiveSessionOpen),
        ],
        correlationID: plan.id
      )
    } catch is CancellationError {
      await leaveOperationGate()
      await liveObservation.cancel()
      return Self.finishedQueryObservationLease()
    } catch {
      await leaveOperationGate()
      await recordConnectionError(error)
      InstantDiagnostics.shared.record(
        error: error,
        subsystem: "instant-swift-data-core",
        category: "query",
        event: "query-observation.registration-failed",
        message: "Could not register a live Instant query observation.",
        metadata: ["namespace": plan.namespace],
        correlationID: plan.id
      )
    }
    if Task.isCancelled {
      await liveObservation.cancel()
      return Self.finishedQueryObservationLease()
    }
    let hydration = hydratingDeferredValues(
      in: liveObservation.stream,
      plan: plan,
      attributes: attributes
    )
    let observation = Self.liveObservationLease(hydration.stream) {
      async let cancelHydration: Void = hydration.cancel()
      async let cancelLiveObservation: Void = liveObservation.cancel()
      _ = await (cancelHydration, cancelLiveObservation)
    }
    let lease = Self.queryObservationLease(observation)
    if Task.isCancelled {
      await lease.cancel()
      return Self.finishedQueryObservationLease()
    }
    return lease
  }

  func observeLiveInfiniteQueryChunk(
    _ plan: InstantQueryPlan,
    onCancellationStarted: (@Sendable () async -> Void)? = nil,
    onDeferredValueHydrationFailure:
      (@Sendable (InstantError) async -> Void)? = nil
  ) async throws -> InstantLiveInfiniteQueryChunkObservation {
    let attributes = await store.attributeSnapshot()
    try Task.checkCancellation()
    guard configuration.liveTransport != nil else {
      let storeObservation = await store.observeInfiniteQueryLease(
        plan,
        onCancellationStarted: onCancellationStarted
      )
      let observation = Self.liveObservationLease(storeObservation.stream) {
        await storeObservation.cancel()
      }
      do {
        try Task.checkCancellation()
      } catch {
        await observation.cancel()
        throw error
      }
      return Self.liveInfiniteQueryChunkObservation(
        hydratingDeferredValues(
          in: observation.stream,
          plan: plan,
          attributes: attributes,
          onFailure: onDeferredValueHydrationFailure
        ),
        cancelUnderlyingObservation: observation.cancel
      )
    }

    let query: InstantLiveJSONValue
    let registrationKey: String
    do {
      query = try InstantLiveQueryEncoder.encode(plan)
      registrationKey = try InstantLiveQueryEncoder.registrationKey(for: query)
    } catch {
      try Task.checkCancellation()
      await recordConnectionError(error)
      try Task.checkCancellation()
      let storeObservation = await store.observeInfiniteQueryLease(
        plan,
        onCancellationStarted: onCancellationStarted
      )
      let observation = Self.liveObservationLease(storeObservation.stream) {
        await storeObservation.cancel()
      }
      do {
        try Task.checkCancellation()
      } catch {
        await observation.cancel()
        throw error
      }
      return Self.liveInfiniteQueryChunkObservation(
        hydratingDeferredValues(
          in: observation.stream,
          plan: plan,
          attributes: attributes,
          onFailure: onDeferredValueHydrationFailure
        ),
        cancelUnderlyingObservation: observation.cancel
      )
    }

    try await enterOperationGateUnlessCancelled(
      operation: "observe live infinite query chunk"
    )
    await liveQueryResultState.retain(key: registrationKey)
    let existingPageInfo: InstantQueryPageInfo?
    do {
      existingPageInfo = try await instantLiveWithTimeout(
        operation: "load live infinite query page info",
        timeoutMilliseconds: 5_000
      ) {
        await self.configuration.onLiveInfiniteQuerySetupCheckpointForTesting?(
          .beforePersistedPageInfoLoad
        )
        try Task.checkCancellation()
        return await self.liveQueryPageInfo(for: registrationKey)
      }
      try Task.checkCancellation()
    } catch {
      await leaveOperationGate()
      await liveQueryResultState.release(key: registrationKey)
      throw error
    }
    let storeObservation = await store.observeLiveQueryLease(
      plan,
      registrationKey: registrationKey,
      remotePageInfo: existingPageInfo.map(InstantQueryRemotePageInfo.ready) ?? .waiting,
      onCancellationStarted: onCancellationStarted
    )
    let liveObservation = Self.liveObservationLease(storeObservation.stream) { [weak self] in
      await storeObservation.cancel()
      guard let self else { return }
      await self.liveQueryResultState.release(key: registrationKey)
      do {
        _ = try await self.liveSession.unregisterQuery(
          key: registrationKey,
          clientEventID: self.configuration.makeID()
        )
      } catch {
        await self.recordConnectionError(error)
      }
    }
    do {
      try await instantLiveWithTimeout(
        operation: "install live infinite query local observation",
        timeoutMilliseconds: 5_000
      ) {
        await self.configuration.onLiveInfiniteQuerySetupCheckpointForTesting?(
          .localObservationInstalled
        )
        try Task.checkCancellation()
      }
      try Task.checkCancellation()
    } catch is CancellationError {
      await leaveOperationGate()
      await liveObservation.cancel()
      throw CancellationError()
    } catch {
      await leaveOperationGate()
      await liveObservation.cancel()
      throw error
    }
    do {
      try await liveSession.registerQuery(
        query,
        key: registrationKey,
        clientEventID: configuration.makeID()
      )
      try Task.checkCancellation()
      await leaveOperationGate()
    } catch is CancellationError {
      await leaveOperationGate()
      await liveObservation.cancel()
      throw CancellationError()
    } catch {
      await leaveOperationGate()
      await recordConnectionError(error)
    }
    return Self.liveInfiniteQueryChunkObservation(
      hydratingDeferredValues(
        in: liveObservation.stream,
        plan: plan,
        attributes: attributes,
        onFailure: onDeferredValueHydrationFailure
      ),
      cancelUnderlyingObservation: liveObservation.cancel
    )
  }

  private func hydratingDeferredValues(
    in stream: AsyncStream<InstantQueryEmission>,
    plan: InstantQueryPlan,
    attributes: [InstantAttribute],
    onFailure: (@Sendable (InstantError) async -> Void)? = nil
  ) -> InstantLiveInfiniteQueryChunkObservationLease<InstantQueryEmission> {
    guard configuration.deferredValueResidency.hasRequestedAttributes(
      for: plan,
      attributes: attributes
    ) else {
      return InstantLiveInfiniteQueryChunkObservationLease(
        stream: stream,
        cancel: {}
      )
    }
    let pair = AsyncStream<InstantQueryEmission>.makeStream(
      bufferingPolicy: .bufferingNewest(1)
    )
    let task = Task { [weak self] in
      guard let self else {
        pair.continuation.finish()
        return
      }
      do {
        for await emission in stream {
          try Task.checkCancellation()
          guard
            let hydrated = try await self.hydrateDeferredValuesIfCurrent(
              in: emission,
              plan: plan,
              attributes: attributes
            )
          else { continue }
          await self.configuration.onLiveInfiniteQueryDeferredHydrationAcquiredForTesting?(
            hydrated.values.count
          )
          try Task.checkCancellation()
          pair.continuation.yield(hydrated)
        }
        pair.continuation.finish()
      } catch is CancellationError {
        pair.continuation.finish()
      } catch {
        let failure = self.deferredValueHydrationFailure(error, plan: plan)
        await onFailure?(failure)
        pair.continuation.finish()
      }
    }
    let termination = InstantLiveObservationTermination {
      task.cancel()
      await task.value
    }
    pair.continuation.onTermination = { @Sendable _ in
      Task { await termination.run() }
    }
    return InstantLiveInfiniteQueryChunkObservationLease(
      stream: pair.stream,
      cancel: {
        pair.continuation.finish()
        await termination.run()
      }
    )
  }

  private static func liveInfiniteQueryChunkObservation(
    _ hydration: InstantLiveInfiniteQueryChunkObservationLease<InstantQueryEmission>,
    cancelUnderlyingObservation: @escaping @Sendable () async -> Void
  ) -> InstantLiveInfiniteQueryChunkObservation {
    let termination = InstantLiveObservationTermination {
      async let cancelHydration: Void = hydration.cancel()
      async let underlyingCancellation: Void = cancelUnderlyingObservation()
      _ = await (cancelHydration, underlyingCancellation)
    }
    return InstantLiveInfiniteQueryChunkObservation(
      stream: hydration.stream,
      cancel: { await termination.run() }
    )
  }

  package func deferredValueHydrationFailure(
    _ error: Error,
    plan: InstantQueryPlan
  ) -> InstantError {
    var failure = (error as? InstantError) ?? InstantError(
      code: .persistenceFailed,
      operation: "hydrate deferred infinite query values",
      namespace: plan.namespace,
      message: String(describing: error),
      recovery: "Inspect the local SQLite cache, then restart this query subscription."
    )
    failure.code = .persistenceFailed
    failure.operation = "hydrate deferred infinite query values"
    if failure.namespace == nil {
      failure.namespace = plan.namespace
    }
    InstantDiagnostics.shared.record(
      error: failure,
      subsystem: "instant-swift-data-core",
      category: "query",
      event: "query.deferred-value-hydration-failed",
      message: "Could not hydrate selected deferred values from the local cache.",
      metadata: ["namespace": plan.namespace],
      correlationID: plan.id
    )
    reportIssue(
      "Instant could not hydrate selected deferred values for query '\(plan.id)': \(failure)"
    )
    return failure
  }

  private func hydrateDeferredValues(
    in emission: InstantQueryEmission,
    plan: InstantQueryPlan,
    rootEntityIDs: Set<String>? = nil,
    attributes: [InstantAttribute]
  ) async throws -> InstantQueryEmission {
    let requests = configuration.deferredValueResidency.hydrationRequests(
      for: plan,
      values: emission.values,
      rootEntityIDs: rootEntityIDs,
      attributes: attributes
    )
    return try await hydrateDeferredValues(
      in: emission,
      requests: requests,
      plan: plan,
      attributes: attributes
    )
  }

  private func hydrateDeferredValues(
    in emission: InstantQueryEmission,
    requests: [InstantDeferredValueHydrationRequest],
    plan: InstantQueryPlan,
    attributes: [InstantAttribute]
  ) async throws -> InstantQueryEmission {
    guard !requests.isEmpty else { return emission }
    recordActorHop(.persistence)
    var triples: [InstantTriple] = []
    for request in requests {
      triples.append(
        contentsOf: try await persistence.loadDeferredValues(
          attributeIDs: request.attributeIDs,
          entityIDs: request.entityIDs
        )
      )
    }
    return configuration.deferredValueResidency.hydrating(
      emission,
      for: plan,
      with: triples,
      attributes: attributes
    )
  }

  private func hydrateDeferredValuesIfCurrent(
    in emission: InstantQueryEmission,
    plan: InstantQueryPlan,
    attributes: [InstantAttribute]
  ) async throws -> InstantQueryEmission? {
    guard configuration.deferredValueResidency.hasRequestedAttributes(
      for: plan,
      attributes: attributes
    ) else { return emission }
    try await enterOperationGateUnlessCancelled(
      operation: "hydrate deferred query emission"
    )
    do {
      guard await store.currentSequence() == emission.sequence else {
        await leaveOperationGate()
        return nil
      }
      let hydrated = try await hydrateDeferredValues(
        in: emission,
        plan: plan,
        attributes: attributes
      )
      await leaveOperationGate()
      return hydrated
    } catch {
      await leaveOperationGate()
      throw error
    }
  }

  package func hydrateDeferredInfiniteQuerySnapshot(
    _ snapshot: InstantInfiniteQuerySnapshot,
    entityIDs: Set<String>,
    plan: InstantQueryPlan,
    attributes: [InstantAttribute]
  ) async throws -> InstantInfiniteQuerySnapshot? {
    guard configuration.deferredValueResidency.hasRequestedAttributes(
      for: plan,
      attributes: attributes
    ) else { return snapshot }
    try await enterOperationGateUnlessCancelled(
      operation: "hydrate deferred infinite query snapshot"
    )
    do {
      guard await store.currentSequence() == snapshot.sequence else {
        await leaveOperationGate()
        return nil
      }
      guard !entityIDs.isEmpty else {
        await leaveOperationGate()
        return snapshot
      }
      let emission = try await hydrateDeferredValues(
        in: InstantQueryEmission(
          queryID: snapshot.queryID,
          sequence: snapshot.sequence,
          values: snapshot.values,
          pageInfo: snapshot.pageInfo
        ),
        plan: plan,
        rootEntityIDs: entityIDs,
        attributes: attributes
      )
      var hydrated = snapshot
      hydrated.values = emission.values
      await leaveOperationGate()
      return hydrated
    } catch {
      await leaveOperationGate()
      throw error
    }
  }

  public func query(_ plan: InstantQueryPlan) async throws -> [InstantEntitySnapshot] {
    try await queryOnce(plan).values
  }

  public func queryOnce(_ plan: InstantQueryPlan) async throws -> InstantQueryEmission {
    let startedAt = Date()
    do {
      let usesLiveTransport: Bool
      if configuration.liveTransport != nil {
        if await liveSession.isOpen {
          usesLiveTransport = true
        } else if configuration.autoConnectLiveTransport {
          usesLiveTransport = try await persistedConnectionState() != .closed
        } else {
          usesLiveTransport = false
        }
      } else {
        usesLiveTransport = false
      }
      InstantDiagnostics.shared.record(
        .debug,
        subsystem: "instant-swift-data-core",
        category: "query",
        event: "query-once.started",
        message: "Started a one-shot Instant query.",
        metadata: [
          "appID": configuration.appID,
          "namespace": plan.namespace,
          "transport": usesLiveTransport ? "websocket" : "local-cache",
        ],
        correlationID: plan.id
      )
      let emission = try await usesLiveTransport
        ? queryOnceThroughLive(plan)
        : materializeLocalQueryOnce(plan, enforcesConnectionFreshness: true)
      InstantDiagnostics.shared.record(
        .debug,
        subsystem: "instant-swift-data-core",
        category: "query",
        event: "query-once.completed",
        message: "One-shot Instant query completed.",
        metadata: [
          "namespace": plan.namespace,
          "resultCount": String(emission.values.count),
          "sequence": String(emission.sequence),
          "durationMilliseconds": String(
            Int64((Date().timeIntervalSince(startedAt) * 1_000).rounded())
          ),
        ],
        correlationID: plan.id
      )
      return emission
    } catch {
      InstantDiagnostics.shared.record(
        error: error,
        subsystem: "instant-swift-data-core",
        category: "query",
        event: "query-once.failed",
        message: "One-shot Instant query failed.",
        metadata: [
          "namespace": plan.namespace,
          "durationMilliseconds": String(
            Int64((Date().timeIntervalSince(startedAt) * 1_000).rounded())
          ),
        ],
        correlationID: plan.id
      )
      throw error
    }
  }

  private func queryOnceThroughLive(_ plan: InstantQueryPlan) async throws -> InstantQueryEmission {
    let query = try InstantLiveQueryEncoder.encode(plan)
    let registrationKey = try InstantLiveQueryEncoder.registrationKey(for: query)
    await liveQueryResultState.retain(key: registrationKey)
    let cleanupOwner = InstantAsyncCancellationOwner(
      cancelAndWait: { [self] in
        await liveQueryResultState.release(key: registrationKey)
        _ = try? await liveSession.unregisterQuery(
          key: registrationKey,
          clientEventID: configuration.makeID()
        )
      }
    )
    let emission: InstantQueryEmission
    do {
      try Task.checkCancellation()
      let observedRevision = await liveQueryAcknowledgements.revision(for: registrationKey)

      // Match Reactor.queryOnce + _flushPendingMessages: record the query before
      // reconnecting so an opening session sends add-query ahead of its durable
      // mutation backlog.
      await enterOperationGate()
      do {
        try await liveSession.registerQuery(
          query,
          key: registrationKey,
          clientEventID: configuration.makeID(),
          requiresServerAcknowledgement: true
        )
        await leaveOperationGate()
      } catch {
        await leaveOperationGate()
        throw error
      }
      try await ensureLiveConnectionIfNeeded()

      let liveQueryAcknowledgementTimeoutMilliseconds: UInt64 = 5_000
      do {
        try await instantLiveWithTimeout(
          operation: "run Instant live query",
          timeoutMilliseconds: liveQueryAcknowledgementTimeoutMilliseconds
        ) {
          try await self.liveQueryAcknowledgements.wait(
            for: registrationKey,
            after: observedRevision
          )
        }
      } catch {
        if let error = error as? InstantError,
          error.operation == "run Instant live query",
          error.code == .permissionRejected || error.code == .validationFailed
        {
          InstantDiagnostics.shared.record(
            error: error,
            subsystem: "instant-swift-data-core",
            category: "query",
            event: "query.live-rejected",
            message: "Live query was rejected by Instant validation or permissions.",
            metadata: ["registrationKey": registrationKey],
            correlationID: plan.id
          )
          throw error
        }
        InstantDiagnostics.shared.record(
          error: error,
          subsystem: "instant-swift-data-core",
          category: "query",
          event: "query.live-ack-timeout",
          message:
            "Live query did not receive a server acknowledgement within the timeout.",
          metadata: [
            "registrationKey": registrationKey,
            "namespace": plan.namespace,
            "timeoutMilliseconds": String(liveQueryAcknowledgementTimeoutMilliseconds),
          ],
          correlationID: plan.id
        )
        await recordConnectionError(error)
        throw error
      }
      try await configuration.onLiveQueryOnceAcknowledgedForTesting?()
      try Task.checkCancellation()
      let pageInfo = await liveQueryPageInfo(for: registrationKey)
      emission = try await materializeLocalQueryOnce(
        plan,
        remotePageInfo: pageInfo.map(InstantQueryRemotePageInfo.ready)
      )
    } catch {
      cleanupOwner.finish()
      await cleanupOwner.wait()
      throw error
    }
    cleanupOwner.finish()
    await cleanupOwner.wait()
    try Task.checkCancellation()
    return emission
  }

  package func queryLocally(_ plan: InstantQueryPlan) async throws -> InstantQueryEmission {
    try await materializeLocalQueryOnce(plan, enforcesConnectionFreshness: false)
  }

  package func materializeLocalInfiniteQueryIdentity(
    _ plan: InstantQueryPlan
  ) async throws -> InstantQueryEmission {
    try await enterOperationGateUnlessCancelled(
      operation: "materialize local infinite query identity"
    )
    do {
      let state = try await loadCompactStateSynchronizingStore()
      if let issue = TripleIndexes.validate(
        plan,
        attributes: AttributeStore(attributes: state.snapshot.store.attributes)
      ) {
        throw validationFailed(
          operation: "validate infinite query identity expansion",
          namespace: issue.namespace,
          path: issue.path,
          message: issue.message,
          recovery: issue.recovery
        )
      }
      recordActorHop(.store)
      let emission = await store.materializeEmission(plan)
      await leaveOperationGate()
      return emission
    } catch {
      await leaveOperationGate()
      throw error
    }
  }

  private func liveQueryPageInfo(for registrationKey: String) async -> InstantQueryPageInfo? {
    if let pageInfo = await liveQueryResultState.pageInfo(for: registrationKey) {
      return pageInfo
    }
    do {
      recordActorHop(.persistence)
      guard let result = try await persistence.liveQueryResult(key: registrationKey) else {
        return nil
      }
      await liveQueryResultState.record(result)
      return result.pageInfo
    } catch {
      InstantDiagnostics.shared.record(
        error: error,
        subsystem: "instant-swift-data-core",
        category: "query",
        event: "live-query-result.load-failed",
        message: "Could not load the persisted live query result.",
        metadata: ["registrationKey": registrationKey]
      )
      return nil
    }
  }

  private func materializeLocalQueryOnce(
    _ plan: InstantQueryPlan,
    enforcesConnectionFreshness: Bool = true,
    remotePageInfo: InstantQueryRemotePageInfo? = nil
  ) async throws
    -> InstantQueryEmission
  {
    await enterOperationGate()
    do {
      for _ in 0..<5 {
        recordActorHop(.persistence)
        let state = try await loadCompactStateSynchronizingStore()
        if let issue = TripleIndexes.validate(
          plan,
          attributes: AttributeStore(attributes: state.snapshot.store.attributes)
        ) {
          throw validationFailed(
            operation: "validate query",
            namespace: issue.namespace,
            path: issue.path,
            message: issue.message,
            recovery: issue.recovery
          )
        }
        if enforcesConnectionFreshness,
          !configuration.isLocalOnly,
          try await persistedConnectionState() == .closed
        {
          recordActorHop(.persistence)
          let cachedQuery = try await persistence.cachedQuery(cacheKey: plan.cacheKey)
          if let issue = TripleIndexes.validate(
            plan,
            attributes: AttributeStore(attributes: state.snapshot.store.attributes)
          ) {
            throw validationFailed(
              operation: "validate query",
              namespace: issue.namespace,
              path: issue.path,
              message: issue.message,
              recovery: issue.recovery
            )
          }
          let freshCachedQuery = await freshCachedQueryForClosedQuery(
            cachedQuery,
            plan: plan,
            state: state
          )
          throw InstantError(
            code: .networkFailed,
            operation: "queryOnce",
            namespace: plan.namespace,
            message: "Cannot run query '\(plan.id)' while the Instant connection is closed.",
            recovery:
              "Call connect() or run 'instant-swift-data connection connect' before querying again.",
            cachedQuery: freshCachedQuery
          )
        }
        recordActorHop(.store)
        let localEmission = await store.materializeEmission(
          plan,
          remotePageInfo: remotePageInfo
        )
        let emission = try await hydrateDeferredValues(
          in: localEmission,
          plan: plan,
          attributes: state.snapshot.store.attributes
        )
        recordActorHop(.persistence)
        let didSave = try await persistence.saveQueryCache(
          InstantCachedQuery(
            queryID: plan.id,
            plan: plan,
            emission: emission,
            updatedAt: configuration.now(),
            storeRevision: state.storeRevision,
            attributeRevision: state.attributeRevision
          ),
          expectedStoreRevision: state.storeRevision,
          expectedAttributeRevision: state.attributeRevision
        )
        if didSave {
          if queryCachePruningCadence.shouldPrune(
            afterSuccessfulWriteWithInterval: configuration.queryCachePruningWriteInterval
          ) {
            await pruneQueryCache(preserving: plan.cacheKey)
          }
          await leaveOperationGate()
          return emission
        }
      }

      throw queryCacheChangedDuringMaterialization(plan)
    } catch {
      await leaveOperationGate()
      throw error
    }
  }

  private func pruneQueryCache(preserving cacheKey: String) async {
    recordActorHop(.store)
    var preservedCacheKeys = await store.activeQueryCacheKeys()
    preservedCacheKeys.insert(cacheKey)
    do {
      recordActorHop(.persistence)
      let result = try await persistence.pruneQueryCache(
        policy: configuration.queryCachePruningPolicy,
        now: configuration.now(),
        preservingCacheKeys: preservedCacheKeys
      )
      guard !result.removedCacheKeys.isEmpty else { return }
      InstantDiagnostics.shared.record(
        .debug,
        subsystem: "instant-swift-data-core",
        category: "query",
        event: "query-cache.pruned",
        message: "Pruned unloaded persisted query results after materialization.",
        metadata: [
          "preservedCount": String(preservedCacheKeys.count),
          "remainingCount": String(result.remainingEntryCount),
          "removedCount": String(result.removedCacheKeys.count),
        ],
        correlationID: cacheKey
      )
    } catch {
      InstantDiagnostics.shared.record(
        error: error,
        subsystem: "instant-swift-data-core",
        category: "query",
        event: "query-cache.prune-failed",
        message: "Could not prune persisted query results after materialization.",
        metadata: ["preservedCount": String(preservedCacheKeys.count)],
        correlationID: cacheKey
      )
    }
  }

  func pruneLiveQueryResults(
    policy: InstantLiveQueryResultPruningPolicy,
    now: InstantTimestamp
  ) async throws -> InstantLiveQueryResultPruningResult {
    await enterOperationGate()
    do {
      let result = try await performPruneLiveQueryResults(policy: policy, now: now)
      await leaveOperationGate()
      return result
    } catch {
      await leaveOperationGate()
      throw error
    }
  }

  private func performPruneLiveQueryResults(
    policy: InstantLiveQueryResultPruningPolicy,
    now: InstantTimestamp
  ) async throws -> InstantLiveQueryResultPruningResult {
    let activeQueryKeys = await liveSession.activeQueryKeys()
    if let onActiveKeysCaptured =
      configuration.onLiveQueryResultPruneActiveKeysCapturedForTesting
    {
      await onActiveKeysCaptured(activeQueryKeys)
    }
    recordActorHop(.persistence)
    let currentStoreSnapshot = await store.snapshot()
    let application = try await persistence.pruneLiveQueryResults(
      policy: policy,
      now: now,
      preservingQueryKeys: activeQueryKeys,
      currentStoreSnapshot: currentStoreSnapshot
    )
    guard !application.result.removedQueryKeys.isEmpty else {
      return application.result
    }
    if application.result.removedOrphanedTripleCount > 0 {
      recordActorHop(.store)
      // An empty snapshot is the meaningful result when pruning removes the
      // final owned row. Skipping it leaves that row visible in the hot actor
      // even though SQLite has already deleted it.
      await replaceStoreSnapshot(application.state.snapshot.store)
      installedStoreRevisions.install(
        storeRevision: application.state.storeRevision,
        attributeRevision: application.state.attributeRevision
      )
    }
    for key in application.result.removedQueryKeys {
      await liveQueryResultState.unload(key: key)
    }
    InstantDiagnostics.shared.record(
      .debug,
      subsystem: "instant-swift-data-core",
      category: "query",
      event: "live-query-results.pruned",
      message: "Pruned unloaded persisted live query results and newly orphaned triples.",
      metadata: [
        "activeCount": String(activeQueryKeys.count),
        "remainingCount": String(application.result.remainingEntryCount),
        "remainingTripleCount": String(application.result.remainingTripleCount),
        "removedCount": String(application.result.removedQueryKeys.count),
        "removedOrphanedTripleCount": String(
          application.result.removedOrphanedTripleCount
        ),
      ]
    )
    return application.result
  }

  private func freshCachedQueryForClosedQuery(
    _ cachedQuery: InstantCachedQuery?,
    plan: InstantQueryPlan,
    state: InstantPersistenceState
  ) async -> InstantCachedQuery? {
    guard let cachedQuery else { return nil }
    guard cachedQuery.storeRevision != state.storeRevision
      || cachedQuery.attributeRevision != state.attributeRevision
    else { return cachedQuery }

    recordActorHop(.store)
    // `loadCompactStateSynchronizingStore` has already adopted the exact
    // persisted store revision. Re-materialize against that hot actor without
    // reconstructing or replacing its complete triple indexes again.
    let localEmission = await store.materializeEmission(plan)
    guard cachedQuery.emission.queryID == localEmission.queryID,
      cachedQuery.emission.values == localEmission.values,
      cachedQuery.emission.pageInfo == localEmission.pageInfo
    else {
      return nil
    }
    return cachedQuery
  }

  public func cachedQuery(_ plan: InstantQueryPlan) async throws -> InstantCachedQuery? {
    recordActorHop(.persistence)
    return try await persistence.cachedQuery(cacheKey: plan.cacheKey)
  }

  public func cachedQueries() async throws -> [InstantCachedQuery] {
    try await persistence.loadQueryCache()
  }

  public func selectedAppID() async throws -> String? {
    try await persistence.loadMetadataValue(key: Self.selectedAppIDMetadataKey)
  }

  public func saveSelectedAppID(_ appID: String) async throws -> String {
    let appID = appID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !appID.isEmpty else {
      throw validationFailed(
        operation: "select app",
        message: "App id must not be empty.",
        recovery: "Pass an app id, or set INSTANT_APP_ID for a temporary override."
      )
    }

    await operationGate.enter()
    do {
      try await persistence.saveMetadataValue(
        appID,
        key: Self.selectedAppIDMetadataKey,
        updatedAt: configuration.now()
      )
      await operationGate.leave()
      return appID
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  public func syncState() async throws -> InstantSyncState {
    InstantSyncState(
      processedTransactionID: try await persistence.loadMetadataValue(
        key: processedTransactionIDMetadataKey
      )
    )
  }

  private func ensureLiveConnectionIfNeeded() async throws {
    guard configuration.liveTransport != nil else { return }
    guard configuration.autoConnectLiveTransport else { return }
    guard await !liveSession.isOpen else { return }
    guard try await persistedConnectionState() != .closed else { return }
    await reconnectController.cancelAndWait()
    _ = try await connectLiveSession(reportsFailure: true, onlyIfNeeded: true)
  }

  private func startLiveMutationDeliveryIfNeeded() async {
    guard configuration.liveTransport != nil else { return }
    await mutationDeliveryPump.request(
      sleep: configuration.liveReconnectSleep
    ) { [weak self] in
      guard let self else { return .finished }
      let liveSessionIsOpen = await self.liveSession.isOpen
      guard self.configuration.autoConnectLiveTransport || liveSessionIsOpen else {
        return .finished
      }
      do {
        try Task.checkCancellation()
        try await self.ensureLiveConnectionIfNeeded()
        guard await self.liveSession.isOpen else {
          // An explicit close wins over a queued or sleeping hydration retry.
          // Stop the pump instead of retaining the runtime and rereading a
          // durable outbox that the user has deliberately taken offline.
          return .finished
        }
        return await self.runAutomaticMutationPumpPass()
      } catch is CancellationError {
        return .finished
      } catch {
        await self.scheduleReconnect(
          after: error,
          event: "connection.optimistic-transaction-connect-failed",
          message: "Instant could not connect after an optimistic transaction and will retry."
        )
        return .finished
      }
    }
  }

  private func scheduleLiveMutationDeadlineWake(
    at deadlineMilliseconds: Int64?
  ) async {
    await mutationDeadlineWake.request(
      deadlineMilliseconds: deadlineMilliseconds,
      now: configuration.now,
      sleep: configuration.liveMutationDeadlineSleep
    ) { [weak self] in
      await self?.startLiveMutationDeliveryIfNeeded()
    }
  }

  /// Schedules one coalesced live outbox delivery pass without making the caller wait for
  /// SQLite hydration or WebSocket I/O. Public server-acceptance waiters poll durable state as
  /// their completion condition; they should not create an overlapping hydration pass on every
  /// poll tick.
  package func requestLiveMutationDelivery() async {
    await startLiveMutationDeliveryIfNeeded()
  }

  package func automaticMutationPumpIsIdleForTesting() async -> Bool {
    await mutationDeliveryPump.isIdleForTesting()
  }

  package func automaticMutationPumpIsSuspendedForTesting() async -> Bool {
    await mutationDeliveryPump.isSuspendedForTesting()
  }

  package func exactCloseBackgroundTasksAreIdleForTesting() async -> Bool {
    await exactCloseBackgroundTaskIdleState().allIdle
  }

  private func exactCloseBackgroundTaskIdleState() async
    -> InstantRuntimeExactCloseIdleState
  {
    let reconnectIsIdle = await reconnectController.isIdleForTesting()
    let receiverIsIdle = await liveSession.receiverTaskIsIdleForTesting()
    let mutationDeliveryIsIdle = await mutationDeliveryPump.isIdleForTesting()
    return InstantRuntimeExactCloseIdleState(
      automaticLiveConnection: automaticLiveConnectionTaskOwner.isIdle,
      startupCookieSync: startupCookieSyncTaskOwner.isIdle,
      reconnect: reconnectIsIdle,
      receiver: receiverIsIdle,
      mutationDeliveryPump: mutationDeliveryIsIdle,
      explicitMutationFlush: explicitMutationFlushOwner.isIdle
    )
  }

  package func operationGateWaiterCountForTesting() async -> Int {
    await operationGate.waiterCount
  }

  package func liveActiveQueryKeysForTesting() async -> Set<String> {
    await liveSession.activeQueryKeys()
  }

  package func liveQueryResultActiveKeysForTesting() async -> Set<String> {
    await liveQueryResultState.activeKeysForTesting()
  }

  private func startAutomaticLiveConnectionIfNeeded() {
    guard configuration.liveTransport != nil else { return }
    guard configuration.autoConnectLiveTransport else { return }
    _ = automaticLiveConnectionTaskOwner.start { [weak self] in
      guard let self else { return }
      await self.configuration.onAutomaticLiveConnectionTaskStartedForTesting?()
      do {
        try Task.checkCancellation()
        try await self.ensureLiveConnectionIfNeeded()
      } catch is CancellationError {
        return
      } catch {
        // A close request can arrive while a cancellation-insensitive
        // connector unwinds with its own error. Cancellation still owns that
        // terminal transition and must not create a reconnect task.
        guard !Task.isCancelled else { return }
        await self.scheduleReconnect(
          after: error,
          event: "connection.auto-connect-failed",
          message: "Automatic Instant connection failed and will retry."
        )
      }
    }
  }

  private func startUserCookieSyncOnStartup() {
    _ = startupCookieSyncTaskOwner.start(priority: .utility) { [weak self] in
      guard let self else { return }
      await self.configuration.onStartupCookieSyncTaskStartedForTesting?()
      do {
        try Task.checkCancellation()
        try await self.syncUserCookieOnStartup()
      } catch is CancellationError {
        return
      } catch {
        // Startup cookie sync is deliberately non-fatal. The throwing helper
        // preserves cancellation so exact close can still own its full tail.
      }
    }
  }

  private func reconnectAfterAuthChangeIfNeeded() async {
    guard configuration.liveTransport != nil else { return }
    guard configuration.autoConnectLiveTransport else { return }
    guard (try? await persistedConnectionState()) != .closed else { return }
    do {
      _ = try await connectLiveSession(reportsFailure: false)
    } catch {
      await scheduleReconnect(
        after: error,
        event: "connection.auth-reconnect-failed",
        message: "Instant could not reconnect after authentication changed and will retry."
      )
    }
  }

  public func markProcessedTransaction(id transactionID: String) async throws -> InstantSyncState {
    let transactionID = transactionID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !transactionID.isEmpty else {
      throw validationFailed(
        operation: "mark processed transaction",
        message: "Transaction id must not be empty.",
        recovery: "Pass the Instant transaction id that has been fully processed."
      )
    }

    await operationGate.enter()
    do {
      try await persistence.saveMetadataValue(
        transactionID,
        key: processedTransactionIDMetadataKey,
        updatedAt: configuration.now()
      )
      _ = try? await publishConnectionStatusWithGateHeld()
      await operationGate.leave()
      return InstantSyncState(processedTransactionID: transactionID)
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  public func connectionStatus() async throws -> InstantConnectionStatus {
    await operationGate.enter()
    do {
      let status = try await connectionStatusWithGateHeld()
      await operationGate.leave()
      return status
    } catch {
      await operationGate.leave()
      if configuration.liveTransport != nil {
        await liveSession.close()
      }
      throw error
    }
  }

  public func observeConnectionStatus() async throws -> AsyncStream<InstantConnectionStatus> {
    await operationGate.enter()
    do {
      let status = try await connectionStatusWithGateHeld()
      let stream = await connectionStatusObservers.observe(
        key: configuration.appID,
        current: status
      )
      await operationGate.leave()
      return stream
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  @discardableResult
  public func connect() async throws -> InstantConnectionStatus {
    await reconnectController.cancelAndWait()
    return try await connectLiveSession(reportsFailure: true)
  }

  private func connectLiveSession(
    reportsFailure: Bool,
    onlyIfNeeded: Bool = false
  ) async throws -> InstantConnectionStatus {
    let startedAt = Date()
    InstantDiagnostics.shared.record(
      .info,
      subsystem: "instant-swift-data-core",
      category: "connection",
      event: "connection.open-started",
      message: "Opening the Instant connection.",
      metadata: [
        "appID": configuration.appID,
        "transport": configuration.liveTransport == nil ? "local-cache" : "websocket",
        "isReconnect": String(!reportsFailure),
        "websocketHost": configuration.websocketURI.host ?? "unknown",
      ]
    )
    var enteredConnectionGate = false
    var enteredOperationGate = false
    do {
      try await connectionGate.enterUnlessCancelled(operation: "connect live session")
      enteredConnectionGate = true
      recordActorHop(.operationGate)
      try await operationGate.enterUnlessCancelled(operation: "connect live session")
      enteredOperationGate = true
      if onlyIfNeeded || !reportsFailure {
        let persistedState = try await persistedConnectionState()
        let liveSessionIsOpen = await liveSession.isOpen
        if persistedState == .closed || (onlyIfNeeded && liveSessionIsOpen) {
          let status = try await connectionStatusWithGateHeld()
          recordActorHop(.operationGate)
          await operationGate.leave()
          enteredOperationGate = false
          await connectionGate.leave()
          enteredConnectionGate = false
          InstantDiagnostics.shared.record(
            .debug,
            subsystem: "instant-swift-data-core",
            category: "connection",
            event: "connection.open-reused",
            message: liveSessionIsOpen
              ? "Reused the existing Instant connection."
              : "Preserved the explicitly closed Instant connection.",
            metadata: [
              "appID": configuration.appID,
              "state": status.state.rawValue,
            ]
          )
          return status
        }
      }
      if let liveTransport = configuration.liveTransport {
        recordActorHop(.persistence)
        let session = try await persistence.loadAuthSession(key: authSessionKey)
        recordActorHop(.operationGate)
        await operationGate.leave()
        enteredOperationGate = false
        do {
          recordActorHop(.liveSession)
          try await liveSession.open(
            request: InstantLiveSessionRequest(
              appID: configuration.appID,
              websocketURI: configuration.websocketURI,
              refreshToken: session?.refreshToken
            ),
            transport: liveTransport,
            makeID: configuration.makeID
          )
          recordActorHop(.liveSession)
          let openedServerAttributes = await liveSession.currentServerAttributes()
          recordActorHop(.operationGate)
          try await operationGate.enterUnlessCancelled(operation: "install opened live session")
          enteredOperationGate = true
          // Store the server's attribute set before anything reads the cache. Namespaces added
          // to the schema after this device's last sync are unknown to it until this runs, and
          // an unknown namespace cannot even be subscribed to, so nothing else would ever
          // deliver them.
          try await applyServerAttributesWithGateHeld(openedServerAttributes)
          let reservedMutationIDs = await automaticMutationRetryReservations.snapshot()
          recordActorHop(.persistence)
          let hasPersistedTransientFailure =
            try await persistence.hasAutomaticFailedMutationRetryCandidate(
              excludingMutationIDs: reservedMutationIDs
            )
          if hasPersistedTransientFailure {
            InstantDiagnostics.shared.record(
              .debug,
              subsystem: "instant-swift-data-core",
              category: "outbox",
              event: "outbox.failed-mutation-retry.scheduled",
              message:
                "Scheduled indexed failed-mutation retry after the live session opened.",
              metadata: ["appID": configuration.appID]
            )
          }
          recordActorHop(.operationGate)
          await operationGate.leave()
          enteredOperationGate = false
        } catch is CancellationError {
          if enteredOperationGate {
            recordActorHop(.operationGate)
            await operationGate.leave()
            enteredOperationGate = false
          }
          recordActorHop(.liveSession)
          await liveSession.close()
          throw CancellationError()
        } catch {
          if enteredOperationGate {
            recordActorHop(.operationGate)
            await operationGate.leave()
            enteredOperationGate = false
          }
          recordActorHop(.liveSession)
          await liveSession.close()
          recordActorHop(.operationGate)
          try await operationGate.enterUnlessCancelled(
            operation: "record failed live session open"
          )
          enteredOperationGate = true
          try await saveErroredConnectionMetadataWithGateHeld(message: String(describing: error))
          if reportsFailure {
            _ = try? await publishConnectionStatusWithGateHeld()
          }
          throw error
        }
      }
      if !enteredOperationGate {
        recordActorHop(.operationGate)
        try await operationGate.enterUnlessCancelled(operation: "finish live session open")
        enteredOperationGate = true
      }
      try await saveOpenedConnectionMetadataWithGateHeld()
      let status = try await publishConnectionStatusWithGateHeld()
      explicitMutationFlushOwner.resume()
      recordActorHop(.operationGate)
      await operationGate.leave()
      enteredOperationGate = false
      var streamWriterReconnectError: Error?
      if configuration.liveTransport != nil {
        recordActorHop(.liveSession)
        await liveSession.startReceiving(
          onEvent: { [weak self] event, attributes in
            guard let self else { return }
            try await self.handleLiveServerEvent(event, serverAttributes: attributes)
          },
          onEventAcquired: configuration.onLiveReceiverEventAcquiredForTesting,
          onFailure: { [weak self] error in
            guard let self else { return }
            await self.handleLiveSessionFailure(error)
          }
        )
        do {
          recordActorHop(.liveSession)
          try await liveSession.reconnectStreamWriters()
        } catch {
          recordActorHop(.liveSession)
          await liveSession.close()
          streamWriterReconnectError = error
        }
        if streamWriterReconnectError == nil {
          await mutationDeliveryPump.resume()
          await startLiveMutationDeliveryIfNeeded()
        }
      }
      await connectionGate.leave()
      enteredConnectionGate = false
      if let streamWriterReconnectError {
        await handleLiveSessionFailure(streamWriterReconnectError)
      }
      InstantDiagnostics.shared.record(
        .notice,
        subsystem: "instant-swift-data-core",
        category: "connection",
        event: "connection.open-completed",
        message: "Instant connection opened.",
        metadata: [
          "appID": configuration.appID,
          "state": status.state.rawValue,
          "authenticated": String(status.isAuthenticated),
          "pendingMutationCount": String(status.pendingMutationCount),
          "durationMilliseconds": String(
            Int64((Date().timeIntervalSince(startedAt) * 1_000).rounded())
          ),
        ]
      )
      return status
    } catch is CancellationError {
      if enteredOperationGate {
        recordActorHop(.operationGate)
        await operationGate.leave()
      }
      if enteredConnectionGate {
        await connectionGate.leave()
      }
      throw CancellationError()
    } catch {
      if enteredOperationGate {
        recordActorHop(.operationGate)
        await operationGate.leave()
      }
      if enteredConnectionGate {
        await connectionGate.leave()
      }
      InstantDiagnostics.shared.record(
        error: error,
        subsystem: "instant-swift-data-core",
        category: "connection",
        event: "connection.open-failed",
        message: "Instant connection failed to open.",
        metadata: [
          "appID": configuration.appID,
          "isReconnect": String(!reportsFailure),
          "durationMilliseconds": String(
            Int64((Date().timeIntervalSince(startedAt) * 1_000).rounded())
          ),
        ]
      )
      throw error
    }
  }

  @discardableResult
  public func closeConnection() async throws -> InstantConnectionStatus {
    // Latch every background producer before waiting on connection work. A
    // task that already owns the connection gate sees cancellation and leaves;
    // no new automatic task can enter behind this close.
    let automaticLiveConnectionTask = automaticLiveConnectionTaskOwner.requestStop()
    let startupCookieSyncTask = startupCookieSyncTaskOwner.requestStop()
    let reconnectTask = await reconnectController.requestStop()
    await mutationDeliveryPump.suspend()
    let explicitMutationFlushTask = explicitMutationFlushOwner.requestStop()
    await connectionGate.enter()
    // Explicit response disposition uses the operation gate. Keep it free
    // while synchronously aborted transport work, renewal, and exact-token
    // disposition finish; only then may durable `.closed` become visible.
    await explicitMutationFlushTask.wait()
    recordActorHop(.operationGate)
    await operationGate.enter()
    var enteredOperationGate = true
    // Invalidate the receiver generation and close its wire now, but retain
    // the exact task handle. Receiver event/failure callbacks can be waiting on
    // the operation gate, so their join belongs strictly after this gate.
    recordActorHop(.liveSession)
    let receiverTask = await liveSession.beginClose()
    do {
      _ = try await releaseAutomaticOutboxClaimsWithGateHeld()
      try await saveClosedConnectionMetadataWithGateHeld()
      let status = try await publishConnectionStatusWithGateHeld()
      recordActorHop(.operationGate)
      await operationGate.leave()
      enteredOperationGate = false
      await waitForExactCloseBackgroundTasks(
        automaticLiveConnectionTask: automaticLiveConnectionTask,
        startupCookieSyncTask: startupCookieSyncTask,
        reconnectTask: reconnectTask,
        receiverTask: receiverTask
      )
      explicitMutationFlushOwner.resume()
      await connectionGate.leave()
      return status
    } catch {
      if enteredOperationGate {
        recordActorHop(.operationGate)
        await operationGate.leave()
      }
      await waitForExactCloseBackgroundTasks(
        automaticLiveConnectionTask: automaticLiveConnectionTask,
        startupCookieSyncTask: startupCookieSyncTask,
        reconnectTask: reconnectTask,
        receiverTask: receiverTask
      )
      explicitMutationFlushOwner.resume()
      await connectionGate.leave()
      throw error
    }
  }

  private func waitForExactCloseBackgroundTasks(
    automaticLiveConnectionTask: InstantRuntimeExactTaskOwner.Handle,
    startupCookieSyncTask: InstantRuntimeExactTaskOwner.Handle,
    reconnectTask: InstantRuntimeExactTaskOwner.Handle,
    receiverTask: InstantRuntimeExactTaskOwner.Handle
  ) async {
    let watchdogSleep = configuration.exactCloseWatchdogSleep
    let watchdog = Task { [weak self] in
      do {
        try await watchdogSleep(5_000)
        try Task.checkCancellation()
      } catch {
        return
      }
      guard let self else { return }
      let state = await self.exactCloseBackgroundTaskIdleState()
      guard !state.allIdle else { return }
      InstantDiagnostics.shared.record(
        .warning,
        subsystem: "instant-swift-data-core",
        category: "connection",
        event: "connection.close-cleanup-stalled",
        message:
          "Instant close has waited 5 seconds for exact background cleanup and will continue waiting.",
        metadata: [
          "appID": self.configuration.appID,
          "nonIdleOwners": state.nonIdleOwnerNames.joined(separator: ", "),
          "automaticLiveConnectionIdle": String(state.automaticLiveConnection),
          "startupCookieSyncIdle": String(state.startupCookieSync),
          "reconnectIdle": String(state.reconnect),
          "receiverIdle": String(state.receiver),
          "mutationDeliveryPumpIdle": String(state.mutationDeliveryPump),
          "explicitMutationFlushIdle": String(state.explicitMutationFlush),
        ]
      )
    }
    async let automaticLiveConnection: Void = automaticLiveConnectionTask.wait()
    async let startupCookieSync: Void = startupCookieSyncTask.wait()
    async let reconnect: Void = reconnectTask.wait()
    async let receiver: Void = receiverTask.wait()
    async let mutationDelivery: Void = mutationDeliveryPump.waitUntilStopped()
    _ = await (
      automaticLiveConnection,
      startupCookieSync,
      reconnect,
      receiver,
      mutationDelivery
    )
    watchdog.cancel()
    await watchdog.value
  }

  private func connectionStatusWithGateHeld(
    pendingMutationCount knownPendingMutationCount: Int? = nil
  ) async throws -> InstantConnectionStatus {
    let pendingMutationCount: Int
    if let knownPendingMutationCount {
      pendingMutationCount = knownPendingMutationCount
    } else {
      recordActorHop(.persistence)
      pendingMutationCount = try await persistence.countOutboxMutations(status: .pending)
    }
    let session = try await persistence.loadAuthSession(key: authSessionKey)
    let processedTransactionID = try await persistence.loadMetadataValue(
      key: processedTransactionIDMetadataKey
    )
    let storedState = try await persistedConnectionState()
    let lastErrorMessage = try await persistence.loadMetadataValue(
      key: connectionLastErrorMetadataKey
    )
    let liveSessionIsOpen = await liveSession.isOpen
    return InstantConnectionStatus(
      appID: configuration.appID,
      apiURI: configuration.apiURI,
      websocketURI: configuration.websocketURI,
      transport: configuration.liveTransport == nil ? .localCacheOnly : .webSocket,
      state: connectionState(
        storedState,
        isAuthenticated: session != nil,
        liveSessionIsOpen: liveSessionIsOpen
      ),
      isAuthenticated: session != nil,
      userID: session?.userID,
      pendingMutationCount: pendingMutationCount,
      processedTransactionID: processedTransactionID,
      lastErrorMessage: lastErrorMessage
    )
  }

  @discardableResult
  private func publishConnectionStatusWithGateHeld(
    pendingMutationCount: Int? = nil
  ) async throws -> InstantConnectionStatus {
    let status = try await connectionStatusWithGateHeld(
      pendingMutationCount: pendingMutationCount
    )
    await connectionStatusObservers.publish(status, for: configuration.appID)
    return status
  }

  private func publishMutationLifecycle(_ mutation: PendingMutation) async {
    let event: InstantMutationLifecycleEvent
    switch mutation.status {
    case .confirmed:
      guard mutation.provesServerAcceptance else { return }
      event = .serverAccepted(mutation)
    case .failed:
      event = .failed(mutation)
    case .pending:
      return
    }
    recordActorHop(.persistence)
    let observationID: String?
    do {
      observationID = try await persistence.mutationLifecyclePublicationIdentity(
        for: mutation.id
      )
    } catch {
      reportIssue(
        "Instant could not prove durable mutation lifecycle ownership for '\(mutation.id)': \(error)"
      )
      return
    }
    guard let observationID else { return }
    await mutationLifecycleObservers.publish(event, for: observationID)
  }

  private func persistedConnectionState() async throws -> InstantConnectionState {
    recordActorHop(.persistence)
    return try await persistence.loadMetadataValue(key: connectionStateMetadataKey)
      .flatMap(InstantConnectionState.init(rawValue:))
      ?? .opened
  }

  private func saveOpenedConnectionMetadataWithGateHeld() async throws {
    recordActorHop(.persistence)
    try await persistence.saveMetadataValue(
      InstantConnectionState.opened.rawValue,
      key: connectionStateMetadataKey,
      updatedAt: configuration.now()
    )
    recordActorHop(.persistence)
    try await persistence.deleteMetadataValue(key: connectionLastErrorMetadataKey)
  }

  private func saveClosedConnectionMetadataWithGateHeld() async throws {
    recordActorHop(.persistence)
    try await persistence.saveMetadataValue(
      InstantConnectionState.closed.rawValue,
      key: connectionStateMetadataKey,
      updatedAt: configuration.now()
    )
    recordActorHop(.persistence)
    try await persistence.deleteMetadataValue(key: connectionLastErrorMetadataKey)
  }

  private func saveErroredConnectionMetadataWithGateHeld(message: String) async throws {
    let now = configuration.now()
    recordActorHop(.persistence)
    try await persistence.saveMetadataValue(
      InstantConnectionState.errored.rawValue,
      key: connectionStateMetadataKey,
      updatedAt: now
    )
    recordActorHop(.persistence)
    try await persistence.saveMetadataValue(
      message,
      key: connectionLastErrorMetadataKey,
      updatedAt: now
    )
  }

  private func recordConnectionError(_ error: Error) async {
    guard !(error is InstantSupersededLiveSessionSend) else { return }
    await operationGate.enter()
    do {
      try await saveErroredConnectionMetadataWithGateHeld(message: String(describing: error))
      await operationGate.leave()
    } catch {
      await operationGate.leave()
    }
  }

  private func handleLiveSessionFailure(_ error: Error) async {
    do {
      _ = try await releaseAutomaticOutboxClaimsForDisconnectedSession()
    } catch is CancellationError {
      return
    } catch {
      InstantDiagnostics.shared.record(
        error: error,
        subsystem: "instant-swift-data-core",
        category: "outbox",
        event: "outbox.mutation.disconnected-claim-release-failed",
        message: "Instant could not release durable mutation claims after the live session ended.",
        metadata: ["appID": configuration.appID]
      )
    }
    guard !Task.isCancelled else { return }
    await scheduleReconnect(
      after: error,
      event: "connection.receive-loop-failed",
      message: "Instant live receive loop ended with an error."
    )
  }

  @discardableResult
  private func releaseAutomaticOutboxClaimsForDisconnectedSession() async throws
    -> Set<String>
  {
    try await enterOperationGateUnlessCancelled(
      operation: "release automatic outbox claims for disconnected session"
    )
    do {
      let released = try await releaseAutomaticOutboxClaimsWithGateHeld()
      await leaveOperationGate()
      return released
    } catch {
      await leaveOperationGate()
      throw error
    }
  }

  /// The operation gate orders durable claim release against the next pump
  /// admission. Once a socket is known dead, none of its claims may survive
  /// into the replacement session or wait for their old five-second lease.
  @discardableResult
  private func releaseAutomaticOutboxClaimsWithGateHeld() async throws -> Set<String> {
    recordActorHop(.persistence)
    let release = try await persistence.releaseAutomaticOutboxClaims(
      claimantID: automaticDeliveryClaimantID
    )
    await scheduleLiveMutationDeadlineWake(
      at: release.nextClaimDeadlineMilliseconds
    )
    recordActorHop(.liveSession)
    await liveSession.releaseMutationReservations(
      release.mutationIDs,
      timedOut: false
    )
    recordActorHop(.outbox)
    for mutationID in release.mutationIDs {
      await outbox.remove(id: mutationID)
    }
    return release.mutationIDs
  }

  private func scheduleReconnect(
    after error: Error,
    event: String,
    message: String
  ) async {
    guard !Task.isCancelled else { return }
    InstantDiagnostics.shared.record(
      error: error,
      subsystem: "instant-swift-data-core",
      category: "connection",
      event: event,
      message: message,
      metadata: ["appID": configuration.appID]
    )
    let recordsOnly = (error as? InstantError)?.operation == "process Instant stream file retries"
    // Order reconnect creation against explicit close. Whichever operation acquires this gate
    // first wins deterministically: close cancels a controller already created, while a later
    // scheduler sees `.closed` and returns without overwriting it or starting a new controller.
    do {
      try await connectionGate.enterUnlessCancelled(operation: "schedule live reconnect")
    } catch is CancellationError {
      return
    } catch {
      return
    }
    var enteredOperationGate = false
    var shouldReconnect = false
    do {
      try await enterOperationGateUnlessCancelled(operation: "schedule live reconnect")
      enteredOperationGate = true
      if try await persistedConnectionState() == .closed {
        await leaveOperationGate()
        enteredOperationGate = false
        await connectionGate.leave()
        return
      }
      shouldReconnect = !recordsOnly
      try await saveErroredConnectionMetadataWithGateHeld(message: String(describing: error))
      await leaveOperationGate()
      enteredOperationGate = false
    } catch is CancellationError {
      if enteredOperationGate {
        await leaveOperationGate()
      }
      await connectionGate.leave()
      return
    } catch {
      if enteredOperationGate {
        await leaveOperationGate()
      }
    }
    if shouldReconnect {
      await reconnectController.start(
        sleep: configuration.liveReconnectSleep,
        reconnect: { [weak self] in
          guard let self else { throw CancellationError() }
          _ = try await self.connectLiveSession(reportsFailure: false)
        }
      )
    }
    await connectionGate.leave()
  }

  private func handleLiveServerEvent(
    _ event: InstantLiveServerEvent,
    serverAttributes: [InstantLiveJSONValue]
  ) async throws {
    InstantDiagnostics.shared.record(
      .debug,
      subsystem: "instant-swift-data-core",
      category: "transport",
      event: "websocket.event-received",
      message: "Received an Instant WebSocket event.",
      metadata: [
        "appID": configuration.appID,
        "op": event.op,
        "serverAttributeCount": String(serverAttributes.count),
      ]
    )
    switch event {
    case let .addQueryOK(queryOK):
      guard let query = queryOK.query else {
        throw InstantError(
          code: .decodeFailed,
          operation: "apply Instant live query result",
          message: "add-query-ok must include q.",
          recovery: "Inspect the canonical Instant add-query-ok payload."
        )
      }
      let registrationKey = try InstantLiveQueryEncoder.registrationKey(for: query)
      guard !queryOK.result.isEmpty else {
        await liveQueryAcknowledgements.record(key: registrationKey)
        return
      }
      guard let processedTransactionID = queryOK.processedTransactionID?.nilIfEmpty else {
        throw InstantError(
          code: .decodeFailed,
          operation: "apply Instant live query result",
          message: "A non-empty add-query-ok must include processed-tx-id.",
          recovery: "Inspect the canonical Instant add-query-ok payload."
        )
      }
      try await applyLiveRefresh(
        InstantLiveRefreshOK(
          clientEventID: nil,
          processedTransactionID: processedTransactionID,
          attrs: serverAttributes,
          computations: [
            .object([
              "instaql-query": query,
              "instaql-result": .array(queryOK.result),
            ])
          ]
        )
      )
      await liveQueryAcknowledgements.record(key: registrationKey)

    case let .addQueryExists(queryOK):
      guard let query = queryOK.query else {
        throw InstantError(
          code: .decodeFailed,
          operation: "acknowledge existing Instant live query",
          message: "add-query-exists must include q.",
          recovery: "Inspect the canonical Instant add-query-exists payload."
        )
      }
      let registrationKey = try InstantLiveQueryEncoder.registrationKey(for: query)
      await liveQueryAcknowledgements.record(key: registrationKey)

    case let .refreshOK(refreshOK):
      try await applyLiveRefresh(
        InstantLiveRefreshOK(
          clientEventID: refreshOK.clientEventID,
          processedTransactionID: refreshOK.processedTransactionID,
          attrs: refreshOK.attrs.isEmpty ? serverAttributes : refreshOK.attrs,
          computations: refreshOK.computations
        )
      )

    case let .transactOK(transactOK):
      guard let clientEventID = transactOK.clientEventID?.nilIfEmpty,
        let transactionID = transactOK.transactionID?.nilIfEmpty
      else {
        InstantDiagnostics.shared.record(
          .error,
          subsystem: "instant-swift-data-core",
          category: "outbox",
          event: "outbox.mutation.transact-ok-malformed",
          message: "Received transact-ok without client-event-id or tx-id.",
          metadata: [
            "clientEventIDPresent": String(transactOK.clientEventID?.nilIfEmpty != nil),
            "transactionIDPresent": String(transactOK.transactionID?.nilIfEmpty != nil),
          ]
        )
        throw InstantError(
          code: .decodeFailed,
          operation: "confirm Instant live transaction",
          message: "transact-ok must include client-event-id and tx-id.",
          recovery: "Inspect the canonical Instant transact-ok payload."
        )
      }
      InstantDiagnostics.shared.record(
        .debug,
        subsystem: "instant-swift-data-core",
        category: "outbox",
        event: "outbox.mutation.transact-ok",
        message: "Server acknowledged an outbox mutation (transact-ok).",
        metadata: [
          "mutationID": clientEventID,
          "serverTransactionID": transactionID,
        ],
        correlationID: clientEventID
      )
      _ = try await acceptMutationIfPresent(
        id: clientEventID,
        serverTransactionID: transactionID
      )
      await startLiveMutationDeliveryIfNeeded()

    case let .refreshPresence(refresh):
      try await applyLivePresenceRefresh(refresh)

    case let .patchPresence(patch):
      try await applyLivePresencePatch(patch)

    case let .serverBroadcast(broadcast):
      try await applyLiveServerBroadcast(broadcast)

    case let .streamAppend(append):
      guard let delivery = await liveSession.takeDeliveredStreamAppend(
        clientEventID: append.clientEventID
      ) else {
        return
      }
      let seenOffset: Int64
      do {
        seenOffset = try await applyLiveStreamAppend(delivery)
      } catch let error as InstantError where error.operation == "fetch Instant stream file" {
        switch await liveSession.recordStreamFileFetchFailure(
          clientEventID: delivery.clientEventID
        ) {
        case let .failure(failure):
          throw failure
        case .requestReconnect, .deliver, .ignored:
          throw error
        }
      }
      await liveSession.recordDeliveredStreamAppend(delivery, seenOffset: seenOffset)

    case let .error(error):
      let clientEventID = error.clientEventID?.nilIfEmpty
      let mutationDisposition: InstantLiveMutationErrorDisposition
      if let clientEventID {
        recordActorHop(.persistence)
        mutationDisposition = try await persistence.liveMutationErrorDisposition(
          id: clientEventID,
          claimantID: automaticDeliveryClaimantID
        )
      } else {
        mutationDisposition = .missing
      }
      if case .alreadyTerminal = mutationDisposition {
        InstantDiagnostics.shared.record(
          .debug,
          subsystem: "instant-swift-data-core",
          category: "outbox",
          event: "outbox.mutation.server-error-already-recorded",
          message: "Ignored a duplicate terminal mutation error already recorded in SQLite.",
          metadata: [
            "mutationID": clientEventID ?? "",
            "errorMessage": error.message,
          ],
          correlationID: clientEventID
        )
        return
      }
      if case .stale = mutationDisposition {
        InstantDiagnostics.shared.record(
          .debug,
          subsystem: "instant-swift-data-core",
          category: "outbox",
          event: "outbox.mutation.server-error-stale-claim",
          message: "Ignored a mutation error after this socket lost its durable delivery claim.",
          metadata: [
            "mutationID": clientEventID ?? "",
            "errorMessage": error.message,
          ],
          correlationID: clientEventID
        )
        return
      }
      if let clientEventID,
        case let .owned(claimToken) = mutationDisposition
      {
        if Self.isRetryableMutationError(error) {
          _ = try await releaseAutomaticOutboxClaimsForDisconnectedSession()
          InstantDiagnostics.shared.record(
            .warning,
            subsystem: "instant-swift-data-core",
            category: "outbox",
            event: "outbox.mutation.server-error-retryable",
            message: "Server returned a retryable error for an outbox mutation.",
            metadata: [
              "mutationID": clientEventID,
              "errorMessage": error.message,
              "serverStatus": error.status.map(String.init) ?? "",
              "serverType": error.type ?? "",
              "serverTraceID": error.traceID ?? "",
            ],
            correlationID: clientEventID
          )
          throw InstantError(
            code: .networkFailed,
            operation: "receive retryable Instant live mutation error",
            serverEventID: clientEventID,
            serverStatus: error.status,
            serverType: error.type,
            serverHint: error.hint,
            serverTraceID: error.traceID,
            serverOriginalEventTraceID: error.originalEventTraceID,
            message: error.message,
            recovery: "Reconnect and resend the durable pending mutation."
          )
        }
        InstantDiagnostics.shared.record(
          .error,
          subsystem: "instant-swift-data-core",
          category: "outbox",
          event: "outbox.mutation.server-error-terminal",
          message: "Server permanently rejected an outbox mutation.",
          metadata: [
            "mutationID": clientEventID,
            "errorMessage": error.message,
            "serverStatus": error.status.map(String.init) ?? "",
            "serverType": error.type ?? "",
            "serverTraceID": error.traceID ?? "",
            "serverHint": error.hint.map { String(describing: $0) } ?? "",
          ],
          correlationID: clientEventID
        )
        _ = try await failClaimedMutation(
          id: clientEventID,
          failure: Self.mutationFailure(from: error),
          requiredClaimToken: claimToken,
          recordsConnectionFailure: false
        )
        await startLiveMutationDeliveryIfNeeded()
        return
      }
      if await liveSession.retireRejectedStreamReader(
        clientEventID: error.clientEventID?.nilIfEmpty,
        message: error.message
      ) {
        return
      }
      if let originalEvent = error.originalEvent,
        originalEvent.op == "add-query",
        let query = originalEvent.fields["q"]
      {
        let registrationKey = try InstantLiveQueryEncoder.registrationKey(for: query)
        let rejection = InstantError(
          code: Self.isPermissionError(error)
            ? .permissionRejected
            : .validationFailed,
          operation: "run Instant live query",
          serverEventID: originalEvent.clientEventID ?? error.clientEventID,
          serverStatus: error.status,
          serverType: error.type,
          serverHint: error.hint,
          serverTraceID: error.traceID,
          serverOriginalEventTraceID: error.originalEventTraceID,
          message: error.message,
          recovery: "Inspect the rejected query and its Instant permissions without reconnecting the healthy live session."
        )
        if await liveSession.retireRejectedQuery(key: registrationKey) {
          await liveQueryResultState.unload(key: registrationKey)
        }
        await liveQueryAcknowledgements.reject(key: registrationKey, error: rejection)
        InstantDiagnostics.shared.record(
          error: rejection,
          subsystem: "instant-swift-data-core",
          category: "query",
          event: "query.live-rejected",
          message: "Instant rejected one live query without interrupting the shared socket.",
          metadata: ["registrationKey": registrationKey]
        )
        return
      }
      throw InstantError(
        code: .networkFailed,
        operation: "receive Instant live server event",
        serverEventID: error.clientEventID,
        serverStatus: error.status,
        serverType: error.type,
        serverHint: error.hint,
        serverTraceID: error.traceID,
        serverOriginalEventTraceID: error.originalEventTraceID,
        message: error.message,
        recovery: "Inspect the Instant runtime WebSocket event and reconnect."
      )

    case .initOK, .joinRoomOK, .leaveRoomOK, .startStreamOK,
      .streamFlushed, .appendFailed, .other:
      break
    }
  }

  private static func isRetryableMutationError(_ error: InstantLiveErrorMessage) -> Bool {
    let type = error.type?.lowercased() ?? ""
    if isPermissionError(error) {
      return false
    }
    if let status = error.status,
      status == 408 || status == 425 || status == 429 || (500...599).contains(status)
    {
      return true
    }
    if type.contains("timeout")
      || type.contains("network")
      || type.contains("service-unavailable")
      || type.contains("temporarily-unavailable")
    {
      return true
    }
    return isRetryableMutationFailureMessage(error.message)
  }

  private static func isPermissionError(_ error: InstantLiveErrorMessage) -> Bool {
    let type = error.type?.lowercased() ?? ""
    let message = error.message.lowercased()
    if error.status == 401 || error.status == 403 {
      return true
    }
    if let status = error.status, (500...599).contains(status) {
      return false
    }
    if type.contains("permission")
      || type.contains("unauthorized")
      || type.contains("forbidden")
    {
      return true
    }
    return message.contains("permission denied")
      || message.contains("not permitted")
      || message.contains("unauthorized")
      || message.contains("forbidden")
  }

  private static func isRetryableMutationFailureMessage(_ rawMessage: String) -> Bool {
    InstantAutomaticFailedMutationRetryPolicy
      .isIndependentlyRetryableFailureMessage(rawMessage)
  }

  private static func mutationFailure(
    from error: InstantLiveErrorMessage
  ) -> InstantMutationFailure {
    let code: InstantError.Code =
      if isPermissionError(error) {
        .permissionRejected
      } else {
        .validationFailed
      }
    return InstantMutationFailure(
      code: code,
      message: error.message,
      status: error.status,
      type: error.type,
      hint: error.hint,
      traceID: error.traceID,
      originalEventTraceID: error.originalEventTraceID
    )
  }

  /// Retries at most one bounded failed-mutation window, then releases the
  /// operation gate so delivery and local writes can make progress.
  ///
  /// `nil` means the exact row proof lost a race and the pump should reload a
  /// fresh window after yielding. A non-nil result says whether another
  /// eligible window remains.
  private func retryOnePersistedTransientMutationFailureWindow() async throws -> Bool? {
    try await enterOperationGateUnlessCancelled(
      operation: "retry one persisted transient mutation failure window"
    )
    do {
      let reservedMutationIDs = await automaticMutationRetryReservations.snapshot()
      recordActorHop(.persistence)
      guard let application = try await persistence.retryAutomaticFailedMutationWindow(
        after: nil,
        excludingMutationIDs: reservedMutationIDs
      ) else {
        await leaveOperationGate()
        return nil
      }

      recordActorHop(.outbox)
      for mutation in application.retriedMutations {
        await outbox.replaceIfPresent(mutation)
      }
      for mutation in application.isolatedMutations {
        await outbox.replaceIfPresent(mutation)
      }
      for mutation in application.quarantinedMutations {
        await outbox.replaceIfPresent(mutation)
      }
      _ = try? await publishConnectionStatusWithGateHeld()
      await leaveOperationGate()
      return application.hasMoreCandidates
    } catch {
      await leaveOperationGate()
      throw error
    }
  }

  private func applyLiveStreamAppend(_ append: InstantLiveStreamAppend) async throws -> Int64 {
    var current = try await persistence.loadStreamContent(
      appID: configuration.appID,
      streamID: append.streamID,
      byteOffset: 0
    )
    if current == nil {
      let userID = try await resolvedAuthenticatedUserID(
        operation: "bootstrap stream metadata",
        noun: "Stream"
      )
      _ = try await persistence.ensureStreamMetadata(
        appID: configuration.appID,
        streamID: append.streamID,
        clientID: append.clientID?.nilIfEmpty ?? append.streamID,
        userID: userID,
        createdAt: configuration.now()
      )
      current = try await persistence.loadStreamContent(
        appID: configuration.appID,
        streamID: append.streamID,
        byteOffset: 0
      )
    }
    guard let current else {
      throw InstantError(
        code: .persistenceFailed,
        operation: "bootstrap stream metadata",
        serverEventID: append.clientEventID,
        message: "Instant stream '\(append.streamID)' was not readable after metadata bootstrap.",
        recovery: "Inspect the local stream persistence transaction and retry the subscription."
      )
    }
    let seenOffset = current.byteOffset + current.byteCount
    let materialization = try await InstantStreamFileAppendMaterializer.materialize(
      append,
      seenOffset: seenOffset,
      transport: streamFileTransport
    )

    if !materialization.data.isEmpty {
      guard let content = String(data: materialization.data, encoding: .utf8) else {
        throw InstantError(
          code: .decodeFailed,
          operation: "materialize Instant stream append",
          path: "content",
          serverEventID: append.clientEventID,
          message: "Instant stream file content is not valid UTF-8.",
          recovery: "Reconnect from a server-confirmed UTF-8 byte boundary."
        )
      }
      _ = try await appendStreamContent(
        streamID: append.streamID,
        content: content,
        expectedOffset: seenOffset
      )
    }
    if append.done {
      _ = try await closeStream(
        streamID: append.streamID,
        abortReason: append.abortReason
      )
    }
    return materialization.nextSeenOffset
  }

  private func applyLivePresenceRefresh(
    _ refresh: InstantLivePresenceRefresh
  ) async throws {
    guard let room = await liveSession.roomHandle(id: refresh.roomID) else { return }
    let remoteMembers = await liveRoomPresenceState.replace(
      room: room,
      sessions: refresh.sessions,
      excludingSessionID: await liveSession.currentSessionID,
      appID: configuration.appID,
      updatedAt: configuration.now()
    )
    let localMembers = try await persistence.loadRoomPresence(
      appID: configuration.appID,
      room: room
    )
    let activeLocalMembers = await activeRoomPresenceState.activeMembers(
      localMembers,
      in: room
    )
    let observerCount = await roomPresenceObservers.activeCount(
      for: roomPresenceObservationKey(room)
    )
    InstantDiagnostics.shared.record(
      .trace,
      subsystem: "instant-swift-data-core",
      category: "presence",
      event: "live-presence.refresh-applied",
      message: "Applied a live room presence refresh.",
      metadata: [
        "roomType": room.type,
        "sessionCount": String(refresh.sessions.count),
        "remoteMemberCount": String(remoteMembers.count),
        "localMemberCount": String(localMembers.count),
        "activeLocalMemberCount": String(activeLocalMembers.count),
        "observerCount": String(observerCount),
      ]
    )
    await roomPresenceObservers.publish(
      mergedRoomPresence(local: activeLocalMembers, remote: remoteMembers),
      for: roomPresenceObservationKey(room)
    )
  }

  private func applyLivePresencePatch(
    _ patch: InstantLivePresencePatch
  ) async throws {
    guard let room = await liveSession.roomHandle(id: patch.roomID) else { return }
    let remoteMembers = try await liveRoomPresenceState.patch(
      room: room,
      edits: patch.edits,
      excludingSessionID: await liveSession.currentSessionID,
      appID: configuration.appID,
      updatedAt: configuration.now()
    )
    let localMembers = try await persistence.loadRoomPresence(
      appID: configuration.appID,
      room: room
    )
    let activeLocalMembers = await activeRoomPresenceState.activeMembers(
      localMembers,
      in: room
    )
    let observerCount = await roomPresenceObservers.activeCount(
      for: roomPresenceObservationKey(room)
    )
    InstantDiagnostics.shared.record(
      .trace,
      subsystem: "instant-swift-data-core",
      category: "presence",
      event: "live-presence.patch-applied",
      message: "Applied a live room presence patch.",
      metadata: [
        "roomType": room.type,
        "editCount": String(patch.edits.count),
        "remoteMemberCount": String(remoteMembers.count),
        "localMemberCount": String(localMembers.count),
        "activeLocalMemberCount": String(activeLocalMembers.count),
        "observerCount": String(observerCount),
      ]
    )
    await roomPresenceObservers.publish(
      mergedRoomPresence(local: activeLocalMembers, remote: remoteMembers),
      for: roomPresenceObservationKey(room)
    )
  }

  private func applyLiveServerBroadcast(
    _ broadcast: InstantLiveServerBroadcast
  ) async throws {
    guard let room = await liveSession.roomHandle(id: broadcast.roomID) else { return }
    guard !broadcast.topic.isEmpty,
      case let .object(envelope)? = broadcast.envelope,
      let rawPayload = envelope["data"]
    else {
      throw InstantError(
        code: .decodeFailed,
        operation: "apply Instant live server broadcast",
        message: "server-broadcast must include room-id, topic, and data.data.",
        recovery: "Inspect the canonical Instant server-broadcast payload."
      )
    }
    let peerID: String
    if case let .string(value)? = envelope["peer-id"] {
      peerID = value
    } else {
      peerID = "unknown-peer"
    }
    let userID: String
    if case let .object(user)? = envelope["user"],
      case let .string(value)? = user["id"]
    {
      userID = value
    } else {
      userID = peerID
    }
    let message = InstantRoomTopicMessage(
      id: broadcast.clientEventID?.nilIfEmpty ?? configuration.makeID(),
      appID: configuration.appID,
      room: room,
      topic: broadcast.topic,
      userID: userID,
      payload: rawPayload.jsonValue,
      createdAt: configuration.now()
    )
    let durableMessages = try await persistence.loadRoomTopicMessages(
      appID: configuration.appID,
      room: room,
      topic: broadcast.topic,
      limit: nil
    )
    await roomTopicObservers.publish(
      durableMessages + [message],
      for: roomTopicObservationKey(room: room, topic: broadcast.topic)
    )
  }

  @discardableResult
  package func sendOutstandingMutationsToLiveSession() async -> Bool {
    guard configuration.liveTransport != nil else { return true }
    let outstanding: InstantAutomaticOutboxTransportSelection
    do {
      outstanding = try await automaticOutboxTransportMutationsForDelivery()
    } catch {
      recordOutboxTransportHydrationFailure(error)
      return false
    }
    do {
      let shouldContinueImmediately = try await deliverAutomaticOutboxSelection(outstanding)
      if shouldContinueImmediately {
        await startLiveMutationDeliveryIfNeeded()
      }
      return true
    } catch {
      if await liveSession.isOpen {
        await scheduleReconnect(
          after: error,
          event: "connection.mutation-delivery-failed",
          message: "Instant could not send durable mutations and will reconnect before retrying."
        )
      }
      return true
    }
  }

  /// Runs one fair pump turn: one bounded retry transition followed by one
  /// bounded delivery claim/send. Returning continuation to the coalescing
  /// pump yields between turns instead of holding the operation gate across a
  /// queue-depth-dependent sweep.
  private func runAutomaticMutationPumpPass()
    async -> InstantRuntimeMutationDeliveryPumpPassResult
  {
    var retryNeedsContinuation = false
    var retryNeedsBackoff = false
    do {
      try Task.checkCancellation()
      if let hasMoreCandidates = try await retryOnePersistedTransientMutationFailureWindow() {
        retryNeedsContinuation = hasMoreCandidates
      } else {
        retryNeedsBackoff = true
      }
    } catch is CancellationError {
      return .finished
    } catch {
      recordFailedMutationRetryWindowFailure(error)
      retryNeedsBackoff = true
    }

    await configuration.onAutomaticMutationPumpRetryWindowCompletedForTesting?()

    let outstanding: InstantAutomaticOutboxTransportSelection
    do {
      try Task.checkCancellation()
      outstanding = try await automaticOutboxTransportMutationsForDelivery()
    } catch is CancellationError {
      return .finished
    } catch {
      recordOutboxTransportHydrationFailure(error)
      return .retryAfterFailure
    }
    do {
      try Task.checkCancellation()
      let deliveryNeedsContinuation = try await deliverAutomaticOutboxSelection(outstanding)
      if retryNeedsBackoff {
        return .retryAfterFailure
      }
      return retryNeedsContinuation || deliveryNeedsContinuation
        ? .continueImmediately
        : .finished
    } catch is CancellationError {
      return .finished
    } catch {
      // A receive-loop failure may close the session between SQLite claim
      // admission and this send. That failure already owns the reconnect;
      // scheduling a second one makes the controller reopen a healthy
      // replacement session again and can strand the retry indefinitely.
      if await liveSession.isOpen {
        await scheduleReconnect(
          after: error,
          event: "connection.mutation-delivery-failed",
          message: "Instant could not send durable mutations and will reconnect before retrying."
        )
      }
      return .finished
    }
  }

  private func deliverAutomaticOutboxSelection(
    _ selection: InstantAutomaticOutboxTransportSelection
  ) async throws -> Bool {
    try Task.checkCancellation()
    var encodingAttributeRevision: Int64?
    if !selection.mutations.isEmpty {
      recordActorHop(.persistence)
      encodingAttributeRevision = try await persistence.currentAttributeRevision()
    }
    recordActorHop(.liveSession)
    await liveSession.releaseMutationReservations(
      selection.reclaimedMutationIDs,
      timedOut: !selection.reclaimedMutationIDs.isEmpty
    )
    let encodingFailures: [InstantLiveMutationEncodingFailure]
    do {
      encodingFailures = try await liveSession.sendMutations(selection.mutations)
    } catch {
      do {
        _ = try await releaseAutomaticOutboxClaimsForDisconnectedSession()
      } catch is CancellationError {
        throw CancellationError()
      } catch let releaseError {
        InstantDiagnostics.shared.record(
          error: releaseError,
          subsystem: "instant-swift-data-core",
          category: "outbox",
          event: "outbox.mutation.send-failure-claim-release-failed",
          message: "Instant could not release durable claims after a live mutation send failed.",
          metadata: [
            "claimTokenPresent": String(selection.claimToken != nil),
            "claimedMutationCount": String(selection.claimedMutationIDs.count),
          ]
        )
      }
      throw error
    }

    do {
      try await persistLiveMutationEncodingFailures(
        encodingFailures,
        failureAttributeRevision: encodingAttributeRevision,
        claimToken: selection.claimToken
      )
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      reportIssue(
        """
        Instant could not record \(encodingFailures.count) quarantined mutation(s), but the connection stays open.

        \(String(describing: error))
        """
      )
    }
    await scheduleLiveMutationDeadlineWake(at: selection.nextClaimDeadlineMilliseconds)
    return selection.shouldContinueImmediately || !encodingFailures.isEmpty
  }

  private func persistLiveMutationEncodingFailures(
    _ failures: [InstantLiveMutationEncodingFailure],
    failureAttributeRevision: Int64?,
    claimToken: String?
  ) async throws {
    guard !failures.isEmpty else { return }
    guard let failureAttributeRevision else {
      throw InstantError(
        code: .persistenceFailed,
        operation: "record live mutation encoding failures",
        message: "Encoding failures did not carry the durable attribute revision they used.",
        recovery: "Retry automatic delivery so the mutation can be classified against a durable schema revision."
      )
    }
    guard let claimToken else {
      throw InstantError(
        code: .persistenceFailed,
        operation: "record live mutation encoding failures",
        message: "Encoding failures did not carry their durable delivery claim token.",
        recovery: "Retry automatic delivery so SQLite can claim the rows again."
      )
    }
    let failuresByMutationID = Dictionary(
      failures.map {
        (
          $0.mutationID,
          InstantMutationFailure(code: .validationFailed, message: $0.message)
        )
      },
      uniquingKeysWith: { _, newest in newest }
    )
    try await enterOperationGateUnlessCancelled(
      operation: "persist live mutation encoding failures"
    )
    do {
      for _ in 0..<5 {
        recordActorHop(.persistence)
        let outboxRevision = try await persistence.currentOutboxRevision()
        guard let application = try await persistence.failOutboxMutationsForDelivery(
          failuresByMutationID,
          failureAttributeRevision: failureAttributeRevision,
          claimToken: claimToken,
          expectedOutboxRevision: outboxRevision
        ) else { continue }
        recordActorHop(.outbox)
        for mutation in application.mutations {
          await publishMutationLifecycle(mutation)
          await outbox.remove(id: mutation.id)
        }
        _ = try? await publishConnectionStatusWithGateHeld()
        await leaveOperationGate()
        return
      }
      throw outboxChangedDuringTransportHydration()
    } catch {
      await leaveOperationGate()
      throw error
    }
  }

  private static func liveObservation<Element: Sendable>(
    _ source: AsyncStream<Element>,
    onTermination: @escaping @Sendable () async -> Void
  ) -> AsyncStream<Element> {
    liveObservationLease(source, onTermination: onTermination).stream
  }

  private static func queryObservationLease(
    _ observation: InstantLiveInfiniteQueryChunkObservationLease<InstantQueryEmission>
  ) -> InstantQueryObservationLease {
    InstantQueryObservationLease(
      stream: observation.stream,
      cancel: observation.cancel
    )
  }

  private static func finishedQueryObservationLease() -> InstantQueryObservationLease {
    .finished()
  }

  private static func liveObservationLease<Element: Sendable>(
    _ source: AsyncStream<Element>,
    onTermination: @escaping @Sendable () async -> Void
  ) -> InstantLiveInfiniteQueryChunkObservationLease<Element> {
    let output = AsyncStream<Element>.makeStream(
      bufferingPolicy: .bufferingNewest(1)
    )
    let task = Task {
      for await emission in source {
        output.continuation.yield(emission)
      }
      output.continuation.finish()
    }
    let termination = InstantLiveObservationTermination(onTermination)
    output.continuation.onTermination = { @Sendable _ in
      task.cancel()
      Task {
        await termination.run()
        await task.value
      }
    }
    return InstantLiveInfiniteQueryChunkObservationLease(
      stream: output.stream,
      cancel: {
        task.cancel()
        output.continuation.finish()
        await termination.run()
        await task.value
      }
    )
  }

  private func connectionState(
    _ state: InstantConnectionState,
    isAuthenticated: Bool,
    liveSessionIsOpen: Bool
  ) -> InstantConnectionState {
    switch state {
    case .opened, .authenticated:
      if configuration.liveTransport != nil, !liveSessionIsOpen {
        return .closed
      }
      return isAuthenticated ? .authenticated : .opened
    case .connecting, .closed, .errored:
      return state
    }
  }

  public func authSession() async throws -> InstantAuthSession? {
    try await persistence.loadAuthSession(key: authSessionKey)
  }

  @discardableResult
  public func syncUserCookieToEndpoint(
    _ session: InstantAuthSession?
  ) async throws -> InstantUserCookieSyncRequest? {
    guard let firstPartyURL = configuration.firstPartyURL else { return nil }

    let syncedAt = configuration.now()
    let request = InstantUserCookieSyncRequest(
      appID: configuration.appID,
      firstPartyURL: firstPartyURL,
      user: session.map(InstantUserCookieSyncUser.init),
      syncedAt: syncedAt
    )
    do {
      try await configuration.userCookieSyncClient.sync(request)
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      // Match Instant's Reactor: endpoint failures are logged there, but the
      // local last-sync marker is still advanced to avoid retry loops.
    }
    // A cancellation-insensitive endpoint can return normally after exact
    // close requested stop. Never convert that late return into a metadata
    // write after the runtime has published its closed boundary.
    try Task.checkCancellation()
    recordActorHop(.persistence)
    try await persistence.saveMetadataValue(
      Self.cookieSyncISOString(from: syncedAt),
      key: appScopedCookieSyncLastUpdatedMetadataKey,
      updatedAt: syncedAt
    )
    return request
  }

  private func syncUserCookieOnStartup() async throws {
    guard configuration.firstPartyURL != nil else { return }

    do {
      recordActorHop(.persistence)
      let lastSynced = try await persistence.loadMetadataValue(
        key: appScopedCookieSyncLastUpdatedMetadataKey
      )
      let lastSyncedMilliseconds = lastSynced.flatMap(Self.cookieSyncMilliseconds(from:)) ?? 0
      let now = configuration.now()
      let shouldSync =
        lastSyncedMilliseconds == 0
        || now.milliseconds - lastSyncedMilliseconds >= Self.cookieSyncIntervalMilliseconds
      guard shouldSync else { return }

      recordActorHop(.persistence)
      let session = try await persistence.loadAuthSession(key: authSessionKey)
      _ = try await syncUserCookieToEndpoint(session)
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      // Match Instant's Reactor startup behavior: cookie sync failures are
      // intentionally non-fatal to runtime bootstrap.
    }
  }

  public func observeAuthSession() async throws -> AsyncStream<InstantAuthSession?> {
    await operationGate.enter()
    do {
      let session = try await persistence.loadAuthSession(key: authSessionKey)
      let stream = await authSessionObservers.observe(current: session)
      await operationGate.leave()
      return stream
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  public func signInAsGuest() async throws -> InstantAuthSession {
    let startedAt = Date()
    InstantDiagnostics.shared.record(
      .info,
      subsystem: "instant-swift-data-core",
      category: "auth",
      event: "guest-auth.started",
      message: "Starting Instant guest authentication.",
      metadata: ["appID": configuration.appID]
    )
    do {
      let now = configuration.now()
      let verification = try await configuration.guestAuthenticator.signIn(
        InstantGuestAuthRequest(
          appID: configuration.appID,
          apiURI: configuration.apiURI,
          signedInAt: now,
          makeID: configuration.makeID
        )
      )
      let session = InstantAuthSession(
        appID: configuration.appID,
        userID: verification.userID,
        refreshToken: verification.refreshToken,
        isGuest: true,
        createdAt: now,
        updatedAt: now,
        email: verification.email,
        imageURL: verification.imageURL,
        type: verification.type ?? .guest
      )
      _ = try await saveGuestUserFields(userID: session.userID, signedInAt: now)
      try await saveAuthSession(session)
      InstantDiagnostics.shared.record(
        .notice,
        subsystem: "instant-swift-data-core",
        category: "auth",
        event: "guest-auth.completed",
        message: "Instant guest authentication completed.",
        metadata: [
          "appID": configuration.appID,
          "userID": session.userID,
          "hasRefreshToken": String(session.refreshToken?.isEmpty == false),
          "durationMilliseconds": String(
            Int64((Date().timeIntervalSince(startedAt) * 1_000).rounded())
          ),
        ]
      )
      return session
    } catch {
      InstantDiagnostics.shared.record(
        error: error,
        subsystem: "instant-swift-data-core",
        category: "auth",
        event: "guest-auth.failed",
        message: "Instant guest authentication failed.",
        metadata: [
          "appID": configuration.appID,
          "durationMilliseconds": String(
            Int64((Date().timeIntervalSince(startedAt) * 1_000).rounded())
          ),
        ]
      )
      throw error
    }
  }

  public func sendMagicCode(email rawEmail: String) async throws -> InstantMagicCodeChallenge {
    let email = try normalizedEmail(rawEmail, operation: "send magic code")
    let now = configuration.now()
    let challenge = try await configuration.magicCodeExchange.send(
      InstantMagicCodeSendRequest(
        appID: configuration.appID,
        apiURI: configuration.apiURI,
        email: email,
        sentAt: now,
        makeID: configuration.makeID
      )
    )

    await operationGate.enter()
    do {
      try await persistence.saveMagicCodeChallenge(challenge, key: magicCodeChallengeKey(email: email))
      await operationGate.leave()
      return challenge
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  public func signInWithMagicCode(
    email rawEmail: String,
    code rawCode: String
  ) async throws -> InstantAuthSession {
    try await signInWithMagicCodeResult(email: rawEmail, code: rawCode).session
  }

  public func signInWithMagicCodeResult(
    email rawEmail: String,
    code rawCode: String,
    extraFields: [String: InstantValue] = [:]
  ) async throws -> InstantMagicCodeSignInResult {
    let email = try normalizedEmail(rawEmail, operation: "sign in with magic code")
    let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !code.isEmpty else {
      throw authValidationFailed(
        operation: "sign in with magic code",
        message: "Magic code must not be empty.",
        recovery: "Run 'instant-swift-data auth magic-code send <email>' and enter the returned local verification code."
      )
    }
    let extraFields = try validatedMagicCodeExtraFields(extraFields)

    await operationGate.enter()
    do {
      let key = magicCodeChallengeKey(email: email)
      guard let challenge = try await persistence.loadMagicCodeChallenge(key: key) else {
        throw authValidationFailed(
          operation: "sign in with magic code",
          message: "No pending magic code exists for '\(email)'.",
          recovery: "Run 'instant-swift-data auth magic-code send \(email)' before verifying."
        )
      }
      recordActorHop(.persistence)
      let stateBeforeVerification = try await loadCompactStateSynchronizingStore()
      try validateMagicCodeExtraFieldsSchema(
        extraFields,
        state: stateBeforeVerification
      )
      let now = configuration.now()
      let currentRefreshToken = try await persistence.loadAuthSession(key: authSessionKey)?
        .refreshToken
      let verification = try await configuration.magicCodeExchange.verify(
        InstantMagicCodeVerifyRequest(
          appID: configuration.appID,
          apiURI: configuration.apiURI,
          email: email,
          code: code,
          challenge: challenge,
          refreshToken: currentRefreshToken,
          extraFields: extraFields,
          verifiedAt: now
        )
      )
      let session = InstantAuthSession(
        appID: configuration.appID,
        userID: verification.userID,
        refreshToken: verification.refreshToken,
        isGuest: false,
        createdAt: now,
        updatedAt: now,
        email: verification.email ?? email,
        imageURL: verification.imageURL,
        type: verification.type ?? .user
      )
      let locallyCreated = try await saveMagicCodeUserFields(
        userID: session.userID,
        email: email,
        extraFields: extraFields,
        verifiedAt: now
      )
      try await persistence.saveAuthSession(session, key: authSessionKey)
      try await persistence.deleteMagicCodeChallenge(key: key)
      await authSessionObservers.yield(session)
      _ = try? await publishConnectionStatusWithGateHeld()
      await operationGate.leave()
      await reconnectAfterAuthChangeIfNeeded()
      _ = try? await syncUserCookieToEndpoint(session)
      return InstantMagicCodeSignInResult(
        session: session,
        created: verification.created ?? locallyCreated
      )
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  private func saveMagicCodeUserFields(
    userID: String,
    email: String,
    extraFields: [String: InstantValue],
    verifiedAt: InstantTimestamp
  ) async throws -> Bool {
    recordActorHop(.persistence)
    let state = try await loadCompactStateSynchronizingStore()
    let attributes = AttributeStore(attributes: state.snapshot.store.attributes)
    let canWriteUsers =
      attributes.namespaces.isEmpty || attributes.namespaces.contains(Self.authUsersNamespace)
    guard canWriteUsers else {
      guard extraFields.isEmpty else {
        throw validationFailed(
          operation: "sign in with magic code",
          namespace: Self.authUsersNamespace,
          message:
            "Cannot write magic-code extra fields because the '$users' namespace is not declared in the local schema.",
          recovery:
            "Declare '$users' attributes before signing in with magic-code extra fields, or omit extra fields for this schema."
        )
      }
      return false
    }

    let authStoreSnapshot = await authoritativeStoreSnapshot(from: state)
    let userExists = authStoreSnapshot.triples.contains { triple in
      triple.entityID == userID && triple.attributeID.hasPrefix(Self.authUsersNamespace + "/")
    }
    guard !userExists else { return false }

    let transactionID = "auth.magic-code.\(configuration.makeID())"
    var operations: [InstantTripleOperation] = [
      .requireEntityMissing(entityID: userID, namespace: Self.authUsersNamespace),
      .insert(
        InstantTriple(
          entityID: userID,
          attributeID: InstantAttribute.primaryKeyID(namespace: Self.authUsersNamespace),
          value: .string(userID),
          txID: transactionID,
          txTime: verifiedAt
        )
      ),
      .insert(
        InstantTriple(
          entityID: userID,
          attributeID: "\(Self.authUsersNamespace)/email",
          value: .string(email),
          txID: transactionID,
          txTime: verifiedAt
        )
      ),
    ]
    for (field, value) in extraFields.sorted(by: { $0.key < $1.key }) {
      operations.append(
        .insert(
          InstantTriple(
            entityID: userID,
            attributeID: "\(Self.authUsersNamespace)/\(field)",
            value: value,
            txID: transactionID,
            txTime: verifiedAt
          )
        )
      )
    }

    _ = try await performApplyServerTransaction(
      InstantStoreTransaction(id: transactionID, operations: operations),
      processedTransactionID: transactionID,
      receivedAt: verifiedAt
    )
    return !userExists
  }

  private func saveGuestUserFields(
    userID: String,
    signedInAt: InstantTimestamp
  ) async throws -> Bool {
    recordActorHop(.persistence)
    let state = try await loadCompactStateSynchronizingStore()
    let attributes = AttributeStore(attributes: state.snapshot.store.attributes)
    let canWriteUsers =
      attributes.namespaces.isEmpty || attributes.namespaces.contains(Self.authUsersNamespace)
    guard canWriteUsers else { return false }

    let authStoreSnapshot = await authoritativeStoreSnapshot(from: state)
    let userExists = authStoreSnapshot.triples.contains { triple in
      triple.entityID == userID && triple.attributeID.hasPrefix(Self.authUsersNamespace + "/")
    }
    guard !userExists else { return false }

    let transactionID = "auth.guest.\(configuration.makeID())"
    _ = try await performApplyServerTransaction(
      InstantStoreTransaction(
        id: transactionID,
        operations: [
          .requireEntityMissing(entityID: userID, namespace: Self.authUsersNamespace),
          .insert(
            InstantTriple(
              entityID: userID,
              attributeID: InstantAttribute.primaryKeyID(namespace: Self.authUsersNamespace),
              value: .string(userID),
              txID: transactionID,
              txTime: signedInAt
            )
          ),
        ]
      ),
      processedTransactionID: transactionID,
      receivedAt: signedInAt
    )
    return true
  }

  private func validateMagicCodeExtraFieldsSchema(
    _ extraFields: [String: InstantValue],
    state: InstantPersistenceState
  ) throws {
    guard !extraFields.isEmpty else { return }
    let attributes = AttributeStore(attributes: state.snapshot.store.attributes)
    guard
      attributes.namespaces.isEmpty
        || attributes.namespaces.contains(Self.authUsersNamespace)
    else {
      throw validationFailed(
        operation: "sign in with magic code",
        namespace: Self.authUsersNamespace,
        message:
          "Cannot write magic-code extra fields because the '$users' namespace is not declared in the local schema.",
        recovery:
          "Declare '$users' attributes before signing in with magic-code extra fields, or omit extra fields for this schema."
      )
    }
  }

  private func validatedMagicCodeExtraFields(
    _ extraFields: [String: InstantValue]
  ) throws -> [String: InstantValue] {
    var validated: [String: InstantValue] = [:]
    for (rawField, value) in extraFields {
      let field = rawField.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !field.isEmpty else {
        throw validationFailed(
          operation: "sign in with magic code",
          message: "Magic-code extra field names must not be empty.",
          recovery: "Remove empty extra-field names before signing in."
        )
      }
      guard !field.contains("/") else {
        throw validationFailed(
          operation: "sign in with magic code",
          path: field,
          message: "Magic-code extra field names must not contain '/'.",
          recovery: "Pass field names such as 'username' or 'displayName', not attribute ids."
        )
      }
      guard field != "id", field != "email" else {
        throw validationFailed(
          operation: "sign in with magic code",
          path: field,
          message: "Magic-code extra fields cannot override the managed '\(field)' field.",
          recovery: "Let Instant Swift Data derive the user id and verified email from the auth response."
        )
      }
      switch value {
      case .ref, .lookupRef:
        throw validationFailed(
          operation: "sign in with magic code",
          path: field,
          message: "Magic-code extra fields cannot contain ref values.",
          recovery: "Use JSON-compatible scalar, date, null, or object values for auth extra fields."
        )
      case .null, .string, .number, .bool, .date, .json:
        validated[field] = value
      }
    }
    return validated
  }

  public func signInWithRefreshToken(
    _ refreshToken: String,
    userID: String? = nil
  ) async throws -> InstantAuthSession {
    let token = refreshToken.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !token.isEmpty else {
      throw authValidationFailed(
        operation: "sign in with token",
        message: "Refresh token must not be empty.",
        recovery: "Pass a refresh token, or use 'instant-swift-data auth guest'."
      )
    }

    let now = configuration.now()
    let trimmedUserID = userID?.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedUserID: String?
    if let trimmedUserID, !trimmedUserID.isEmpty {
      normalizedUserID = trimmedUserID
    } else {
      normalizedUserID = nil
    }
    let verification = try await configuration.refreshTokenVerifier.verify(
      InstantRefreshTokenVerificationRequest(
        appID: configuration.appID,
        apiURI: configuration.apiURI,
        refreshToken: token,
        userID: normalizedUserID,
        signedInAt: now,
        makeID: configuration.makeID
      )
    )
    let session = InstantAuthSession(
      appID: configuration.appID,
      userID: verification.userID,
      refreshToken: verification.refreshToken,
      isGuest: verification.type == .guest,
      createdAt: now,
      updatedAt: now,
      email: verification.email,
      imageURL: verification.imageURL,
      type: verification.type
    )
    try await saveAuthSession(session)
    return session
  }

  public func signInWithIDToken(
    clientName rawClientName: String,
    idToken rawIDToken: String,
    nonce rawNonce: String? = nil
  ) async throws -> InstantAuthSession {
    let clientName = rawClientName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clientName.isEmpty else {
      throw authValidationFailed(
        operation: "sign in with id token",
        message: "Client name must not be empty.",
        recovery: "Pass the Instant OAuth client name, for example 'google-ios'."
      )
    }
    let idToken = rawIDToken.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !idToken.isEmpty else {
      throw authValidationFailed(
        operation: "sign in with id token",
        message: "ID token must not be empty.",
        recovery: "Pass the ID token returned by the native OAuth provider."
      )
    }
    let now = configuration.now()
    let refreshToken = try await authSession()?.refreshToken
    let verification = try await configuration.idTokenExchange.signIn(
      InstantIDTokenSignInRequest(
        appID: configuration.appID,
        apiURI: configuration.apiURI,
        clientName: clientName,
        idToken: idToken,
        nonce: rawNonce,
        refreshToken: refreshToken,
        signedInAt: now,
        makeID: configuration.makeID
      )
    )
    let session = InstantAuthSession(
      appID: configuration.appID,
      userID: verification.userID,
      refreshToken: verification.refreshToken,
      isGuest: false,
      createdAt: now,
      updatedAt: now,
      email: verification.email,
      imageURL: verification.imageURL,
      type: verification.type ?? .user
    )
    try await saveAuthSession(session)
    return session
  }

  public func promoteGuestWithIDToken(
    clientName rawClientName: String,
    idToken rawIDToken: String,
    nonce rawNonce: String? = nil
  ) async throws -> InstantGuestPromotionExchangeResult {
    let clientName = rawClientName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clientName.isEmpty else {
      throw authValidationFailed(
        operation: "promote guest with id token",
        message: "Client name must not be empty.",
        recovery: "Pass the Instant OAuth client name, for example 'apple'."
      )
    }
    let idToken = rawIDToken.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !idToken.isEmpty else {
      throw authValidationFailed(
        operation: "promote guest with id token",
        message: "ID token must not be empty.",
        recovery: "Pass the ID token returned by the native OAuth provider."
      )
    }

    await authPromotionGate.enter()
    do {
      try Task.checkCancellation()
      let guest = try await guestPromotionSnapshot()
      let now = configuration.now()
      let verification = try await configuration.idTokenExchange.signIn(
        InstantIDTokenSignInRequest(
          appID: configuration.appID,
          apiURI: configuration.apiURI,
          clientName: clientName,
          idToken: idToken,
          nonce: rawNonce,
          refreshToken: guest.refreshToken,
          signedInAt: now,
          makeID: configuration.makeID
        )
      )
      let session = promotedAuthSession(
        userID: verification.userID,
        refreshToken: verification.refreshToken,
        email: verification.email,
        imageURL: verification.imageURL,
        type: verification.type,
        timestamp: now
      )
      let result = try await commitGuestPromotion(
        guest: guest.session,
        promoted: session,
        linkEvidence: verification.guestPromotionLinkEvidence
      )
      await authPromotionGate.leave()
      return result
    } catch {
      await authPromotionGate.leave()
      throw error
    }
  }

  public func signInWithOAuth(
    code rawCode: String,
    codeVerifier rawCodeVerifier: String? = nil
  ) async throws -> InstantAuthSession {
    let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !code.isEmpty else {
      throw authValidationFailed(
        operation: "sign in with oauth",
        message: "OAuth authorization code must not be empty.",
        recovery: "Pass the authorization code returned by the OAuth callback."
      )
    }

    let now = configuration.now()
    // Match Instant's transport shape: pass the current refresh token so a live
    // OAuth exchange can upgrade/link the existing session when supported.
    let refreshToken = try await authSession()?.refreshToken
    let verification = try await configuration.oauthExchange.signIn(
      InstantOAuthSignInRequest(
        appID: configuration.appID,
        apiURI: configuration.apiURI,
        code: code,
        codeVerifier: rawCodeVerifier,
        refreshToken: refreshToken,
        signedInAt: now,
        makeID: configuration.makeID
      )
    )
    let session = InstantAuthSession(
      appID: configuration.appID,
      userID: verification.userID,
      refreshToken: verification.refreshToken,
      isGuest: false,
      createdAt: now,
      updatedAt: now,
      email: verification.email,
      imageURL: verification.imageURL,
      type: verification.type ?? .user
    )
    try await saveAuthSession(session)
    return session
  }

  public func promoteGuestWithOAuth(
    code rawCode: String,
    codeVerifier rawCodeVerifier: String? = nil
  ) async throws -> InstantGuestPromotionExchangeResult {
    let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !code.isEmpty else {
      throw authValidationFailed(
        operation: "promote guest with oauth",
        message: "OAuth authorization code must not be empty.",
        recovery: "Pass the authorization code returned by the OAuth callback."
      )
    }

    await authPromotionGate.enter()
    do {
      try Task.checkCancellation()
      let guest = try await guestPromotionSnapshot()
      let now = configuration.now()
      let verification = try await configuration.oauthExchange.signIn(
        InstantOAuthSignInRequest(
          appID: configuration.appID,
          apiURI: configuration.apiURI,
          code: code,
          codeVerifier: rawCodeVerifier,
          refreshToken: guest.refreshToken,
          signedInAt: now,
          makeID: configuration.makeID
        )
      )
      let session = promotedAuthSession(
        userID: verification.userID,
        refreshToken: verification.refreshToken,
        email: verification.email,
        imageURL: verification.imageURL,
        type: verification.type,
        timestamp: now
      )
      let result = try await commitGuestPromotion(
        guest: guest.session,
        promoted: session,
        linkEvidence: verification.guestPromotionLinkEvidence
      )
      await authPromotionGate.leave()
      return result
    } catch {
      await authPromotionGate.leave()
      throw error
    }
  }

  private func guestPromotionSnapshot() async throws -> (
    session: InstantAuthSession,
    refreshToken: String
  ) {
    guard let session = try await authSession(), session.isGuest else {
      throw InstantError(
        code: .authFailed,
        operation: "promote guest account",
        message: "Guest promotion requires an active guest session.",
        recovery:
          "Sign in as a guest first, then exchange the provider credential without signing out."
      )
    }
    guard
      let refreshToken = session.refreshToken?.trimmingCharacters(in: .whitespacesAndNewlines),
      !refreshToken.isEmpty
    else {
      throw InstantError(
        code: .authFailed,
        operation: "promote guest account",
        message: "The active guest session has no refresh token to link during provider exchange.",
        recovery: "Create a fresh online guest session before connecting an auth provider."
      )
    }
    return (session, refreshToken)
  }

  private func promotedAuthSession(
    userID: String,
    refreshToken: String?,
    email: String?,
    imageURL: String?,
    type: InstantAuthUserType?,
    timestamp: InstantTimestamp
  ) -> InstantAuthSession {
    InstantAuthSession(
      appID: configuration.appID,
      userID: userID,
      refreshToken: refreshToken,
      isGuest: false,
      createdAt: timestamp,
      updatedAt: timestamp,
      email: email,
      imageURL: imageURL,
      type: type ?? .user
    )
  }

  private func commitGuestPromotion(
    guest: InstantAuthSession,
    promoted: InstantAuthSession,
    linkEvidence: InstantGuestPromotionLinkEvidence?
  ) async throws -> InstantGuestPromotionExchangeResult {
    // The provider exchange has already succeeded and may have consumed a one-time credential.
    // Cancellation can suppress stale UI callbacks, but it must not discard this server result.
    await operationGate.enter()
    do {
      let current = try await persistence.loadAuthSession(key: authSessionKey)
      guard current == guest else {
        let error = InstantError(
          code: .authFailed,
          operation: "promote guest account",
          message:
            "Provider exchange succeeded, but the local auth session changed before promotion could be committed.",
          recovery:
            "Keep the current session and reconcile it with Instant before retrying; the provider credential may already be consumed."
        )
        InstantDiagnostics.shared.record(
          error: error,
          subsystem: "instant-swift-data-core",
          category: "auth",
          event: "guest-promotion.compare-and-swap-diverged",
          message: "Refused to overwrite auth after a successful guest-promotion exchange.",
          metadata: [
            "guestUserID": guest.userID,
            "promotedUserID": promoted.userID,
            "currentUserID": current?.userID ?? "signed-out",
            "currentIsGuest": current.map { String($0.isGuest) } ?? "none",
          ]
        )
        throw error
      }
      try await persistAuthSessionWithGateHeld(promoted)
      await operationGate.leave()
    } catch {
      await operationGate.leave()
      throw error
    }

    recordPersistedAuthSession(promoted)
    await reconnectAfterAuthChangeIfNeeded()
    _ = try? await syncUserCookieToEndpoint(promoted)

    let disposition: InstantGuestPromotionExchangeDisposition
    if promoted.userID == guest.userID {
      disposition = .upgradedInPlace
    } else if linkEvidence == .instantServerAcceptedGuestToken {
      disposition = .linkedToExistingUser
    } else {
      disposition = .identityChangedWithoutVerifiedLink
    }
    return InstantGuestPromotionExchangeResult(
      guestUserID: guest.userID,
      session: promoted,
      disposition: disposition
    )
  }

  public func oauthAuthorizationURL(
    clientName rawClientName: String,
    redirectURL: URL
  ) throws -> URL {
    let clientName = rawClientName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clientName.isEmpty else {
      throw authValidationFailed(
        operation: "create oauth authorization URL",
        message: "OAuth client name must not be empty.",
        recovery: "Pass the Instant OAuth client name, for example 'google'."
      )
    }
    guard redirectURL.scheme?.isEmpty == false else {
      throw authValidationFailed(
        operation: "create oauth authorization URL",
        message: "OAuth redirect URL must be absolute.",
        recovery: "Pass the redirect URL registered with the OAuth client."
      )
    }

    var components = try endpointComponents(path: ["runtime", "oauth", "start"])
    components.queryItems = [
      URLQueryItem(name: "app_id", value: configuration.appID),
      URLQueryItem(name: "client_name", value: clientName),
      URLQueryItem(name: "redirect_uri", value: redirectURL.absoluteString),
    ]
    guard let url = components.url else {
      throw endpointFailed(operation: "create oauth authorization URL")
    }
    return url
  }

  public func issuerURI() throws -> URL {
    var components = try endpointComponents(path: ["runtime", configuration.appID])
    components.queryItems = nil
    guard let url = components.url else {
      throw endpointFailed(operation: "create oauth issuer URI")
    }
    return url
  }

  public func signOut() async throws {
    try await signOut(invalidateToken: true)
  }

  public func signOut(invalidateToken: Bool = true) async throws {
    let signedOutAt = configuration.now()
    var invalidationRequest: InstantAuthTokenInvalidationRequest?
    await operationGate.enter()
    do {
      let session = try await persistence.loadAuthSession(key: authSessionKey)
      if invalidateToken, let refreshToken = session?.refreshToken {
        invalidationRequest = InstantAuthTokenInvalidationRequest(
          appID: configuration.appID,
          apiURI: configuration.apiURI,
          refreshToken: refreshToken,
          signedOutAt: signedOutAt
        )
      }
      try await persistence.deleteAuthSession(key: authSessionKey)
      await authSessionObservers.yield(nil)
      _ = try? await publishConnectionStatusWithGateHeld()
      await operationGate.leave()
    } catch {
      await operationGate.leave()
      throw error
    }

    await reconnectAfterAuthChangeIfNeeded()
    _ = try? await syncUserCookieToEndpoint(nil)

    if let invalidationRequest {
      do {
        try await configuration.authTokenInvalidator.invalidate(invalidationRequest)
      } catch {
        // Match Instant's client: failed token invalidation must not undo local sign-out.
      }
    }
  }

  public func joinRoom(_ room: InstantRoomHandle = .default) async throws -> InstantRoomHandle {
    let room = try validatedRoom(room, operation: "join room")
    if configuration.liveTransport != nil {
      try await liveSession.joinRoom(room, clientEventID: configuration.makeID())
    }
    return room
  }

  public func leaveRoom(_ room: InstantRoomHandle = .default) async throws -> InstantRoomHandle {
    let room = try validatedRoom(room, operation: "leave room")
    if configuration.liveTransport != nil {
      try await liveSession.leaveRoom(room, clientEventID: configuration.makeID())
      await liveRoomPresenceState.remove(room: room)
      await activeRoomPresenceState.removeAll(in: room)
    }
    return room
  }

  @discardableResult
  public func setPresence(
    room: InstantRoomHandle,
    userID: String? = nil,
    values: [String: JSONValue]
  ) async throws -> InstantRoomPresenceMember {
    let room = try validatedRoom(room, operation: "set room presence")

    await operationGate.enter()
    do {
      let userID = try await resolvedRoomUserID(userID, operation: "set room presence")
      let now = configuration.now()
      let member = InstantRoomPresenceMember(
        appID: configuration.appID,
        room: room,
        userID: userID,
        values: values,
        updatedAt: now
      )
      try await persistence.saveRoomPresence(member)
      if configuration.liveTransport != nil {
        await activeRoomPresenceState.activate(userID: userID, in: room)
      }
      let localMembers = try await persistence.loadRoomPresence(
        appID: configuration.appID,
        room: room
      )
      let members = await combinedRoomPresence(localMembers, room: room)
      await roomPresenceObservers.publish(
        members,
        for: roomPresenceObservationKey(room)
      )
      if configuration.liveTransport != nil {
        try await liveSession.setPresence(
          room: room,
          values: values,
          clientEventID: configuration.makeID()
        )
      }
      await operationGate.leave()
      return member
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  public func roomPresence(room: InstantRoomHandle) async throws -> [InstantRoomPresenceMember] {
    let room = try validatedRoom(room, operation: "list room presence")
    let localMembers = try await persistence.loadRoomPresence(
      appID: configuration.appID,
      room: room
    )
    return await combinedRoomPresence(localMembers, room: room)
  }

  public func observeRoomPresence(room: InstantRoomHandle) async throws
    -> AsyncStream<[InstantRoomPresenceMember]>
  {
    let room = try validatedRoom(room, operation: "observe room presence")

    await operationGate.enter()
    do {
      let localMembers = try await persistence.loadRoomPresence(
        appID: configuration.appID,
        room: room
      )
      let members = await combinedRoomPresence(localMembers, room: room)
      let stream = await roomPresenceObservers.observe(
        key: roomPresenceObservationKey(room),
        current: members
      )
      await operationGate.leave()
      return stream
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  public func leavePresence(room: InstantRoomHandle, userID: String? = nil) async throws -> String {
    let room = try validatedRoom(room, operation: "leave room presence")

    await operationGate.enter()
    do {
      let userID = try await resolvedRoomUserID(userID, operation: "leave room presence")
      try await persistence.deleteRoomPresence(
        appID: configuration.appID,
        room: room,
        userID: userID
      )
      if configuration.liveTransport != nil {
        await activeRoomPresenceState.deactivate(userID: userID, in: room)
      }
      let localMembers = try await persistence.loadRoomPresence(
        appID: configuration.appID,
        room: room
      )
      let members = await combinedRoomPresence(localMembers, room: room)
      await roomPresenceObservers.publish(
        members,
        for: roomPresenceObservationKey(room)
      )
      await operationGate.leave()
      return userID
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  func activeRoomPresenceObservationCount(room: InstantRoomHandle) async throws -> Int {
    let room = try validatedRoom(room, operation: "inspect room presence observers")
    return await roomPresenceObservers.activeCount(for: roomPresenceObservationKey(room))
  }

  @discardableResult
  public func publishTopicMessage(
    room: InstantRoomHandle,
    topic rawTopic: String,
    userID: String? = nil,
    payload: JSONValue
  ) async throws -> InstantRoomTopicMessage {
    let room = try validatedRoom(room, operation: "publish room topic")
    let topic = try validatedNonEmpty(
      rawTopic,
      label: "Topic",
      operation: "publish room topic",
      recovery: "Pass the room topic name to publish."
    )

    await operationGate.enter()
    do {
      let userID = try await resolvedRoomUserID(userID, operation: "publish room topic")
      let message = InstantRoomTopicMessage(
        id: configuration.makeID(),
        appID: configuration.appID,
        room: room,
        topic: topic,
        userID: userID,
        payload: payload,
        createdAt: configuration.now()
      )
      try await persistence.saveRoomTopicMessage(message)
      let messages = try await persistence.loadRoomTopicMessages(
        appID: configuration.appID,
        room: room,
        topic: topic,
        limit: nil
      )
      await roomTopicObservers.publish(
        messages,
        for: roomTopicObservationKey(room: room, topic: topic)
      )
      if configuration.liveTransport != nil {
        try await liveSession.publishTopic(
          room: room,
          topic: topic,
          payload: payload,
          clientEventID: configuration.makeID()
        )
      }
      await operationGate.leave()
      return message
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  public func roomTopicMessages(
    room: InstantRoomHandle,
    topic rawTopic: String,
    limit: Int? = nil
  ) async throws -> [InstantRoomTopicMessage] {
    if let limit, limit < 0 {
      throw validationFailed(
        operation: "list room topic",
        message: "Topic message limit must be greater than or equal to 0.",
        recovery: "Pass a non-negative --limit value, or omit --limit to list every local message."
      )
    }
    let room = try validatedRoom(room, operation: "list room topic")
    let topic = try validatedNonEmpty(
      rawTopic,
      label: "Topic",
      operation: "list room topic",
      recovery: "Pass the room topic name to list."
    )
    return try await persistence.loadRoomTopicMessages(
      appID: configuration.appID,
      room: room,
      topic: topic,
      limit: limit
    )
  }

  public func observeRoomTopicMessages(
    room: InstantRoomHandle,
    topic rawTopic: String
  ) async throws -> AsyncStream<[InstantRoomTopicMessage]> {
    let room = try validatedRoom(room, operation: "observe room topic")
    let topic = try validatedNonEmpty(
      rawTopic,
      label: "Topic",
      operation: "observe room topic",
      recovery: "Pass the room topic name to observe."
    )

    await operationGate.enter()
    do {
      let messages = try await persistence.loadRoomTopicMessages(
        appID: configuration.appID,
        room: room,
        topic: topic,
        limit: nil
      )
      let stream = await roomTopicObservers.observe(
        key: roomTopicObservationKey(room: room, topic: topic),
        current: messages
      )
      await operationGate.leave()
      return stream
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  func activeRoomTopicObservationCount(
    room: InstantRoomHandle,
    topic rawTopic: String
  ) async throws -> Int {
    let room = try validatedRoom(room, operation: "inspect room topic observers")
    let topic = try validatedNonEmpty(
      rawTopic,
      label: "Topic",
      operation: "inspect room topic observers",
      recovery: "Pass the room topic name to inspect."
    )
    return await roomTopicObservers.activeCount(
      for: roomTopicObservationKey(room: room, topic: topic)
    )
  }

  public func uploadFile(
    from sourceURL: URL,
    name rawName: String? = nil,
    contentType rawContentType: String? = nil
  ) async throws -> InstantStoredFile {
    let file = try await preparedStoredFile(
      from: sourceURL,
      name: rawName,
      contentType: rawContentType,
      operation: "upload file"
    )
    return try await savePreparedStoredFile(file, contentsOf: sourceURL)
  }

  public func uploadFileProgress(
    from sourceURL: URL,
    name rawName: String? = nil,
    contentType rawContentType: String? = nil
  ) async throws -> AsyncThrowingStream<InstantFileUploadProgress, Error> {
    try await uploadFileProgressLease(
      from: sourceURL,
      name: rawName,
      contentType: rawContentType
    ).stream
  }

  /// Progress stream lease around a single upload.
  ///
  /// Kept intentionally thin: the prior abortable prepared-operation graph
  /// hung Swift 6.3 SIL `ClosureLifetimeFixup` for tens of minutes on this
  /// 13k-line primary. Reintroduce exact cancel/join on a smaller unit after
  /// InstantRuntime is split.
  package func uploadFileProgressLease(
    from sourceURL: URL,
    name rawName: String? = nil,
    contentType rawContentType: String? = nil
  ) async throws
    -> InstantManagedStreamLease<AsyncThrowingStream<InstantFileUploadProgress, Error>> {
    let file = try await preparedStoredFile(
      from: sourceURL,
      name: rawName,
      contentType: rawContentType,
      operation: "upload file"
    )
    let totalByteCount = try await persistence.regularFileByteCount(
      at: sourceURL,
      operation: "upload file"
    )
    let output = AsyncThrowingStream<InstantFileUploadProgress, Error>.makeStream(
      bufferingPolicy: .bufferingNewest(2)
    )
    let task = Task { [weak self] in
      guard let self else {
        output.continuation.finish()
        return
      }
      output.continuation.yield(
        InstantFileUploadProgress(
          operationID: file.id,
          appID: file.appID,
          fileID: file.id,
          fileName: file.name,
          contentType: file.contentType,
          state: .loading,
          completedByteCount: 0,
          totalByteCount: totalByteCount,
          progress: 0,
          updatedAt: self.configuration.now()
        )
      )
      do {
        try Task.checkCancellation()
        let savedFile = try await self.savePreparedStoredFile(file, contentsOf: sourceURL)
        try Task.checkCancellation()
        output.continuation.yield(
          InstantFileUploadProgress(
            operationID: file.id,
            appID: file.appID,
            fileID: file.id,
            fileName: file.name,
            contentType: file.contentType,
            state: .success,
            completedByteCount: savedFile.byteCount,
            totalByteCount: max(totalByteCount, savedFile.byteCount),
            progress: 1,
            file: savedFile,
            updatedAt: self.configuration.now()
          )
        )
        output.continuation.finish()
      } catch is CancellationError {
        output.continuation.finish()
      } catch {
        output.continuation.yield(
          InstantFileUploadProgress(
            operationID: file.id,
            appID: file.appID,
            fileID: file.id,
            fileName: file.name,
            contentType: file.contentType,
            state: .error,
            completedByteCount: 0,
            totalByteCount: totalByteCount,
            progress: 0,
            errorMessage: error.localizedDescription,
            updatedAt: self.configuration.now()
          )
        )
        output.continuation.finish(throwing: error)
      }
    }
    let lease = InstantManagedStreamLease(
      stream: output.stream,
      onCancellationRequested: { task.cancel() }
    )
    lease.install {
      task.cancel()
      output.continuation.finish()
      await task.value
    }
    return lease
  }

  private func savePreparedStoredFile(
    _ file: InstantStoredFile,
    contentsOf sourceURL: URL
  ) async throws -> InstantStoredFile {
    try Task.checkCancellation()
    var file = file
    var uploadedPath: String?
    var uploadedRefreshToken: String?
    if let storageTransport {
      let byteCount = try await persistence.regularFileByteCount(
        at: sourceURL,
        operation: "upload file"
      )
      let refreshToken = try await storageRefreshToken(operation: "upload file")
      let response = try await storageTransport.upload(
        InstantStorageUploadRequest(
          appID: configuration.appID,
          apiURI: configuration.apiURI,
          path: file.name,
          sourceURL: sourceURL,
          byteCount: byteCount,
          refreshToken: refreshToken,
          contentType: file.contentType
        )
      )
      file.id = response.id
      uploadedPath = file.name
      uploadedRefreshToken = refreshToken
    }
    await operationGate.enter()
    do {
      let savedFile = try await persistence.saveStoredFile(file, contentsOf: sourceURL)
      let files = try await persistence.loadStoredFiles(appID: configuration.appID)
      await storedFilesObservers.publish(
        files,
        for: storedFilesObservationKey
      )
      await operationGate.leave()
      return savedFile
    } catch {
      await operationGate.leave()
      if let storageTransport,
        let uploadedPath,
        let uploadedRefreshToken
      {
        _ = try? await storageTransport.delete(
          InstantStorageDeleteRequest(
            appID: configuration.appID,
            apiURI: configuration.apiURI,
            path: uploadedPath,
            refreshToken: uploadedRefreshToken
          )
        )
      }
      throw error
    }
  }

  private func preparedStoredFile(
    from sourceURL: URL,
    name rawName: String?,
    contentType rawContentType: String?,
    operation: String
  ) async throws -> InstantStoredFile {
    let name = try resolvedFileName(rawName, sourceURL: sourceURL, operation: operation)
    let contentType = rawContentType?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .nilIfEmpty
    let userID = try await resolvedFileUserID(operation: operation)
    let now = configuration.now()
    return InstantStoredFile(
      id: configuration.makeID(),
      appID: configuration.appID,
      name: name,
      contentType: contentType,
      byteCount: 0,
      localPath: "",
      ownerUserID: userID,
      createdAt: now,
      updatedAt: now
    )
  }

  public func storedFiles() async throws -> [InstantStoredFile] {
    _ = try await resolvedFileUserID(operation: "list files")
    if storageTransport != nil, configuration.liveTransport != nil {
      do {
        let remote = try await queryOnce(Self.storedFilesQuery).values
        return try await mergedStoredFiles(remoteSnapshots: remote)
      } catch let error as InstantError where error.code == .networkFailed {
        // Preserve Instant's offline-first behavior: a disconnected device can
        // still enumerate files it has already downloaded.
      }
    }
    return try await persistence.loadStoredFiles(appID: configuration.appID)
  }

  public func storageSnapshot() async throws -> InstantStorageSnapshot {
    await operationGate.enter()
    do {
      let snapshot = try await persistence.storageSnapshot(appID: configuration.appID)
      await operationGate.leave()
      return snapshot
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  public func observeStoredFiles() async throws -> AsyncStream<[InstantStoredFile]> {
    if storageTransport != nil, configuration.liveTransport != nil {
      _ = try await resolvedFileUserID(operation: "observe files")
      do {
        _ = try await queryOnce(Self.storedFilesQuery)
      } catch let error as InstantError where error.code == .networkFailed {
        return try await localStoredFilesStream()
      }
      let remoteStream = await observe(Self.storedFilesQuery)
      return AsyncStream { continuation in
        let task = Task {
          for await emission in remoteStream {
            guard !Task.isCancelled else { break }
            do {
              continuation.yield(
                try await self.mergedStoredFiles(remoteSnapshots: emission.values)
              )
            } catch {
              continuation.finish()
              return
            }
          }
          continuation.finish()
        }
        continuation.onTermination = { @Sendable _ in task.cancel() }
      }
    }
    return try await localStoredFilesStream()
  }

  private func localStoredFilesStream() async throws -> AsyncStream<[InstantStoredFile]> {
    await operationGate.enter()
    do {
      _ = try await resolvedFileUserID(operation: "observe files")
      let files = try await persistence.loadStoredFiles(appID: configuration.appID)
      let stream = await storedFilesObservers.observe(
        key: storedFilesObservationKey,
        current: files
      )
      await operationGate.leave()
      return stream
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  public func storedFileContents(
    id rawID: String,
    name rawName: String? = nil
  ) async throws -> InstantStoredFileContents {
    let id = try validatedNonEmpty(
      rawID,
      label: "File id",
      operation: "read file",
      recovery: "Pass the id returned by 'instant-swift-data files list'."
    )
    let name = try rawName.map {
      try validatedNonEmpty(
        $0,
        label: "File name",
        operation: "read file",
        recovery: "Pass the storage path returned when the file was uploaded."
      )
    }

    let userID = try await resolvedFileUserID(operation: "read file")
    if let contents = try await persistence.readStoredFileContents(
      appID: configuration.appID,
      fileID: id
    ) {
      return contents
    }

    guard let storageTransport else {
      throw validationFailed(
        operation: "read file",
        localID: id,
        message: "No downloaded file exists for id '\(id)'.",
        recovery: "Run 'instant-swift-data files list' to inspect available file ids."
      )
    }
    if let name {
      let refreshToken = try await storageRefreshToken(operation: "read file")
      let data = try await storageTransport.downloadFile(
        InstantStorageFileDownloadRequest(
          appID: configuration.appID,
          apiURI: configuration.apiURI,
          path: name,
          refreshToken: refreshToken
        )
      )
      let now = configuration.now()
      let file = InstantStoredFile(
        id: id,
        appID: configuration.appID,
        name: name,
        contentType: nil,
        byteCount: Int64(data.count),
        localPath: "",
        ownerUserID: userID,
        createdAt: now,
        updatedAt: now
      )
      let saved = try await persistence.saveDownloadedFile(file, data: data)
      let localFiles = try await persistence.loadStoredFiles(appID: configuration.appID)
      await storedFilesObservers.publish(localFiles, for: storedFilesObservationKey)
      return InstantStoredFileContents(file: saved, data: data)
    }
    guard configuration.liveTransport != nil else {
      throw validationFailed(
        operation: "read file",
        localID: id,
        message: "No downloaded file exists for id '\(id)'.",
        recovery: "Run 'instant-swift-data files list' to inspect available file ids."
      )
    }
    let remoteFiles = try await remoteStoredFiles()
    guard let file = remoteFiles.first(where: { $0.id == id }), let remoteURL = file.remoteURL else {
      throw validationFailed(
        operation: "read file",
        localID: id,
        message: "No remote file exists for id '\(id)'.",
        recovery: "Run 'instant-swift-data files list' to inspect remote file ids."
      )
    }
    let data = try await storageTransport.download(
      InstantStorageDownloadRequest(url: remoteURL)
    )
    let saved = try await persistence.saveDownloadedFile(file, data: data)
    let localFiles = try await persistence.loadStoredFiles(appID: configuration.appID)
    await storedFilesObservers.publish(localFiles, for: storedFilesObservationKey)
    return InstantStoredFileContents(file: saved, data: data)
  }

  @discardableResult
  public func deleteStoredFile(id rawID: String) async throws -> InstantStoredFile {
    let id = try validatedNonEmpty(
      rawID,
      label: "File id",
      operation: "delete file",
      recovery: "Pass the id returned by 'instant-swift-data files list'."
    )

    _ = try await resolvedFileUserID(operation: "delete file")
    let file = try await storedFiles().first(where: { $0.id == id })
    guard let file else {
      throw validationFailed(
        operation: "delete file",
        localID: id,
        message: "No local or remote file exists for id '\(id)'.",
        recovery: "Run 'instant-swift-data files list' to inspect available file ids."
      )
    }
    do {
      if let storageTransport {
        let refreshToken = try await storageRefreshToken(operation: "delete file")
        _ = try await storageTransport.delete(
          InstantStorageDeleteRequest(
            appID: configuration.appID,
            apiURI: configuration.apiURI,
            path: file.name,
            refreshToken: refreshToken
          )
        )
      }
      _ = try await persistence.deleteStoredFile(
        appID: configuration.appID,
        fileID: id
      )
      let files = try await persistence.loadStoredFiles(appID: configuration.appID)
      await storedFilesObservers.publish(
        files,
        for: storedFilesObservationKey
      )
      return file
    } catch {
      throw error
    }
  }

  private static let storedFilesQuery = InstantQueryPlan(
    id: "instant.storage.files",
    namespace: "$files",
    order: .serverCreatedAt
  )

  private func remoteStoredFiles() async throws -> [InstantStoredFile] {
    let emission = try await queryOnce(Self.storedFilesQuery)
    return try await mergedStoredFiles(
      remoteSnapshots: emission.values,
      includeLocalOnly: false
    )
  }

  private func mergedStoredFiles(
    remoteSnapshots: [InstantEntitySnapshot],
    includeLocalOnly: Bool = true
  ) async throws -> [InstantStoredFile] {
    let remote = remoteSnapshots.compactMap(remoteStoredFile(from:))
    let local = try await persistence.loadStoredFiles(appID: configuration.appID)
    var filesByID = Dictionary(uniqueKeysWithValues: remote.map { ($0.id, $0) })
    for var file in local {
      if let discovered = filesByID[file.id] {
        file.name = discovered.name
        file.contentType = discovered.contentType ?? file.contentType
        file.remoteURL = discovered.remoteURL
      }
      if includeLocalOnly || filesByID[file.id] != nil {
        filesByID[file.id] = file
      }
    }
    return filesByID.values.sorted {
      ($0.name, $0.id) < ($1.name, $1.id)
    }
  }

  private func remoteStoredFile(from snapshot: InstantEntitySnapshot) -> InstantStoredFile? {
    guard
      let name = snapshot.stringValue(for: "path"),
      let urlString = snapshot.stringValue(for: "url"),
      let url = URL(string: urlString)
    else { return nil }
    let unknownTimestamp = InstantTimestamp(milliseconds: 0)
    return InstantStoredFile(
      id: snapshot.id,
      appID: configuration.appID,
      name: name,
      contentType: snapshot.stringValue(for: "content-type"),
      byteCount: 0,
      localPath: "",
      ownerUserID: "",
      createdAt: unknownTimestamp,
      updatedAt: unknownTimestamp,
      remoteURL: url
    )
  }

  func activeStoredFilesObservationCount() async -> Int {
    await storedFilesObservers.activeCount(for: storedFilesObservationKey)
  }

  private func storageRefreshToken(operation: String) async throws -> String {
    guard let refreshToken = try await persistence.loadAuthSession(key: authSessionKey)?
      .refreshToken?.trimmingCharacters(in: .whitespacesAndNewlines),
      !refreshToken.isEmpty
    else {
      throw InstantError(
        code: .authFailed,
        operation: operation,
        message: "Instant storage requires an authenticated refresh token.",
        recovery: "Sign in before uploading or deleting files."
      )
    }
    return refreshToken
  }

  public func appendStreamChunk(
    streamID rawStreamID: String,
    payload: JSONValue
  ) async throws -> InstantStreamChunk {
    let streamID = try validatedNonEmpty(
      rawStreamID,
      label: "Stream id",
      operation: "append stream chunk",
      recovery: "Pass a stream id, such as 'chat/lobby'."
    )

    await operationGate.enter()
    do {
      let userID = try await resolvedAuthenticatedUserID(
        operation: "append stream chunk",
        noun: "Stream"
      )
      let chunk = try await persistence.appendStreamChunk(
        appID: configuration.appID,
        streamID: streamID,
        chunkID: configuration.makeID(),
        payload: payload,
        userID: userID,
        createdAt: configuration.now()
      )
      let chunks = try await persistence.loadStreamChunks(
        appID: configuration.appID,
        streamID: streamID,
        limit: nil,
        afterIndex: nil
      )
      await streamChunksObservers.publish(
        chunks,
        for: streamChunksObservationKey(streamID: streamID)
      )
      await operationGate.leave()
      return chunk
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  public func streamChunks(
    streamID rawStreamID: String,
    limit: Int? = nil,
    afterIndex: Int64? = nil
  ) async throws
    -> [InstantStreamChunk]
  {
    if let limit, limit < 0 {
      throw validationFailed(
        operation: "read stream chunks",
        message: "Stream chunk limit must be greater than or equal to 0.",
        recovery: "Pass a non-negative --limit value, or omit --limit to read every local chunk."
      )
    }
    if let afterIndex, afterIndex < 0 {
      throw validationFailed(
        operation: "read stream chunks",
        message: "Stream chunk after-index must be greater than or equal to 0.",
        recovery: "Pass a previously emitted chunk index, or omit afterIndex to read every local chunk."
      )
    }
    let streamID = try validatedNonEmpty(
      rawStreamID,
      label: "Stream id",
      operation: "read stream chunks",
      recovery: "Pass a stream id, such as 'chat/lobby'."
    )

    await operationGate.enter()
    do {
      _ = try await resolvedAuthenticatedUserID(operation: "read stream chunks", noun: "Stream")
      let chunks = try await persistence.loadStreamChunks(
        appID: configuration.appID,
        streamID: streamID,
        limit: limit,
        afterIndex: afterIndex
      )
      await operationGate.leave()
      return chunks
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  public func observeStreamChunks(
    streamID rawStreamID: String,
    afterIndex: Int64? = nil
  ) async throws
    -> AsyncStream<[InstantStreamChunk]>
  {
    if let afterIndex, afterIndex < 0 {
      throw validationFailed(
        operation: "observe stream chunks",
        message: "Stream chunk after-index must be greater than or equal to 0.",
        recovery: "Pass a previously emitted chunk index, or omit afterIndex to observe every local chunk."
      )
    }
    let streamID = try validatedNonEmpty(
      rawStreamID,
      label: "Stream id",
      operation: "observe stream chunks",
      recovery: "Pass a stream id, such as 'chat/lobby'."
    )

    await operationGate.enter()
    do {
      _ = try await resolvedAuthenticatedUserID(
        operation: "observe stream chunks",
        noun: "Stream"
      )
      let chunks = try await persistence.loadStreamChunks(
        appID: configuration.appID,
        streamID: streamID,
        limit: nil,
        afterIndex: nil
      )
      let stream = await streamChunksObservers.observe(
        key: streamChunksObservationKey(streamID: streamID),
        current: chunks
      )
      await operationGate.leave()
      if let afterIndex {
        return Self.streamChunks(after: afterIndex, from: stream)
      }
      return stream
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  private static func streamChunks(
    after afterIndex: Int64,
    from stream: AsyncStream<[InstantStreamChunk]>
  ) -> AsyncStream<[InstantStreamChunk]> {
    let mapped = AsyncStream<[InstantStreamChunk]>.makeStream(bufferingPolicy: .bufferingNewest(1))
    let task = Task {
      for await chunks in stream {
        mapped.continuation.yield(chunks.filter { $0.index > afterIndex })
      }
      mapped.continuation.finish()
    }
    mapped.continuation.onTermination = { @Sendable _ in
      task.cancel()
    }
    return mapped.stream
  }

  public func createStream(clientID rawClientID: String) async throws -> InstantStreamMetadata {
    let clientID = try validatedNonEmpty(
      rawClientID,
      label: "Stream client id",
      operation: "create stream",
      recovery: "Pass a stable, unique client id for the writer."
    )

    await operationGate.enter()
    do {
      let userID = try await resolvedAuthenticatedUserID(operation: "create stream", noun: "Stream")
      let metadata: InstantStreamMetadata
      if configuration.liveTransport != nil, await liveSession.isOpen {
        let started = try await liveSession.startStream(
          clientID: clientID,
          reconnectToken: configuration.makeID(),
          clientEventID: configuration.makeID()
        )
        guard started.clientID == clientID, started.offset == 0 else {
          throw InstantError(
            code: .decodeFailed,
            operation: "start Instant live stream",
            path: "offset",
            serverEventID: started.clientEventID,
            message:
              "Instant acknowledged client id '\(started.clientID)' at byte offset \(started.offset), expected '\(clientID)' at 0.",
            recovery: "Use a new client id, or reconnect the existing writer with its original token."
          )
        }
        metadata = try await persistence.ensureStreamMetadata(
          appID: configuration.appID,
          streamID: started.streamID,
          clientID: clientID,
          userID: userID,
          createdAt: configuration.now()
        )
      } else {
        metadata = try await persistence.createStream(
          appID: configuration.appID,
          streamID: configuration.makeID(),
          clientID: clientID,
          userID: userID,
          createdAt: configuration.now()
        )
      }
      await operationGate.leave()
      return metadata
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  public func streamMetadata(streamID rawStreamID: String) async throws -> InstantStreamMetadata {
    let streamID = try validatedNonEmpty(
      rawStreamID,
      label: "Stream id",
      operation: "read stream metadata",
      recovery: "Pass the persistent stream id returned by createStream(clientID:)."
    )

    await operationGate.enter()
    do {
      _ = try await resolvedAuthenticatedUserID(operation: "read stream metadata", noun: "Stream")
      guard let metadata = try await persistence.loadStreamMetadata(
        appID: configuration.appID,
        streamID: streamID
      ) else {
        throw streamNotFound(
          operation: "read stream metadata",
          localID: streamID,
          recovery: "Create the stream first, or read by the matching client id."
        )
      }
      await operationGate.leave()
      return metadata
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  public func streamMetadata(clientID rawClientID: String) async throws -> InstantStreamMetadata {
    let clientID = try validatedNonEmpty(
      rawClientID,
      label: "Stream client id",
      operation: "read stream metadata",
      recovery: "Pass the client id used when creating the stream."
    )

    await operationGate.enter()
    do {
      _ = try await resolvedAuthenticatedUserID(operation: "read stream metadata", noun: "Stream")
      guard let metadata = try await persistence.loadStreamMetadata(
        appID: configuration.appID,
        clientID: clientID
      ) else {
        throw streamNotFound(
          operation: "read stream metadata",
          localID: clientID,
          recovery: "Create the stream first, or read by the persistent stream id."
        )
      }
      await operationGate.leave()
      return metadata
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  public func appendStreamContent(
    streamID rawStreamID: String,
    content: String,
    expectedOffset: Int64? = nil
  ) async throws -> InstantStreamContentAppend {
    let streamID = try validatedNonEmpty(
      rawStreamID,
      label: "Stream id",
      operation: "append stream content",
      recovery: "Pass the persistent stream id returned by createStream(clientID:)."
    )
    try validateStreamByteOffset(expectedOffset, operation: "append stream content")

    await operationGate.enter()
    do {
      let userID = try await resolvedAuthenticatedUserID(
        operation: "append stream content",
        noun: "Stream"
      )
      guard let append = try await persistence.appendStreamContent(
        appID: configuration.appID,
        streamID: streamID,
        chunkID: configuration.makeID(),
        content: content,
        expectedOffset: expectedOffset,
        userID: userID,
        createdAt: configuration.now()
      ) else {
        throw streamNotFound(
          operation: "append stream content",
          localID: streamID,
          recovery: "Create the stream before appending content."
        )
      }
      try await liveSession.appendStream(
        streamID: streamID,
        chunks: [content],
        offset: append.offset,
        done: false,
        abortReason: nil,
        clientEventID: configuration.makeID()
      )
      try await publishStreamContentUpdates(streamID: streamID)
      await operationGate.leave()
      return append
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  public func closeStream(
    streamID rawStreamID: String,
    abortReason rawAbortReason: String? = nil
  ) async throws -> InstantStreamMetadata {
    let streamID = try validatedNonEmpty(
      rawStreamID,
      label: "Stream id",
      operation: "close stream",
      recovery: "Pass the persistent stream id returned by createStream(clientID:)."
    )
    let abortReason = rawAbortReason?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedAbortReason = abortReason?.isEmpty == true ? nil : abortReason

    await operationGate.enter()
    do {
      _ = try await resolvedAuthenticatedUserID(operation: "close stream", noun: "Stream")
      guard let metadata = try await persistence.closeStream(
        appID: configuration.appID,
        streamID: streamID,
        abortReason: normalizedAbortReason,
        updatedAt: configuration.now()
      ) else {
        throw streamNotFound(
          operation: "close stream",
          localID: streamID,
          recovery: "Create the stream before closing it."
        )
      }
      try await liveSession.finishStream(
        streamID: streamID,
        offset: metadata.size ?? 0,
        abortReason: normalizedAbortReason,
        clientEventID: configuration.makeID()
      )
      try await publishStreamContentUpdates(streamID: streamID)
      await operationGate.leave()
      return metadata
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  public func streamContent(
    streamID rawStreamID: String,
    byteOffset: Int64 = 0
  ) async throws -> InstantStreamContentRead {
    let streamID = try validatedNonEmpty(
      rawStreamID,
      label: "Stream id",
      operation: "read stream content",
      recovery: "Pass a persistent stream id."
    )
    try validateStreamByteOffset(byteOffset, operation: "read stream content")

    await operationGate.enter()
    do {
      _ = try await resolvedAuthenticatedUserID(operation: "read stream content", noun: "Stream")
      guard let read = try await persistence.loadStreamContent(
        appID: configuration.appID,
        streamID: streamID,
        byteOffset: byteOffset
      ) else {
        throw streamNotFound(
          operation: "read stream content",
          localID: streamID,
          recovery: "Create the stream first, or read by the matching client id."
        )
      }
      await operationGate.leave()
      return read
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  public func streamContent(
    clientID rawClientID: String,
    byteOffset: Int64 = 0
  ) async throws -> InstantStreamContentRead {
    let clientID = try validatedNonEmpty(
      rawClientID,
      label: "Stream client id",
      operation: "read stream content",
      recovery: "Pass the client id used when creating the stream."
    )
    try validateStreamByteOffset(byteOffset, operation: "read stream content")

    await operationGate.enter()
    do {
      _ = try await resolvedAuthenticatedUserID(operation: "read stream content", noun: "Stream")
      guard let read = try await persistence.loadStreamContent(
        appID: configuration.appID,
        clientID: clientID,
        byteOffset: byteOffset
      ) else {
        throw streamNotFound(
          operation: "read stream content",
          localID: clientID,
          recovery: "Create the stream first, or read by the persistent stream id."
        )
      }
      await operationGate.leave()
      return read
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  public func observeStreamContent(
    streamID rawStreamID: String,
    byteOffset: Int64 = 0
  ) async throws -> AsyncStream<InstantStreamContentRead> {
    let streamID = try validatedNonEmpty(
      rawStreamID,
      label: "Stream id",
      operation: "observe stream content",
      recovery: "Pass a persistent stream id."
    )
    try validateStreamByteOffset(byteOffset, operation: "observe stream content")

    await operationGate.enter()
    do {
      _ = try await resolvedAuthenticatedUserID(operation: "observe stream content", noun: "Stream")
      let read = try await persistence.loadStreamContent(
        appID: configuration.appID,
        streamID: streamID,
        byteOffset: byteOffset
      )
      if read == nil, configuration.liveTransport == nil {
        throw streamNotFound(
          operation: "observe stream content",
          localID: streamID,
          recovery: "Create the stream first, or observe by the matching client id."
        )
      }
      let stream = await streamContentObservers.observe(
        key: streamContentObservationKey(streamID: streamID),
        byteOffset: byteOffset,
        current: read
      )
      await operationGate.leave()
      return await liveStreamContentObservation(
        stream,
        key: "stream-id:\(streamID):\(byteOffset)",
        streamID: streamID,
        initialByteOffset: read.map { $0.byteOffset + $0.byteCount } ?? byteOffset
      )
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  public func observeStreamContent(
    clientID rawClientID: String,
    byteOffset: Int64 = 0
  ) async throws -> AsyncStream<InstantStreamContentRead> {
    let clientID = try validatedNonEmpty(
      rawClientID,
      label: "Stream client id",
      operation: "observe stream content",
      recovery: "Pass the client id used when creating the stream."
    )
    try validateStreamByteOffset(byteOffset, operation: "observe stream content")

    await operationGate.enter()
    do {
      _ = try await resolvedAuthenticatedUserID(operation: "observe stream content", noun: "Stream")
      let read = try await persistence.loadStreamContent(
        appID: configuration.appID,
        clientID: clientID,
        byteOffset: byteOffset
      )
      if read == nil, configuration.liveTransport == nil {
        throw streamNotFound(
          operation: "observe stream content",
          localID: clientID,
          recovery: "Create the stream first, or observe by the persistent stream id."
        )
      }
      let stream = await streamContentObservers.observe(
        key: streamContentObservationKey(clientID: clientID),
        byteOffset: byteOffset,
        current: read
      )
      await operationGate.leave()
      return await liveStreamContentObservation(
        stream,
        key: "client-id:\(clientID):\(byteOffset)",
        clientID: clientID,
        initialByteOffset: read.map { $0.byteOffset + $0.byteCount } ?? byteOffset
      )
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  private func liveStreamContentObservation(
    _ stream: AsyncStream<InstantStreamContentRead>,
    key: String,
    clientID: String? = nil,
    streamID: String? = nil,
    initialByteOffset: Int64
  ) async -> AsyncStream<InstantStreamContentRead> {
    guard configuration.liveTransport != nil else { return stream }
    do {
      try await liveSession.registerStreamReader(
        key: key,
        clientID: clientID,
        streamID: streamID,
        initialByteOffset: initialByteOffset,
        clientEventID: configuration.makeID()
      )
    } catch {
      await recordConnectionError(error)
    }
    return Self.liveObservation(stream) { [weak self] in
      guard let self else { return }
      do {
        try await self.liveSession.unregisterStreamReader(
          key: key,
          clientEventID: self.configuration.makeID()
        )
      } catch {
        await self.recordConnectionError(error)
      }
    }
  }

  func activeStreamChunksObservationCount(streamID rawStreamID: String) async throws -> Int {
    let streamID = try validatedNonEmpty(
      rawStreamID,
      label: "Stream id",
      operation: "inspect stream observers",
      recovery: "Pass a stream id to inspect."
    )
    return await streamChunksObservers.activeCount(
      for: streamChunksObservationKey(streamID: streamID)
    )
  }

  func activeStreamContentObservationCount(streamID rawStreamID: String) async throws -> Int {
    let streamID = try validatedNonEmpty(
      rawStreamID,
      label: "Stream id",
      operation: "inspect stream content observers",
      recovery: "Pass a stream id to inspect."
    )
    return await streamContentObservers.activeCount(
      for: streamContentObservationKey(streamID: streamID)
    )
  }

  public func createShare(
    rootNamespace rawRootNamespace: String,
    rootID rawRootID: String
  ) async throws -> InstantShareSnapshot {
    let rootNamespace = try validatedNonEmpty(
      rawRootNamespace,
      label: "Share root namespace",
      operation: "create share",
      recovery: "Pass the namespace of the root record to share, such as 'remindersLists'."
    )
    let rootID = try validatedNonEmpty(
      rawRootID,
      label: "Share root id",
      operation: "create share",
      recovery: "Pass the id of the root record to share."
    )

    await operationGate.enter()
    do {
      let userID = try await resolvedAuthenticatedUserID(operation: "create share", noun: "Share")
      let activeRootShares = try await persistence.loadActiveShareSnapshots(
        appID: configuration.appID,
        rootNamespace: rootNamespace,
        rootID: rootID
      )
      if let activeRootShare = activeRootShares.first {
        guard activeRootShare.share.ownerUserID == userID else {
          throw shareRootOwnershipPermissionRejected(snapshot: activeRootShare, userID: userID)
        }
        throw duplicateShareRejected(snapshot: activeRootShare)
      }
      let now = configuration.now()
      let shareID = configuration.makeID()
      let share = InstantShare(
        id: shareID,
        appID: configuration.appID,
        rootNamespace: rootNamespace,
        rootID: rootID,
        ownerUserID: userID,
        token: "local-share-\(configuration.makeID())",
        createdAt: now,
        updatedAt: now
      )
      let membership = InstantShareMembership(
        appID: configuration.appID,
        shareID: shareID,
        userID: userID,
        role: .owner,
        acceptedAt: now
      )
      let snapshot = try await persistence.createShare(share, ownerMembership: membership)
      for membership in snapshot.memberships where !membership.isRevoked {
        try await publishShares(for: membership.userID)
      }
      await operationGate.leave()
      return snapshot
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  public func acceptShare(token rawToken: String) async throws -> InstantShareSnapshot {
    let token = try validatedNonEmpty(
      rawToken,
      label: "Share token",
      operation: "accept share",
      recovery: "Pass the token printed by 'instant-swift-data shares create'."
    )

    await operationGate.enter()
    do {
      let userID = try await resolvedAuthenticatedUserID(operation: "accept share", noun: "Share")
      guard
        let snapshot = try await persistence.acceptShare(
          appID: configuration.appID,
          token: token,
          userID: userID,
          acceptedAt: configuration.now()
        )
      else {
        throw shareNotFound(operation: "accept share", localID: token)
      }
      for membership in snapshot.memberships where !membership.isRevoked {
        try await publishShares(for: membership.userID)
      }
      await operationGate.leave()
      return snapshot
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  public func shares() async throws -> [InstantShareSnapshot] {
    await operationGate.enter()
    var gateIsHeld = true
    do {
      let userID = try await resolvedAuthenticatedUserID(operation: "list shares", noun: "Share")
      if let contract = configuration.liveShareContract {
        await operationGate.leave()
        gateIsHeld = false
        return try contract.snapshots(
          appID: configuration.appID,
          roots: try await query(contract.queryPlan)
        )
      }
      let snapshots = try await persistence.loadShareSnapshots(
        appID: configuration.appID,
        userID: userID
      )
      await operationGate.leave()
      return snapshots
    } catch {
      if gateIsHeld { await operationGate.leave() }
      throw error
    }
  }

  public func observeShares() async throws -> AsyncStream<[InstantShareSnapshot]> {
    await operationGate.enter()
    var gateIsHeld = true
    do {
      let userID = try await resolvedAuthenticatedUserID(operation: "observe shares", noun: "Share")
      if let contract = configuration.liveShareContract {
        await operationGate.leave()
        gateIsHeld = false
        let emissions = await observe(contract.queryPlan)
        return liveShareObservation(contract: contract, emissions: emissions)
      }
      let snapshots = try await persistence.loadShareSnapshots(
        appID: configuration.appID,
        userID: userID
      )
      let stream = await sharesObservers.observe(
        key: sharesObservationKey(userID: userID),
        current: snapshots
      )
      await operationGate.leave()
      return stream
    } catch {
      if gateIsHeld { await operationGate.leave() }
      throw error
    }
  }

  private func liveShareObservation(
    contract: InstantLiveShareContract,
    emissions: AsyncStream<InstantQueryEmission>
  ) -> AsyncStream<[InstantShareSnapshot]> {
    contract.observe(
      appID: configuration.appID,
      emissions: emissions
    ) { [weak self] error in
      await self?.recordConnectionError(error)
    }
  }

  public func updateShareMembershipRole(
    shareID rawShareID: String,
    userID rawTargetUserID: String,
    role: InstantShareRole
  ) async throws -> InstantShareSnapshot {
    let shareID = try validatedNonEmpty(
      rawShareID,
      label: "Share id",
      operation: "update share role",
      recovery: "Pass a share id from 'instant-swift-data shares list'."
    )
    let targetUserID = try validatedNonEmpty(
      rawTargetUserID,
      label: "Share member user id",
      operation: "update share role",
      recovery: "Pass the user id of an accepted share member."
    )
    guard role != .owner else {
      throw validationFailed(
        operation: "update share role",
        localID: shareID,
        message: "The owner role cannot be assigned through membership role updates.",
        recovery: "Create a new share as the intended owner, or assign reader/writer to members."
      )
    }

    await operationGate.enter()
    do {
      let userID = try await resolvedAuthenticatedUserID(operation: "update share role", noun: "Share")
      guard let snapshot = try await persistence.loadShareSnapshot(
        appID: configuration.appID,
        shareID: shareID
      ), !snapshot.share.isRevoked else {
        throw shareNotFound(operation: "update share role", localID: shareID)
      }
      guard snapshot.share.ownerUserID == userID else {
        throw shareRolePermissionRejected(snapshot: snapshot, userID: userID)
      }
      guard snapshot.share.ownerUserID != targetUserID else {
        throw validationFailed(
          operation: "update share role",
          localID: targetUserID,
          message: "The share owner's membership role cannot be changed.",
          recovery: "Update reader/writer roles for accepted non-owner members."
        )
      }
      guard snapshot.memberships.contains(where: { membership in
        membership.userID == targetUserID && !membership.isRevoked
      }) else {
        throw shareMembershipNotFound(
          operation: "update share role",
          shareID: shareID,
          userID: targetUserID
        )
      }
      guard let updated = try await persistence.updateShareMembershipRole(
        appID: configuration.appID,
        shareID: shareID,
        userID: targetUserID,
        role: role,
        updatedAt: configuration.now()
      ) else {
        throw shareMembershipNotFound(
          operation: "update share role",
          shareID: shareID,
          userID: targetUserID
        )
      }
      for membership in updated.memberships where !membership.isRevoked {
        try await publishShares(for: membership.userID)
      }
      await operationGate.leave()
      return updated
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  public func revokeShare(id rawShareID: String) async throws -> InstantShareSnapshot {
    let shareID = try validatedNonEmpty(
      rawShareID,
      label: "Share id",
      operation: "revoke share",
      recovery: "Pass a share id from 'instant-swift-data shares list'."
    )

    await operationGate.enter()
    do {
      let userID = try await resolvedAuthenticatedUserID(operation: "revoke share", noun: "Share")
      guard let snapshot = try await persistence.loadShareSnapshot(
        appID: configuration.appID,
        shareID: shareID
      ) else {
        throw shareNotFound(operation: "revoke share", localID: shareID)
      }
      guard snapshot.share.ownerUserID == userID else {
        throw sharePermissionRejected(snapshot: snapshot, userID: userID)
      }
      let revoked = try await persistence.revokeShare(
        appID: configuration.appID,
        shareID: shareID,
        revokedAt: configuration.now()
      ) ?? snapshot
      for membership in revoked.memberships {
        try await publishShares(for: membership.userID)
      }
      await operationGate.leave()
      return revoked
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  private func authorizeSharedRootWrites(
    transaction: InstantStoreTransaction,
    snapshot: InstantStoreSnapshot
  ) async throws {
    let targets = sharedRootWriteTargets(in: transaction, snapshot: snapshot)
    guard !targets.isEmpty else { return }

    for target in targets.sorted(by: sharedRootWriteTargetSort) {
      let snapshots = try await persistence.loadActiveShareSnapshots(
        appID: configuration.appID,
        rootNamespace: target.namespace,
        rootID: target.id
      )
      guard !snapshots.isEmpty else { continue }

      guard let session = try await persistence.loadAuthSession(key: authSessionKey) else {
        throw sharedRootWritePermissionRejected(snapshot: snapshots[0], userID: nil)
      }

      if target.namespace != nil {
        guard canWriteSharedRoot(snapshots, userID: session.userID) else {
          throw sharedRootWritePermissionRejected(
            snapshot: snapshots[0],
            userID: session.userID
          )
        }
      } else {
        let snapshotsByNamespace = Dictionary(grouping: snapshots, by: \.share.rootNamespace)
        for namespace in snapshotsByNamespace.keys.sorted() {
          let namespaceSnapshots = snapshotsByNamespace[namespace] ?? []
          guard canWriteSharedRoot(namespaceSnapshots, userID: session.userID) else {
            throw sharedRootWritePermissionRejected(
              snapshot: namespaceSnapshots[0],
              userID: session.userID
            )
          }
        }
      }
    }
  }

  private func sharedRootWriteTargets(
    in transaction: InstantStoreTransaction,
    snapshot: InstantStoreSnapshot
  ) -> Set<InstantSharedRootWriteTarget> {
    let attributesByID = Dictionary(
      snapshot.attributes.map { ($0.id, $0) },
      uniquingKeysWith: { lhs, _ in lhs }
    )
    var targets: Set<InstantSharedRootWriteTarget> = []

    for operation in transaction.operations {
      switch operation {
      case let .insert(triple), let .merge(triple), let .retract(triple):
        let attribute = attributesByID[triple.attributeID]
        let namespace = sharedRootNamespace(for: triple.attributeID, attribute: attribute)
        targets.insert(InstantSharedRootWriteTarget(namespace: namespace, id: triple.entityID))
        insertRefWriteTargets(
          for: triple.value,
          attribute: attribute,
          snapshot: snapshot,
          attributesByID: attributesByID,
          into: &targets
        )

      case let .insertByLookup(lookup, attributeID, value, _, _),
        let .mergeByLookup(lookup, attributeID, value, _, _),
        let .retractByLookup(lookup, attributeID, value, _, _):
        let attribute = attributesByID[attributeID]
        insertRefWriteTargets(
          for: value,
          attribute: attribute,
          snapshot: snapshot,
          attributesByID: attributesByID,
          into: &targets
        )
        let sourceIDs = entityIDs(
          matching: lookup,
          snapshot: snapshot,
          attributesByID: attributesByID
        )
        if sourceIDs.isEmpty, let target = primaryKeyLookupWriteTarget(
          lookup,
          attributesByID: attributesByID
        ) {
          targets.insert(target)
        }
        guard !sourceIDs.isEmpty else { continue }
        let namespace = sharedRootNamespace(for: attributeID, attribute: attribute)
        for entityID in sourceIDs {
          targets.insert(InstantSharedRootWriteTarget(namespace: namespace, id: entityID))
        }

      case let .deleteEntity(entityID):
        targets.formUnion(
          cascadeDeleteWriteTargets(
            entityID: entityID,
            namespace: nil,
            snapshot: snapshot,
            attributesByID: attributesByID
          )
        )

      case let .deleteEntityInNamespace(entityID, namespace):
        targets.formUnion(
          cascadeDeleteWriteTargets(
            entityID: entityID,
            namespace: namespace,
            snapshot: snapshot,
            attributesByID: attributesByID
          )
        )

      case let .deleteEntityByLookup(lookup):
        let lookupAttribute = lookupAttribute(for: lookup.attributeID, attributesByID: attributesByID)
        let lookupNamespace = lookupAttribute?.namespace
        let entityIDs = entityIDs(
          matching: lookup,
          snapshot: snapshot,
          attributesByID: attributesByID
        )
        if entityIDs.isEmpty, let target = primaryKeyLookupWriteTarget(
          lookup,
          attributesByID: attributesByID
        ) {
          targets.formUnion(
            cascadeDeleteWriteTargets(
              entityID: target.id,
              namespace: target.namespace,
              snapshot: snapshot,
              attributesByID: attributesByID
            )
          )
          targets.insert(target)
        } else {
          for entityID in entityIDs {
            targets.formUnion(
              cascadeDeleteWriteTargets(
                entityID: entityID,
                namespace: lookupNamespace,
                snapshot: snapshot,
                attributesByID: attributesByID
              )
            )
          }
        }

      case .requireEntityMissing, .requireEntityMissingByLookup, .requireEntityExists,
        .requireEntityExistsByLookup, .requireTripleExists, .ruleParams, .ruleParamsByLookup:
        break
      }
    }

    return targets
  }

  private func primaryKeyLookupWriteTarget(
    _ lookup: InstantLookupRef,
    attributesByID: [String: InstantAttribute]
  ) -> InstantSharedRootWriteTarget? {
    let attribute = attributesByID[lookup.attributeID]
    let isPrimaryKey = attribute?.primaryKey == true
      || attribute?.name == "id"
      || lookup.attributeID.hasSuffix("/id")
    guard isPrimaryKey, case let .string(entityID) = lookup.value else { return nil }
    return InstantSharedRootWriteTarget(
      namespace: sharedRootNamespace(for: lookup.attributeID, attribute: attribute),
      id: entityID
    )
  }

  private func sharedRootNamespace(
    for attributeID: String,
    attribute: InstantAttribute?
  ) -> String? {
    if let attribute {
      return attribute.namespace
    }
    let parts = attributeID.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
    guard parts.count == 2, !parts[0].isEmpty else { return nil }
    return String(parts[0])
  }

  private func insertRefWriteTargets(
    for value: InstantValue,
    attribute: InstantAttribute?,
    snapshot: InstantStoreSnapshot,
    attributesByID: [String: InstantAttribute],
    into targets: inout Set<InstantSharedRootWriteTarget>
  ) {
    let targetNamespace: String?
    if let attribute {
      guard attribute.valueType == .ref else { return }
      targetNamespace = attribute.linkNamespace
    } else {
      targetNamespace = nil
    }

    switch value {
    case let .ref(entityID):
      targets.insert(InstantSharedRootWriteTarget(namespace: targetNamespace, id: entityID))

    case let .lookupRef(lookup):
      let entityIDs = entityIDs(
        matching: lookup,
        snapshot: snapshot,
        attributesByID: attributesByID
      )
      if entityIDs.isEmpty, let target = primaryKeyLookupWriteTarget(
        lookup,
        attributesByID: attributesByID
      ) {
        targets.insert(
          InstantSharedRootWriteTarget(
            namespace: targetNamespace ?? target.namespace,
            id: target.id
          )
        )
      }
      for entityID in entityIDs {
        targets.insert(InstantSharedRootWriteTarget(namespace: targetNamespace, id: entityID))
      }

    case .null, .bool, .number, .string, .date, .json:
      break
    }
  }

  private struct RuntimeLookupAttribute {
    var attribute: InstantAttribute
    var isReverse: Bool
    var namespace: String
  }

  private func lookupAttribute(
    for attributeID: String,
    attributesByID: [String: InstantAttribute]
  ) -> RuntimeLookupAttribute? {
    if let attribute = attributesByID[attributeID] {
      return RuntimeLookupAttribute(
        attribute: attribute,
        isReverse: false,
        namespace: attribute.namespace
      )
    }
    guard let attribute = attributesByID.values.first(where: { $0.reverseIdentity == attributeID })
    else {
      return nil
    }
    return RuntimeLookupAttribute(
      attribute: attribute,
      isReverse: true,
      namespace: attribute.linkNamespace
        ?? sharedRootNamespace(for: attributeID, attribute: nil)
        ?? attribute.namespace
    )
  }

  private func cascadeDeleteWriteTargets(
    entityID: String,
    namespace: String?,
    snapshot: InstantStoreSnapshot,
    attributesByID: [String: InstantAttribute],
    visited: Set<InstantSharedRootWriteTarget> = []
  ) -> Set<InstantSharedRootWriteTarget> {
    let visit = InstantSharedRootWriteTarget(namespace: namespace, id: entityID)
    guard !visited.contains(visit) else { return [] }
    var visited = visited
    visited.insert(visit)
    var targets: Set<InstantSharedRootWriteTarget> = [
      visit
    ]

    let outgoingTriples = snapshot.triples.filter { triple in
      guard triple.entityID == entityID else { return false }
      guard let namespace else { return true }
      return attributesByID[triple.attributeID]?.namespace == namespace
    }
    let incomingTriples = snapshot.triples.filter { triple in
      guard let attribute = attributesByID[triple.attributeID],
        attribute.valueType == .ref,
        case let .ref(targetID) = triple.value
      else {
        return false
      }
      guard targetID == entityID else { return false }
      guard let namespace else { return true }
      return attribute.linkNamespace == namespace
    }

    for triple in outgoingTriples {
      guard let attribute = attributesByID[triple.attributeID],
        attribute.valueType == .ref,
        case let .ref(targetID) = triple.value
      else {
        continue
      }
      targets.insert(InstantSharedRootWriteTarget(namespace: attribute.linkNamespace, id: targetID))
      if attribute.onDeleteReverse == .cascade {
        targets.formUnion(
          cascadeDeleteWriteTargets(
            entityID: targetID,
            namespace: attribute.linkNamespace,
            snapshot: snapshot,
            attributesByID: attributesByID,
            visited: visited
          )
        )
      }
    }

    for triple in incomingTriples {
      let attribute = attributesByID[triple.attributeID]
      targets.insert(
        InstantSharedRootWriteTarget(namespace: attribute?.namespace, id: triple.entityID)
      )
      if attribute?.onDelete == .cascade {
        targets.formUnion(
          cascadeDeleteWriteTargets(
            entityID: triple.entityID,
            namespace: attribute?.namespace,
            snapshot: snapshot,
            attributesByID: attributesByID,
            visited: visited
          )
        )
      }
    }

    return targets
  }

  private func entityIDs(
    matching lookup: InstantLookupRef,
    snapshot: InstantStoreSnapshot,
    attributesByID: [String: InstantAttribute]
  ) -> [String] {
    guard let lookupAttribute = lookupAttribute(
      for: lookup.attributeID,
      attributesByID: attributesByID
    ) else {
      return entityIDs(
        matchingForwardAttribute: lookup.attributeID,
        value: lookup.value,
        snapshot: snapshot
      )
    }

    if lookupAttribute.isReverse {
      guard case let .ref(sourceID) = lookup.value else { return [] }
      let ids = snapshot.triples.compactMap { triple -> String? in
        guard triple.entityID == sourceID,
          triple.attributeID == lookupAttribute.attribute.id
        else {
          return nil
        }
        return triple.value.refValue
      }
      return Array(Set(ids)).sorted()
    }

    return entityIDs(
      matchingForwardAttribute: lookupAttribute.attribute.id,
      value: lookup.value,
      snapshot: snapshot
    )
  }

  private func entityIDs(
    matchingForwardAttribute attributeID: String,
    value expectedValue: InstantLookupValue,
    snapshot: InstantStoreSnapshot
  ) -> [String] {
    let ids = snapshot.triples.compactMap { triple -> String? in
      guard triple.attributeID == attributeID,
        lookupValue(expectedValue, matches: triple.value)
      else {
        return nil
      }
      return triple.entityID
    }
    return Array(Set(ids)).sorted()
  }

  private func lookupValue(_ lookupValue: InstantLookupValue, matches value: InstantValue) -> Bool {
    switch (lookupValue, value) {
    case (.null, .null):
      return true
    case let (.bool(lhs), .bool(rhs)):
      return lhs == rhs
    case let (.number(lhs), .number(rhs)):
      return lhs == rhs
    case let (.string(lhs), .string(rhs)):
      return lhs == rhs
    case let (.date(lhs), .date(rhs)):
      return lhs == rhs
    case let (.json(lhs), .json(rhs)):
      return lhs == rhs
    case let (.ref(lhs), .ref(rhs)):
      return lhs == rhs
    case (.null, _), (.bool, _), (.number, _), (.string, _), (.date, _), (.json, _), (.ref, _):
      return false
    }
  }

  private func canWriteSharedRoot(
    _ snapshots: [InstantShareSnapshot],
    userID: String
  ) -> Bool {
    snapshots.contains { snapshot in
      snapshot.memberships.contains { membership in
        membership.userID == userID
          && !membership.isRevoked
          && membership.role.canWriteSharedRoot
      }
    }
  }

  private func sharedRootWriteTargetSort(
    _ lhs: InstantSharedRootWriteTarget,
    _ rhs: InstantSharedRootWriteTarget
  ) -> Bool {
    if lhs.id == rhs.id {
      return (lhs.namespace ?? "") < (rhs.namespace ?? "")
    }
    return lhs.id < rhs.id
  }

  public func pendingMutations() async -> [PendingMutation] {
    await durableOutboxMutations(
      statuses: [.pending]
    ) { [outbox] in await outbox.pending() }
  }

  public func failedMutations() async -> [PendingMutation] {
    await durableOutboxMutations(
      statuses: [.failed]
    ) { [outbox] in await outbox.all().filter { $0.status == .failed } }
  }

  public func pendingMutationCount() async -> Int {
    do {
      recordActorHop(.persistence)
      return try await persistence.countOutboxMutations(status: .pending)
    } catch {
      InstantDiagnostics.shared.record(
        error: error,
        subsystem: "instant-swift-data-core",
        category: "outbox",
        event: "outbox.pending-count-failed",
        message: "Could not count durable pending mutations; using the resident outbox count."
      )
      reportIssue("Instant could not count durable pending mutations: \(error)")
      recordActorHop(.outbox)
      return await outbox.pending().count
    }
  }

  public func observeMutationLifecycle(
    id rawID: String
  ) async throws -> AsyncStream<InstantMutationLifecycleEvent> {
    let id = try validatedNonEmpty(
      rawID,
      label: "Mutation id",
      operation: "observe mutation lifecycle",
      recovery: "Pass the transaction id used to submit the mutation."
    )
    await enterOperationGate()
    let resolution: InstantMutationLifecycleResolution
    do {
      recordActorHop(.persistence)
      resolution = try await persistence.resolveMutationLifecycle(id: id)
      await leaveOperationGate()
    } catch {
      await leaveOperationGate()
      throw error
    }
    return await mutationLifecycleObservers.observe(
      key: resolution.observationID,
      current: resolution.event
    )
  }

  public func outboxMutations() async -> [PendingMutation] {
    await durableOutboxMutations(
      statuses: [.pending, .failed]
    ) { [outbox] in await outbox.all().filter { $0.status != .confirmed } }
  }

  package func mutationDeliveryBarrierMutations() async -> [PendingMutation] {
    await outbox.all()
  }

  package func mutationDeliveryBarrierSummary() async throws
    -> InstantMutationDeliveryBarrierSummary
  {
    recordActorHop(.persistence)
    return try await persistence.mutationDeliveryBarrierSummary()
  }

  private func durableOutboxMutations(
    statuses: [InstantMutationStatus],
    fallback: @Sendable () async -> [PendingMutation]
  ) async -> [PendingMutation] {
    await enterOperationGate()
    do {
      for _ in 0..<5 {
        let state = try await loadCompactStateSynchronizingStore()
        guard let mutations = try await persistence.loadOutboxMutations(
          statuses: statuses,
          expectedStoreRevision: state.storeRevision,
          expectedOutboxRevision: state.outboxRevision
        ) else { continue }
        await leaveOperationGate()
        return mutations
      }
      throw outboxChangedDuringInspection()
    } catch {
      await leaveOperationGate()
      InstantDiagnostics.shared.record(
        error: error,
        subsystem: "instant-swift-data-core",
        category: "outbox",
        event: "outbox.inspection-hydration-failed",
        message: "Could not reconstruct durable outbox mutations for inspection."
      )
      reportIssue(
        "Instant could not reconstruct durable outbox mutations for inspection: \(error)"
      )
      return await fallback()
    }
  }

  func liveMutationReservationCountsForTesting() async -> (
    ids: Int,
    stepCounts: Int,
    deadlines: Int
  ) {
    await liveSession.mutationReservationCountsForTesting()
  }

  public func outboxTransportMutations(includeFailed: Bool = false) async
    -> [InstantTransportMutation]
  {
    do {
      return try await outboxTransportMutationsForDelivery(includeFailed: includeFailed)
    } catch {
      recordOutboxTransportHydrationFailure(error)
      return []
    }
  }

  private func recordOutboxTransportHydrationFailure(_ error: Error) {
    InstantDiagnostics.shared.record(
      error: error,
      subsystem: "instant-swift-data-core",
      category: "outbox",
      event: "outbox.transport-hydration-failed",
      message: "Could not reconstruct durable outbox transactions for delivery."
    )
    reportIssue(
      """
      Instant could not reconstruct durable outbox transactions for delivery.

      \(String(describing: error))

      The mutations remain durable in SQLite and were not sent. Inspect the local cache, then retry.
      """
    )
  }

  private func recordFailedMutationRetryWindowFailure(_ error: Error) {
    InstantDiagnostics.shared.record(
      error: error,
      subsystem: "instant-swift-data-core",
      category: "outbox",
      event: "outbox.failed-mutation-retry.window-failed",
      message: "Could not transition one bounded failed-mutation retry window."
    )
    reportIssue(
      """
      Instant could not transition one bounded failed-mutation retry window.

      \(String(describing: error))

      The mutations remain durable in SQLite. The healthy delivery pump will retry after a bounded delay.
      """
    )
  }

  private func outboxTransportMutationsForDelivery(includeFailed: Bool = false) async throws
    -> [InstantTransportMutation]
  {
    await enterOperationGate()
    do {
      for _ in 0..<5 {
        recordActorHop(.persistence)
        let state = try await loadCompactStateSynchronizingStore()
        let statuses: [InstantMutationStatus] = includeFailed
          ? [.pending, .confirmed, .failed]
          : [.pending, .confirmed]
        guard let hydrated = try await persistence.loadOutboxMutations(
          statuses: statuses,
          expectedStoreRevision: state.storeRevision,
          expectedOutboxRevision: state.outboxRevision
        ) else { continue }
        // Public inspection is read-only. SQLite remains the queue authority;
        // only the atomic automatic-delivery claim populates the resident
        // rejection/barrier actor.
        let mutations = hydrated
          .filter { mutation in
            switch mutation.status {
            case .pending:
              return true
            case .confirmed:
              return !mutation.provesServerAcceptance
            case .failed:
              return includeFailed
            }
          }
          .sorted(by: PendingMutation.creationOrder)
        // Inspection may omit a row that was quarantined while its optimistic
        // overlay remains locally visible. Without the automatic claim's
        // revision-qualified durable successor proof, visible-state filtering
        // could therefore erase an older write and return neither intent. Raw
        // ordered operations are the conservative truthful projection.
        let transport = mutations.map { mutation in
          var transportMutation = InstantTransportMutation(mutation)
          // A local receipt preserves the existing public `.confirmed` result, but it is still
          // unacknowledged from Instant's perspective and must use the wire-level pending shape.
          if mutation.status == .confirmed, !mutation.provesServerAcceptance {
            transportMutation.status = .pending
          }
          return transportMutation
        }
        await leaveOperationGate()
        return transport
      }
      throw outboxChangedDuringTransportHydration()
    } catch {
      await leaveOperationGate()
      throw error
    }
  }

  private func automaticOutboxTransportMutationsForDelivery() async throws
    -> InstantAutomaticOutboxTransportSelection
  {
    try await enterOperationGateUnlessCancelled(
      operation: "claim automatic outbox transport mutations for delivery"
    )
    do {
      recordActorHop(.persistence)
      let window = try await persistence.claimAutomaticOutboxDeliveryWindow(
        InstantAutomaticOutboxClaimRequest(
          claimantID: automaticDeliveryClaimantID,
          claimToken: UUID().uuidString.lowercased(),
          now: configuration.now()
        )
      )
      recordActorHop(.outbox)
      for mutation in window.failedMutations {
        await publishMutationLifecycle(mutation)
        await outbox.remove(id: mutation.id)
      }
      for mutation in window.mutations {
        await outbox.replace(mutation)
      }
      if !window.failedMutations.isEmpty {
        _ = try? await publishConnectionStatusWithGateHeld()
      }
      let mutations = InstantBoundedOutboxDelivery.transportMutations(in: window)
      await leaveOperationGate()
      return InstantAutomaticOutboxTransportSelection(
        mutations: mutations,
        claimToken: window.claimToken,
        claimedMutationIDs: Set(window.mutations.map(\.id)),
        reclaimedMutationIDs: window.reclaimedMutationIDs,
        nextClaimDeadlineMilliseconds: window.nextClaimDeadlineMilliseconds,
        shouldContinueImmediately: window.shouldContinueImmediately
      )
    } catch {
      await leaveOperationGate()
      throw error
    }
  }

  public func flushPendingMutations(limit: Int? = nil) async throws
    -> InstantMutationTransportFlushResult
  {
    if let limit, limit < 0 {
      throw validationFailed(
        operation: "flush outbox",
        message: "Flush limit must be greater than or equal to 0.",
        recovery:
          "Pass a non-negative --limit value, or omit --limit to flush one fixed bounded delivery window."
      )
    }
    if limit == 0 {
      return try await emptyExplicitMutationFlushResult()
    }

    try await enterMutationFlushGateUnlessCancelled()
    guard let handle = explicitMutationFlushOwner.start({ [self] ownerToken in
      try await performBoundedExplicitMutationFlush(
        limit: limit,
        ownerToken: ownerToken
      )
    }) else {
      await leaveMutationFlushGate()
      throw InstantError(
        code: .networkFailed,
        operation: "flush outbox",
        message: "Cannot begin an explicit flush while Instant is closing or closed.",
        recovery: "Call connect() before flushing one bounded pending-mutation window."
      )
    }
    let completion = await withTaskCancellationHandler {
      await handle.completion()
    } onCancel: {
      self.explicitMutationFlushOwner.cancel(handle)
    }
    await leaveMutationFlushGate()
    guard let completion else { throw CancellationError() }
    switch completion {
    case let .success(result):
      return result
    case let .failure(error):
      throw error
    case .cancelled:
      throw CancellationError()
    }
  }

  private func emptyExplicitMutationFlushResult() async throws
    -> InstantMutationTransportFlushResult
  {
    try await enterOperationGateUnlessCancelled(operation: "read empty explicit flush result")
    do {
      recordActorHop(.persistence)
      let pendingMutationCount = try await persistence.countOutboxMutations(status: .pending)
      let mutationCount = try await persistence.countOutboxMutations()
      await leaveOperationGate()
      return InstantMutationTransportFlushResult(
        request: InstantMutationTransportRequest(
          appID: configuration.appID,
          apiURI: configuration.apiURI,
          websocketURI: configuration.websocketURI,
          mutations: []
        ),
        results: [],
        confirmed: [],
        failed: [],
        pendingMutationCount: pendingMutationCount,
        mutationCount: mutationCount
      )
    } catch {
      await leaveOperationGate()
      throw error
    }
  }

  private func performBoundedExplicitMutationFlush(
    limit: Int?,
    ownerToken: UInt64
  ) async throws -> InstantMutationTransportFlushResult {
    let flushClaimToken = UUID().uuidString.lowercased()
    let flushClaimantID = "\(automaticDeliveryClaimantID)-explicit-\(flushClaimToken)"
    let request: InstantMutationTransportRequest
    let selectedMutations: [PendingMutation]
    let selectedMutationIDs: Set<String>
    let selectionFailures: [PendingMutation]
    let selectionDecodedBodyByteCount: Int
    let pendingCountAfterSelection: Int
    let mutationCountAfterSelection: Int

    try await enterOperationGateUnlessCancelled(operation: "select bounded explicit outbox flush")
    do {
      recordActorHop(.persistence)
      let window = try await persistence.claimExplicitOutboxDeliveryWindow(
        limit: limit,
        claimantID: flushClaimantID,
        claimToken: flushClaimToken,
        now: configuration.now()
      )
      selectedMutations = window.mutations
      selectedMutationIDs = Set(window.mutations.map(\.id))
      selectionFailures = window.failedMutations
      selectionDecodedBodyByteCount = window.decodedBodyByteCount
      request = InstantMutationTransportRequest(
        appID: configuration.appID,
        apiURI: configuration.apiURI,
        websocketURI: configuration.websocketURI,
        mutations: InstantBoundedOutboxDelivery.transportMutations(in: window)
      )
      recordActorHop(.outbox)
      for mutation in window.failedMutations {
        await publishMutationLifecycle(mutation)
        await outbox.remove(id: mutation.id)
      }
      for mutation in window.mutations {
        await outbox.replace(mutation)
      }
      if !window.failedMutations.isEmpty {
        _ = try? await publishConnectionStatusWithGateHeld()
      }
      if !window.mutations.isEmpty,
        try await persistedConnectionState() == .closed
      {
        recordActorHop(.persistence)
        _ = try await persistence.releaseAutomaticOutboxClaim(token: flushClaimToken)
        throw InstantError(
          code: .networkFailed,
          operation: "flush outbox",
          message:
            "Cannot flush \(window.mutations.count) pending mutation(s) while the Instant connection is closed.",
          recovery: "Call connect() before flushing pending mutations."
        )
      }
      recordActorHop(.persistence)
      pendingCountAfterSelection = try await persistence.countOutboxMutations(status: .pending)
      mutationCountAfterSelection = try await persistence.countOutboxMutations()
      await leaveOperationGate()
    } catch {
      await leaveOperationGate()
      throw error
    }

    if Task.isCancelled {
      if !selectedMutations.isEmpty {
        let release = Task { [self] in
          recordActorHop(.persistence)
          _ = try? await persistence.releaseAutomaticOutboxClaim(token: flushClaimToken)
        }
        await release.value
      }
      throw CancellationError()
    }

    guard !selectedMutations.isEmpty else {
      return InstantMutationTransportFlushResult(
        request: request,
        results: [],
        confirmed: [],
        failed: selectionFailures,
        pendingMutationCount: pendingCountAfterSelection,
        mutationCount: mutationCountAfterSelection
      )
    }

    let race = InstantExplicitMutationTransportRace()
    let transportOperation = configuration.mutationTransport.prepareOperation(request)
    let operationCancellation = InstantExplicitMutationOperationCancellation(
      operation: transportOperation,
      race: race
    )
    explicitMutationFlushOwner.installCancellation(token: ownerToken) {
      operationCancellation.cancel()
    }
    if Task.isCancelled {
      operationCancellation.cancel()
      let release = Task { [self] in
        recordActorHop(.persistence)
        _ = try? await persistence.releaseAutomaticOutboxClaim(token: flushClaimToken)
      }
      await release.value
      throw CancellationError()
    }
    recordActorHop(.mutationTransport)
    let transportTask = Task { () -> InstantExplicitMutationTransportOutcome in
      let outcome: InstantExplicitMutationTransportOutcome
      do {
        outcome = .response(try await transportOperation.run())
      } catch is CancellationError {
        outcome = .cancelled
      } catch let error as InstantError {
        outcome = .failure(error)
      } catch {
        outcome = .failure(InstantError(
          code: .networkFailed,
          operation: "flush Instant mutation transport",
          message: String(describing: error),
          recovery: "Inspect the configured mutation transport and retry the bounded durable outbox window."
        ))
      }
      race.resolve(.completed)
      return outcome
    }
    operationCancellation.installTransportTask(transportTask)
    let deadlineSleep = configuration.explicitMutationTransportDeadlineSleep
    let deadlineTask = Task {
      do {
        try await deadlineSleep(
          UInt64(InstantOutboxClaimLimits.claimTimeoutMilliseconds)
        )
        try Task.checkCancellation()
        transportOperation.abort()
        transportTask.cancel()
        race.resolve(.timedOut)
      } catch {}
    }
    operationCancellation.installDeadlineTask(deadlineTask)
    let renewalSleep = configuration.explicitMutationClaimRenewalSleep
    let renewalTask = Task { [self] in
      while true {
        do {
          try await renewalSleep(1_000)
          try Task.checkCancellation()
          recordActorHop(.persistence)
          let renewed = try await persistence.renewOutboxClaim(
            token: flushClaimToken,
            claimantID: flushClaimantID,
            deadlineMilliseconds: configuration.now().milliseconds
              + InstantOutboxClaimLimits.claimTimeoutMilliseconds
          )
          guard renewed else {
            throw InstantError(
              code: .networkFailed,
              operation: "renew explicit outbox claim",
              message: "The exact explicit-flush claim was lost before transport disposition.",
              recovery: "Do not resend this window until its durable mutation state is inspected."
            )
          }
        } catch is CancellationError {
          return
        } catch let error as InstantError {
          transportOperation.abort()
          transportTask.cancel()
          deadlineTask.cancel()
          race.resolve(.renewalFailed(error))
          return
        } catch {
          let failure = InstantError(
            code: .persistenceFailed,
            operation: "renew explicit outbox claim",
            message: String(describing: error),
            recovery: "Inspect the durable outbox claim before retrying this bounded window."
          )
          transportOperation.abort()
          transportTask.cancel()
          deadlineTask.cancel()
          race.resolve(.renewalFailed(failure))
          return
        }
      }
    }
    let event = await race.firstEvent()
    let terminalError: InstantError?
    let returnsCancellation: Bool
    let cleanupPhase: String?
    switch event {
    case .completed:
      terminalError = nil
      returnsCancellation = false
      cleanupPhase = "response-disposition"
      deadlineTask.cancel()
    case .timedOut:
      terminalError = InstantError(
        code: .networkFailed,
        operation: "flush Instant mutation transport",
        message: "Timed out after 5000ms waiting for the configured Instant mutation transport.",
        recovery:
          "Instant aborted the transport and kept the exact durable claim renewed while awaiting final response disposition."
      )
      returnsCancellation = false
      cleanupPhase = "deadline"
    case .cancelled:
      terminalError = nil
      returnsCancellation = true
      cleanupPhase = "cancellation-or-close"
    case let .renewalFailed(error):
      terminalError = error
      returnsCancellation = false
      cleanupPhase = "claim-renewal"
    }

    let cleanupWatchdog: Task<Void, Never>? = cleanupPhase.map { phase in
      let sleep = configuration.explicitMutationCleanupWatchdogSleep
      return Task { [weak self] in
        do {
          try await sleep(5_000)
          try Task.checkCancellation()
        } catch {
          return
        }
        guard let self else { return }
        InstantDiagnostics.shared.record(
          .warning,
          subsystem: "instant-swift-data-core",
          category: "outbox",
          event: "outbox.explicit-flush.cleanup-stalled",
          message:
            "Instant has waited another 5 seconds for exact explicit-flush cleanup and will continue waiting.",
          metadata: [
            "appID": self.configuration.appID,
            "phase": phase,
            "claimToken": flushClaimToken,
            "selectedMutationCount": String(selectedMutations.count),
            "decodedBodyByteCount": String(selectionDecodedBodyByteCount),
          ]
        )
      }
    }

    let outcome = await transportTask.value
    let disposition = Task { [self] () -> InstantExplicitMutationDisposition in
      switch outcome {
      case let .response(response):
        do {
          return .success(try await applyExplicitMutationTransportResponse(
            request: request,
            response: response,
            selectedMutations: selectedMutations,
            selectedMutationIDs: selectedMutationIDs,
            selectionFailures: selectionFailures,
            claimToken: flushClaimToken
          ))
        } catch let error as InstantError {
          return .responseFailure(error)
        } catch {
          return .responseFailure(InstantError(
            code: .persistenceFailed,
            operation: "apply explicit mutation transport response",
            message: String(describing: error),
            recovery: "Inspect the exact durable outbox claim before retrying."
          ))
        }
      case let .failure(error):
        recordActorHop(.persistence)
        _ = try? await persistence.releaseAutomaticOutboxClaim(token: flushClaimToken)
        await recordConnectionError(error)
        return .transportFailure(error)
      case .cancelled:
        recordActorHop(.persistence)
        _ = try? await persistence.releaseAutomaticOutboxClaim(token: flushClaimToken)
        return .transportCancelled
      }
    }
    let dispositionResult = await disposition.value
    renewalTask.cancel()
    deadlineTask.cancel()
    _ = await (renewalTask.value, deadlineTask.value)
    cleanupWatchdog?.cancel()
    await cleanupWatchdog?.value

    if case let .responseFailure(error) = dispositionResult {
      throw error
    }
    if let terminalError {
      await recordConnectionError(terminalError)
      throw terminalError
    }
    if returnsCancellation || Task.isCancelled {
      throw CancellationError()
    }
    switch dispositionResult {
    case let .success(result):
      return result
    case let .transportFailure(error):
      throw error
    case .transportCancelled:
      throw InstantError(
        code: .networkFailed,
        operation: "flush Instant mutation transport",
        message: "The configured mutation transport ended through cancellation.",
        recovery: "Retry the bounded durable outbox window when the transport is available."
      )
    case .responseFailure:
      fatalError("The explicit response-disposition failure was handled above.")
    }
  }

  private func applyExplicitMutationTransportResponse(
    request: InstantMutationTransportRequest,
    response: InstantMutationTransportResponse,
    selectedMutations: [PendingMutation],
    selectedMutationIDs: Set<String>,
    selectionFailures: [PendingMutation],
    claimToken: String
  ) async throws -> InstantMutationTransportFlushResult {
    guard response.results.count <= InstantOutboxClaimLimits.maximumMutationCount else {
      recordActorHop(.persistence)
      _ = try? await persistence.releaseAutomaticOutboxClaim(token: claimToken)
      throw InstantError(
        code: .validationFailed,
        operation: "apply explicit mutation transport response",
        message:
          "The mutation transport returned more results than one bounded delivery window permits.",
        recovery:
          "Return at most \(InstantOutboxClaimLimits.maximumMutationCount) results and only one outcome per mutation id."
      )
    }
    var resultByMutationID: [String: InstantMutationTransportResult] = [:]
    resultByMutationID.reserveCapacity(selectedMutationIDs.count)
    for result in response.results where selectedMutationIDs.contains(result.mutationID) {
      if let existing = resultByMutationID[result.mutationID] {
        guard existing == result else {
          recordActorHop(.persistence)
          _ = try? await persistence.releaseAutomaticOutboxClaim(token: claimToken)
          throw InstantError(
            code: .validationFailed,
            operation: "apply explicit mutation transport response",
            localID: result.mutationID,
            message:
              "The mutation transport returned conflicting terminal results for one bounded-window mutation.",
            recovery:
              "Fix the transport to return at most one outcome per mutation id before retrying."
          )
        }
      } else {
        resultByMutationID[result.mutationID] = result
      }
    }
    let results = selectedMutations.compactMap { resultByMutationID[$0.id] }
    // A transport may return several terminal results for one claimed window. Reject each row
    // through the row-addressed component path before confirming successors, so no accepted
    // optimistic layer disappears before a rejected predecessor is peeled and replayed.
    var terminalFailures = selectionFailures
    do {
      for result in results where result.outcome == .failed {
        let message =
          result.message ?? "The Instant mutation transport rejected the mutation."
        if let failed = try await failClaimedMutation(
            id: result.mutationID,
            failure: InstantMutationFailure(
              code: PendingMutation.failureCode(message: message),
              message: message
            ),
            requiredClaimToken: claimToken,
            recordsConnectionFailure: true
          )
        {
          terminalFailures.append(failed)
        }
      }
    } catch {
      recordActorHop(.persistence)
      _ = try? await persistence.releaseAutomaticOutboxClaim(token: claimToken)
      throw error
    }

    await enterOperationGate()
    do {
      let confirmationResults = results.filter { $0.outcome == .confirmed }
      recordActorHop(.persistence)
      let confirmedMutations = try await persistence.confirmExplicitlyFlushedOutboxMutations(
        confirmationResults,
        selectedMutations: selectedMutations,
        claimToken: claimToken
      )
      if !confirmedMutations.isEmpty {
        recordActorHop(.outbox)
        await outbox.remove(ids: Set(confirmedMutations.map(\.id)))
      }
      for mutation in confirmedMutations {
        await publishMutationLifecycle(mutation)
      }

      recordActorHop(.persistence)
      let remainingFailedMutationCount = try await persistence.countOutboxMutations(
        status: .failed
      )
      if terminalFailures.isEmpty,
        remainingFailedMutationCount == 0,
        try await persistedConnectionState() != .closed
      {
        try await saveOpenedConnectionMetadataWithGateHeld()
      }
      _ = try? await publishConnectionStatusWithGateHeld()
      recordActorHop(.persistence)
      _ = try await persistence.releaseAutomaticOutboxClaim(token: claimToken)
      let remainingPendingCount = try await persistence.countOutboxMutations(status: .pending)
      let remainingMutationCount = try await persistence.countOutboxMutations()
      await leaveOperationGate()
      return InstantMutationTransportFlushResult(
        request: request,
        results: results,
        confirmed: confirmedMutations,
        failed: terminalFailures,
        pendingMutationCount: remainingPendingCount,
        mutationCount: remainingMutationCount
      )
    } catch {
      recordActorHop(.persistence)
      _ = try? await persistence.releaseAutomaticOutboxClaim(token: claimToken)
      await leaveOperationGate()
      throw error
    }
  }

  @discardableResult
  public func confirmMutation(id: String) async throws -> PendingMutation {
    await enterOperationGate()
    do {
      let result = try await performConfirmMutationIfPresent(id: id)
      guard let mutation = result.mutation else {
        throw outboxMutationNotFound(id: id)
      }
      await leaveOperationGate()
      InstantDiagnostics.shared.record(
        .notice,
        subsystem: "instant-swift-data-core",
        category: "mutation",
        event: "transaction.local-confirmed",
        message: "A caller locally confirmed an outbox mutation without server-acceptance proof.",
        metadata: ["pendingMutationCount": String(result.pendingMutationCount)],
        correlationID: id
      )
      return mutation
    } catch {
      await leaveOperationGate()
      InstantDiagnostics.shared.record(
        error: error,
        subsystem: "instant-swift-data-core",
        category: "mutation",
        event: "transaction.confirmation-failed",
        message: "Failed to apply a local outbox confirmation.",
        correlationID: id
      )
      throw error
    }
  }

  @discardableResult
  public func failMutation(id: String, message: String) async throws -> PendingMutation {
    try await failMutation(
      id: id,
      failure: InstantMutationFailure(
        code: PendingMutation.failureCode(message: message),
        message: message
      )
    )
  }

  @discardableResult
  package func failMutation(
    id: String,
    failure: InstantMutationFailure,
    recordsConnectionFailure: Bool = true
  ) async throws -> PendingMutation {
    await operationGate.enter()
    do {
      let mutation = try await performFailMutationWithGateHeld(
        id: id,
        failure: failure,
        recordsConnectionFailure: recordsConnectionFailure
      )
      await operationGate.leave()
      return mutation
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  /// Applies a transport terminal rejection only while this runtime still owns
  /// the exact durable delivery claim. The live socket keeps its registered
  /// queries; the local rollback publication is sufficient, matching upstream
  /// Reactor `_handleMutationError`.
  private func failClaimedMutation(
    id: String,
    failure: InstantMutationFailure,
    requiredClaimToken: String,
    recordsConnectionFailure: Bool
  ) async throws -> PendingMutation? {
    for _ in 0..<5 {
      let state: InstantPersistenceState
      let storeSnapshot: InstantStoreSnapshot
      await operationGate.enter()
      do {
        state = try await loadCompactStateSynchronizingStore()
        storeSnapshot = await authoritativeStoreSnapshot(from: state)
        await operationGate.leave()
      } catch {
        await operationGate.leave()
        throw error
      }

      recordActorHop(.persistence)
      let load = try await persistence.loadClaimedTerminalFailureComponent(
        id: id,
        claimToken: requiredClaimToken,
        expectedStoreRevision: state.storeRevision,
        expectedAttributeRevision: state.attributeRevision
      )
      switch load {
      case .alreadyTerminal:
        return nil

      case .staleClaim:
        recordActorHop(.persistence)
        guard try await persistence.outboxClaimMatches(
          id: id,
          token: requiredClaimToken
        ) else { return nil }
        continue

      case let .normalizationRequired(firstMutationID):
        recordActorHop(.persistence)
        let normalization = try await persistence.normalizeOptimisticEffectMetadata(
          startingAtMutationID: firstMutationID
        )
        if normalization.normalizedMutationIDs.isEmpty,
          let blockedMutationID = normalization.blockedMutationID
        {
          throw InstantError(
            code: .persistenceFailed,
            operation: "normalize terminal failure component",
            localID: blockedMutationID,
            message:
              "Mutation '\(blockedMutationID)' cannot prove its optimistic effect from the bounded durable body.",
            recovery:
              "Preserve the durable row and run an authoritative refresh before retrying its rejection."
          )
        }
        continue

      case let .componentLimitExceeded(mutationCountAtLeast, encodedBodyByteCountAtLeast):
        await operationGate.enter()
        do {
          recordActorHop(.persistence)
          guard let application = try await persistence.failOutboxMutationsForDelivery(
            [id: failure],
            failureAttributeRevision: nil,
            claimToken: requiredClaimToken,
            expectedOutboxRevision: state.outboxRevision,
            metadataEntries: connectionFailureMetadataEntries(
              for: failure,
              recordsConnectionFailure: recordsConnectionFailure
            )
          ) else {
            await operationGate.leave()
            continue
          }
          guard let failedMutation = application.mutations.first(where: { $0.id == id }) else {
            recordActorHop(.persistence)
            let stillOwnsClaim = try await persistence.outboxClaimMatches(
              id: id,
              token: requiredClaimToken
            )
            await operationGate.leave()
            guard stillOwnsClaim else { return nil }
            continue
          }
          InstantDiagnostics.shared.record(
            .notice,
            subsystem: "instant-swift-data-core",
            category: "outbox",
            event: "outbox.mutation.terminal-component-deferred",
            message:
              "Recorded a terminal mutation failure without loading its oversized optimistic component.",
            metadata: [
              "mutationID": id,
              "componentMutationCountAtLeast": String(mutationCountAtLeast),
              "componentEncodedBodyByteCountAtLeast": String(encodedBodyByteCountAtLeast),
              "decodedBodyCount": String(application.decodedBodyCount),
              "decodedBodyByteCount": String(application.decodedBodyByteCount),
            ],
            correlationID: id
          )
          recordActorHop(.outbox)
          await outbox.remove(id: failedMutation.id)
          _ = try? await publishConnectionStatusWithGateHeld()
          await publishMutationLifecycle(failedMutation)
          await operationGate.leave()
          return failedMutation
        } catch {
          await operationGate.leave()
          throw error
        }

      case let .ready(component):
        let removal = try await prepareClaimedTerminalFailureComponent(
          component,
          failure: failure,
          snapshot: storeSnapshot
        )
        await operationGate.enter()
        do {
          recordActorHop(.persistence)
          let commit = try await persistence.commitClaimedTerminalFailure(
            targetID: id,
            claimToken: requiredClaimToken,
            expectedStoreRevision: component.expectedStoreRevision,
            expectedAttributeRevision: state.attributeRevision,
            expectedComponentRowRevisions: component.rowRevisions,
            expectedComponentIDs: component.ids,
            failedMutation: removal.failedMutation,
            rebasedSuccessors: removal.rebasedSuccessors,
            changedEntityTriples: removal.prepared?.changedEntityTriples ?? [:],
            metadataEntries: connectionFailureMetadataEntries(
              for: failure,
              recordsConnectionFailure: recordsConnectionFailure
            )
          )
          guard let commit else {
            recordActorHop(.persistence)
            let stillOwnsClaim = try await persistence.outboxClaimMatches(
              id: id,
              token: requiredClaimToken
            )
            await operationGate.leave()
            guard stillOwnsClaim else { return nil }
            continue
          }
          if commit.didChange {
            if let prepared = removal.prepared {
              recordActorHop(.store)
              _ = await store.commitAndPublish(prepared)
            }
            let installedRevisions = installedStoreRevisions.snapshot()
            installedStoreRevisions.install(
              storeRevision: component.expectedStoreRevision + 1,
              attributeRevision: installedRevisions.attributes
            )
            recordActorHop(.outbox)
            if let failedMutation = commit.failedMutation {
              await outbox.remove(id: failedMutation.id)
            }
            for successor in commit.rebasedSuccessors {
              await outbox.replaceIfPresent(successor)
            }
            _ = try? await publishConnectionStatusWithGateHeld()
            if let failedMutation = commit.failedMutation {
              await publishMutationLifecycle(failedMutation)
            }
          }
          await operationGate.leave()
          return commit.failedMutation
        } catch {
          await operationGate.leave()
          throw error
        }
      }
    }

    throw outboxChangedDuringStatusUpdate(id: id)
  }

  /// Loads persistence metadata without allowing a newer SQLite revision to
  /// advance the compact cache past the hot `InstantStore` actor.
  ///
  /// `SQLitePersistenceStore` deliberately drops triples after a disk load.
  /// Every runtime path that can observe that load must therefore install the
  /// returned full store snapshot before a later cache hit is treated as
  /// authoritative. Otherwise a read-only outbox inspection can make the next
  /// local query or mutation use a stale actor snapshot.
  private func loadCompactStateSynchronizingStore() async throws -> InstantPersistenceState {
    let installedRevisions = installedStoreRevisions.snapshot()
    let loaded = try await persistence.loadStateWithSource(
      installedStoreRevision: installedRevisions.store,
      installedAttributeRevision: installedRevisions.attributes
    )
    await adoptPersistedStoreIfNeeded(loaded.storeAdoption)
    installedStoreRevisions.install(
      storeRevision: loaded.state.storeRevision,
      attributeRevision: loaded.state.attributeRevision
    )
    return loaded.state
  }

  private func adoptPersistedStoreIfNeeded(
    _ adoption: InstantPersistenceStoreAdoption
  ) async {
    switch adoption {
    case .none:
      break

    case let .attributes(attributes):
      recordActorHop(.store)
      _ = await store.replaceAttributes(attributes)

    case let .snapshot(snapshot):
      recordActorHop(.store)
      await replaceStoreSnapshot(snapshot)
    }
  }

  private func replaceStoreSnapshot(_ snapshot: InstantStoreSnapshot) async {
    storeAdoptionMetrics.recordStoreSnapshotReplacement()
    await store.replaceSnapshot(snapshot)
  }

  /// Cross-file query helpers use this gate-owning entry point so an external
  /// SQLite revision and the hot store actor become visible as one local state
  /// transition.
  package func attributesForInfiniteQueryValidation() async throws -> [InstantAttribute] {
    try await enterOperationGateUnlessCancelled(
      operation: "validate infinite query attributes"
    )
    do {
      let attributes = try await loadCompactStateSynchronizingStore().snapshot.store.attributes
      try Task.checkCancellation()
      await leaveOperationGate()
      return attributes
    } catch {
      await leaveOperationGate()
      throw error
    }
  }

  /// Reconstructs durable mutation bodies while preserving the same
  /// store-revision synchronization invariant as compact runtime loads.
  private func loadStateWithDurableOutboxSynchronizingStore() async throws
    -> InstantPersistenceState
  {
    for _ in 0..<5 {
      let installedRevisions = installedStoreRevisions.snapshot()
      let loaded = try await persistence.loadStateWithSource(
        installedStoreRevision: installedRevisions.store,
        installedAttributeRevision: installedRevisions.attributes
      )
      await adoptPersistedStoreIfNeeded(loaded.storeAdoption)
      installedStoreRevisions.install(
        storeRevision: loaded.state.storeRevision,
        attributeRevision: loaded.state.attributeRevision
      )
      guard let outbox = try await persistence.loadOutboxMutations(
        statuses: [.pending, .confirmed, .failed],
        expectedStoreRevision: loaded.state.storeRevision,
        expectedOutboxRevision: loaded.state.outboxRevision
      ) else { continue }
      var state = loaded.state
      state.snapshot.outbox = outbox
      return state
    }
    throw outboxChangedDuringInspection()
  }

  /// Persistence memory cache may thin `store.triples` (dual-residency P2.1). When
  /// empty, InstantStore is the authoritative in-memory corpus.
  private func authoritativeStoreSnapshot(
    from state: InstantPersistenceState
  ) async -> InstantStoreSnapshot {
    if state.snapshot.store.triples.isEmpty {
      return await store.snapshot()
    }
    return state.snapshot.store
  }

  private func performFailMutationWithGateHeld(
    id: String,
    failure: InstantMutationFailure,
    recordsConnectionFailure: Bool = true
  ) async throws -> PendingMutation {
    guard let mutation = try await performFailMutationWithGateHeld(
      id: id,
      failure: failure,
      recordsConnectionFailure: recordsConnectionFailure,
      requiredClaimToken: nil
    ) else {
      throw outboxMutationNotFound(id: id)
    }
    return mutation
  }

  private func performFailMutationWithGateHeld(
    id: String,
    failure: InstantMutationFailure,
    recordsConnectionFailure: Bool,
    requiredClaimToken: String?
  ) async throws -> PendingMutation? {
    for _ in 0..<5 {
      if let requiredClaimToken {
        recordActorHop(.persistence)
        guard try await persistence.outboxClaimMatches(
          id: id,
          token: requiredClaimToken
        ) else { return nil }
      }
      let state = try await loadStateWithDurableOutboxSynchronizingStore()
      guard let original = state.snapshot.outbox.first(where: { $0.id == id }),
        let update = InstantOutbox.failing(
          id: id,
          failure: failure,
          in: state.snapshot.outbox
        )
      else {
        if requiredClaimToken != nil { return nil }
        await outbox.replace(with: state.snapshot.outbox)
        throw outboxMutationNotFound(id: id)
      }
      let storeSnapshot = await authoritativeStoreSnapshot(from: state)
      let removal = try await prepareTerminalFailureRemoval(
        original: original,
        failedMutations: update.mutations,
        snapshot: storeSnapshot
      )
      let metadataEntries = connectionFailureMetadataEntries(
        for: failure,
        recordsConnectionFailure: recordsConnectionFailure
      )
      let nextSnapshot = InstantPersistenceSnapshot(
        store: removal.prepared?.snapshot ?? storeSnapshot,
        outbox: removal.mutations
      )
      let didSave = try await persistence.saveSnapshot(
        nextSnapshot,
        replacing: InstantPersistenceSnapshot(
          store: removal.replacingStoreSnapshot,
          outbox: state.snapshot.outbox
        ),
        metadataEntries: metadataEntries,
        requiredOutboxClaimMutationID: requiredClaimToken == nil ? nil : id,
        requiredOutboxClaimToken: requiredClaimToken,
        expectedStoreRevision: state.storeRevision,
        expectedAttributeRevision: state.attributeRevision,
        expectedOutboxRevision: state.outboxRevision
      )
      if didSave {
        if let prepared = removal.prepared {
          _ = await store.commitAndPublish(prepared)
        }
        installedStoreRevisions.install(
          storeRevision: state.storeRevision + 1,
          attributeRevision: state.attributeRevision + 1
        )
        await outbox.replace(with: removal.mutations)
        _ = try? await publishConnectionStatusWithGateHeld()
        await publishMutationLifecycle(removal.failedMutation)
        return removal.failedMutation
      }
      if let requiredClaimToken {
        recordActorHop(.persistence)
        guard try await persistence.outboxClaimMatches(
          id: id,
          token: requiredClaimToken
        ) else { return nil }
      }
    }

    throw outboxChangedDuringStatusUpdate(id: id)
  }

  private func connectionFailureMetadataEntries(
    for failure: InstantMutationFailure,
    recordsConnectionFailure: Bool
  ) -> [InstantPersistenceMetadataEntry] {
    guard recordsConnectionFailure else { return [] }
    let now = configuration.now()
    return [
      InstantPersistenceMetadataEntry(
        key: connectionStateMetadataKey,
        value: InstantConnectionState.errored.rawValue,
        updatedAt: now
      ),
      InstantPersistenceMetadataEntry(
        key: connectionLastErrorMetadataKey,
        value: failure.message,
        updatedAt: now
      ),
    ]
  }

  /// Peels and replays only the transitive optimistic component selected from
  /// SQLite metadata. This preparation deliberately runs outside the operation
  /// gate; the subsequent targeted commit re-proves the complete component and
  /// every row revision before publishing it.
  private func prepareClaimedTerminalFailureComponent(
    _ component: InstantTerminalFailureComponent,
    failure: InstantMutationFailure,
    snapshot: InstantStoreSnapshot
  ) async throws -> (
    prepared: PreparedStoreMutation?,
    failedMutation: PendingMutation,
    rebasedSuccessors: [PendingMutation]
  ) {
    let original = component.target
    var failedMutation = original
    failedMutation.status = .failed
    failedMutation.failureMessage = failure.message
    failedMutation.failure = failure
    failedMutation.serverTransactionID = nil
    failedMutation.confirmationSource = nil

    guard original.optimisticOverlayState != nil || original.rollbackTransaction != nil else {
      throw unknownOptimisticOverlayState(
        id: original.id,
        operation: "reject claimed mutation"
      )
    }

    failedMutation.optimisticOverlayState = .removed
    failedMutation.rollbackTransaction = nil
    guard original.optimisticOverlayState != .removed else {
      return (nil, failedMutation, component.successors)
    }
    guard let failedRollback = original.rollbackTransaction else {
      let footprint = InstantOptimisticEffectFootprint.normalized(for: original)
      guard footprint?.entityIDs.isEmpty == true, footprint?.isGlobal == false else {
        throw InstantError(
          code: .persistenceFailed,
          operation: "reject claimed mutation",
          localID: original.id,
          message:
            "Mutation '\(original.id)' has an active optimistic effect but no durable rollback.",
          recovery:
            "Preserve the row and run an authoritative refresh instead of guessing its inverse."
        )
      }
      return (nil, failedMutation, component.successors)
    }

    var rebasedSuccessors = component.successors.sorted(by: PendingMutation.creationOrder)
    let deferredTriples = try await deferredValuesForPreparing(
      [failedRollback]
        + rebasedSuccessors.compactMap(\.rollbackTransaction)
        + rebasedSuccessors.map(\.transaction)
    )
    let hydratedSnapshot = configuration.deferredValueResidency.hydrating(
      snapshot,
      with: deferredTriples
    )
    var prepared: PreparedStoreMutation?
    var changedEntityIDs: Set<String> = []

    for successor in rebasedSuccessors.reversed() {
      guard successor.optimisticOverlayState != .removed else { continue }
      guard let rollback = successor.rollbackTransaction else {
        let footprint = InstantOptimisticEffectFootprint.normalized(for: successor)
        guard footprint?.entityIDs.isEmpty == true, footprint?.isGlobal == false else {
          throw InstantError(
            code: .persistenceFailed,
            operation: "reject claimed mutation",
            localID: successor.id,
            message:
              "Successor mutation '\(successor.id)' has an active optimistic effect but no durable rollback.",
            recovery:
              "Preserve the component and run an authoritative refresh instead of guessing its inverse."
          )
        }
        continue
      }
      let next = if let prepared {
        try await store.prepare(rollback, applyingTo: prepared)
      } else {
        try await store.prepare(rollback, applyingTo: hydratedSnapshot)
      }
      changedEntityIDs.formUnion(next.result.changedEntityIDs)
      prepared = next
    }

    let removedFailure = if let prepared {
      try await store.prepare(failedRollback, applyingTo: prepared)
    } else {
      try await store.prepare(failedRollback, applyingTo: hydratedSnapshot)
    }
    changedEntityIDs.formUnion(removedFailure.result.changedEntityIDs)
    var replayPrepared = removedFailure

    for index in rebasedSuccessors.indices {
      var successor = rebasedSuccessors[index]
      let newestTimestamp = replayPrepared.indexes.newestTransactionTimeMilliseconds ?? 0
      let optimisticTimestamp = InstantTimestamp(
        milliseconds: newestTimestamp == Int64.max ? newestTimestamp : newestTimestamp + 1
      )
      let operations = Self.rebaseDurableTransaction(
        in: &successor,
        at: optimisticTimestamp
      )
      successor.rollbackTransaction = nil
      successor.optimisticOverlayState = .applied
      if !operations.isEmpty {
        let replay = try await store.prepare(
          InstantStoreTransaction(id: successor.transaction.id, operations: operations),
          applyingTo: replayPrepared
        )
        changedEntityIDs.formUnion(replay.result.changedEntityIDs)
        successor.rollbackTransaction = Self.rollbackTransaction(
          mutationID: successor.id,
          prepared: replay
        )
        replayPrepared = replay
      }
      rebasedSuccessors[index] = successor
    }

    return (
      PreparedStoreMutation(
        result: InstantStoreMutationResult(
          transactionID: failedRollback.id,
          changedEntityIDs: changedEntityIDs,
          tripleCount: replayPrepared.indexes.tripleCount,
          emissions: []
        ),
        sequence: replayPrepared.sequence,
        attributes: replayPrepared.attributes,
        indexes: replayPrepared.indexes
      ),
      failedMutation,
      rebasedSuccessors
    )
  }

  private func prepareTerminalFailureRemoval(
    original: PendingMutation,
    failedMutations: [PendingMutation],
    snapshot: InstantStoreSnapshot
  ) async throws -> (
    prepared: PreparedStoreMutation?,
    replacingStoreSnapshot: InstantStoreSnapshot,
    mutations: [PendingMutation],
    failedMutation: PendingMutation
  ) {
    guard let failedIndex = failedMutations.firstIndex(where: { $0.id == original.id }) else {
      throw outboxMutationNotFound(id: original.id)
    }
    var mutations = failedMutations
    var failedMutation = mutations[failedIndex]

    // A pre-overlay-state row cannot tell us whether its optimistic writes are still materialized.
    // Preserve both the cache and the durable row until an authoritative recovery path proves the
    // state. A transaction id is correlation, not a safe inverse operation.
    guard original.optimisticOverlayState != nil || original.rollbackTransaction != nil else {
      mutations[failedIndex] = failedMutation
      return (nil, snapshot, mutations, failedMutation)
    }

    failedMutation.optimisticOverlayState = .removed
    failedMutation.rollbackTransaction = nil
    mutations[failedIndex] = failedMutation
    guard original.optimisticOverlayState != .removed,
      let failedRollback = original.rollbackTransaction
    else {
      return (nil, snapshot, mutations, failedMutation)
    }

    let successors = mutations.sorted(by: PendingMutation.creationOrder).filter { mutation in
      PendingMutation.creationOrder(original, mutation)
        && mutation.status != .failed
        && mutation.optimisticOverlayState != .removed
    }
    let deferredTriples = try await deferredValuesForPreparing(
      [failedRollback]
        + successors.compactMap(\.rollbackTransaction)
        + successors.map(\.transaction)
    )
    let hydratedSnapshot = configuration.deferredValueResidency.hydrating(
      snapshot,
      with: deferredTriples
    )
    var prepared: PreparedStoreMutation?
    var changedEntityIDs: Set<String> = []

    // Strip successors in reverse so the rejected layer's exact inverse is applied to the state it
    // originally covered. Replaying them below rebuilds each successor inverse over the new base.
    for successor in successors.reversed() {
      guard let rollback = successor.rollbackTransaction else {
        guard successor.optimisticOverlayState != nil else {
          throw unknownOptimisticOverlayState(id: successor.id, operation: "reject mutation")
        }
        continue
      }
      let next = if let prepared {
        try await store.prepare(rollback, applyingTo: prepared)
      } else {
        try await store.prepare(rollback, applyingTo: hydratedSnapshot)
      }
      changedEntityIDs.formUnion(next.result.changedEntityIDs)
      prepared = next
    }

    let removedFailure = if let prepared {
      try await store.prepare(failedRollback, applyingTo: prepared)
    } else {
      try await store.prepare(failedRollback, applyingTo: hydratedSnapshot)
    }
    changedEntityIDs.formUnion(removedFailure.result.changedEntityIDs)
    var replayPrepared = removedFailure

    for successor in successors {
      guard let successorIndex = mutations.firstIndex(where: { $0.id == successor.id }) else {
        continue
      }
      var rebasedSuccessor = mutations[successorIndex]
      let newestTimestamp = replayPrepared.indexes.newestTransactionTimeMilliseconds ?? 0
      let optimisticTimestamp = InstantTimestamp(
        milliseconds: newestTimestamp == Int64.max ? newestTimestamp : newestTimestamp + 1
      )
      let operations = Self.rebaseDurableTransaction(
        in: &rebasedSuccessor,
        at: optimisticTimestamp
      )
      rebasedSuccessor.rollbackTransaction = nil
      rebasedSuccessor.optimisticOverlayState = .applied
      if !operations.isEmpty {
        let replay = try await store.prepare(
          InstantStoreTransaction(id: rebasedSuccessor.transaction.id, operations: operations),
          applyingTo: replayPrepared
        )
        changedEntityIDs.formUnion(replay.result.changedEntityIDs)
        rebasedSuccessor.rollbackTransaction = Self.rollbackTransaction(
          mutationID: rebasedSuccessor.id,
          prepared: replay
        )
        replayPrepared = replay
      }
      mutations[successorIndex] = rebasedSuccessor
    }

    return (
      PreparedStoreMutation(
        result: InstantStoreMutationResult(
          transactionID: failedRollback.id,
          changedEntityIDs: changedEntityIDs,
          tripleCount: replayPrepared.indexes.tripleCount,
          emissions: []
        ),
        sequence: replayPrepared.sequence,
        attributes: replayPrepared.attributes,
        indexes: replayPrepared.indexes
      ),
      hydratedSnapshot,
      mutations,
      failedMutation
    )
  }

  /// Removes one server-rejected mutation and its still-visible optimistic writes after its caller
  /// has explicitly handled the failure.
  ///
  /// Instant's TypeScript reactor deletes a rejected mutation in `_handleMutationError` before
  /// rejecting the transaction promise. Instant Swift Data adapts that behavior by retaining a
  /// durable failed row for diagnostics and retry by default, and only deleting it through this
  /// package-scoped acknowledgement boundary after the caller returns `.discard`.
  @discardableResult
  package func discardFailedMutation(
    id: String,
    allowingActiveDisposition: Bool = false
  ) async throws -> PendingMutation {
    await operationGate.enter()
    do {
      let hasActiveRetryReservation = await automaticMutationRetryReservations.contains(id)
      guard allowingActiveDisposition || !hasActiveRetryReservation
      else {
        throw activeMutationDispositionError(
          id: id,
          operation: "discard failed outbox mutation"
        )
      }
      for _ in 0..<5 {
        let state = try await loadStateWithDurableOutboxSynchronizingStore()
        guard let mutation = state.snapshot.outbox.first(where: { $0.id == id }) else {
          await outbox.replace(with: state.snapshot.outbox)
          throw InstantError(
            code: .validationFailed,
            operation: "discard failed outbox mutation",
            localID: id,
            message: "The failed outbox mutation '\(id)' was not found.",
            recovery: "Inspect the current outbox and discard only a retained failed mutation."
          )
        }
        guard mutation.status == .failed,
          let update = InstantOutbox.discardingFailed(id: id, in: state.snapshot.outbox)
        else {
          await outbox.replace(with: state.snapshot.outbox)
          throw InstantError(
            code: .validationFailed,
            operation: "discard failed outbox mutation",
            localID: id,
            message: "The outbox mutation '\(id)' is \(mutation.status.rawValue), not failed.",
            recovery: "Wait for a server rejection before explicitly discarding the mutation."
          )
        }
        guard mutation.optimisticOverlayState != nil || mutation.rollbackTransaction != nil else {
          await outbox.replace(with: state.snapshot.outbox)
          throw unknownOptimisticOverlayState(
            id: id,
            operation: "discard failed outbox mutation"
          )
        }
        let storeSnapshot = await authoritativeStoreSnapshot(from: state)
        let removal = try await prepareTerminalFailureRemoval(
          original: mutation,
          failedMutations: state.snapshot.outbox,
          snapshot: storeSnapshot
        )
        let remainingMutations = removal.mutations.filter { $0.id != id }
        let nextSnapshot = InstantPersistenceSnapshot(
          store: removal.prepared?.snapshot ?? storeSnapshot,
          outbox: remainingMutations
        )
        let didSave = try await persistence.saveSnapshot(
          nextSnapshot,
          replacing: InstantPersistenceSnapshot(
            store: removal.replacingStoreSnapshot,
            outbox: state.snapshot.outbox
          ),
          expectedStoreRevision: state.storeRevision,
          expectedAttributeRevision: state.attributeRevision,
          expectedOutboxRevision: state.outboxRevision
        )
        if didSave {
          await outbox.replace(with: remainingMutations)
          if let prepared = removal.prepared {
            _ = await store.commitAndPublish(prepared)
          }
          installedStoreRevisions.install(
            storeRevision: state.storeRevision + 1,
            attributeRevision: state.attributeRevision + 1
          )
          _ = try? await publishConnectionStatusWithGateHeld()
          await operationGate.leave()
          return update.mutation
        }
      }

      throw InstantError(
        code: .persistenceFailed,
        operation: "discard failed outbox mutation",
        localID: id,
        message: "The local outbox changed repeatedly while discarding mutation '\(id)'.",
        recovery: "Retry after inspecting the current outbox."
      )
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  package func withAutomaticMutationRetrySuspended<Result: Sendable>(
    id: String,
    operation: @Sendable () async throws -> Result
  ) async rethrows -> Result {
    await automaticMutationRetryReservations.reserve(id)
    do {
      let result = try await operation()
      await automaticMutationRetryReservations.release(id)
      return result
    } catch {
      await automaticMutationRetryReservations.release(id)
      throw error
    }
  }

  private func performRetryMutationWithGateHeld(
    id: String,
    requiringFailedStatus: Bool = false
  ) async throws -> PendingMutation {
    for _ in 0..<5 {
      recordActorHop(.persistence)
      let state = try await loadStateWithDurableOutboxSynchronizingStore()
      guard let original = state.snapshot.outbox.first(where: { $0.id == id }),
        let update = InstantOutbox.retrying(id: id, in: state.snapshot.outbox)
      else {
        recordActorHop(.outbox)
        await outbox.replace(with: state.snapshot.outbox)
        throw outboxMutationNotFound(id: id)
      }
      guard !requiringFailedStatus || original.status == .failed else {
        recordActorHop(.outbox)
        await outbox.replace(with: state.snapshot.outbox)
        throw InstantError(
          code: .validationFailed,
          operation: "retry failed outbox mutation",
          localID: id,
          localMutationDisposition: .retainedUnknown,
          message: "The outbox mutation '\(id)' is \(original.status.rawValue), not failed.",
          recovery: "Refresh the failed-mutation list and retry only a retained failed mutation."
        )
      }
      guard original.optimisticOverlayState != nil || original.rollbackTransaction != nil else {
        recordActorHop(.outbox)
        await outbox.replace(with: state.snapshot.outbox)
        throw unknownOptimisticOverlayState(id: id, operation: "retry outbox mutation")
      }

      var retriedMutation = update.mutation
      var retriedMutations = update.mutations
      let shouldReapplyOptimisticOverlay =
        original.optimisticOverlayState == .removed
      let preparedRetry: PreparedStoreMutation?
      if shouldReapplyOptimisticOverlay {
        let retryStoreSnapshot = await authoritativeStoreSnapshot(from: state)
        let newestTimestamp = retryStoreSnapshot.triples.reduce(Int64.min) { newest, triple in
          max(newest, triple.txTime.milliseconds)
        }
        let optimisticTimestamp = InstantTimestamp(
          milliseconds: newestTimestamp == Int64.max
            ? newestTimestamp
            : max(newestTimestamp, 0) + 1
        )
        let operations = Self.rebaseDurableTransaction(
          in: &retriedMutation,
          at: optimisticTimestamp
        )
        if operations.isEmpty {
          preparedRetry = nil
          retriedMutation.rollbackTransaction = nil
        } else {
          let retryTransaction = InstantStoreTransaction(
            id: retriedMutation.transaction.id,
            operations: operations
          )
          let deferredTriples = try await deferredValuesForPreparing(retryTransaction)
          recordActorHop(.store)
          let prepared = try await store.prepareCurrent(
            retryTransaction,
            hydratingDeferredValues: deferredTriples
          )
          preparedRetry = prepared
          retriedMutation.rollbackTransaction = Self.rollbackTransaction(
            mutationID: retriedMutation.id,
            prepared: prepared
          )
        }
        retriedMutation.optimisticOverlayState = .applied
      } else {
        preparedRetry = nil
        if retriedMutation.optimisticOverlayState == nil {
          retriedMutation.optimisticOverlayState = .applied
        }
      }
      guard let retriedIndex = retriedMutations.firstIndex(where: { $0.id == id }) else {
        throw outboxMutationNotFound(id: id)
      }
      retriedMutations[retriedIndex] = retriedMutation
      let shouldClearConnectionFailure: Bool
      if retriedMutations.contains(where: { $0.status == .failed }) {
        shouldClearConnectionFailure = false
      } else {
        shouldClearConnectionFailure = try await persistedConnectionState() != .closed
      }
      let metadataEntries =
        shouldClearConnectionFailure
        ? [
          InstantPersistenceMetadataEntry(
            key: connectionStateMetadataKey,
            value: InstantConnectionState.opened.rawValue,
            updatedAt: configuration.now()
          )
        ]
        : []
      let deletingMetadataKeys =
        shouldClearConnectionFailure
        ? [connectionLastErrorMetadataKey]
        : []

      recordActorHop(.persistence)
      let didSave: Bool
      if let preparedRetry {
        didSave = try await persistence.saveLocalMutation(
          changedEntityTriples: preparedRetry.changedEntityTriples,
          outbox: retriedMutations,
          pendingMutation: retriedMutation,
          metadataEntries: metadataEntries,
          deletingMetadataKeys: deletingMetadataKeys,
          expectedStoreRevision: state.storeRevision,
          expectedAttributeRevision: state.attributeRevision,
          expectedOutboxRevision: state.outboxRevision
        )
      } else {
        didSave = try await persistence.saveOutbox(
          retriedMutations,
          replacing: state.snapshot.outbox,
          metadataEntries: metadataEntries,
          deletingMetadataKeys: deletingMetadataKeys,
          expectedStoreRevision: state.storeRevision,
          expectedOutboxRevision: state.outboxRevision
        )
      }
      guard didSave else { continue }

      if let preparedRetry {
        recordActorHop(.store)
        _ = await store.commitAndPublish(preparedRetry)
        installedStoreRevisions.install(
          storeRevision: state.storeRevision + 1,
          attributeRevision: state.attributeRevision
        )
      }
      recordActorHop(.outbox)
      await outbox.replace(with: retriedMutations)
      _ = try? await publishConnectionStatusWithGateHeld()
      return retriedMutation
    }

    throw outboxChangedDuringStatusUpdate(id: id)
  }

  @discardableResult
  public func retryMutation(id: String) async throws -> PendingMutation {
    await operationGate.enter()
    do {
      guard await !automaticMutationRetryReservations.contains(id) else {
        throw activeMutationDispositionError(
          id: id,
          operation: "retry outbox mutation"
        )
      }
      let mutation = try await performRetryMutationWithGateHeld(id: id)
      await operationGate.leave()
      await startLiveMutationDeliveryIfNeeded()
      return mutation
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  @discardableResult
  package func retryFailedMutation(id: String) async throws -> PendingMutation {
    await operationGate.enter()
    do {
      guard await !automaticMutationRetryReservations.contains(id) else {
        throw activeMutationDispositionError(
          id: id,
          operation: "retry failed outbox mutation"
        )
      }
      let mutation = try await performRetryMutationWithGateHeld(
        id: id,
        requiringFailedStatus: true
      )
      await operationGate.leave()
      await startLiveMutationDeliveryIfNeeded()
      return mutation
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  private func activeMutationDispositionError(
    id: String,
    operation: String
  ) -> InstantError {
    InstantError(
      code: .validationFailed,
      operation: operation,
      localID: id,
      localMutationDisposition: .retainedForRetry,
      message: "The outbox mutation '\(id)' is awaiting a server-rejection disposition.",
      recovery: "Wait for the rejection handler to retain or discard the failed mutation."
    )
  }

  @discardableResult
  public func drainPendingMutationsLocally(limit: Int? = nil) async throws -> [PendingMutation] {
    if let limit, limit < 0 {
      throw validationFailed(
        operation: "drain outbox",
        message: "Drain limit must be greater than or equal to 0.",
        recovery: "Pass a non-negative --limit value, or omit --limit to drain every pending mutation."
      )
    }

    await enterOperationGate()
    do {
      for _ in 0..<5 {
        recordActorHop(.persistence)
        let state = try await loadStateWithDurableOutboxSynchronizingStore()
        let update = InstantOutbox.confirmingPending(limit: limit, in: state.snapshot.outbox)
        guard !update.confirmed.isEmpty else {
          recordActorHop(.outbox)
          await outbox.replace(with: state.snapshot.outbox)
          await leaveOperationGate()
          return []
        }
        recordActorHop(.persistence)
        let didSave = try await persistence.saveOutbox(
          update.mutations,
          replacing: state.snapshot.outbox,
          expectedOutboxRevision: state.outboxRevision
        )
        if didSave {
          recordActorHop(.outbox)
          await outbox.replace(with: update.mutations)
          _ = try? await publishConnectionStatusWithGateHeld()
          for mutation in update.confirmed {
            await publishMutationLifecycle(mutation)
          }
          await leaveOperationGate()
          return update.confirmed
        }
      }

      throw outboxChangedDuringDrain()
    } catch {
      await leaveOperationGate()
      throw error
    }
  }

  public func localID(named name: String) async throws -> String {
    try await persistence.localID(named: name, makeID: configuration.makeID)
  }

  public func localIDs() async throws -> [InstantLocalID] {
    try await persistence.loadLocalIDs()
  }

  /// Stable Instant client id for this device + app install.
  ///
  /// Upstream: Instant TS `Reactor.getLocalId` / `db.getLocalId(name)` with a
  /// reserved name (``InstantClientID/name``). Local store only (not network
  /// latency — the `async` is actor isolation on SQLite persistence). Not the
  /// live websocket `session-id`.
  ///
  /// Caches into ``InstantClientID/current`` for **synchronous** product reads
  /// after the first resolve (bootstrap / auth setup).
  public func clientID() async throws -> String {
    let id = try await localID(named: InstantClientID.name)
    InstantClientID.prepareCurrent(id)
    return id
  }

  private func saveAuthSession(_ session: InstantAuthSession) async throws {
    await operationGate.enter()
    do {
      try await persistAuthSessionWithGateHeld(session)
      await operationGate.leave()
      recordPersistedAuthSession(session)
    } catch {
      await operationGate.leave()
      InstantDiagnostics.shared.record(
        error: error,
        subsystem: "instant-swift-data-core",
        category: "auth",
        event: "auth-session.persistence-failed",
        message: "Failed to persist an Instant auth session.",
        metadata: [
          "appID": session.appID,
          "userID": session.userID,
          "isGuest": String(session.isGuest),
        ]
      )
      throw error
    }
    await reconnectAfterAuthChangeIfNeeded()
    _ = try? await syncUserCookieToEndpoint(session)
  }

  private func persistAuthSessionWithGateHeld(_ session: InstantAuthSession) async throws {
    try await persistence.saveAuthSession(session, key: authSessionKey)
    await authSessionObservers.yield(session)
    _ = try? await publishConnectionStatusWithGateHeld()
  }

  private func recordPersistedAuthSession(_ session: InstantAuthSession) {
    InstantDiagnostics.shared.record(
      .debug,
      subsystem: "instant-swift-data-core",
      category: "auth",
      event: "auth-session.persisted",
      message: "Persisted and published an Instant auth session.",
      metadata: [
        "appID": session.appID,
        "userID": session.userID,
        "isGuest": String(session.isGuest),
        "hasRefreshToken": String(session.refreshToken?.isEmpty == false),
      ]
    )
  }

  private func outboxMutationNotFound(id: String) -> InstantError {
    InstantError(
      code: .validationFailed,
      operation: "update outbox mutation",
      localID: id,
      message: "No pending or historical outbox mutation exists for id '\(id)'.",
      recovery: "Run 'instant-swift-data outbox inspect' to list known mutation ids."
    )
  }

  private func unknownOptimisticOverlayState(id: String, operation: String) -> InstantError {
    InstantError(
      code: .persistenceFailed,
      operation: operation,
      localID: id,
      localMutationDisposition: .retainedUnknown,
      message:
        "Mutation '\(id)' predates durable optimistic-overlay metadata, so its local cache effect is unknown.",
      recovery:
        "Retain the mutation and run an authoritative recovery that explicitly verifies the server effect before retrying or discarding it."
    )
  }

  private func outboxChangedDuringStatusUpdate(id: String) -> InstantError {
    InstantError(
      code: .persistenceFailed,
      operation: "update outbox mutation",
      localID: id,
      message: "The local outbox changed repeatedly while updating mutation '\(id)'.",
      recovery: "Retry the outbox update after inspecting the current outbox."
    )
  }

  private func outboxChangedDuringLifecycleObservation(id: String) -> InstantError {
    InstantError(
      code: .persistenceFailed,
      operation: "observe mutation lifecycle",
      localID: id,
      message: "The local outbox changed repeatedly while reading mutation '\(id)'.",
      recovery: "Retry lifecycle observation after inspecting the current outbox."
    )
  }

  private func outboxChangedDuringInspection() -> InstantError {
    InstantError(
      code: .persistenceFailed,
      operation: "inspect outbox mutations",
      message: "The local outbox changed repeatedly while reconstructing durable mutations.",
      recovery: "Retry inspection after the current outbox write completes."
    )
  }

  private func outboxChangedDuringDrain() -> InstantError {
    InstantError(
      code: .persistenceFailed,
      operation: "drain outbox",
      message: "The local outbox changed repeatedly while draining pending mutations.",
      recovery: "Retry the drain after inspecting the current outbox."
    )
  }

  private func outboxChangedDuringTransportHydration() -> InstantError {
    InstantError(
      code: .persistenceFailed,
      operation: "prepare outbox transport",
      message: "The local outbox changed repeatedly while reconstructing durable mutations.",
      recovery: "Retry delivery after inspecting the current outbox."
    )
  }

  private func transactionChangedDuringPersistence(id: String) -> InstantError {
    InstantError(
      code: .persistenceFailed,
      operation: "persist transaction",
      localID: id,
      message: "The local store changed repeatedly while persisting transaction '\(id)'.",
      recovery: "Retry the transaction after reloading the local cache."
    )
  }

  private func serverTransactionChangedDuringPersistence(id: String) -> InstantError {
    InstantError(
      code: .persistenceFailed,
      operation: "apply server transaction",
      localID: id,
      message: "The local store changed repeatedly while applying server transaction '\(id)'.",
      recovery: "Retry after reloading the local cache."
    )
  }

  private func persistenceChangedDuringMigration(name: String) -> InstantError {
    InstantError(
      code: .persistenceFailed,
      operation: "migrate local persistence",
      localID: name,
      message: "The local store changed repeatedly while applying migration '\(name)'.",
      recovery: "Retry after reloading the local cache."
    )
  }

  private func validationFailed(
    operation: String,
    namespace: String? = nil,
    path: String? = nil,
    localID: String? = nil,
    message: String,
    recovery: String
  ) -> InstantError {
    InstantError(
      code: .validationFailed,
      operation: operation,
      namespace: namespace,
      path: path,
      localID: localID,
      message: message,
      recovery: recovery
    )
  }

  private func authValidationFailed(
    operation: String,
    message: String,
    recovery: String
  ) -> InstantError {
    InstantError(
      code: .authFailed,
      operation: operation,
      message: message,
      recovery: recovery
    )
  }

  private func endpointComponents(path pathComponents: [String]) throws -> URLComponents {
    guard InstantRuntimeConfiguration.isValidAPIURI(configuration.apiURI) else {
      throw Self.endpointValidationFailed(
        name: "apiURI",
        requirement: "an absolute http or https URL with a host and no query or fragment"
      )
    }
    var url = configuration.apiURI
    for pathComponent in pathComponents {
      url.appendPathComponent(pathComponent)
    }
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      throw endpointFailed(operation: "create Instant endpoint URL")
    }
    return components
  }

  private func endpointFailed(operation: String) -> InstantError {
    InstantError(
      code: .implementationFailed,
      operation: operation,
      message: "The Instant endpoint URL could not be constructed.",
      recovery: "Check the configured apiURI and appID before retrying."
    )
  }

  private func shareNotFound(operation: String, localID: String) -> InstantError {
    validationFailed(
      operation: operation,
      localID: localID,
      message: "Share '\(localID)' was not found or has been revoked.",
      recovery: "Check the share id or token, then create a new share if needed."
    )
  }

  private func streamNotFound(
    operation: String,
    localID: String,
    recovery: String
  ) -> InstantError {
    validationFailed(
      operation: operation,
      localID: localID,
      message: "Stream '\(localID)' was not found.",
      recovery: recovery
    )
  }

  private func validateStreamByteOffset(
    _ byteOffset: Int64?,
    operation: String
  ) throws {
    if let byteOffset, byteOffset < 0 {
      throw validationFailed(
        operation: operation,
        message: "Stream byte offset must be greater than or equal to 0.",
        recovery: "Pass a non-negative byte offset, or omit it to start at the beginning."
      )
    }
  }

  private func shareMembershipNotFound(
    operation: String,
    shareID: String,
    userID: String
  ) -> InstantError {
    validationFailed(
      operation: operation,
      localID: userID,
      message: "User '\(userID)' is not an active member of share '\(shareID)'.",
      recovery: "Have the user accept the share token before updating their role."
    )
  }

  private func sharePermissionRejected(snapshot: InstantShareSnapshot, userID: String) -> InstantError {
    InstantError(
      code: .permissionRejected,
      operation: "revoke share",
      localID: snapshot.share.id,
      message:
        "User '\(userID)' cannot revoke share '\(snapshot.share.id)' owned by '\(snapshot.share.ownerUserID)'.",
      recovery: "Sign in as the share owner before revoking it."
    )
  }

  private func shareRolePermissionRejected(
    snapshot: InstantShareSnapshot,
    userID: String
  ) -> InstantError {
    let message =
      "User '\(userID)' cannot update roles for share '\(snapshot.share.id)' owned by '\(snapshot.share.ownerUserID)'."
    return InstantError(
      code: .permissionRejected,
      operation: "update share role",
      localID: snapshot.share.id,
      message: message,
      recovery: "Sign in as the share owner before updating member roles."
    )
  }

  private func duplicateShareRejected(snapshot: InstantShareSnapshot) -> InstantError {
    let root = "\(snapshot.share.rootNamespace)/\(snapshot.share.rootID)"
    return validationFailed(
      operation: "create share",
      namespace: snapshot.share.rootNamespace,
      localID: snapshot.share.rootID,
      message:
        "Shared root '\(root)' already has active share '\(snapshot.share.id)'.",
      recovery: "Use the existing share token, or revoke the current share before creating another one."
    )
  }

  private func shareRootOwnershipPermissionRejected(
    snapshot: InstantShareSnapshot,
    userID: String
  ) -> InstantError {
    let root = "\(snapshot.share.rootNamespace)/\(snapshot.share.rootID)"
    let message =
      "User '\(userID)' cannot create a share for shared root '\(root)' owned by '\(snapshot.share.ownerUserID)'."
    return InstantError(
      code: .permissionRejected,
      operation: "create share",
      namespace: snapshot.share.rootNamespace,
      localID: snapshot.share.rootID,
      message: message,
      recovery: "Sign in as the share owner, or ask the owner to manage the existing share."
    )
  }

  private func sharedRootWritePermissionRejected(
    snapshot: InstantShareSnapshot,
    userID: String?
  ) -> InstantError {
    let root = "\(snapshot.share.rootNamespace)/\(snapshot.share.rootID)"
    let role = userID.flatMap { userID in
      snapshot.memberships.first { $0.userID == userID }?.role.rawValue
    }
    let message: String
    if let userID {
      if let role {
        message =
          "User '\(userID)' has \(role) access to shared root '\(root)' and cannot write it."
      } else {
        message =
          "User '\(userID)' is not a member of share '\(snapshot.share.id)' for shared root '\(root)'."
      }
    } else {
      message = "Shared root '\(root)' requires a signed-in owner or writer before it can be written."
    }

    return InstantError(
      code: .permissionRejected,
      operation: "write shared root",
      namespace: snapshot.share.rootNamespace,
      localID: snapshot.share.rootID,
      message: message,
      recovery: "Sign in as the share owner or a writer before mutating the shared record."
    )
  }

  private func normalizedEmail(_ email: String, operation: String) throws -> String {
    let email = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard email.contains("@"), email.contains(".") else {
      throw authValidationFailed(
        operation: operation,
        message: "Email address '\(email)' is not valid.",
        recovery: "Pass an email address such as user@example.com."
      )
    }
    return email
  }

  private func resolvedRoomUserID(_ userID: String?, operation: String) async throws -> String {
    if let userID = userID?.trimmingCharacters(in: .whitespacesAndNewlines), !userID.isEmpty {
      return userID
    }
    if let session = try await persistence.loadAuthSession(key: authSessionKey) {
      return session.userID
    }
    throw authValidationFailed(
      operation: operation,
      message: "Room operations require a signed-in user.",
      recovery: "Run 'instant-swift-data auth guest' first, or pass --user-id <id>."
    )
  }

  private func resolvedFileUserID(operation: String) async throws -> String {
    try await resolvedAuthenticatedUserID(operation: operation, noun: "File")
  }

  private func resolvedAuthenticatedUserID(operation: String, noun: String) async throws -> String {
    if let session = try await persistence.loadAuthSession(key: authSessionKey) {
      return session.userID
    }
    throw authValidationFailed(
      operation: operation,
      message: "\(noun) operations require a signed-in user.",
      recovery: "Run 'instant-swift-data auth guest' first."
    )
  }

  private func resolvedFileName(
    _ rawName: String?,
    sourceURL: URL,
    operation: String
  ) throws -> String {
    let name = rawName?.trimmingCharacters(in: .whitespacesAndNewlines)
      ?? sourceURL.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else {
      throw validationFailed(
        operation: operation,
        message: "File name must not be empty.",
        recovery: "Pass --name <name>, or upload a file path with a non-empty last path component."
      )
    }
    return name
  }

  private func validatedRoom(
    _ room: InstantRoomHandle,
    operation: String
  ) throws -> InstantRoomHandle {
    InstantRoomHandle(
      type: try validatedNonEmpty(
        room.type,
        label: "Room type",
        operation: operation,
        recovery: "Pass a room type, such as 'chat'."
      ),
      id: try validatedNonEmpty(
        room.id,
        label: "Room id",
        operation: operation,
        recovery: "Pass a room id, such as 'lobby'."
      )
    )
  }

  private func validatedNonEmpty(
    _ value: String,
    label: String,
    operation: String,
    recovery: String
  ) throws -> String {
    let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else {
      throw validationFailed(
        operation: operation,
        message: "\(label) must not be empty.",
        recovery: recovery
      )
    }
    return value
  }

  private func queryCacheChangedDuringMaterialization(_ plan: InstantQueryPlan) -> InstantError {
    InstantError(
      code: .persistenceFailed,
      operation: "cache query result",
      message: "The local SQLite store changed repeatedly while materializing query '\(plan.id)'.",
      recovery: "Retry the query, or reduce concurrent writes against the same local cache."
    )
  }

  private var authSessionKey: String {
    "auth:\(configuration.appID)"
  }

  private func magicCodeChallengeKey(email: String) -> String {
    "auth.magic_code:\(configuration.appID):\(email)"
  }

  private var processedTransactionIDMetadataKey: String {
    "sync.processed_transaction_id:\(configuration.appID)"
  }

  private var connectionStateMetadataKey: String {
    "connection.state:\(configuration.appID)"
  }

  private var connectionLastErrorMetadataKey: String {
    "connection.last_error:\(configuration.appID)"
  }

  private var appScopedCookieSyncLastUpdatedMetadataKey: String {
    "\(Self.cookieSyncLastUpdatedMetadataKey):\(configuration.appID)"
  }

  private func roomPresenceObservationKey(_ room: InstantRoomHandle) -> InstantRoomPresenceObservationKey {
    InstantRoomPresenceObservationKey(appID: configuration.appID, room: room)
  }

  private func combinedRoomPresence(
    _ localMembers: [InstantRoomPresenceMember],
    room: InstantRoomHandle
  ) async -> [InstantRoomPresenceMember] {
    guard configuration.liveTransport != nil else { return localMembers }
    let activeLocalMembers = await activeRoomPresenceState.activeMembers(
      localMembers,
      in: room
    )
    let currentSessionID = await liveSession.currentSessionID
    let remoteMembers = await liveRoomPresenceState.current(
      room: room,
      excludingSessionID: currentSessionID,
      appID: configuration.appID,
      updatedAt: configuration.now()
    )
    return mergedRoomPresence(local: activeLocalMembers, remote: remoteMembers)
  }

  private func mergedRoomPresence(
    local: [InstantRoomPresenceMember],
    remote: [InstantRoomPresenceMember]
  ) -> [InstantRoomPresenceMember] {
    var membersByID = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
    for member in remote {
      membersByID[member.id] = member
    }
    return membersByID.values.sorted { $0.id < $1.id }
  }

  private func roomTopicObservationKey(
    room: InstantRoomHandle,
    topic: String
  ) -> InstantRoomTopicObservationKey {
    InstantRoomTopicObservationKey(
      appID: configuration.appID,
      room: room,
      topic: topic
    )
  }

  private var storedFilesObservationKey: InstantStoredFilesObservationKey {
    InstantStoredFilesObservationKey(appID: configuration.appID)
  }

  private func streamChunksObservationKey(streamID: String) -> InstantStreamChunksObservationKey {
    InstantStreamChunksObservationKey(appID: configuration.appID, streamID: streamID)
  }

  private func streamContentObservationKey(streamID: String) -> InstantStreamContentObservationKey {
    InstantStreamContentObservationKey(
      appID: configuration.appID,
      selector: .streamID(streamID)
    )
  }

  private func streamContentObservationKey(clientID: String) -> InstantStreamContentObservationKey {
    InstantStreamContentObservationKey(
      appID: configuration.appID,
      selector: .clientID(clientID)
    )
  }

  private func sharesObservationKey(userID: String) -> InstantSharesObservationKey {
    InstantSharesObservationKey(appID: configuration.appID, userID: userID)
  }

  private func publishStreamContentUpdates(streamID: String) async throws {
    guard let metadata = try await persistence.loadStreamMetadata(
      appID: configuration.appID,
      streamID: streamID
    ) else { return }
    let keys = [
      streamContentObservationKey(streamID: streamID),
      streamContentObservationKey(clientID: metadata.clientID),
    ]
    for key in keys {
      let byteOffsets = await streamContentObservers.byteOffsets(for: key)
      for byteOffset in byteOffsets {
        if let read = try await persistence.loadStreamContent(
          appID: configuration.appID,
          streamID: streamID,
          byteOffset: byteOffset
        ) {
          await streamContentObservers.publish(read, for: key, byteOffset: byteOffset)
        }
      }
    }
  }

  private func publishShares(for userID: String) async throws {
    let snapshots = try await persistence.loadShareSnapshots(
      appID: configuration.appID,
      userID: userID
    )
    await sharesObservers.publish(snapshots, for: sharesObservationKey(userID: userID))
  }

  private static func emptyObservation(_ plan: InstantQueryPlan) -> AsyncStream<InstantQueryEmission> {
    AsyncStream<InstantQueryEmission> { continuation in
      continuation.yield(InstantQueryEmission(queryID: plan.id, sequence: 0, values: []))
      continuation.finish()
    }
  }

  private func recordActorHop(_ boundary: InstantActorHopBoundary) {
    configuration.actorHopRecorder?.record(boundary)
  }

  /// `operation` defaults to the caller's own function so a stalled gate names
  /// the function that is actually holding it rather than this wrapper.
  private func enterOperationGate(operation: String = #function) async {
    recordActorHop(.operationGate)
    await operationGate.enter(operation: operation)
  }

  /// Cancellation-aware variant for callers that already throw. A caller that
  /// throws here never acquired the gate and must not leave it.
  private func enterOperationGateUnlessCancelled(operation: String = #function) async throws {
    recordActorHop(.operationGate)
    try await operationGate.enterUnlessCancelled(operation: operation)
  }

  private func leaveOperationGate() async {
    recordActorHop(.operationGate)
    await operationGate.leave()
  }

  private func enterMutationFlushGateUnlessCancelled(
    operation: String = #function
  ) async throws {
    recordActorHop(.mutationFlushGate)
    try await mutationFlushGate.enterUnlessCancelled(operation: operation)
  }

  private func leaveMutationFlushGate() async {
    recordActorHop(.mutationFlushGate)
    await mutationFlushGate.leave()
  }
}

private extension InstantStoreMutationResult {
  func serverApplicationResult(
    processedTransactionID: String,
    pendingMutations: [PendingMutation]
  ) -> InstantServerTransactionApplicationResult {
    InstantServerTransactionApplicationResult(
      mutation: self,
      syncState: InstantSyncState(processedTransactionID: processedTransactionID),
      pendingMutationCount: pendingMutations.filter { $0.status == .pending }.count
    )
  }
}

private extension InstantEntitySnapshot {
  func stringValue(for field: String) -> String? {
    guard case let .string(value) = values[field]?.first else { return nil }
    return value
  }
}

private extension InstantTripleOperation {
  var localWriteTransactionIDs: [String] {
    switch self {
    case let .merge(triple), let .insert(triple), let .retract(triple):
      return [triple.txID]

    case let .mergeByLookup(_, _, _, txID, _),
      let .insertByLookup(_, _, _, txID, _),
      let .retractByLookup(_, _, _, txID, _):
      return [txID]

    case .requireEntityMissing, .requireEntityMissingByLookup,
      .requireEntityExists, .requireEntityExistsByLookup,
      .requireTripleExists,
      .deleteEntity, .deleteEntityInNamespace, .deleteEntityByLookup,
      .ruleParams, .ruleParamsByLookup:
      return []
    }
  }

  var isRebasedLocalWrite: Bool {
    switch self {
    case .merge, .mergeByLookup, .insert, .insertByLookup, .retract, .retractByLookup,
      .deleteEntity, .deleteEntityInNamespace, .deleteEntityByLookup:
      return true

    case .requireEntityMissing, .requireEntityMissingByLookup,
      .requireEntityExists, .requireEntityExistsByLookup,
      .requireTripleExists,
      .ruleParams, .ruleParamsByLookup:
      return false
    }
  }

  func rebased(at timestamp: InstantTimestamp) -> Self {
    switch self {
    case var .merge(triple):
      triple.txTime = timestamp
      return .merge(triple)

    case let .mergeByLookup(entity, attributeID, value, txID, _):
      return .mergeByLookup(
        entity: entity,
        attributeID: attributeID,
        value: value,
        txID: txID,
        txTime: timestamp
      )

    case var .insert(triple):
      triple.txTime = timestamp
      return .insert(triple)

    case let .insertByLookup(entity, attributeID, value, txID, _):
      return .insertByLookup(
        entity: entity,
        attributeID: attributeID,
        value: value,
        txID: txID,
        txTime: timestamp
      )

    case var .retract(triple):
      triple.txTime = timestamp
      return .retract(triple)

    case let .retractByLookup(entity, attributeID, value, txID, _):
      return .retractByLookup(
        entity: entity,
        attributeID: attributeID,
        value: value,
        txID: txID,
        txTime: timestamp
      )

    case .deleteEntity, .deleteEntityInNamespace, .deleteEntityByLookup:
      return self

    case .requireEntityMissing, .requireEntityMissingByLookup,
      .requireEntityExists, .requireEntityExistsByLookup,
      .requireTripleExists,
      .ruleParams, .ruleParamsByLookup:
      return self
    }
  }
}

private extension String {
  var nilIfEmpty: String? {
    isEmpty ? nil : self
  }
}
