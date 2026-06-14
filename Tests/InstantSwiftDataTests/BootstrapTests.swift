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
  func runtimeBackedClientForwardsShareOperations() async throws {
    let appID = "share-forwarding-\(UUID().uuidString)"
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataShareForwarding-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    try await withDependencies {
      try await $0.bootstrapInstantSwiftData(
        appID: appID,
        persistenceURL: directory.appendingPathComponent("cache.sqlite"),
        context: .test,
        initialAttributes: TodoExample.attributes
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var client

      guard client.runtime != nil else {
        Issue.record("Expected a runtime-backed client.")
        return
      }

      _ = try await client.signInWithRefreshToken("owner-refresh", userID: "user-1")
      var ownerIterator = try await client.observeShares().makeAsyncIterator()
      let ownerInitialShares = await ownerIterator.next()
      expectNoDifference(ownerInitialShares, [])

      let created = try await client.createShare(
        rootNamespace: TodoExample.namespace,
        rootID: "todo-public-client"
      )
      let listedShares = try await client.shares()
      expectNoDifference(listedShares, [created])
      let ownerCreatedEmission = await ownerIterator.next()
      expectNoDifference(ownerCreatedEmission, [created])

      _ = try await client.signInWithRefreshToken("invitee-refresh", userID: "user-2")
      let accepted = try await client.acceptShare(token: created.share.token)
      var inviteeIterator = try await client.observeShares().makeAsyncIterator()
      let inviteeInitialShares = await inviteeIterator.next()
      expectNoDifference(inviteeInitialShares, [accepted])
      let ownerAcceptedEmission = await ownerIterator.next()
      expectNoDifference(ownerAcceptedEmission, [accepted])

      _ = try await client.signInWithRefreshToken("owner-refresh", userID: "user-1")
      let promoted = try await client.updateShareMembershipRole(
        shareID: created.share.id,
        userID: "user-2",
        role: .writer
      )
      let ownerPromotedEmission = await ownerIterator.next()
      expectNoDifference(ownerPromotedEmission, [promoted])
      let inviteePromotedEmission = await inviteeIterator.next()
      expectNoDifference(inviteePromotedEmission, [promoted])

      _ = try await client.revokeShare(id: created.share.id)
      let ownerRevokedEmission = await ownerIterator.next()
      expectNoDifference(ownerRevokedEmission, [])
      let inviteeRevokedEmission = await inviteeIterator.next()
      expectNoDifference(inviteeRevokedEmission, [])
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
      let mockAuthSubscription = try await client.subscribeAuthSession()
      var mockAuthSubscriptionIterator = mockAuthSubscription.makeAsyncIterator()
      let mockSubscribedSession = try #require(try await mockAuthSubscriptionIterator.next())
      expectNoDifference(mockSubscribedSession?.userID, "mock-observed-user")
      mockAuthSubscription.cancel()
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
      let auth = auth
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

    let auth = AuthSession()
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
  func roomClientOperationsUseInjectedClosures() async throws {
    let room = InstantRoomHandle(type: "chat", id: "lobby")
    let member = mockRoomPresenceMember(room: room, userID: "user-1")
    let message = mockRoomTopicMessage(room: room, topic: "sendEmoji")
    let client = roomClient(
      setPresence: { room, userID, values in
        expectNoDifference(room, InstantRoomHandle(type: "chat", id: "lobby"))
        expectNoDifference(userID, "user-1")
        expectNoDifference(values, ["status": .string("online")])
        return member
      },
      roomPresence: { room in
        expectNoDifference(room, InstantRoomHandle(type: "chat", id: "lobby"))
        return [member]
      },
      observeRoomPresence: { room in
        expectNoDifference(room, InstantRoomHandle(type: "chat", id: "lobby"))
        return AsyncStream { continuation in
          continuation.yield([member])
          continuation.finish()
        }
      },
      leavePresence: { room, userID in
        expectNoDifference(room, InstantRoomHandle(type: "chat", id: "lobby"))
        expectNoDifference(userID, "user-1")
        return "user-1"
      },
      publishTopicMessage: { room, topic, userID, payload in
        expectNoDifference(room, InstantRoomHandle(type: "chat", id: "lobby"))
        expectNoDifference(topic, "sendEmoji")
        expectNoDifference(userID, "user-1")
        expectNoDifference(payload, .object(["emoji": .string("wave")]))
        return message
      },
      roomTopicMessages: { room, topic, limit in
        expectNoDifference(room, InstantRoomHandle(type: "chat", id: "lobby"))
        expectNoDifference(topic, "sendEmoji")
        expectNoDifference(limit, 1)
        return [message]
      },
      observeRoomTopicMessages: { room, topic in
        expectNoDifference(room, InstantRoomHandle(type: "chat", id: "lobby"))
        expectNoDifference(topic, "sendEmoji")
        return AsyncStream { continuation in
          continuation.yield([message])
          continuation.finish()
        }
      }
    )

    let setMember = try await client.setRoomPresence(
      room: room,
      userID: "user-1",
      values: ["status": .string("online")]
    )
    expectNoDifference(setMember, member)
    let listedMembers = try await client.roomPresence(room: room)
    expectNoDifference(listedMembers, [member])

    var presenceIterator = try await client.observeRoomPresence(room: room).makeAsyncIterator()
    let observedMembers = await presenceIterator.next()
    expectNoDifference(observedMembers, [member])

    let leftUserID = try await client.leaveRoomPresence(room: room, userID: "user-1")
    expectNoDifference(leftUserID, "user-1")
    let publishedMessage = try await client.publishRoomTopicMessage(
      room: room,
      topic: "sendEmoji",
      userID: "user-1",
      payload: .object(["emoji": .string("wave")])
    )
    expectNoDifference(publishedMessage, message)
    let listedMessages = try await client.roomTopicMessages(
      room: room,
      topic: "sendEmoji",
      limit: 1
    )
    expectNoDifference(listedMessages, [message])

    var topicIterator = try await client.observeRoomTopicMessages(
      room: room,
      topic: "sendEmoji"
    ).makeAsyncIterator()
    let observedMessages = await topicIterator.next()
    expectNoDifference(observedMessages, [message])
  }

  @Test
  func roomPresencePropertyWrapperLoadsUsingDependencyClient() async throws {
    let room = InstantRoomHandle(type: "chat", id: "lobby")
    let member = mockRoomPresenceMember(room: room, userID: "user-1")
    let client = roomClient(
      roomPresence: { room in
        expectNoDifference(room, InstantRoomHandle(type: "chat", id: "lobby"))
        return [member]
      }
    )

    try await withDependencies {
      $0.defaultInstantSwiftData = client
    } operation: {
      @RoomPresence("chat", "lobby") var members: [InstantRoomPresenceMember]

      try await $members.load()

      expectNoDifference(members, [member])
      expectNoDifference($members.loadError, nil)
      expectNoDifference($members.isLoading, false)
    }
  }

  @Test
  func roomPresencePropertyWrapperTaskBindsObservedMembers() async throws {
    let room = InstantRoomHandle(type: "chat", id: "lobby")
    let member = mockRoomPresenceMember(room: room, userID: "user-1")
    let client = roomClient(
      observeRoomPresence: { room in
        expectNoDifference(room, InstantRoomHandle(type: "chat", id: "lobby"))
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
          continuation.yield([])
          continuation.yield([member])
          continuation.finish()
        }
      }
    )

    @RoomPresence var members: [InstantRoomPresenceMember]

    try await $members.task("chat", "lobby", using: client)

    expectNoDifference(members, [member])
    expectNoDifference($members.loadError, nil)
    expectNoDifference($members.isLoading, false)
  }

  @Test
  func roomPresencePropertyWrapperSubscribeCancelsUnderlyingObservation() async throws {
    let termination = RoomObservationTermination()
    let client = roomClient(
      observeRoomPresence: { _ in
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
          continuation.yield([])
          continuation.onTermination = { @Sendable _ in
            Task {
              await termination.record()
            }
          }
        }
      }
    )

    let presence = RoomPresence("chat", "lobby")
    let subscription = try await presence.subscribe(using: client)
    var iterator = subscription.makeAsyncIterator()
    let initialMembers = try await iterator.next()
    expectNoDifference(initialMembers, [])

    subscription.cancel()
    #expect(try await iterator.next() == nil)
    await termination.wait()
  }

  @Test
  func roomPresencePropertyWrapperRecordsMissingRoomError() async throws {
    let presence = RoomPresence()

    do {
      _ = try await presence.subscribe(using: roomClient())
      Issue.record("Expected @RoomPresence without a room to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.operation, "subscribe RoomPresence")
      expectNoDifference(presence.loadError?.operation, "subscribe RoomPresence")
    } catch {
      Issue.record("Unexpected error: \(error).")
    }

    expectNoDifference(presence.wrappedValue, [])
    expectNoDifference(presence.isLoading, false)
  }

  @Test
  func roomPresencePropertyWrapperSubscribeCancellationAfterObserveDoesNotSucceed() async throws {
    let gate = AuthSessionLoadGate()
    let client = roomClient(
      observeRoomPresence: { _ in
        await gate.recordStarted()
        await gate.waitUntilReleased()
        return AsyncStream { continuation in continuation.finish() }
      }
    )
    let presence = RoomPresence("chat", "lobby")

    let task = Task {
      let presence = presence
      _ = try await presence.subscribe(using: client)
    }

    await gate.waitUntilStarted()
    task.cancel()
    await gate.release()

    do {
      try await task.value
      Issue.record("Expected @RoomPresence subscribe cancellation to throw CancellationError.")
    } catch is CancellationError {
    } catch {
      Issue.record("Expected CancellationError, got \(error).")
    }
  }

  @Test
  func roomTopicMessagesPropertyWrapperLoadsUsingDependencyClient() async throws {
    let room = InstantRoomHandle(type: "chat", id: "lobby")
    let message = mockRoomTopicMessage(room: room, topic: "sendEmoji")
    let client = roomClient(
      roomTopicMessages: { room, topic, limit in
        expectNoDifference(room, InstantRoomHandle(type: "chat", id: "lobby"))
        expectNoDifference(topic, "sendEmoji")
        expectNoDifference(limit, 1)
        return [message]
      }
    )

    try await withDependencies {
      $0.defaultInstantSwiftData = client
    } operation: {
      @RoomTopicMessages("chat", "lobby", "sendEmoji", limit: 1)
      var messages: [InstantRoomTopicMessage]

      try await $messages.load()

      expectNoDifference(messages, [message])
      expectNoDifference($messages.loadError, nil)
      expectNoDifference($messages.isLoading, false)
    }
  }

  @Test
  func roomTopicMessagesPropertyWrapperRecordsNegativeLimitErrors() async throws {
    let messages = RoomTopicMessages("chat", "lobby", "sendEmoji", limit: -1)

    do {
      try await messages.load(using: roomClient())
      Issue.record("Expected @RoomTopicMessages negative load limit to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed)
      expectNoDifference(error.operation, "load RoomTopicMessages")
      expectNoDifference(messages.loadError?.operation, "load RoomTopicMessages")
    } catch {
      Issue.record("Unexpected error: \(error).")
    }

    expectNoDifference(messages.wrappedValue, [])
    expectNoDifference(messages.isLoading, false)

    do {
      _ = try await messages.subscribe(
        "chat",
        "lobby",
        "sendEmoji",
        limit: -1,
        using: roomClient()
      )
      Issue.record("Expected @RoomTopicMessages negative subscribe limit to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed)
      expectNoDifference(error.operation, "subscribe RoomTopicMessages")
      expectNoDifference(messages.loadError?.operation, "subscribe RoomTopicMessages")
    } catch {
      Issue.record("Unexpected error: \(error).")
    }
  }

  @Test
  func roomTopicMessagesPropertyWrapperTaskBindsObservedMessages() async throws {
    let room = InstantRoomHandle(type: "chat", id: "lobby")
    let message = mockRoomTopicMessage(room: room, topic: "sendEmoji")
    let laterMessage = mockRoomTopicMessage(
      room: room,
      topic: "sendEmoji",
      id: "message-2",
      payload: .object(["emoji": .string("sparkles")])
    )
    let client = roomClient(
      observeRoomTopicMessages: { room, topic in
        expectNoDifference(room, InstantRoomHandle(type: "chat", id: "lobby"))
        expectNoDifference(topic, "sendEmoji")
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
          continuation.yield([])
          continuation.yield([message, laterMessage])
          continuation.finish()
        }
      }
    )

    @RoomTopicMessages var messages: [InstantRoomTopicMessage]

    try await $messages.task("chat", "lobby", "sendEmoji", limit: 1, using: client)

    expectNoDifference(messages, [message])
    expectNoDifference($messages.loadError, nil)
    expectNoDifference($messages.isLoading, false)
  }

  @Test
  func roomTopicMessagesPropertyWrapperSubscribeCancelsUnderlyingObservation() async throws {
    let termination = RoomObservationTermination()
    let client = roomClient(
      observeRoomTopicMessages: { room, topic in
        expectNoDifference(room, InstantRoomHandle(type: "chat", id: "lobby"))
        expectNoDifference(topic, "sendEmoji")
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
          continuation.yield([])
          continuation.onTermination = { @Sendable _ in
            Task {
              await termination.record()
            }
          }
        }
      }
    )

    let messages = RoomTopicMessages("chat", "lobby", "sendEmoji")
    let subscription = try await messages.subscribe(using: client)
    var iterator = subscription.makeAsyncIterator()
    let initialMessages = try await iterator.next()
    expectNoDifference(initialMessages, [])

    subscription.cancel()
    #expect(try await iterator.next() == nil)
    await termination.wait()
  }

  @Test
  func roomTopicClientSubscriptionAdapterAppliesLimitAndValidatesInput() async throws {
    let room = InstantRoomHandle(type: "chat", id: "lobby")
    let first = mockRoomTopicMessage(room: room, topic: "sendEmoji")
    let second = mockRoomTopicMessage(
      room: room,
      topic: "sendEmoji",
      id: "message-2",
      payload: .object(["emoji": .string("sparkles")])
    )
    let client = roomClient(
      observeRoomTopicMessages: { room, topic in
        expectNoDifference(room, InstantRoomHandle(type: "chat", id: "lobby"))
        expectNoDifference(topic, "sendEmoji")
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
          continuation.yield([first, second])
          continuation.finish()
        }
      }
    )

    let subscription = try await client.subscribeRoomTopicMessages(
      room: room,
      topic: "sendEmoji",
      limit: 1
    )
    var iterator = subscription.makeAsyncIterator()
    let firstEmission = try await iterator.next()
    expectNoDifference(firstEmission, [first])

    do {
      _ = try await client.subscribeRoomTopicMessages(
        room: room,
        topic: "sendEmoji",
        limit: -1
      )
      Issue.record("Expected negative room topic subscription limit to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed)
      expectNoDifference(error.operation, "subscribe room topic messages")
    } catch {
      Issue.record("Unexpected error: \(error).")
    }
  }

  @Test
  func roomTopicMessagesPropertyWrapperSubscribeCancellationAfterObserveDoesNotSucceed()
    async throws
  {
    let gate = AuthSessionLoadGate()
    let client = roomClient(
      observeRoomTopicMessages: { _, _ in
        await gate.recordStarted()
        await gate.waitUntilReleased()
        return AsyncStream { continuation in continuation.finish() }
      }
    )
    let messages = RoomTopicMessages("chat", "lobby", "sendEmoji")

    let task = Task {
      let messages = messages
      _ = try await messages.subscribe(using: client)
    }

    await gate.waitUntilStarted()
    task.cancel()
    await gate.release()

    do {
      try await task.value
      Issue.record("Expected @RoomTopicMessages subscribe cancellation to throw CancellationError.")
    } catch is CancellationError {
    } catch {
      Issue.record("Expected CancellationError, got \(error).")
    }
  }

  @Test
  func projectedAdapterLifecycleAPIsWorkFromImmutableModels() async throws {
    let session = mockAuthSession(userID: "immutable-user")
    let room = InstantRoomHandle(type: "chat", id: "lobby")
    let member = mockRoomPresenceMember(room: room, userID: "user-1")
    let firstMessage = mockRoomTopicMessage(room: room, topic: "sendEmoji")
    let laterMessage = mockRoomTopicMessage(
      room: room,
      topic: "sendEmoji",
      id: "message-2",
      payload: .object(["emoji": .string("sparkles")])
    )
    let authClient = authSessionClient(
      load: { session },
      observe: {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
          continuation.yield(nil)
          continuation.yield(session)
          continuation.finish()
        }
      }
    )
    let roomsClient = roomClient(
      roomPresence: { room in
        expectNoDifference(room, InstantRoomHandle(type: "chat", id: "lobby"))
        return [member]
      },
      observeRoomPresence: { room in
        expectNoDifference(room, InstantRoomHandle(type: "chat", id: "lobby"))
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
          continuation.yield([])
          continuation.yield([member])
          continuation.finish()
        }
      },
      roomTopicMessages: { room, topic, limit in
        expectNoDifference(room, InstantRoomHandle(type: "chat", id: "lobby"))
        expectNoDifference(topic, "sendEmoji")
        expectNoDifference(limit, 1)
        return [firstMessage, laterMessage]
      },
      observeRoomTopicMessages: { room, topic in
        expectNoDifference(room, InstantRoomHandle(type: "chat", id: "lobby"))
        expectNoDifference(topic, "sendEmoji")
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
          continuation.yield([])
          continuation.yield([firstMessage, laterMessage])
          continuation.finish()
        }
      }
    )
    let localIDRecorder = LocalIDRecorder()
    let localIDClient = localIDClient(localIDRecorder)
    let model = ImmutableProjectedAdapterLifecycleModel()

    try await model.exerciseAuth(using: authClient)
    try await model.exerciseRoom(room: room, topic: "sendEmoji", using: roomsClient)
    try await model.exerciseLocalID(using: localIDClient)

    expectNoDifference(model.session, session)
    expectNoDifference(model.members, [member])
    expectNoDifference(model.messages, [firstMessage])
    expectNoDifference(model.localID, "local-id-session")
    expectNoDifference(model.$session.loadError, nil)
    expectNoDifference(model.$members.loadError, nil)
    expectNoDifference(model.$messages.loadError, nil)
    expectNoDifference(model.$localID.loadError, nil)
    let resolvedNames = await localIDRecorder.recordedNames()
    expectNoDifference(resolvedNames, ["device", "session"])
  }

  @Test
  func fileAndStreamClientOperationsUseInjectedClosures() async throws {
    let sourceURL = URL(fileURLWithPath: "/tmp/mock-file.txt")
    let file = mockStoredFile(id: "file-1", name: "mock-file.txt")
    let contents = InstantStoredFileContents(file: file, data: Data("hello".utf8))
    let progress = mockFileUploadProgress(file: file, state: .success)
    let chunk = mockStreamChunk(streamID: "chat/lobby")
    let client = integrationClient(
      uploadFile: { url, name, contentType in
        expectNoDifference(url, sourceURL)
        expectNoDifference(name, "renamed.txt")
        expectNoDifference(contentType, "text/plain")
        return file
      },
      uploadFileProgress: { url, name, contentType in
        expectNoDifference(url, sourceURL)
        expectNoDifference(name, "renamed.txt")
        expectNoDifference(contentType, "text/plain")
        return AsyncThrowingStream { continuation in
          continuation.yield(progress)
          continuation.finish()
        }
      },
      storedFiles: { [file] },
      observeStoredFiles: {
        AsyncStream { continuation in
          continuation.yield([file])
          continuation.finish()
        }
      },
      storedFileContents: { id in
        expectNoDifference(id, "file-1")
        return contents
      },
      deleteStoredFile: { id in
        expectNoDifference(id, "file-1")
        return file
      },
      appendStreamChunk: { streamID, payload in
        expectNoDifference(streamID, "chat/lobby")
        expectNoDifference(payload, .object(["text": .string("hello")]))
        return chunk
      },
      streamChunks: { streamID, limit in
        expectNoDifference(streamID, "chat/lobby")
        expectNoDifference(limit, 1)
        return [chunk]
      },
      observeStreamChunks: { streamID in
        expectNoDifference(streamID, "chat/lobby")
        return AsyncStream { continuation in
          continuation.yield([chunk])
          continuation.finish()
        }
      }
    )

    let uploadedFile = try await client.uploadFile(
      from: sourceURL,
      name: "renamed.txt",
      contentType: "text/plain"
    )
    expectNoDifference(uploadedFile, file)
    var progressIterator = try await client.uploadFileProgress(
      from: sourceURL,
      name: "renamed.txt",
      contentType: "text/plain"
    )
    .makeAsyncIterator()
    let observedProgress = try await progressIterator.next()
    expectNoDifference(observedProgress, progress)
    let listedFiles = try await client.storedFiles()
    expectNoDifference(listedFiles, [file])
    var filesIterator = try await client.observeStoredFiles().makeAsyncIterator()
    let observedFiles = await filesIterator.next()
    expectNoDifference(observedFiles, [file])
    let storedContents = try await client.storedFileContents(id: "file-1")
    expectNoDifference(storedContents, contents)
    let deletedFile = try await client.deleteStoredFile(id: "file-1")
    expectNoDifference(deletedFile, file)
    let appendedChunk = try await client.appendStreamChunk(
      streamID: "chat/lobby",
      payload: .object(["text": .string("hello")])
    )
    expectNoDifference(appendedChunk, chunk)
    let listedChunks = try await client.streamChunks(streamID: "chat/lobby", limit: 1)
    expectNoDifference(listedChunks, [chunk])
    var chunksIterator = try await client.observeStreamChunks(streamID: "chat/lobby")
      .makeAsyncIterator()
    let observedChunks = await chunksIterator.next()
    expectNoDifference(observedChunks, [chunk])
  }

  @Test
  func storedFilesPropertyWrapperLoadsUsingDependencyClient() async throws {
    let file = mockStoredFile(id: "file-1")
    let client = integrationClient(
      storedFiles: { [file] }
    )

    try await withDependencies {
      $0.defaultInstantSwiftData = client
    } operation: {
      @StoredFiles var files: [InstantStoredFile]

      try await $files.load()

      expectNoDifference(files, [file])
      expectNoDifference($files.loadError, nil)
      expectNoDifference($files.isLoading, false)
    }
  }

  @Test
  func storedFilesPropertyWrapperPreservesCachedValueAndRecordsLoadError() async throws {
    let cached = [mockStoredFile(id: "cached-file")]
    let expectedError = InstantError(
      code: .implementationFailed,
      operation: "load test StoredFiles",
      message: "files failed",
      recovery: "Retry with a working files client."
    )
    let client = integrationClient(
      storedFiles: { throw expectedError }
    )

    @StoredFiles var files: [InstantStoredFile] = cached

    do {
      try await $files.load(using: client)
      Issue.record("Expected @StoredFiles to surface client failures.")
    } catch let error as InstantError {
      expectNoDifference(error.operation, "load test StoredFiles")
      expectNoDifference($files.loadError?.operation, "load test StoredFiles")
    } catch {
      Issue.record("Unexpected error: \(error).")
    }

    expectNoDifference(files, cached)
    expectNoDifference($files.isLoading, false)
  }

  @Test
  func storedFilesPropertyWrapperTaskBindsObservedFiles() async throws {
    let file = mockStoredFile(id: "file-1")
    let client = integrationClient(
      observeStoredFiles: {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
          continuation.yield([])
          continuation.yield([file])
          continuation.finish()
        }
      }
    )

    @StoredFiles var files: [InstantStoredFile]

    try await $files.task(using: client)

    expectNoDifference(files, [file])
    expectNoDifference($files.loadError, nil)
    expectNoDifference($files.isLoading, false)
  }

  @Test
  func storedFilesPropertyWrapperSubscribeCancelsUnderlyingObservation() async throws {
    let termination = RoomObservationTermination()
    let client = integrationClient(
      observeStoredFiles: {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
          continuation.yield([])
          continuation.onTermination = { @Sendable _ in
            Task {
              await termination.record()
            }
          }
        }
      }
    )

    let files = StoredFiles()
    let subscription = try await files.subscribe(using: client)
    var iterator = subscription.makeAsyncIterator()
    let initialFiles = try await iterator.next()
    expectNoDifference(initialFiles, [])

    subscription.cancel()
    #expect(try await iterator.next() == nil)
    await termination.wait()
  }

  @Test
  func storedFilesClientSubscriptionAdapterCancelsUnderlyingObservation() async throws {
    let file = mockStoredFile(id: "file-1")
    let termination = RoomObservationTermination()
    let client = integrationClient(
      observeStoredFiles: {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
          continuation.yield([file])
          continuation.onTermination = { @Sendable _ in
            Task {
              await termination.record()
            }
          }
        }
      }
    )

    let subscription = try await client.subscribeStoredFiles()
    var iterator = subscription.makeAsyncIterator()
    let firstEmission = try await iterator.next()
    expectNoDifference(firstEmission, [file])

    subscription.cancel()
    #expect(try await iterator.next() == nil)
    await termination.wait()
  }

  @Test
  func storedFilesClientSubscriptionAdapterCancellationAfterObserveDoesNotSucceed()
    async throws
  {
    let gate = AuthSessionLoadGate()
    let client = integrationClient(
      observeStoredFiles: {
        await gate.recordStarted()
        await gate.waitUntilReleased()
        return AsyncStream { continuation in continuation.finish() }
      }
    )

    let task = Task {
      _ = try await client.subscribeStoredFiles()
    }

    await gate.waitUntilStarted()
    task.cancel()
    await gate.release()

    do {
      try await task.value
      Issue.record("Expected stored files subscription cancellation to throw CancellationError.")
    } catch is CancellationError {
    } catch {
      Issue.record("Expected CancellationError, got \(error).")
    }
  }

  @Test
  func streamChunksPropertyWrapperLoadsUsingDependencyClient() async throws {
    let chunk = mockStreamChunk(streamID: "chat/lobby")
    let client = integrationClient(
      streamChunks: { streamID, limit in
        expectNoDifference(streamID, "chat/lobby")
        expectNoDifference(limit, 1)
        return [chunk]
      }
    )

    try await withDependencies {
      $0.defaultInstantSwiftData = client
    } operation: {
      @StreamChunks("chat/lobby", limit: 1) var chunks: [InstantStreamChunk]

      try await $chunks.load()

      expectNoDifference(chunks, [chunk])
      expectNoDifference($chunks.loadError, nil)
      expectNoDifference($chunks.isLoading, false)
    }
  }

  @Test
  func streamChunksPropertyWrapperRecordsNegativeLimitErrors() async throws {
    let chunks = StreamChunks("chat/lobby", limit: -1)

    do {
      try await chunks.load(using: integrationClient())
      Issue.record("Expected @StreamChunks negative load limit to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed)
      expectNoDifference(error.operation, "load StreamChunks")
      expectNoDifference(chunks.loadError?.operation, "load StreamChunks")
    } catch {
      Issue.record("Unexpected error: \(error).")
    }

    expectNoDifference(chunks.wrappedValue, [])
    expectNoDifference(chunks.isLoading, false)

    do {
      _ = try await chunks.subscribe("chat/lobby", limit: -1, using: integrationClient())
      Issue.record("Expected @StreamChunks negative subscribe limit to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed)
      expectNoDifference(error.operation, "subscribe StreamChunks")
      expectNoDifference(chunks.loadError?.operation, "subscribe StreamChunks")
    } catch {
      Issue.record("Unexpected error: \(error).")
    }
  }

  @Test
  func streamChunksPropertyWrapperTaskBindsObservedChunks() async throws {
    let chunk = mockStreamChunk(streamID: "chat/lobby")
    let laterChunk = mockStreamChunk(id: "chunk-2", streamID: "chat/lobby", index: 1)
    let client = integrationClient(
      observeStreamChunks: { streamID in
        expectNoDifference(streamID, "chat/lobby")
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
          continuation.yield([])
          continuation.yield([chunk, laterChunk])
          continuation.finish()
        }
      }
    )

    @StreamChunks var chunks: [InstantStreamChunk]

    try await $chunks.task("chat/lobby", limit: 1, using: client)

    expectNoDifference(chunks, [chunk])
    expectNoDifference($chunks.loadError, nil)
    expectNoDifference($chunks.isLoading, false)
  }

  @Test
  func streamChunksPropertyWrapperSubscribeCancelsUnderlyingObservation() async throws {
    let chunk = mockStreamChunk(streamID: "chat/lobby")
    let laterChunk = mockStreamChunk(id: "chunk-2", streamID: "chat/lobby", index: 1)
    let termination = RoomObservationTermination()
    let client = integrationClient(
      observeStreamChunks: { streamID in
        expectNoDifference(streamID, "chat/lobby")
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
          continuation.yield([chunk, laterChunk])
          continuation.onTermination = { @Sendable _ in
            Task {
              await termination.record()
            }
          }
        }
      }
    )

    let chunks = StreamChunks("chat/lobby", limit: 1)
    let subscription = try await chunks.subscribe(using: client)
    var iterator = subscription.makeAsyncIterator()
    let initialChunks = try await iterator.next()
    expectNoDifference(initialChunks, [chunk])

    subscription.cancel()
    #expect(try await iterator.next() == nil)
    await termination.wait()
  }

  @Test
  func streamClientSubscriptionAdapterAppliesLimitAndValidatesInput() async throws {
    let first = mockStreamChunk(streamID: "chat/lobby")
    let second = mockStreamChunk(id: "chunk-2", streamID: "chat/lobby", index: 1)
    let client = integrationClient(
      observeStreamChunks: { streamID in
        expectNoDifference(streamID, "chat/lobby")
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
          continuation.yield([first, second])
          continuation.finish()
        }
      }
    )

    let subscription = try await client.subscribeStreamChunks(
      streamID: "chat/lobby",
      limit: 1
    )
    var iterator = subscription.makeAsyncIterator()
    let firstEmission = try await iterator.next()
    expectNoDifference(firstEmission, [first])

    do {
      _ = try await client.subscribeStreamChunks(streamID: "chat/lobby", limit: -1)
      Issue.record("Expected negative stream chunk subscription limit to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed)
      expectNoDifference(error.operation, "subscribe stream chunks")
    } catch {
      Issue.record("Unexpected error: \(error).")
    }
  }

  @Test
  func streamClientSubscriptionAdapterCancellationAfterObserveDoesNotSucceed()
    async throws
  {
    let gate = AuthSessionLoadGate()
    let client = integrationClient(
      observeStreamChunks: { _ in
        await gate.recordStarted()
        await gate.waitUntilReleased()
        return AsyncStream { continuation in continuation.finish() }
      }
    )

    let task = Task {
      _ = try await client.subscribeStreamChunks(streamID: "chat/lobby")
    }

    await gate.waitUntilStarted()
    task.cancel()
    await gate.release()

    do {
      try await task.value
      Issue.record("Expected stream chunk subscription cancellation to throw CancellationError.")
    } catch is CancellationError {
    } catch {
      Issue.record("Expected CancellationError, got \(error).")
    }
  }

  @Test
  func shareClientOperationsUseInjectedClosures() async throws {
    let snapshot = mockShareSnapshot()
    let accepted = mockShareSnapshot(
      memberships: [("user-1", .owner), ("user-2", .reader)]
    )
    let promoted = mockShareSnapshot(
      memberships: [("user-1", .owner), ("user-2", .writer)]
    )
    let client = integrationClient(
      createShare: { namespace, id in
        expectNoDifference(namespace, "todos")
        expectNoDifference(id, "todo-1")
        return snapshot
      },
      acceptShare: { token in
        expectNoDifference(token, snapshot.share.token)
        return accepted
      },
      shares: { [accepted] },
      observeShares: {
        AsyncStream { continuation in
          continuation.yield([accepted])
          continuation.finish()
        }
      },
      updateShareMembershipRole: { shareID, userID, role in
        expectNoDifference(shareID, snapshot.share.id)
        expectNoDifference(userID, "user-2")
        expectNoDifference(role, .writer)
        return promoted
      },
      revokeShare: { id in
        expectNoDifference(id, snapshot.share.id)
        return snapshot
      }
    )

    let createdShare = try await client.createShare(rootNamespace: "todos", rootID: "todo-1")
    expectNoDifference(createdShare, snapshot)
    let acceptedShare = try await client.acceptShare(token: snapshot.share.token)
    expectNoDifference(acceptedShare, accepted)
    let listedShares = try await client.shares()
    expectNoDifference(listedShares, [accepted])
    var shareIterator = try await client.observeShares().makeAsyncIterator()
    let observedShares = await shareIterator.next()
    expectNoDifference(observedShares, [accepted])
    let promotedShare = try await client.updateShareMembershipRole(
      shareID: snapshot.share.id,
      userID: "user-2",
      role: .writer
    )
    expectNoDifference(promotedShare, promoted)
    let revokedShare = try await client.revokeShare(id: snapshot.share.id)
    expectNoDifference(revokedShare, snapshot)
  }

  @Test
  func shareClientSubscriptionAdapterCancelsUnderlyingObservation() async throws {
    let snapshot = mockShareSnapshot()
    let termination = RoomObservationTermination()
    let client = integrationClient(
      observeShares: {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
          continuation.yield([snapshot])
          continuation.onTermination = { @Sendable _ in
            Task {
              await termination.record()
            }
          }
        }
      }
    )

    let subscription = try await client.subscribeShares()
    var iterator = subscription.makeAsyncIterator()
    let firstEmission = try await iterator.next()
    expectNoDifference(firstEmission, [snapshot])

    subscription.cancel()
    #expect(try await iterator.next() == nil)
    await termination.wait()
  }

  @Test
  func shareClientSubscriptionAdapterCancellationAfterObserveDoesNotSucceed() async throws {
    let gate = AuthSessionLoadGate()
    let client = integrationClient(
      observeShares: {
        await gate.recordStarted()
        await gate.waitUntilReleased()
        return AsyncStream { continuation in continuation.finish() }
      }
    )

    let task = Task {
      _ = try await client.subscribeShares()
    }

    await gate.waitUntilStarted()
    task.cancel()
    await gate.release()

    do {
      try await task.value
      Issue.record("Expected share subscription cancellation to throw CancellationError.")
    } catch is CancellationError {
    } catch {
      Issue.record("Expected CancellationError, got \(error).")
    }
  }

  @Test
  func sharesPropertyWrapperLoadsUsingDependencyClient() async throws {
    let snapshot = mockShareSnapshot()
    let client = integrationClient(
      shares: { [snapshot] }
    )

    try await withDependencies {
      $0.defaultInstantSwiftData = client
    } operation: {
      @Shares var shares: [InstantShareSnapshot]

      try await $shares.load()

      expectNoDifference(shares, [snapshot])
      expectNoDifference($shares.loadError, nil)
      expectNoDifference($shares.isLoading, false)
    }
  }

  @Test
  func sharesPropertyWrapperPreservesCachedValueAndRecordsLoadError() async throws {
    let cached = [mockShareSnapshot(id: "cached-share")]
    let expectedError = InstantError(
      code: .implementationFailed,
      operation: "load test Shares",
      message: "shares failed",
      recovery: "Retry with a working shares client."
    )
    let client = integrationClient(
      shares: { throw expectedError }
    )

    @Shares var shares: [InstantShareSnapshot] = cached

    do {
      try await $shares.load(using: client)
      Issue.record("Expected @Shares to surface client failures.")
    } catch let error as InstantError {
      expectNoDifference(error.operation, "load test Shares")
      expectNoDifference($shares.loadError?.operation, "load test Shares")
    } catch {
      Issue.record("Unexpected error: \(error).")
    }

    expectNoDifference(shares, cached)
    expectNoDifference($shares.isLoading, false)
  }

  @Test
  func sharesPropertyWrapperTaskBindsObservedShares() async throws {
    let snapshot = mockShareSnapshot()
    let accepted = mockShareSnapshot(
      memberships: [("user-1", .owner), ("user-2", .reader)]
    )
    let client = integrationClient(
      observeShares: {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
          continuation.yield([snapshot])
          continuation.yield([accepted])
          continuation.finish()
        }
      }
    )

    @Shares var shares: [InstantShareSnapshot]

    try await $shares.task(using: client)

    expectNoDifference(shares, [accepted])
    expectNoDifference($shares.loadError, nil)
    expectNoDifference($shares.isLoading, false)
  }

  @Test
  func sharesPropertyWrapperSubscribeCancelsUnderlyingObservation() async throws {
    let snapshot = mockShareSnapshot()
    let termination = RoomObservationTermination()
    let client = integrationClient(
      observeShares: {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
          continuation.yield([snapshot])
          continuation.onTermination = { @Sendable _ in
            Task {
              await termination.record()
            }
          }
        }
      }
    )

    let shares = Shares()
    let subscription = try await shares.subscribe(using: client)
    var iterator = subscription.makeAsyncIterator()
    let initialShares = try await iterator.next()
    expectNoDifference(initialShares, [snapshot])

    subscription.cancel()
    #expect(try await iterator.next() == nil)
    await termination.wait()
  }

  @Test
  func projectedStorageStreamShareLifecycleAPIsWorkFromImmutableModels() async throws {
    let file = mockStoredFile(id: "immutable-file")
    let firstChunk = mockStreamChunk(streamID: "chat/lobby")
    let laterChunk = mockStreamChunk(id: "chunk-2", streamID: "chat/lobby", index: 1)
    let share = mockShareSnapshot(id: "immutable-share")
    let acceptedShare = mockShareSnapshot(
      id: "immutable-share",
      memberships: [("user-1", .owner), ("user-2", .reader)]
    )
    let client = integrationClient(
      storedFiles: { [file] },
      observeStoredFiles: {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
          continuation.yield([])
          continuation.yield([file])
          continuation.finish()
        }
      },
      streamChunks: { streamID, limit in
        expectNoDifference(streamID, "chat/lobby")
        expectNoDifference(limit, 1)
        return [firstChunk]
      },
      observeStreamChunks: { streamID in
        expectNoDifference(streamID, "chat/lobby")
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
          continuation.yield([])
          continuation.yield([firstChunk, laterChunk])
          continuation.finish()
        }
      },
      shares: { [share] },
      observeShares: {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
          continuation.yield([share])
          continuation.yield([acceptedShare])
          continuation.finish()
        }
      }
    )
    let model = ImmutableProjectedStorageStreamShareLifecycleModel()

    try await model.exercise(streamID: "chat/lobby", using: client)

    expectNoDifference(model.files, [file])
    expectNoDifference(model.chunks, [firstChunk])
    expectNoDifference(model.shares, [acceptedShare])
    expectNoDifference(model.$files.loadError, nil)
    expectNoDifference(model.$chunks.loadError, nil)
    expectNoDifference(model.$shares.loadError, nil)
  }

  #if canImport(SwiftUI)
    @Test
    func storageStreamShareWrappersExposeSwiftUIBindings() {
      let file = mockStoredFile(id: "binding-file")
      let chunk = mockStreamChunk(streamID: "chat/bindings")
      let share = mockShareSnapshot(id: "binding-share")

      let files = StoredFiles()
      files.binding.wrappedValue = [file]
      expectNoDifference(files.wrappedValue, [file])

      let chunks = StreamChunks("chat/bindings")
      chunks.binding.wrappedValue = [chunk]
      expectNoDifference(chunks.wrappedValue, [chunk])

      let shares = Shares()
      shares.binding.wrappedValue = [share]
      expectNoDifference(shares.wrappedValue, [share])
    }
  #endif

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

    do {
      _ = try await mock.roomPresence(room: InstantRoomHandle(type: "chat", id: "lobby"))
      #expect(Bool(false), "Expected old-shape mock client rooms to fail without room closures.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .implementationFailed)
      expectNoDifference(error.operation, "access InstantSwiftData rooms")
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    do {
      _ = try await mock.observeRoomPresence(room: InstantRoomHandle(type: "chat", id: "lobby"))
      #expect(Bool(false), "Expected old-shape mock client room observers to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .implementationFailed)
      expectNoDifference(error.operation, "access InstantSwiftData rooms")
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    do {
      _ = try await mock.storedFiles()
      #expect(Bool(false), "Expected old-shape mock client files to fail without file closures.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .implementationFailed)
      expectNoDifference(error.operation, "access InstantSwiftData files")
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    do {
      _ = try await mock.streamChunks(streamID: "chat/lobby")
      #expect(Bool(false), "Expected old-shape mock client streams to fail without stream closures.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .implementationFailed)
      expectNoDifference(error.operation, "access InstantSwiftData streams")
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    do {
      _ = try await mock.shares()
      #expect(Bool(false), "Expected old-shape mock client shares to fail without share closures.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .implementationFailed)
      expectNoDifference(error.operation, "access InstantSwiftData shares")
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

private actor RoomObservationTermination {
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

private actor LocalIDRecorder {
  private var names: [String] = []

  func resolve(_ name: String) -> String {
    names.append(name)
    return "local-id-\(name)"
  }

  func recordedNames() -> [String] {
    names
  }
}

private struct ImmutableProjectedAdapterLifecycleModel {
  @AuthSession var session: InstantAuthSession?
  @RoomPresence var members: [InstantRoomPresenceMember]
  @RoomTopicMessages var messages: [InstantRoomTopicMessage]
  @LocalID var localID: String?

  func exerciseAuth(using client: InstantSwiftDataClient) async throws {
    try await $session.load(using: client)
    let subscription = try await $session.subscribe(using: client)
    subscription.cancel()
    try await $session.task(using: client)
  }

  func exerciseRoom(
    room: InstantRoomHandle,
    topic: String,
    using client: InstantSwiftDataClient
  ) async throws {
    try await $members.load(room: room, using: client)
    let membersSubscription = try await $members.subscribe(room: room, using: client)
    membersSubscription.cancel()
    try await $members.task(room: room, using: client)

    try await $messages.load(room: room, topic: topic, limit: 1, using: client)
    let messagesSubscription = try await $messages.subscribe(
      room: room,
      topic: topic,
      limit: 1,
      using: client
    )
    messagesSubscription.cancel()
    try await $messages.task(room: room, topic: topic, limit: 1, using: client)
  }

  func exerciseLocalID(using client: InstantSwiftDataClient) async throws {
    try await $localID.load("device", using: client)
    try await $localID.task("session", using: client)
  }
}

private struct ImmutableProjectedStorageStreamShareLifecycleModel {
  @StoredFiles var files: [InstantStoredFile]
  @StreamChunks var chunks: [InstantStreamChunk]
  @Shares var shares: [InstantShareSnapshot]

  func exercise(streamID: String, using client: InstantSwiftDataClient) async throws {
    try await $files.load(using: client)
    let filesSubscription = try await $files.subscribe(using: client)
    filesSubscription.cancel()
    try await $files.task(using: client)

    try await $chunks.load(streamID, limit: 1, using: client)
    let chunksSubscription = try await $chunks.subscribe(streamID, limit: 1, using: client)
    chunksSubscription.cancel()
    try await $chunks.task(streamID, limit: 1, using: client)

    try await $shares.load(using: client)
    let sharesSubscription = try await $shares.subscribe(using: client)
    sharesSubscription.cancel()
    try await $shares.task(using: client)
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

private func mockRoomPresenceMember(
  room: InstantRoomHandle,
  userID: String,
  values: [String: JSONValue] = ["status": .string("online")]
) -> InstantRoomPresenceMember {
  InstantRoomPresenceMember(
    appID: "mock-app",
    room: room,
    userID: userID,
    values: values,
    updatedAt: InstantTimestamp(milliseconds: 3)
  )
}

private func mockRoomTopicMessage(
  room: InstantRoomHandle,
  topic: String,
  id: String = "message-1",
  payload: JSONValue = .object(["emoji": .string("wave")])
) -> InstantRoomTopicMessage {
  InstantRoomTopicMessage(
    id: id,
    appID: "mock-app",
    room: room,
    topic: topic,
    userID: "user-1",
    payload: payload,
    createdAt: InstantTimestamp(milliseconds: 4)
  )
}

private func mockStoredFile(
  id: String,
  name: String = "mock-file.txt",
  contentType: String? = "text/plain"
) -> InstantStoredFile {
  InstantStoredFile(
    id: id,
    appID: "mock-app",
    name: name,
    contentType: contentType,
    byteCount: 5,
    localPath: "/tmp/\(name)",
    ownerUserID: "user-1",
    createdAt: InstantTimestamp(milliseconds: 5),
    updatedAt: InstantTimestamp(milliseconds: 6)
  )
}

private func mockFileUploadProgress(
  file: InstantStoredFile,
  state: InstantStorageOperationState
) -> InstantFileUploadProgress {
  InstantFileUploadProgress(
    operationID: file.id,
    appID: file.appID,
    fileID: file.id,
    fileName: file.name,
    contentType: file.contentType,
    state: state,
    completedByteCount: file.byteCount,
    totalByteCount: file.byteCount,
    progress: state == .success ? 1 : 0,
    file: state == .success ? file : nil,
    updatedAt: InstantTimestamp(milliseconds: 7)
  )
}

private func mockStreamChunk(
  id: String = "chunk-1",
  streamID: String,
  index: Int64 = 0,
  payload: JSONValue = .object(["text": .string("hello")])
) -> InstantStreamChunk {
  InstantStreamChunk(
    id: id,
    appID: "mock-app",
    streamID: streamID,
    index: index,
    payload: payload,
    userID: "user-1",
    createdAt: InstantTimestamp(milliseconds: 8 + index)
  )
}

private func mockShareSnapshot(
  id: String = "share-1",
  rootNamespace: String = "todos",
  rootID: String = "todo-1",
  ownerUserID: String = "user-1",
  memberships: [(userID: String, role: InstantShareRole)] = [("user-1", .owner)]
) -> InstantShareSnapshot {
  InstantShareSnapshot(
    share: InstantShare(
      id: id,
      appID: "mock-app",
      rootNamespace: rootNamespace,
      rootID: rootID,
      ownerUserID: ownerUserID,
      token: "token-\(id)",
      createdAt: InstantTimestamp(milliseconds: 9),
      updatedAt: InstantTimestamp(milliseconds: 10)
    ),
    memberships: memberships.map { membership in
      InstantShareMembership(
        appID: "mock-app",
        shareID: id,
        userID: membership.userID,
        role: membership.role,
        acceptedAt: InstantTimestamp(milliseconds: 11)
      )
    }
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

private func localIDClient(_ recorder: LocalIDRecorder) -> InstantSwiftDataClient {
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
    localID: { name in
      await recorder.resolve(name)
    }
  )
}

private func roomClient(
  setPresence: @escaping @Sendable (
    InstantRoomHandle,
    String?,
    [String: JSONValue]
  ) async throws -> InstantRoomPresenceMember = { room, userID, values in
    mockRoomPresenceMember(room: room, userID: userID ?? "mock-user", values: values)
  },
  roomPresence: @escaping @Sendable (InstantRoomHandle) async throws
    -> [InstantRoomPresenceMember] = { _ in [] },
  observeRoomPresence: @escaping @Sendable (InstantRoomHandle) async throws
    -> AsyncStream<[InstantRoomPresenceMember]> = { _ in
      AsyncStream { continuation in continuation.finish() }
    },
  leavePresence: @escaping @Sendable (InstantRoomHandle, String?) async throws
    -> String = { _, userID in userID ?? "mock-user" },
  publishTopicMessage: @escaping @Sendable (
    InstantRoomHandle,
    String,
    String?,
    JSONValue
  ) async throws -> InstantRoomTopicMessage = { room, topic, _, payload in
    mockRoomTopicMessage(room: room, topic: topic, payload: payload)
  },
  roomTopicMessages: @escaping @Sendable (InstantRoomHandle, String, Int?) async throws
    -> [InstantRoomTopicMessage] = { _, _, _ in [] },
  observeRoomTopicMessages: @escaping @Sendable (InstantRoomHandle, String) async throws
    -> AsyncStream<[InstantRoomTopicMessage]> = { _, _ in
      AsyncStream { continuation in continuation.finish() }
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
    observe: { _ in AsyncStream { continuation in continuation.finish() } },
    pendingMutations: { [] },
    localID: { name in "mock-\(name)" },
    setRoomPresence: setPresence,
    roomPresence: roomPresence,
    observeRoomPresence: observeRoomPresence,
    leaveRoomPresence: leavePresence,
    publishRoomTopicMessage: publishTopicMessage,
    roomTopicMessages: roomTopicMessages,
    observeRoomTopicMessages: observeRoomTopicMessages
  )
}

private func integrationClient(
  uploadFile: @escaping @Sendable (URL, String?, String?) async throws
    -> InstantStoredFile = { _, name, contentType in
      mockStoredFile(id: "mock-file", name: name ?? "mock-file.txt", contentType: contentType)
    },
  uploadFileProgress: @escaping @Sendable (URL, String?, String?) async throws
    -> AsyncThrowingStream<InstantFileUploadProgress, Error> = { _, name, contentType in
      let file = mockStoredFile(
        id: "mock-file",
        name: name ?? "mock-file.txt",
        contentType: contentType
      )
      return AsyncThrowingStream { continuation in
        continuation.yield(mockFileUploadProgress(file: file, state: .success))
        continuation.finish()
      }
    },
  storedFiles: @escaping @Sendable () async throws -> [InstantStoredFile] = { [] },
  observeStoredFiles: @escaping @Sendable () async throws
    -> AsyncStream<[InstantStoredFile]> = {
      AsyncStream { continuation in continuation.finish() }
    },
  storedFileContents: @escaping @Sendable (String) async throws
    -> InstantStoredFileContents = { id in
      let file = mockStoredFile(id: id)
      return InstantStoredFileContents(file: file, data: Data())
    },
  deleteStoredFile: @escaping @Sendable (String) async throws -> InstantStoredFile = { id in
    mockStoredFile(id: id)
  },
  appendStreamChunk: @escaping @Sendable (String, JSONValue) async throws
    -> InstantStreamChunk = { streamID, payload in
      mockStreamChunk(streamID: streamID, payload: payload)
    },
  streamChunks: @escaping @Sendable (String, Int?) async throws
    -> [InstantStreamChunk] = { _, _ in [] },
  observeStreamChunks: @escaping @Sendable (String) async throws
    -> AsyncStream<[InstantStreamChunk]> = { _ in
      AsyncStream { continuation in continuation.finish() }
    },
  createShare: @escaping @Sendable (String, String) async throws
    -> InstantShareSnapshot = { namespace, id in
      mockShareSnapshot(rootNamespace: namespace, rootID: id)
    },
  acceptShare: @escaping @Sendable (String) async throws -> InstantShareSnapshot = { token in
    mockShareSnapshot(id: token)
  },
  shares: @escaping @Sendable () async throws -> [InstantShareSnapshot] = { [] },
  observeShares: @escaping @Sendable () async throws
    -> AsyncStream<[InstantShareSnapshot]> = {
      AsyncStream { continuation in continuation.finish() }
    },
  updateShareMembershipRole: @escaping @Sendable (
    String,
    String,
    InstantShareRole
  ) async throws -> InstantShareSnapshot = { shareID, userID, role in
    mockShareSnapshot(
      id: shareID,
      memberships: [("user-1", .owner), (userID, role)]
    )
  },
  revokeShare: @escaping @Sendable (String) async throws -> InstantShareSnapshot = { id in
    mockShareSnapshot(id: id)
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
    observe: { _ in AsyncStream { continuation in continuation.finish() } },
    pendingMutations: { [] },
    localID: { name in "mock-\(name)" },
    uploadFile: uploadFile,
    uploadFileProgress: uploadFileProgress,
    storedFiles: storedFiles,
    observeStoredFiles: observeStoredFiles,
    storedFileContents: storedFileContents,
    deleteStoredFile: deleteStoredFile,
    appendStreamChunk: appendStreamChunk,
    streamChunks: streamChunks,
    observeStreamChunks: observeStreamChunks,
    createShare: createShare,
    acceptShare: acceptShare,
    shares: shares,
    observeShares: observeShares,
    updateShareMembershipRole: updateShareMembershipRole,
    revokeShare: revokeShare
  )
}
