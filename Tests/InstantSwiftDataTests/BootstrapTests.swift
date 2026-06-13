import CustomDump
import Darwin
import Dependencies
import Foundation
import InstantSwiftData
import Testing

@Suite(.serialized)
struct BootstrapTests {
  @Test
  func defaultClientReportsMissingBootstrap() async {
    @Dependency(\.defaultInstantSwiftData) var client

    do {
      _ = try await client.transact(InstantStoreTransaction(id: "tx", operations: []))
      #expect(Bool(false), "Expected the default client to fail before bootstrap.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .implementationFailed)
      expectNoDifference(error.operation, "access default InstantSwiftData client")
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    do {
      _ = try await client.query(TodoExample.query)
      #expect(Bool(false), "Expected the default client query to fail before bootstrap.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .implementationFailed)
      expectNoDifference(error.operation, "access default InstantSwiftData client")
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    do {
      _ = try await client.authSession()
      #expect(Bool(false), "Expected the default client auth session to fail before bootstrap.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .implementationFailed)
      expectNoDifference(error.operation, "access default InstantSwiftData client")
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    do {
      _ = try await client.observeAuthSession()
      #expect(Bool(false), "Expected the default client auth observer to fail before bootstrap.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .implementationFailed)
      expectNoDifference(error.operation, "access default InstantSwiftData client")
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    do {
      _ = try await client.signInWithIDToken(clientName: "google-ios", idToken: "token")
      #expect(Bool(false), "Expected the default client ID token auth to fail before bootstrap.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .implementationFailed)
      expectNoDifference(error.operation, "access default InstantSwiftData client")
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    do {
      _ = try await client.signInWithOAuth(code: "oauth-code")
      #expect(Bool(false), "Expected the default client OAuth auth to fail before bootstrap.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .implementationFailed)
      expectNoDifference(error.operation, "access default InstantSwiftData client")
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }
  }

  @Test
  func bootstrapInstallsRuntimeBackedClient() async throws {
    let appID = "bootstrap-test-\(UUID().uuidString)"
    let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
    let fixedUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!

    try await withDependencies {
      $0.date.now = fixedDate
      $0.uuid = .constant(fixedUUID)
      try await $0.bootstrapInstantSwiftData(
        appID: appID,
        apiURI: try #require(URL(string: "https://api.example.test/custom")),
        websocketURI: try #require(URL(string: "wss://ws.example.test/runtime/session")),
        context: .test,
        initialAttributes: TodoExample.attributes
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var client

      guard let runtime = client.runtime else {
        #expect(Bool(false), "Expected a runtime-backed client.")
        return
      }
      #expect(runtime.configuration.persistenceURL.path.contains(fixedUUID.uuidString.lowercased()))
      expectNoDifference(runtime.configuration.apiURI.absoluteString, "https://api.example.test/custom")
      expectNoDifference(
        runtime.configuration.websocketURI.absoluteString,
        "wss://ws.example.test/runtime/session"
      )

      let authorizationURL = try client.oauthAuthorizationURL(
        clientName: "google-ios",
        redirectURL: try #require(URL(string: "myapp://oauth/callback"))
      )
      let authorizationComponents = try #require(
        URLComponents(url: authorizationURL, resolvingAgainstBaseURL: false)
      )
      expectNoDifference(authorizationComponents.host, "api.example.test")
      let issuerURI = try client.issuerURI()
      expectNoDifference(issuerURI.absoluteString, "https://api.example.test/custom/runtime/\(appID)")

      let localID = try await client.localID(named: "todos.bootstrap")
      expectNoDifference(localID, fixedUUID.uuidString.lowercased())

      let transaction = InstantStoreTransaction(
        id: "tx-bootstrap",
        operations: TodoExample.createOperations(
          id: "todo-bootstrap",
          text: "Use dependencies",
          createdAt: InstantTimestamp(milliseconds: 1_700_000_000_000),
          transactionID: "tx-bootstrap"
        )
      )
      try await client.transact(transaction)

      let snapshots = try await client.query(TodoExample.query)
      let todos = try TodoExample.decode(snapshots)
      expectNoDifference(
        todos,
        [
          TodoRecord(
            id: "todo-bootstrap",
            text: "Use dependencies",
            isCompleted: false,
            createdAt: InstantTimestamp(milliseconds: 1_700_000_000_000)
          )
        ]
      )

      let emission = try await client.queryOnce(
        InstantQueryPlan(
          id: "bootstrap-test.first",
          namespace: TodoExample.namespace,
          first: 1
        )
      )
      expectNoDifference(emission.queryID, "bootstrap-test.first")
      expectNoDifference(emission.values.map(\.id), ["todo-bootstrap"])
      expectNoDifference(emission.pageInfo?.hasNextPage, false)

      let status = try await client.connectionStatus()
      expectNoDifference(status.appID, appID)
      expectNoDifference(status.apiURI.absoluteString, "https://api.example.test/custom")
      expectNoDifference(
        status.websocketURI.absoluteString,
        "wss://ws.example.test/runtime/session"
      )
      expectNoDifference(status.transport, .localCacheOnly)
      expectNoDifference(status.state, .opened)
      expectNoDifference(status.pendingMutationCount, 1)

      let closedStatus = try await client.closeConnection()
      expectNoDifference(closedStatus.state, .closed)
      expectNoDifference(closedStatus.pendingMutationCount, 1)

      let reconnectedStatus = try await client.connect()
      expectNoDifference(reconnectedStatus.state, .opened)
      expectNoDifference(reconnectedStatus.pendingMutationCount, 1)
    }
  }

  @Test
  func bootstrapUsesMagicCodeExchangeDependency() async throws {
    let appID = "magic-code-dependency-\(UUID().uuidString)"
    let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataMagicCode-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let exchange = InstantMagicCodeExchange(
      send: { request in
        InstantMagicCodeChallenge(
          appID: request.appID,
          email: request.email,
          code: "246810",
          createdAt: request.sentAt,
          expiresAt: InstantTimestamp(milliseconds: request.sentAt.milliseconds + 60_000)
        )
      },
      verify: { request in
        InstantMagicCodeVerification(
          userID: "dependency:\(request.appID):\(request.email):\(request.code)",
          refreshToken: "challenge:\(request.challenge.code)"
        )
      }
    )

    try await withDependencies {
      $0.date.now = fixedDate
      $0.instantMagicCodeExchange = exchange
      try await $0.bootstrapInstantSwiftData(
        appID: appID,
        persistenceURL: directory.appendingPathComponent("cache.sqlite"),
        context: .test
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var client

      let emptySession = try await client.authSession()
      expectNoDifference(emptySession, nil)
      let authStream = try await client.observeAuthSession()
      var authIterator = authStream.makeAsyncIterator()
      let observedEmptySession = try #require(await authIterator.next())
      expectNoDifference(observedEmptySession, nil)

      let guestSession = try await client.signInAsGuest()
      expectNoDifference(guestSession.appID, appID)
      expectNoDifference(guestSession.isGuest, true)
      let persistedGuestSession = try await client.authSession()
      expectNoDifference(persistedGuestSession, guestSession)
      let observedGuestSession = try #require(await authIterator.next())
      expectNoDifference(observedGuestSession, guestSession)

      try await client.signOut()
      let signedOutGuestSession = try await client.authSession()
      expectNoDifference(signedOutGuestSession, nil)
      let observedSignedOutGuestSession = try #require(await authIterator.next())
      expectNoDifference(observedSignedOutGuestSession, nil)

      let challenge = try await client.sendMagicCode(email: " User@Example.COM ")
      expectNoDifference(challenge.code, "246810")

      let session = try await client.signInWithMagicCode(
        email: "user@example.com",
        code: "246810"
      )
      expectNoDifference(session.userID, "dependency:\(appID):user@example.com:246810")
      expectNoDifference(session.refreshToken, "challenge:246810")
      let persistedMagicSession = try await client.authSession()
      expectNoDifference(persistedMagicSession, session)
      let observedMagicSession = try #require(await authIterator.next())
      expectNoDifference(observedMagicSession, session)

      try await client.signOut()
      let signedOutMagicSession = try await client.authSession()
      expectNoDifference(signedOutMagicSession, nil)
      let observedSignedOutMagicSession = try #require(await authIterator.next())
      expectNoDifference(observedSignedOutMagicSession, nil)

      let tokenSession = try await client.signInWithRefreshToken(
        " refresh-token ",
        userID: " token-user "
      )
      expectNoDifference(tokenSession.userID, "token-user")
      expectNoDifference(tokenSession.refreshToken, "refresh-token")
      expectNoDifference(tokenSession.isGuest, false)
      let persistedTokenSession = try await client.authSession()
      expectNoDifference(persistedTokenSession, tokenSession)
      let observedTokenSession = try #require(await authIterator.next())
      expectNoDifference(observedTokenSession, tokenSession)
    }
  }

  @Test
  func bootstrapUsesRefreshTokenVerifierDependency() async throws {
    let appID = "refresh-token-dependency-\(UUID().uuidString)"
    let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataRefreshToken-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let verifier = InstantRefreshTokenVerifier(
      verify: { request in
        InstantRefreshTokenVerification(
          userID:
            "dependency:\(request.appID):\(request.refreshToken):\(request.userID ?? "nil"):\(request.signedInAt.milliseconds)",
          refreshToken: "dependency-refresh:\(request.refreshToken)"
        )
      }
    )

    try await withDependencies {
      $0.date.now = fixedDate
      $0.instantRefreshTokenVerifier = verifier
      try await $0.bootstrapInstantSwiftData(
        appID: appID,
        persistenceURL: directory.appendingPathComponent("cache.sqlite"),
        context: .test
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var client

      let session = try await client.signInWithRefreshToken(
        " refresh-token ",
        userID: " token-user "
      )
      expectNoDifference(
        session.userID,
        "dependency:\(appID):refresh-token:token-user:1700000000000"
      )
      expectNoDifference(session.refreshToken, "dependency-refresh:refresh-token")
      let persistedSession = try await client.authSession()
      expectNoDifference(persistedSession, session)
    }
  }

  @Test
  func bootstrapUsesIDTokenExchangeDependency() async throws {
    let appID = "id-token-dependency-\(UUID().uuidString)"
    let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataIDToken-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let exchange = InstantIDTokenExchange(
      signIn: { request in
        InstantIDTokenVerification(
          userID:
            "dependency:\(request.appID):\(request.clientName):\(request.idToken):\(request.nonce ?? "nil")",
          refreshToken: "dependency-refresh:\(request.signedInAt.milliseconds)"
        )
      }
    )

    try await withDependencies {
      $0.date.now = fixedDate
      $0.instantIDTokenExchange = exchange
      try await $0.bootstrapInstantSwiftData(
        appID: appID,
        persistenceURL: directory.appendingPathComponent("cache.sqlite"),
        context: .test
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var client

      let authStream = try await client.observeAuthSession()
      var authIterator = authStream.makeAsyncIterator()
      let observedEmptySession = try #require(await authIterator.next())
      expectNoDifference(observedEmptySession, nil)

      let session = try await client.signInWithIDToken(
        clientName: " google-ios ",
        idToken: " jwt-token ",
        nonce: " nonce-1 "
      )
      expectNoDifference(
        session.userID,
        "dependency:\(appID):google-ios:jwt-token: nonce-1 "
      )
      expectNoDifference(session.refreshToken, "dependency-refresh:1700000000000")
      let persistedSession = try await client.authSession()
      expectNoDifference(persistedSession, session)
      let observedSession = try #require(await authIterator.next())
      expectNoDifference(observedSession, session)
    }
  }

  @Test
  func bootstrapUsesOAuthExchangeDependency() async throws {
    let appID = "oauth-dependency-\(UUID().uuidString)"
    let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataOAuth-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let exchange = InstantOAuthExchange(
      signIn: { request in
        InstantOAuthVerification(
          userID:
            "dependency:\(request.appID):\(request.code):\(request.codeVerifier ?? "nil"):\(request.refreshToken ?? "nil")",
          refreshToken: "dependency-oauth-refresh:\(request.signedInAt.milliseconds)"
        )
      }
    )

    try await withDependencies {
      $0.date.now = fixedDate
      $0.instantOAuthExchange = exchange
      try await $0.bootstrapInstantSwiftData(
        appID: appID,
        persistenceURL: directory.appendingPathComponent("cache.sqlite"),
        context: .test
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var client

      _ = try await client.signInWithRefreshToken("existing-refresh", userID: "existing-user")
      let session = try await client.signInWithOAuth(
        code: " oauth-code ",
        codeVerifier: " verifier with spaces "
      )
      expectNoDifference(
        session.userID,
        "dependency:\(appID):oauth-code: verifier with spaces :existing-refresh"
      )
      expectNoDifference(session.refreshToken, "dependency-oauth-refresh:1700000000000")
      let persistedSession = try await client.authSession()
      expectNoDifference(persistedSession, session)
    }
  }

  @Test
  func bootstrapUsesAuthTokenInvalidatorDependency() async throws {
    let appID = "sign-out-dependency-\(UUID().uuidString)"
    let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataSignOut-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let recorder = AuthTokenInvalidationRecorder()
    let invalidator = InstantAuthTokenInvalidator(
      invalidate: { request in
        await recorder.record(request)
      }
    )

    try await withDependencies {
      $0.date.now = fixedDate
      $0.instantAuthTokenInvalidator = invalidator
      try await $0.bootstrapInstantSwiftData(
        appID: appID,
        persistenceURL: directory.appendingPathComponent("cache.sqlite"),
        context: .test
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var client

      _ = try await client.signInWithRefreshToken("refresh-token", userID: "token-user")
      let signOut: () async throws -> Void = client.signOut
      try await signOut()
      let signedOutSession = try await client.authSession()
      expectNoDifference(signedOutSession, nil)
      let defaultRequests = await recorder.requests()
      expectNoDifference(defaultRequests.count, 1)
      expectNoDifference(defaultRequests.first?.appID, appID)
      expectNoDifference(defaultRequests.first?.refreshToken, "refresh-token")
      expectNoDifference(defaultRequests.first?.signedOutAt.milliseconds, 1_700_000_000_000)

      _ = try await client.signInWithRefreshToken("second-refresh-token", userID: "token-user")
      try await client.signOut(invalidateToken: false)
      let skippedInvalidationSession = try await client.authSession()
      expectNoDifference(skippedInvalidationSession, nil)
      let skippedRequests = await recorder.requests()
      expectNoDifference(skippedRequests.count, 1)
    }
  }

  @Test
  func bootstrapUsesMutationTransportDependency() async throws {
    let appID = "mutation-transport-dependency-\(UUID().uuidString)"
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataMutationTransport-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let recorder = BootstrapMutationTransportRecorder()
    let transport = InstantMutationTransportClient { request in
      await recorder.record(request)
      return InstantMutationTransportResponse(
        results: request.mutations.map { mutation in
          InstantMutationTransportResult(mutationID: mutation.mutationID, outcome: .confirmed)
        }
      )
    }

    try await withDependencies {
      $0.instantMutationTransport = transport
      try await $0.bootstrapInstantSwiftData(
        appID: appID,
        persistenceURL: directory.appendingPathComponent("cache.sqlite"),
        context: .test,
        initialAttributes: TodoExample.attributes
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var client
      let createdAt = InstantTimestamp(milliseconds: 1_700_000_000_000)

      try await client.transact(
        InstantStoreTransaction(
          id: "tx-dependency-flush",
          operations: TodoExample.createOperations(
            id: "todo-dependency-flush",
            text: "dependency transport",
            createdAt: createdAt,
            transactionID: "tx-dependency-flush"
          )
        )
      )

      let result = try await client.flushPendingMutations()
      expectNoDifference(result.request.appID, appID)
      expectNoDifference(result.request.mutations.map(\.mutationID), ["tx-dependency-flush"])
      expectNoDifference(result.confirmed.map(\.id), ["tx-dependency-flush"])
      expectNoDifference(result.pendingMutationCount, 0)

      let requests = await recorder.requests()
      expectNoDifference(requests.map { $0.appID }, [appID])
      expectNoDifference(requests.first?.mutations.map(\.mutationID), ["tx-dependency-flush"])
      let pendingMutations = await client.pendingMutations()
      expectNoDifference(pendingMutations, [])
    }
  }

  @Test
  func dependencyOverrideCanInstallMockClient() async throws {
    let signOutOptions = SignOutOptionsRecorder()
    let mock = InstantSwiftDataClient(
      transact: { transaction in
        InstantStoreMutationResult(
          transactionID: transaction.id,
          changedEntityIDs: [],
          tripleCount: 0,
          emissions: []
        )
      },
      query: { _ in
        [
          InstantEntitySnapshot(
            id: "mock-todo",
            namespace: TodoExample.namespace,
            values: [
              "text": .one(.string("Mocked")),
              "isCompleted": .one(.bool(true)),
              "createdAt": .one(.date(Date(timeIntervalSince1970: 1_700_000_001))),
            ]
          )
        ]
      },
      observe: { _ in AsyncStream { continuation in continuation.finish() } },
      pendingMutations: { [] },
      localID: { name in "mock-\(name)" },
      authSession: {
        InstantAuthSession(
          appID: "mock-app",
          userID: "mock-user",
          refreshToken: "mock-refresh",
          isGuest: false,
          createdAt: InstantTimestamp(milliseconds: 1),
          updatedAt: InstantTimestamp(milliseconds: 2)
        )
      },
      observeAuthSession: {
        AsyncStream { continuation in
          continuation.yield(
            InstantAuthSession(
              appID: "mock-app",
              userID: "mock-observed-user",
              refreshToken: "mock-observed-refresh",
              isGuest: false,
              createdAt: InstantTimestamp(milliseconds: 8),
              updatedAt: InstantTimestamp(milliseconds: 9)
            )
          )
          continuation.finish()
        }
      },
      signInAsGuest: {
        InstantAuthSession(
          appID: "mock-app",
          userID: "mock-guest",
          isGuest: true,
          createdAt: InstantTimestamp(milliseconds: 3),
          updatedAt: InstantTimestamp(milliseconds: 3)
        )
      },
      sendMagicCode: { email in
        InstantMagicCodeChallenge(
          appID: "mock-app",
          email: email,
          code: "135790",
          createdAt: InstantTimestamp(milliseconds: 4),
          expiresAt: InstantTimestamp(milliseconds: 5)
        )
      },
      signInWithMagicCode: { email, code in
        InstantAuthSession(
          appID: "mock-app",
          userID: "\(email):\(code)",
          refreshToken: "mock-magic-refresh",
          isGuest: false,
          createdAt: InstantTimestamp(milliseconds: 6),
          updatedAt: InstantTimestamp(milliseconds: 6)
        )
      },
      signInWithRefreshToken: { refreshToken, userID in
        InstantAuthSession(
          appID: "mock-app",
          userID: userID ?? "mock-token-user",
          refreshToken: refreshToken,
          isGuest: false,
          createdAt: InstantTimestamp(milliseconds: 7),
          updatedAt: InstantTimestamp(milliseconds: 7)
        )
      },
      oauthAuthorizationURL: { clientName, redirectURL in
        var components = URLComponents(string: "https://mock.example/runtime/oauth/start")!
        components.queryItems = [
          URLQueryItem(name: "client", value: clientName),
          URLQueryItem(name: "redirect", value: redirectURL.absoluteString),
        ]
        return components.url!
      },
      issuerURI: {
        URL(string: "https://mock.example/runtime/mock-app")!
      },
      signOut: {},
      signInWithIDToken: { clientName, idToken, nonce in
        InstantAuthSession(
          appID: "mock-app",
          userID: "\(clientName):\(idToken):\(nonce ?? "nil")",
          refreshToken: "mock-id-token-refresh",
          isGuest: false,
          createdAt: InstantTimestamp(milliseconds: 10),
          updatedAt: InstantTimestamp(milliseconds: 10)
        )
      },
      signInWithOAuth: { code, codeVerifier in
        InstantAuthSession(
          appID: "mock-app",
          userID: "\(code):\(codeVerifier ?? "nil")",
          refreshToken: "mock-oauth-refresh",
          isGuest: false,
          createdAt: InstantTimestamp(milliseconds: 11),
          updatedAt: InstantTimestamp(milliseconds: 11)
        )
      },
      signOutWithOptions: { invalidateToken in
        await signOutOptions.record(invalidateToken)
      }
    )

    try await withDependencies {
      $0.defaultInstantSwiftData = mock
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var client

      let localID = try await client.localID(named: "todo")
      expectNoDifference(localID, "mock-todo")

      let snapshots = try await client.query(TodoExample.query)
      let todos = try TodoExample.decode(snapshots)
      expectNoDifference(todos.map(\.text), ["Mocked"])
      expectNoDifference(todos.map(\.isCompleted), [true])

      let mockSession = try await client.authSession()
      expectNoDifference(mockSession?.userID, "mock-user")
      let mockAuthStream = try await client.observeAuthSession()
      var mockAuthIterator = mockAuthStream.makeAsyncIterator()
      let mockObservedSession = try #require(await mockAuthIterator.next())
      expectNoDifference(mockObservedSession?.userID, "mock-observed-user")
      let mockGuest = try await client.signInAsGuest()
      expectNoDifference(mockGuest.userID, "mock-guest")
      let mockChallenge = try await client.sendMagicCode(email: "mock@example.com")
      expectNoDifference(mockChallenge.code, "135790")
      let mockMagicSession = try await client.signInWithMagicCode(
        email: "mock@example.com",
        code: "135790"
      )
      expectNoDifference(mockMagicSession.userID, "mock@example.com:135790")
      let mockTokenSession = try await client.signInWithRefreshToken("mock-token", userID: nil)
      expectNoDifference(mockTokenSession.userID, "mock-token-user")
      let mockAuthorizationURL = try client.oauthAuthorizationURL(
        clientName: "mock-client",
        redirectURL: try #require(URL(string: "myapp://oauth"))
      )
      let mockAuthorizationComponents = try #require(
        URLComponents(url: mockAuthorizationURL, resolvingAgainstBaseURL: false)
      )
      expectNoDifference(mockAuthorizationComponents.host, "mock.example")
      let mockIssuerURI = try client.issuerURI()
      expectNoDifference(mockIssuerURI.absoluteString, "https://mock.example/runtime/mock-app")
      let mockIDTokenSession = try await client.signInWithIDToken(
        clientName: "mock-client",
        idToken: "mock-id-token",
        nonce: nil
      )
      expectNoDifference(mockIDTokenSession.userID, "mock-client:mock-id-token:nil")
      let mockOAuthSession = try await client.signInWithOAuth(
        code: "mock-code",
        codeVerifier: nil
      )
      expectNoDifference(mockOAuthSession.userID, "mock-code:nil")
      try await client.signOut(invalidateToken: false)
      let recordedSignOutOptions = await signOutOptions.values()
      expectNoDifference(recordedSignOutOptions, [false])
    }
  }

  @Test
  func authSessionPropertyWrapperStartsNil() {
    @AuthSession var session: InstantAuthSession?

    expectNoDifference(session, nil)
    expectNoDifference($session.loadError, nil)
    expectNoDifference($session.isLoading, false)
  }

  @Test
  func authSessionPropertyWrapperLoadsUsingDependencyClient() async throws {
    let loaded = mockAuthSession(userID: "cached-user")
    let client = authSessionClient(
      load: { loaded },
      observe: { AsyncStream { continuation in continuation.finish() } }
    )

    try await withDependencies {
      $0.defaultInstantSwiftData = client
    } operation: {
      @AuthSession var session: InstantAuthSession?

      try await $session.load()

      expectNoDifference(session, loaded)
      expectNoDifference($session.loadError, nil)
      expectNoDifference($session.isLoading, false)
    }
  }

  @Test
  func authSessionPropertyWrapperLoadCancellationDoesNotOverwriteCachedValue() async throws {
    let gate = AuthSessionLoadGate()
    let cached = mockAuthSession(userID: "cached-user")
    let loaded = mockAuthSession(userID: "late-user")
    let client = authSessionClient(
      load: {
        await gate.recordStarted()
        await gate.waitUntilReleased()
        return loaded
      },
      observe: { AsyncStream { continuation in continuation.finish() } }
    )
    let auth = AuthSession(wrappedValue: cached)

    let task = Task {
      var auth = auth
      try await auth.load(using: client)
    }

    await gate.waitUntilStarted()
    task.cancel()
    await gate.release()

    do {
      try await task.value
      Issue.record("Expected @AuthSession load cancellation to throw CancellationError.")
    } catch is CancellationError {
    } catch {
      Issue.record("Expected CancellationError, got \(error).")
    }

    expectNoDifference(auth.wrappedValue, cached)
    expectNoDifference(auth.loadError, nil)
    expectNoDifference(auth.isLoading, false)
  }

  @Test
  func authSessionPropertyWrapperTaskBindsObservedSessions() async throws {
    let signedIn = mockAuthSession(userID: "observed-user")
    let client = authSessionClient(
      load: { nil },
      observe: {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
          continuation.yield(nil)
          continuation.yield(signedIn)
          continuation.finish()
        }
      }
    )

    @AuthSession var session: InstantAuthSession?

    try await $session.task(using: client)

    expectNoDifference(session, signedIn)
    expectNoDifference($session.loadError, nil)
    expectNoDifference($session.isLoading, false)
  }

  @Test
  func authSessionPropertyWrapperSubscribeCancelsUnderlyingObservation() async throws {
    let termination = AuthSessionTermination()
    let client = authSessionClient(
      load: { nil },
      observe: {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
          continuation.yield(nil)
          continuation.onTermination = { @Sendable _ in
            Task {
              await termination.record()
            }
          }
        }
      }
    )

    var auth = AuthSession()
    let subscription = try await auth.subscribe(using: client)
    var iterator = subscription.makeAsyncIterator()
    let initial = try await iterator.next()
    if case .some(nil) = initial {
    } else {
      #expect(Bool(false), "Expected initial auth session emission to be nil.")
    }

    subscription.cancel()
    #expect(try await iterator.next() == nil)
    await termination.wait()
  }

  @Test
  func authSessionPropertyWrapperPreservesCachedValueAndRecordsLoadError() async throws {
    let cached = mockAuthSession(userID: "cached-user")
    let expectedError = InstantError(
      code: .implementationFailed,
      operation: "load test AuthSession",
      message: "auth failed",
      recovery: "Retry with a working auth client."
    )
    let client = authSessionClient(
      load: { throw expectedError },
      observe: { AsyncStream { continuation in continuation.finish() } }
    )

    @AuthSession var session: InstantAuthSession? = cached

    do {
      try await $session.load(using: client)
      #expect(Bool(false), "Expected @AuthSession to surface client failures.")
    } catch let error as InstantError {
      expectNoDifference(error.operation, "load test AuthSession")
      expectNoDifference($session.loadError?.operation, "load test AuthSession")
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    expectNoDifference(session, cached)
    expectNoDifference($session.isLoading, false)
  }

  @Test
  func cliDefaultPersistenceURLHonorsHomeEnvironment() {
    let key = "INSTANT_SWIFT_DATA_HOME"
    let previous = getenv(key).map { String(cString: $0) }
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataCLIHome-\(UUID().uuidString)", isDirectory: true)

    #expect(setenv(key, directory.path, 1) == 0)
    defer {
      if let previous {
        setenv(key, previous, 1)
      } else {
        unsetenv(key)
      }
    }

    let url = DependencyValues.defaultInstantSwiftDataPersistenceURL(
      appID: "ignored-for-cli",
      context: .cli
    )

    expectNoDifference(url.path, directory.appendingPathComponent("state.sqlite").path)
  }

  @Test
  func mockClientQueryOnceFallsBackToSnapshots() async throws {
    let mock = InstantSwiftDataClient(
      transact: { transaction in
        InstantStoreMutationResult(
          transactionID: transaction.id,
          changedEntityIDs: [],
          tripleCount: transaction.operations.count,
          emissions: []
        )
      },
      query: { plan in
        [
          InstantEntitySnapshot(
            id: "mock-todo",
            namespace: plan.namespace,
            values: [
              "text": .one(.string("Mock once"))
            ]
          )
        ]
      },
      observe: { _ in AsyncStream { continuation in continuation.finish() } },
      pendingMutations: { [] },
      localID: { name in "mock-\(name)" }
    )

    let plan = InstantQueryPlan(id: "mock.once", namespace: TodoExample.namespace)
    let emission = try await mock.queryOnce(plan)
    expectNoDifference(emission.queryID, "mock.once")
    expectNoDifference(emission.sequence, 0)
    expectNoDifference(emission.values.map(\.id), ["mock-todo"])
    expectNoDifference(emission.pageInfo, nil)

    do {
      _ = try await mock.authSession()
      #expect(Bool(false), "Expected old-shape mock client auth to fail without auth closures.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .implementationFailed)
      expectNoDifference(error.operation, "access InstantSwiftData auth")
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    do {
      _ = try await mock.observeAuthSession()
      #expect(Bool(false), "Expected old-shape mock client auth observer to fail without auth closures.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .implementationFailed)
      expectNoDifference(error.operation, "access InstantSwiftData auth")
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    do {
      _ = try await mock.connectionStatus()
      #expect(Bool(false), "Expected old-shape mock client status to fail without status closure.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .implementationFailed)
      expectNoDifference(error.operation, "inspect InstantSwiftData connection")
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    do {
      _ = try await mock.connect()
      #expect(Bool(false), "Expected old-shape mock client connect to fail without status closure.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .implementationFailed)
      expectNoDifference(error.operation, "inspect InstantSwiftData connection")
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    do {
      _ = try await mock.closeConnection()
      #expect(Bool(false), "Expected old-shape mock client close to fail without status closure.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .implementationFailed)
      expectNoDifference(error.operation, "inspect InstantSwiftData connection")
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    do {
      _ = try await mock.signInWithIDToken(clientName: "google-ios", idToken: "token")
      #expect(Bool(false), "Expected old-shape mock client ID token auth to fail without auth closures.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .implementationFailed)
      expectNoDifference(error.operation, "access InstantSwiftData auth")
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    do {
      _ = try await mock.signInWithOAuth(code: "oauth-code")
      #expect(Bool(false), "Expected old-shape mock client OAuth auth to fail without auth closures.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .implementationFailed)
      expectNoDifference(error.operation, "access InstantSwiftData auth")
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }
  }
}

private actor AuthTokenInvalidationRecorder {
  private var values: [InstantAuthTokenInvalidationRequest] = []

  func record(_ request: InstantAuthTokenInvalidationRequest) {
    values.append(request)
  }

  func requests() -> [InstantAuthTokenInvalidationRequest] {
    values
  }
}

private actor BootstrapMutationTransportRecorder {
  private var recordedRequests: [InstantMutationTransportRequest] = []

  func record(_ request: InstantMutationTransportRequest) {
    recordedRequests.append(request)
  }

  func requests() -> [InstantMutationTransportRequest] {
    recordedRequests
  }
}

private actor SignOutOptionsRecorder {
  private var recordedValues: [Bool] = []

  func record(_ invalidateToken: Bool) {
    recordedValues.append(invalidateToken)
  }

  func values() -> [Bool] {
    recordedValues
  }
}

private actor AuthSessionTermination {
  private var didTerminate = false
  private var continuations: [CheckedContinuation<Void, Never>] = []

  func record() {
    didTerminate = true
    for continuation in continuations {
      continuation.resume()
    }
    continuations.removeAll()
  }

  func wait() async {
    if didTerminate { return }
    await withCheckedContinuation { continuation in
      continuations.append(continuation)
    }
  }
}

private actor AuthSessionLoadGate {
  private var didStart = false
  private var didRelease = false
  private var startContinuations: [CheckedContinuation<Void, Never>] = []
  private var releaseContinuations: [CheckedContinuation<Void, Never>] = []

  func recordStarted() {
    didStart = true
    for continuation in startContinuations {
      continuation.resume()
    }
    startContinuations.removeAll()
  }

  func waitUntilStarted() async {
    if didStart { return }
    await withCheckedContinuation { continuation in
      startContinuations.append(continuation)
    }
  }

  func release() {
    didRelease = true
    for continuation in releaseContinuations {
      continuation.resume()
    }
    releaseContinuations.removeAll()
  }

  func waitUntilReleased() async {
    if didRelease { return }
    await withCheckedContinuation { continuation in
      releaseContinuations.append(continuation)
    }
  }
}

private func mockAuthSession(userID: String, isGuest: Bool = false) -> InstantAuthSession {
  InstantAuthSession(
    appID: "mock-app",
    userID: userID,
    refreshToken: isGuest ? nil : "mock-refresh-\(userID)",
    isGuest: isGuest,
    createdAt: InstantTimestamp(milliseconds: 1),
    updatedAt: InstantTimestamp(milliseconds: 2)
  )
}

private func authSessionClient(
  load: @escaping @Sendable () async throws -> InstantAuthSession?,
  observe: @escaping @Sendable () async throws -> AsyncStream<InstantAuthSession?>
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
    observe: { _ in AsyncStream { continuation in continuation.finish() } },
    pendingMutations: { [] },
    localID: { name in "mock-\(name)" },
    authSession: load,
    observeAuthSession: observe
  )
}
