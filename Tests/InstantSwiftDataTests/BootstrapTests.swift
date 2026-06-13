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
  func dependencyOverrideCanInstallMockClient() async throws {
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
      try await client.signOut()
    }
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
