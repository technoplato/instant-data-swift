import CustomDump
import Dependencies
import Foundation
import Testing

@testable import InstantSwiftData

#if canImport(SwiftUI)
  import SwiftUI

  @Suite(.serialized)
  struct V3AuthLoginFixtureTests {
    private let sourceReferences = [
      "upstream/instant/client/packages/vue/src/tests/InstantVueDatabase.test.ts:216-297",
      "upstream/instant/client/packages/core/src/authAPI.ts:8-184",
      "upstream/instant/client/packages/core/__tests__/src/auth-extra-fields.e2e.test.ts:99-144",
      "screens/v3/auth-login.md:1-264",
    ]

    @Test @MainActor
    func authLoginSyntaxCompilesWithDeclaredProviders() {
      let screen = V3AuthLoginFixture()
      let view: any View = screen
      _ = view

      expectNoDifference(
        V3VoiceTrailAuthProviders.all.map(\.id.rawValue),
        ["magic-code", "apple", "google", "github", "enterprise-oidc"]
      )
      expectNoDifference(
        sourceReferences,
        [
          "upstream/instant/client/packages/vue/src/tests/InstantVueDatabase.test.ts:216-297",
          "upstream/instant/client/packages/core/src/authAPI.ts:8-184",
          "upstream/instant/client/packages/core/__tests__/src/auth-extra-fields.e2e.test.ts:99-144",
          "screens/v3/auth-login.md:1-264",
        ]
      )
    }

    @Test @MainActor
    func magicCodeActionsOwnStateAndRestoreDurableSessionAfterRelaunch() async throws {
      let cacheURL = v3AuthCacheURL("magic-code")
      let appID = "v3-auth-magic-code"
      let runtime = try await v3AuthRuntime(appID: appID, cacheURL: cacheURL)
      let client = InstantSwiftDataClient(runtime: runtime)
      let state = InstantAuthState<V3VoiceTrailUser>(
        providers: V3VoiceTrailAuthProviders.all
      )
      let callbacks = V3AuthCallbackRecorder()
      state.email = "person@example.com"

      let sendTask = state.sendMagicCode(
        using: client,
        onChallengeSent: { callbacks.challenges.append($0) },
        onFailure: { callbacks.failures.append($0) }
      )
      await sendTask.value
      let challenge = try #require(callbacks.challenges.first)
      expectNoDifference(state.mode, .magicCodeSent(email: "person@example.com"))
      expectNoDifference(state.isBusy, false)
      expectNoDifference(callbacks.failures, [])

      state.magicCode = challenge.code
      let verifyTask = state.verifyMagicCode(
        using: client,
        onSignedIn: { callbacks.signedIn.append($0) },
        onFailure: { callbacks.failures.append($0) }
      )
      await verifyTask.value
      let signedIn = try #require(callbacks.signedIn.first)
      expectNoDifference(signedIn.providerID, .magicCode)
      expectNoDifference(state.session, signedIn.session)
      expectNoDifference(state.user?.id.rawValue, signedIn.session.userID)
      expectNoDifference(state.user?.session, signedIn.session)
      expectNoDifference(state.user?.email, "person@example.com")
      expectNoDifference(state.user?.type, .user)
      expectNoDifference(state.user?.isGuest, false)
      expectNoDifference(state.status, .signedIn(signedIn.session))
      expectNoDifference(callbacks.challenges.count, 1)
      expectNoDifference(callbacks.signedIn.count, 1)
      expectNoDifference(callbacks.failures, [])

      let relaunchedRuntime = try await v3AuthRuntime(appID: appID, cacheURL: cacheURL)
      let relaunchedState = InstantAuthState<V3VoiceTrailUser>(
        providers: V3VoiceTrailAuthProviders.all
      )
      relaunchedState.startObservationIfNeeded(
        using: InstantSwiftDataClient(runtime: relaunchedRuntime)
      )
      try await waitForV3AuthCondition(operation: "restore durable auth session") {
        relaunchedState.session == signedIn.session
      }
      expectNoDifference(relaunchedState.status, .signedIn(signedIn.session))
      expectNoDifference(relaunchedState.user?.id.rawValue, signedIn.session.userID)
      expectNoDifference(callbacks.signedIn.count, 1)
      relaunchedState.stopObservation()
    }

    @Test @MainActor
    func invalidMagicCodePublishesFailureOnceAndCanRetry() async throws {
      let runtime = try await v3AuthRuntime(
        appID: "v3-auth-invalid-code",
        cacheURL: v3AuthCacheURL("invalid-code")
      )
      let client = InstantSwiftDataClient(runtime: runtime)
      let state = InstantAuthState<V3VoiceTrailUser>(
        providers: V3VoiceTrailAuthProviders.all
      )
      let callbacks = V3AuthCallbackRecorder()
      state.email = "retry@example.com"

      let sendTask = state.sendMagicCode(
        using: client,
        onChallengeSent: { callbacks.challenges.append($0) },
        onFailure: { callbacks.failures.append($0) }
      )
      await sendTask.value
      let challenge = try #require(callbacks.challenges.first)

      state.magicCode = "wrong-code"
      let failedTask = state.verifyMagicCode(
        using: client,
        onSignedIn: { callbacks.signedIn.append($0) },
        onFailure: { callbacks.failures.append($0) }
      )
      await failedTask.value
      expectNoDifference(callbacks.failures.count, 1)
      expectNoDifference(callbacks.signedIn, [])
      expectNoDifference(state.mode, .magicCodeSent(email: "retry@example.com"))
      guard case .failed = state.status else {
        Issue.record("Expected invalid magic code to produce failed auth status.")
        return
      }

      state.magicCode = challenge.code
      let retryTask = state.verifyMagicCode(
        using: client,
        onSignedIn: { callbacks.signedIn.append($0) },
        onFailure: { callbacks.failures.append($0) }
      )
      await retryTask.value
      expectNoDifference(callbacks.failures.count, 1)
      expectNoDifference(callbacks.signedIn.count, 1)
      let signedIn = try #require(callbacks.signedIn.first)
      expectNoDifference(state.status, .signedIn(signedIn.session))
    }

    @Test @MainActor
    func replacingAuthActionCancelsStaleMagicCodeCallback() async throws {
      let gate = V3AuthChallengeGate()
      let guest = v3AuthSession(userID: "guest-after-cancel", isGuest: true)
      let client = v3AuthClient(
        signInAsGuest: { guest },
        sendMagicCode: { email in
          await gate.started()
          await gate.waitForRelease()
          return v3AuthChallenge(email: email)
        }
      )
      let state = InstantAuthState<V3VoiceTrailUser>(
        providers: V3VoiceTrailAuthProviders.all
      )
      let callbacks = V3AuthCallbackRecorder()
      state.email = "cancel@example.com"

      let staleTask = state.sendMagicCode(
        using: client,
        onChallengeSent: { callbacks.challenges.append($0) },
        onFailure: { callbacks.failures.append($0) }
      )
      await gate.waitUntilStarted()
      let guestTask = state.signInAsGuest(
        using: client,
        onSignedIn: { callbacks.signedIn.append($0) },
        onFailure: { callbacks.failures.append($0) }
      )
      await guestTask.value
      await gate.release()
      await staleTask.value

      expectNoDifference(callbacks.challenges, [])
      expectNoDifference(callbacks.signedIn.map(\.providerID), [.guest])
      expectNoDifference(callbacks.failures, [])
      expectNoDifference(state.status, .signedIn(guest))
      expectNoDifference(state.isBusy, false)
    }

    @Test @MainActor
    func signOutClearsOwnedStateAndForwardsTokenInvalidationChoice() async throws {
      let guest = v3AuthSession(userID: "guest-to-sign-out", isGuest: true)
      let signOuts = V3AuthSignOutRecorder()
      let client = v3AuthClient(
        signInAsGuest: { guest },
        signOutWithOptions: { invalidateToken in
          await signOuts.record(invalidateToken)
        }
      )
      let state = InstantAuthState<V3VoiceTrailUser>(
        providers: V3VoiceTrailAuthProviders.all
      )
      let callbacks = V3AuthCallbackRecorder()

      await state.signInAsGuest(using: client).value
      state.email = "person@example.com"
      state.magicCode = "123456"
      await state.signOut(
        using: client,
        invalidateToken: false,
        onSignedOut: { callbacks.signedOutCount += 1 },
        onFailure: { callbacks.failures.append($0) }
      ).value

      let signOutValues = await signOuts.values()
      expectNoDifference(signOutValues, [false])
      expectNoDifference(callbacks.signedOutCount, 1)
      expectNoDifference(callbacks.failures, [])
      expectNoDifference(state.session, nil)
      expectNoDifference(state.status, .signedOut)
      expectNoDifference(state.mode, .enteringEmail)
      expectNoDifference(state.email, "")
      expectNoDifference(state.magicCode, "")
      expectNoDifference(state.isBusy, false)
    }

    @Test @MainActor
    func installedClientOwnsEveryDefaultAuthAction() async {
      let installedOperations = V3AuthOperationRecorder()
      let fallbackOperations = V3AuthOperationRecorder()
      let installedClient = v3AuthRoutingClient(
        recorder: installedOperations,
        userIDPrefix: "installed"
      )
      let fallbackClient = v3AuthRoutingClient(
        recorder: fallbackOperations,
        userIDPrefix: "fallback"
      )
      let provider = AuthProvider.apple(clientName: "apple-ios", presentation: .native)
      let credential = InstantAuthProviderCredential(
        providerID: provider.id,
        payload: .idToken(value: "apple-token", nonce: "apple-nonce")
      )

      await withDependencies {
        $0.defaultInstantSwiftData = fallbackClient
        $0.instantAuthProviderAuthorizer = InstantAuthProviderAuthorizer { _ in credential }
      } operation: {
        let state = InstantAuthState<V3VoiceTrailUser>(
          providers: V3VoiceTrailAuthProviders.all
        )
        state.installDefaultClient(installedClient)

        state.email = "person@example.com"
        await state.sendMagicCode().value
        state.magicCode = "123456"
        await state.verifyMagicCode().value
        await state.signInAsGuest().value
        await state.signOut().value
        await state.signIn(provider).value
      }

      let routedOperations = await installedOperations.values()
      let fallbackValues = await fallbackOperations.values()
      expectNoDifference(
        routedOperations,
        ["send-magic-code", "verify-magic-code", "guest", "sign-out", "provider"]
      )
      expectNoDifference(fallbackValues, [])
    }

    @Test @MainActor
    func runtimeLessCopyIsStableWhileReplacementRestartsAndTeardownCancels() async throws {
      let lifecycle = V3AuthLifecycleRecorder()
      let client = v3AuthLifecycleClient(recorder: lifecycle)
      let clientCopy = client
      let replacementClient = v3AuthLifecycleClient(recorder: lifecycle)
      var state: InstantAuthState<V3VoiceTrailUser>? = InstantAuthState(
        providers: V3VoiceTrailAuthProviders.all
      )
      weak let weakState = state

      state?.installDefaultClient(client)
      state?.startObservationIfNeeded()
      try await waitForV3AuthAsyncCondition(operation: "start auth observation") {
        await lifecycle.snapshot().observationStarts == 1
      }

      state?.installDefaultClient(clientCopy)
      state?.installDefaultClient(clientCopy)
      state?.installDefaultClient(clientCopy)
      try await Task.sleep(for: .milliseconds(20))
      let stableSnapshot = await lifecycle.snapshot()
      expectNoDifference(
        stableSnapshot,
        V3AuthLifecycleRecorder.Snapshot(
          observationStarts: 1,
          observationTerminations: 0,
          actionStarts: 0,
          actionCancellations: 0
        )
      )

      state?.installDefaultClient(replacementClient)
      try await waitForV3AuthAsyncCondition(operation: "replace auth observation client") {
        let snapshot = await lifecycle.snapshot()
        return snapshot.observationStarts == 2 && snapshot.observationTerminations == 1
      }

      let activeAction = state?.signInAsGuest()
      try await waitForV3AuthAsyncCondition(operation: "start auth action") {
        await lifecycle.snapshot().actionStarts == 1
      }
      state = nil
      #expect(weakState === nil)
      try await waitForV3AuthAsyncCondition(operation: "tear down auth work") {
        let snapshot = await lifecycle.snapshot()
        return snapshot.observationTerminations == 2 && snapshot.actionCancellations == 1
      }
      await activeAction?.value
    }

    @Test @MainActor
    func providerActionExchangesTypedCredentialAndFiresCallbacksOnce() async throws {
      let provider = AuthProvider.apple(clientName: "apple-ios", presentation: .native)
      let credential = InstantAuthProviderCredential(
        providerID: provider.id,
        payload: .idToken(value: "apple-token", nonce: "apple-nonce")
      )
      let session = v3AuthSession(userID: "apple-user", isGuest: false)
      let exchange = V3AuthProviderExchangeRecorder(session: session)
      let client = v3AuthClient(
        signInWithIDToken: { clientName, token, nonce in
          await exchange.record(clientName: clientName, token: token, nonce: nonce)
          return session
        }
      )
      let state = InstantAuthState<V3VoiceTrailUser>(
        providers: V3VoiceTrailAuthProviders.all
      )
      let callbacks = V3AuthCallbackRecorder()
      let task = state.signIn(
        provider,
        using: client,
        authorizer: InstantAuthProviderAuthorizer { _ in credential },
        onProviderCompleted: { callbacks.credentials.append($0) },
        onSignedIn: { callbacks.signedIn.append($0) },
        onFailure: { callbacks.failures.append($0) }
      )
      await task.value

      expectNoDifference(callbacks.credentials, [credential])
      expectNoDifference(callbacks.signedIn.map(\.providerID), [provider.id])
      expectNoDifference(callbacks.failures, [])
      let exchangedValues = await exchange.values()
      expectNoDifference(
        exchangedValues,
        [.init(clientName: "apple-ios", token: "apple-token", nonce: "apple-nonce")]
      )
      expectNoDifference(state.status, .signedIn(session))
    }
  }

  @MainActor
  private struct V3AuthLoginFixture: View {
    @InstantAuth(V3VoiceTrailUser.self, providers: V3VoiceTrailAuthProviders.self)
    private var auth

    var body: some View {
      VStack {
        ForEach(auth.providers) { provider in
          Button(provider.title) {
            auth.signIn(
              provider,
              onProviderCompleted: { _ in },
              onSignedIn: { _ in },
              onFailure: { _ = $0.recoveryMessage }
            )
          }
        }
        TextField("Email", text: $auth.email)
        switch auth.mode {
        case .magicCodeSent, .verifyingMagicCode:
          TextField("Code", text: $auth.magicCode)
          Button("Verify code") {
            auth.verifyMagicCode(onSignedIn: { _ in }, onFailure: { _ in })
          }
          Button("Use a different email") {
            auth.resetMagicCode()
          }
        default:
          Button("Send magic code") {
            auth.sendMagicCode(onChallengeSent: { _ in }, onFailure: { _ in })
          }
        }
        Button("Continue as guest") {
          auth.signInAsGuest(onSignedIn: { _ in }, onFailure: { _ in })
        }
      }
      .disabled(auth.isBusy)
    }
  }

  private enum V3VoiceTrailAuthProviders: InstantAuthProviderCatalog {
    static let magicCode = AuthProvider.magicCode(
      email: .instant,
      extraFields: V3VoiceTrailUser.Signup.self
    )
    static let apple = AuthProvider.apple(clientName: "apple-ios", presentation: .native)
    static let google = AuthProvider.google(clientName: "google-ios", presentation: .native)
    static let github = AuthProvider.github(
      clientName: "github-web",
      presentation: .externalBrowser
    )
    static let enterprise = AuthProvider.authorizationCode(
      id: "enterprise-oidc",
      clientName: "enterprise-oidc"
    )
    static let all = [magicCode, apple, google, github, enterprise]
  }

  private struct V3VoiceTrailUser: Hashable, Codable, InstantEntityModel {
    struct Signup: Sendable {}

    var id: InstantID<V3VoiceTrailUser>
    var email: String

    static let instantNamespace = "$users"
    static let email = InstantAttributePath<V3VoiceTrailUser, String>("email")
    static let instantAttributes = [
      InstantAttribute(
        id: "$users/email",
        namespace: instantNamespace,
        name: "email",
        valueType: .string,
        isIndexed: true,
        isUnique: true
      )
    ]

    init(snapshot: InstantEntitySnapshot) throws {
      guard case .string(let email) = snapshot.values["email"]?.first else {
        throw InstantError(
          code: .decodeFailed,
          operation: "decode V3 auth user fixture",
          namespace: Self.instantNamespace,
          localID: snapshot.id,
          message: "Expected an email value.",
          recovery: "Keep the V3 auth fixture aligned with the users schema."
        )
      }
      id = InstantID(rawValue: snapshot.id)
      self.email = email
    }
  }

  @MainActor
  private final class V3AuthCallbackRecorder {
    var challenges: [InstantMagicCodeChallenge] = []
    var credentials: [InstantAuthProviderCredential] = []
    var signedIn: [InstantAuthSignedInEvent] = []
    var failures: [InstantError] = []
    var signedOutCount = 0
  }

  private actor V3AuthSignOutRecorder {
    private var recorded: [Bool] = []

    func record(_ invalidateToken: Bool) {
      recorded.append(invalidateToken)
    }

    func values() -> [Bool] {
      recorded
    }
  }

  private actor V3AuthOperationRecorder {
    private var operations: [String] = []

    func record(_ operation: String) {
      operations.append(operation)
    }

    func values() -> [String] {
      operations
    }
  }

  private actor V3AuthLifecycleRecorder {
    struct Snapshot: Equatable, Sendable {
      var observationStarts: Int
      var observationTerminations: Int
      var actionStarts: Int
      var actionCancellations: Int
    }

    private var observationStarts = 0
    private var observationTerminations = 0
    private var actionStarts = 0
    private var actionCancellations = 0

    func observationStarted() {
      observationStarts += 1
    }

    func observationTerminated() {
      observationTerminations += 1
    }

    func actionStarted() {
      actionStarts += 1
    }

    func actionCancelled() {
      actionCancellations += 1
    }

    func snapshot() -> Snapshot {
      Snapshot(
        observationStarts: observationStarts,
        observationTerminations: observationTerminations,
        actionStarts: actionStarts,
        actionCancellations: actionCancellations
      )
    }
  }

  private actor V3AuthChallengeGate {
    private var didStart = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func started() {
      didStart = true
      let waiters = startWaiters
      startWaiters = []
      for waiter in waiters { waiter.resume() }
    }

    func waitUntilStarted() async {
      guard !didStart else { return }
      await withCheckedContinuation { startWaiters.append($0) }
    }

    func waitForRelease() async {
      await withCheckedContinuation { releaseWaiters.append($0) }
    }

    func release() {
      let waiters = releaseWaiters
      releaseWaiters = []
      for waiter in waiters { waiter.resume() }
    }
  }

  private actor V3AuthProviderExchangeRecorder {
    struct Value: Equatable, Sendable {
      var clientName: String
      var token: String
      var nonce: String?
    }

    private let session: InstantAuthSession
    private var recorded: [Value] = []

    init(session: InstantAuthSession) {
      self.session = session
    }

    func record(clientName: String, token: String, nonce: String?) {
      recorded.append(Value(clientName: clientName, token: token, nonce: nonce))
    }

    func values() -> [Value] {
      recorded
    }
  }

  private func v3AuthRuntime(appID: String, cacheURL: URL) async throws -> InstantRuntime {
    try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: appID,
        persistenceURL: cacheURL,
        initialAttributes: []
      )
    )
  }

  private func v3AuthCacheURL(_ suffix: String) -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("v3-auth-\(suffix)-\(UUID().uuidString).sqlite")
  }

  private func v3AuthSession(userID: String, isGuest: Bool) -> InstantAuthSession {
    let timestamp = InstantTimestamp(milliseconds: 1_700_000_600_000)
    return InstantAuthSession(
      appID: "v3-auth-test",
      userID: userID,
      isGuest: isGuest,
      createdAt: timestamp,
      updatedAt: timestamp
    )
  }

  private func v3AuthChallenge(email: String) -> InstantMagicCodeChallenge {
    InstantMagicCodeChallenge(
      appID: "v3-auth-test",
      email: email,
      code: "123456",
      createdAt: InstantTimestamp(milliseconds: 1_700_000_600_000),
      expiresAt: InstantTimestamp(milliseconds: 1_700_000_900_000)
    )
  }

  private func v3AuthClient(
    observeAuthSession:
      @escaping @Sendable () async throws -> AsyncStream<InstantAuthSession?> = {
        AsyncStream { $0.finish() }
      },
    signInAsGuest: @escaping @Sendable () async throws -> InstantAuthSession = {
      v3AuthSession(userID: "unused-guest", isGuest: true)
    },
    sendMagicCode: @escaping @Sendable (String) async throws -> InstantMagicCodeChallenge = {
      v3AuthChallenge(email: $0)
    },
    signInWithMagicCode:
      @escaping @Sendable (String, String) async throws -> InstantAuthSession = { _, _ in
        v3AuthSession(userID: "unused-magic-code", isGuest: false)
      },
    signOutWithOptions: @escaping @Sendable (Bool) async throws -> Void = { _ in },
    signInWithIDToken:
      @escaping @Sendable (String, String, String?) async throws
      -> InstantAuthSession = { _, _, _ in
        v3AuthSession(userID: "unused-id-token", isGuest: false)
      }
  ) -> InstantSwiftDataClient {
    InstantSwiftDataClient(
      transact: { transaction in
        InstantStoreMutationResult(
          transactionID: transaction.id,
          changedEntityIDs: [],
          tripleCount: transaction.operations.count,
          emissions: []
        )
      },
      query: { _ in [] },
      observe: { _ in AsyncStream { $0.finish() } },
      pendingMutations: { [] },
      localID: { "v3-auth-\($0)" },
      observeAuthSession: observeAuthSession,
      signInAsGuest: signInAsGuest,
      sendMagicCode: sendMagicCode,
      signInWithMagicCode: signInWithMagicCode,
      signInWithIDToken: signInWithIDToken,
      signOutWithOptions: signOutWithOptions
    )
  }

  private func v3AuthRoutingClient(
    recorder: V3AuthOperationRecorder,
    userIDPrefix: String
  ) -> InstantSwiftDataClient {
    v3AuthClient(
      signInAsGuest: {
        await recorder.record("guest")
        return v3AuthSession(userID: "\(userIDPrefix)-guest", isGuest: true)
      },
      sendMagicCode: { email in
        await recorder.record("send-magic-code")
        return v3AuthChallenge(email: email)
      },
      signInWithMagicCode: { _, _ in
        await recorder.record("verify-magic-code")
        return v3AuthSession(userID: "\(userIDPrefix)-magic-code", isGuest: false)
      },
      signOutWithOptions: { _ in
        await recorder.record("sign-out")
      },
      signInWithIDToken: { _, _, _ in
        await recorder.record("provider")
        return v3AuthSession(userID: "\(userIDPrefix)-provider", isGuest: false)
      }
    )
  }

  private func v3AuthLifecycleClient(
    recorder: V3AuthLifecycleRecorder
  ) -> InstantSwiftDataClient {
    v3AuthClient(
      observeAuthSession: {
        await recorder.observationStarted()
        let stream = AsyncStream<InstantAuthSession?>.makeStream()
        stream.continuation.onTermination = { @Sendable _ in
          Task { await recorder.observationTerminated() }
        }
        return stream.stream
      },
      signInAsGuest: {
        await recorder.actionStarted()
        return try await withTaskCancellationHandler {
          try await Task.sleep(for: .seconds(60))
          return v3AuthSession(userID: "unexpected-finished-action", isGuest: true)
        } onCancel: {
          Task { await recorder.actionCancelled() }
        }
      }
    )
  }

  private func waitForV3AuthCondition(
    operation: String,
    condition: @escaping @MainActor @Sendable () -> Bool
  ) async throws {
    for _ in 0..<100 {
      if await condition() { return }
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    throw InstantError(
      code: .validationFailed,
      operation: operation,
      message: "Timed out waiting for V3 auth state.",
      recovery: "Inspect the auth session observation and action lifecycle."
    )
  }

  private func waitForV3AuthAsyncCondition(
    operation: String,
    condition: @escaping @Sendable () async -> Bool
  ) async throws {
    for _ in 0..<100 {
      if await condition() { return }
      try await Task.sleep(for: .milliseconds(10))
    }
    throw InstantError(
      code: .validationFailed,
      operation: operation,
      message: "Timed out waiting for V3 auth lifecycle.",
      recovery: "Inspect the auth dependency installation and teardown lifecycle."
    )
  }
#endif
