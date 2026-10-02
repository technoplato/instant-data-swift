import CustomDump
import Foundation
import Testing

@testable import InstantSwiftData

/// A second sign-in is a temporary client of the primary's app: its own store and connection, so a second identity
/// signs in beside the primary without promoting, linking, or replacing the primary's session (#361).
///
/// Instant's client keeps one auth session per store and forwards a guest's refresh token to magic-code and OAuth
/// exchanges (`Reactor.signInWithMagicCode`, `Reactor.exchangeCodeForToken`) and any current token to ID-token
/// exchanges (`Reactor.signInWithIdToken`). These tests pin that a second sign-in sends no refresh token at all, never
/// changes the primary, revokes only a token it minted, and leaves no store behind. The network is the fake server
/// below: auth endpoints through `InstantAuthHTTPClient` and websockets through `InstantLiveTransportClient`.
@Suite(.serialized)
struct InstantSecondSignInTests {
  @Test(
    "A second sign-in sends no refresh token and leaves the primary's session and outbox unchanged",
    arguments: [false, true]
  )
  func secondSignInsSendNoRefreshTokenAndLeaveThePrimaryUntouched(primaryIsGuest: Bool) async throws {
    let fixture = try await SecondSignInFixture.make(primary: primaryIsGuest ? .guest : .user)
    defer { fixture.removePrimaryStore() }
    let server = fixture.server
    await server.expectMagicCode(email: "b@example.com", code: "123456", signsIn: "user-b")
    await server.expectOAuthCode("code-b", signsIn: "user-b")
    await server.expectIDToken("id-token-b", signsIn: "user-b")
    try await fixture.queueNoteOnPrimary()
    let before = try await fixture.primaryState()
    #expect(before.session.isGuest == primaryIsGuest)
    expectNoDifference(before.outbox.map(\.status), [.pending])
    let firstRequest = await server.authRequests.count

    let magicCode = try await InstantSecondSignIn.open(beside: fixture.primary)
    _ = try await magicCode.sendMagicCode(email: "b@example.com")
    let magicCodeSession = try await magicCode.signInWithMagicCode(email: "b@example.com", code: "123456")
    let oauth = try await InstantSecondSignIn.open(beside: fixture.primary)
    let oauthSession = try await oauth.signIn(
      with: InstantAuthProviderCredential(
        providerID: InstantAuthProviderID(rawValue: "google"),
        payload: .authorizationCode(value: "code-b", codeVerifier: "verifier-b")
      ),
      provider: .google(
        clientName: "google",
        presentation: .externalBrowser,
        redirectURL: URL(string: "second-sign-in://oauth-callback")
      )
    )
    let idToken = try await InstantSecondSignIn.open(beside: fixture.primary)
    let idTokenSession = try await idToken.signInWithIDToken(
      clientName: "apple",
      idToken: "id-token-b",
      nonce: "nonce-b"
    )

    expectNoDifference(
      [magicCodeSession.userID, oauthSession.userID, idTokenSession.userID],
      ["user-b", "user-b", "user-b"]
    )
    let secondRequests = await server.authRequests.dropFirst(firstRequest)
    expectNoDifference(
      secondRequests.map(\.path),
      [
        "/runtime/auth/send_magic_code",
        "/runtime/auth/verify_magic_code",
        "/runtime/oauth/token",
        "/runtime/oauth/id_token",
      ]
    )
    expectNoDifference(secondRequests.filter(\.carriesRefreshToken), [])
    let during = try await fixture.primaryState()
    expectNoDifference(during, before)

    await magicCode.close()
    await oauth.close()
    await idToken.close()
    let after = try await fixture.primaryState()
    expectNoDifference(after, before)
  }

  @Test("Closing revokes only the token the second sign-in minted, once, and deletes its store")
  func closeRevokesOnlyTheTokenThisSignInMinted() async throws {
    let fixture = try await SecondSignInFixture.make(primary: .user)
    defer { fixture.removePrimaryStore() }
    await fixture.server.expectMagicCode(email: "b@example.com", code: "123456", signsIn: "user-b")
    let second = try await InstantSecondSignIn.open(beside: fixture.primary)
    let storeURL = try #require(second.client.runtime?.configuration.persistenceURL)
    _ = try await second.sendMagicCode(email: "b@example.com")
    let session = try await second.signInWithMagicCode(email: "b@example.com", code: "123456")
    let mintedToken = try #require(session.refreshToken)
    #expect(existingStoreFiles(storeURL).isEmpty == false)
    expectNoDifference(storeURL.deletingLastPathComponent().lastPathComponent, "InstantSecondSignIn")
    #expect(storeURL.lastPathComponent.hasPrefix(fixture.appID + "-"))

    await second.close()
    await second.close()

    let signOuts = await fixture.server.signOutTokens
    expectNoDifference(signOuts, [mintedToken])
    expectNoDifference(existingStoreFiles(storeURL), [])
    let primarySession = try await fixture.primary.authSession()
    expectNoDifference(primarySession?.refreshToken, "token-a")
  }

  @Test("Closing never revokes an adopted token: the primary's, or a stored credential's")
  func closeNeverRevokesAnAdoptedToken() async throws {
    let fixture = try await SecondSignInFixture.make(primary: .user)
    defer { fixture.removePrimaryStore() }
    await fixture.server.addUser(FakeInstantUser(id: "user-c", email: "c@example.com"), refreshToken: "token-c")
    let before = try await fixture.primaryState()

    let twin = try await InstantSecondSignIn.open(sharingSessionOf: fixture.primary)
    let twinStoreURL = try #require(twin.client.runtime?.configuration.persistenceURL)
    let twinSession = try #require(try await twin.session())
    expectNoDifference(twinSession.userID, "user-a")
    expectNoDifference(twinSession.refreshToken, "token-a")
    let stored = try await InstantSecondSignIn.open(beside: fixture.primary)
    let storedStoreURL = try #require(stored.client.runtime?.configuration.persistenceURL)
    let storedSession = try await stored.adoptRefreshToken("token-c")
    expectNoDifference(storedSession.userID, "user-c")

    await twin.close()
    await stored.close()

    let signOuts = await fixture.server.signOutTokens
    expectNoDifference(signOuts, [])
    expectNoDifference(existingStoreFiles(twinStoreURL), [])
    expectNoDifference(existingStoreFiles(storedStoreURL), [])
    let after = try await fixture.primaryState()
    expectNoDifference(after, before)
  }

  @Test("A failed sign-in still cleans up: no revocation, no store left")
  func aFailedSignInStillCleansUp() async throws {
    let fixture = try await SecondSignInFixture.make(primary: .user)
    defer { fixture.removePrimaryStore() }
    await fixture.server.expectMagicCode(email: "b@example.com", code: "123456", signsIn: "user-b")
    let second = try await InstantSecondSignIn.open(beside: fixture.primary)
    let storeURL = try #require(second.client.runtime?.configuration.persistenceURL)
    _ = try await second.sendMagicCode(email: "b@example.com")

    await #expect(throws: InstantError.self) {
      _ = try await second.signInWithMagicCode(email: "b@example.com", code: "000000")
    }
    let sessionAfterFailure = try await second.session()
    expectNoDifference(sessionAfterFailure, nil)
    await second.close()

    let signOuts = await fixture.server.signOutTokens
    expectNoDifference(signOuts, [])
    expectNoDifference(existingStoreFiles(storeURL), [])
  }

  @Test("A cancelled sign-in still cleans up: no revocation, no store left")
  func aCancelledSignInStillCleansUp() async throws {
    let fixture = try await SecondSignInFixture.make(primary: .user)
    defer { fixture.removePrimaryStore() }
    let server = fixture.server
    await server.expectOAuthCode("code-b", signsIn: "user-b")
    await server.holdRequests(to: "/runtime/oauth/token")
    let second = try await InstantSecondSignIn.open(beside: fixture.primary)
    let storeURL = try #require(second.client.runtime?.configuration.persistenceURL)

    let signIn = Task {
      try await second.signInWithOAuth(code: "code-b", codeVerifier: "verifier-b")
    }
    try await server.waitUntilHeldRequestArrives()
    signIn.cancel()
    await #expect(throws: CancellationError.self) {
      _ = try await signIn.value
    }
    await second.close()

    let signOuts = await server.signOutTokens
    expectNoDifference(signOuts, [])
    expectNoDifference(existingStoreFiles(storeURL), [])
  }

  @Test("Closing while a sign-in is in flight revokes the token that sign-in mints afterward")
  func closingDuringASignInRevokesTheTokenItMints() async throws {
    let fixture = try await SecondSignInFixture.make(primary: .user)
    defer { fixture.removePrimaryStore() }
    let server = fixture.server
    await server.expectOAuthCode("code-b", signsIn: "user-b")
    await server.holdRequests(to: "/runtime/oauth/token")
    let second = try await InstantSecondSignIn.open(beside: fixture.primary)
    let storeURL = try #require(second.client.runtime?.configuration.persistenceURL)

    let signIn = Task {
      try await second.signInWithOAuth(code: "code-b", codeVerifier: "verifier-b")
    }
    try await server.waitUntilHeldRequestArrives()
    await second.close()
    await server.releaseHeldRequests()
    await #expect(throws: CancellationError.self) {
      _ = try await signIn.value
    }

    let signOuts = await server.signOutTokens
    let minted = await server.mintedTokens
    expectNoDifference(minted.count, 1)
    expectNoDifference(signOuts, minted)
    expectNoDifference(existingStoreFiles(storeURL), [])
  }

  @Test("A second sign-in that has a session refuses every other sign-in")
  func aSignedInSecondSignInRefusesAnotherSignIn() async throws {
    let fixture = try await SecondSignInFixture.make(primary: .user)
    defer { fixture.removePrimaryStore() }
    let server = fixture.server
    await server.expectMagicCode(email: "b@example.com", code: "123456", signsIn: "user-b")
    await server.expectOAuthCode("code-b", signsIn: "user-b")
    await server.addUser(FakeInstantUser(id: "user-c"), refreshToken: "token-c")
    let second = try await InstantSecondSignIn.open(beside: fixture.primary)
    defer { Task { await second.close() } }
    _ = try await second.sendMagicCode(email: "b@example.com")
    _ = try await second.signInWithMagicCode(email: "b@example.com", code: "123456")
    let requestsAfterSignIn = await server.authRequests.count

    let refusals: [InstantError?] = [
      await thrownInstantError { _ = try await second.sendMagicCode(email: "b@example.com") },
      await thrownInstantError { _ = try await second.signInWithOAuth(code: "code-b") },
      await thrownInstantError {
        _ = try await second.signInWithIDToken(clientName: "apple", idToken: "id-token-b")
      },
      await thrownInstantError { _ = try await second.adoptRefreshToken("token-c") },
    ]

    expectNoDifference(refusals.map { $0?.code }, [.authFailed, .authFailed, .authFailed, .authFailed])
    #expect(refusals.allSatisfy { $0?.message.contains("already signed in") == true })
    let requestsAfterRefusals = await server.authRequests.count
    expectNoDifference(requestsAfterRefusals, requestsAfterSignIn)
    let session = try await second.session()
    expectNoDifference(session?.userID, "user-b")
    await second.close()
  }

  @Test("transactAwaitingServer returns once Instant accepts the write")
  func transactAwaitingServerReturnsOnAcceptance() async throws {
    let fixture = try await SecondSignInFixture.make(primary: .user)
    defer { fixture.removePrimaryStore() }
    let second = try await fixture.openSignedInSecond()
    defer { Task { await second.close() } }

    try await second.transactAwaitingServer(
      noteTransaction(id: "tx-accepted", text: "accepted"),
      operation: "the note"
    )

    let transacts = await fixture.server.transacts
    expectNoDifference(transacts.map(\.userID), ["user-b"])
    expectNoDifference(transacts.map(\.transactionID), ["tx-accepted"])
    await second.close()
  }

  @Test("transactAwaitingServer throws the server's refusal")
  func transactAwaitingServerThrowsTheServersRefusal() async throws {
    let fixture = try await SecondSignInFixture.make(primary: .user)
    defer { fixture.removePrimaryStore() }
    await fixture.server.answerTransacts { _ in .refuse("Permission denied: not perms-pass?") }
    let second = try await fixture.openSignedInSecond()
    defer { Task { await second.close() } }

    let error = await thrownInstantError {
      try await second.transactAwaitingServer(
        noteTransaction(id: "tx-refused", text: "refused"),
        operation: "the note"
      )
    }

    expectNoDifference(error?.code, .permissionRejected)
    expectNoDifference(error?.localID, "tx-refused")
    expectNoDifference(error?.message, "Permission denied: not perms-pass?")
    await second.close()
  }

  @Test("transactAwaitingServer throws a timeout that names the write when Instant does not answer")
  func transactAwaitingServerTimesOutNamingTheWrite() async throws {
    let fixture = try await SecondSignInFixture.make(primary: .user)
    defer { fixture.removePrimaryStore() }
    await fixture.server.answerTransacts { _ in .hold }
    let second = try await fixture.openSignedInSecond()
    defer { Task { await second.close() } }

    let error = await thrownInstantError {
      try await second.transactAwaitingServer(
        noteTransaction(id: "tx-unanswered", text: "unanswered"),
        operation: "the note",
        timeout: .milliseconds(200)
      )
    }

    expectNoDifference(error?.code, .networkFailed)
    expectNoDifference(error?.localID, "tx-unanswered")
    expectNoDifference(error?.message, "Waited 200 milliseconds for Instant to accept the note.")
    let transacts = await fixture.server.transacts
    expectNoDifference(transacts.map(\.transactionID), ["tx-unanswered"])
    await second.close()
  }

  @Test("The server wait defaults to five seconds and says so")
  func theDefaultServerWaitIsFiveSeconds() {
    expectNoDifference(InstantSecondSignIn.waitDescription(.seconds(5)), "5 seconds")
    expectNoDifference(InstantSecondSignIn.waitDescription(.seconds(1)), "1 second")
    expectNoDifference(InstantSecondSignIn.waitDescription(.milliseconds(1_500)), "1500 milliseconds")
  }

  @Test("queryServer returns the server's answer, read as the second identity")
  func queryServerReturnsTheServersAnswer() async throws {
    let fixture = try await SecondSignInFixture.make(primary: .user)
    defer { fixture.removePrimaryStore() }
    await fixture.server.expectMagicCode(email: "b@example.com", code: "123456", signsIn: "user-b")
    let second = try await InstantSecondSignIn.open(
      beside: fixture.primary,
      registering: [.primaryKey(namespace: "$users"), fakeUsersEmailAttribute]
    )
    defer { Task { await second.close() } }
    _ = try await second.sendMagicCode(email: "b@example.com")
    _ = try await second.signInWithMagicCode(email: "b@example.com", code: "123456")

    let users = try await second.queryServer(
      InstantQueryPlan(
        id: "second-sign-in-user",
        namespace: "$users",
        filters: [.equals(field: "id", value: .string("user-b"))]
      )
    )

    expectNoDifference(users.map(\.id), ["user-b"])
    expectNoDifference(users.first?.values["email"], .one(.string("b@example.com")))
    let readers = await fixture.server.queryUserIDs
    expectNoDifference(readers, ["user-b"])
    await second.close()
  }

  @Test("Opening beside a client with no connection to Instant fails loudly")
  func openingBesideALocalOnlyClientFails() async throws {
    let storeURL = temporaryStoreURL("local-only-primary")
    defer { removeStoreFiles(storeURL) }
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "second-sign-in-local-only",
        persistenceURL: storeURL,
        initialAttributes: [fakeNoteTextAttribute]
      )
    )

    let error = await thrownInstantError {
      _ = try await InstantSecondSignIn.open(beside: InstantSwiftDataClient(runtime: runtime))
    }

    expectNoDifference(error?.code, .validationFailed)
    #expect(error?.message.hasPrefix("Linking another sign-in needs a connection to Instant") == true)
  }

  @Test("Sharing the session of a signed-out primary fails")
  func sharingTheSessionOfASignedOutPrimaryFails() async throws {
    let fixture = try await SecondSignInFixture.make(primary: .none)
    defer { fixture.removePrimaryStore() }

    let error = await thrownInstantError {
      _ = try await InstantSecondSignIn.open(sharingSessionOf: fixture.primary)
    }

    expectNoDifference(error?.code, .authFailed)
    #expect(error?.message.contains("not signed in") == true)
    let verifications = await fixture.server.authRequests.filter {
      $0.path == "/runtime/auth/verify_refresh_token"
    }
    expectNoDifference(verifications, [])
  }

  /// `InstantClientID.current` is a process-wide cache that only `clientID()` writes. Other suites write it while this
  /// one runs, so the test proves the cause instead: opening never resolves a client id on the temporary store.
  @Test("Opening never resolves a client id, so it never writes InstantClientID.current")
  func openingNeverPreparesAClientID() async throws {
    let fixture = try await SecondSignInFixture.make(primary: .user)
    defer { fixture.removePrimaryStore() }

    let beside = try await InstantSecondSignIn.open(beside: fixture.primary)
    let twin = try await InstantSecondSignIn.open(sharingSessionOf: fixture.primary)
    let besideIDs = try await #require(beside.client.runtime).localIDs()
    let twinIDs = try await #require(twin.client.runtime).localIDs()
    await beside.close()
    await twin.close()

    expectNoDifference(besideIDs.filter { $0.name == InstantClientID.name }, [])
    expectNoDifference(twinIDs.filter { $0.name == InstantClientID.name }, [])
  }
}

// MARK: - Fixture

/// A primary client of the fake server's app, on its own temporary store. It never connects, so a write queued on it
/// stays pending, and the second sign-ins copy its configuration: endpoints, exchanges, and live transport.
struct SecondSignInFixture {
  enum PrimarySignIn {
    case none
    case user
    case guest
  }

  struct PrimaryState: Equatable {
    var session: InstantAuthSession
    var outbox: [PendingMutation]
  }

  var server: FakeInstantServer
  var primary: InstantSwiftDataClient
  var primaryStoreURL: URL
  var appID: String

  static func make(
    appID: String = "second-sign-in-\(UUID().uuidString.prefix(8).lowercased())",
    attributes: [InstantAttribute] = [fakeNoteTextAttribute],
    primary signIn: PrimarySignIn
  ) async throws -> Self {
    let server = FakeInstantServer()
    await server.addUser(FakeInstantUser(id: "user-a", email: "a@example.com"), refreshToken: "token-a")
    await server.addUser(FakeInstantUser(id: "user-b", email: "b@example.com"), refreshToken: "token-b")
    await server.addGuest(FakeInstantUser(id: "guest-a", isGuest: true), refreshToken: "token-guest-a")
    let storeURL = temporaryStoreURL("primary")
    var configuration = InstantRuntimeConfiguration(
      appID: appID,
      apiURI: URL(string: "https://api.instant.test")!,
      websocketURI: URL(string: "wss://api.instant.test/runtime/session")!,
      persistenceURL: storeURL,
      initialAttributes: attributes,
      refreshTokenVerifier: .live(httpClient: server.http),
      guestAuthenticator: .live(httpClient: server.http),
      magicCodeExchange: .live(httpClient: server.http),
      idTokenExchange: .live(httpClient: server.http),
      oauthExchange: .live(httpClient: server.http),
      authTokenInvalidator: .live(httpClient: server.http),
      liveTransport: server.transport
    )
    configuration.autoConnectLiveTransport = false
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    let primary = InstantSwiftDataClient(runtime: runtime)
    switch signIn {
    case .none:
      break
    case .user:
      _ = try await primary.signInWithRefreshToken("token-a")
    case .guest:
      _ = try await primary.signInAsGuest()
    }
    return Self(server: server, primary: primary, primaryStoreURL: storeURL, appID: appID)
  }

  func primaryState() async throws -> PrimaryState {
    PrimaryState(
      session: try #require(try await primary.authSession()),
      outbox: try await #require(primary.runtime).outboxMutations()
    )
  }

  /// Queues one write on the primary. The primary never connects, so the write stays in its outbox.
  func queueNoteOnPrimary() async throws {
    try await primary.transact(noteTransaction(id: "tx-primary-note", text: "queued on the primary"))
  }

  /// A second sign-in signed in as `user-b` by magic code.
  func openSignedInSecond(registering attributes: [InstantAttribute] = []) async throws
    -> InstantSecondSignIn
  {
    await server.expectMagicCode(email: "b@example.com", code: "123456", signsIn: "user-b")
    let second = try await InstantSecondSignIn.open(beside: primary, registering: attributes)
    _ = try await second.sendMagicCode(email: "b@example.com")
    _ = try await second.signInWithMagicCode(email: "b@example.com", code: "123456")
    return second
  }

  func removePrimaryStore() {
    removeStoreFiles(primaryStoreURL)
  }
}

let fakeNoteTextAttribute = InstantAttribute(
  id: "notes/text",
  namespace: "notes",
  name: "text",
  valueType: .string
)

let fakeUsersEmailAttribute = InstantAttribute(
  id: "$users/email",
  namespace: "$users",
  name: "email",
  valueType: .string,
  isRequired: false,
  isIndexed: true,
  isUnique: true
)

func noteTransaction(id: String, text: String) -> InstantStoreTransaction {
  InstantStoreTransaction(
    id: id,
    operations: [
      .insert(
        InstantTriple(
          entityID: "note-\(id)",
          attributeID: fakeNoteTextAttribute.id,
          value: .string(text),
          txID: id,
          txTime: InstantTimestamp(milliseconds: 1_700_000_000_000)
        )
      )
    ]
  )
}

func temporaryStoreURL(_ name: String) -> URL {
  FileManager.default.temporaryDirectory.appendingPathComponent(
    "instant-second-sign-in-test-\(name)-\(UUID().uuidString).sqlite"
  )
}

func storeFilePaths(_ url: URL) -> [String] {
  [url.path, url.path + "-wal", url.path + "-shm", url.path + "-journal"]
}

func existingStoreFiles(_ url: URL) -> [String] {
  storeFilePaths(url).filter { FileManager.default.fileExists(atPath: $0) }
}

func removeStoreFiles(_ url: URL) {
  for path in storeFilePaths(url) {
    try? FileManager.default.removeItem(atPath: path)
  }
}

func thrownInstantError(_ body: () async throws -> Void) async -> InstantError? {
  do {
    try await body()
    Issue.record("Expected an InstantError, but nothing was thrown.")
    return nil
  } catch let error as InstantError {
    return error
  } catch {
    Issue.record("Expected an InstantError, received \(String(describing: error)).")
    return nil
  }
}

// MARK: - Fake Instant server

/// A user the fake server knows.
struct FakeInstantUser: Hashable, Sendable {
  var id: String
  var email: String?
  var isGuest = false
}

/// One request the fake server's auth endpoints received.
struct FakeAuthRequest: Hashable, Sendable {
  var path: String
  /// Every top-level field name of the JSON body.
  var fieldNames: Set<String>
  /// The top-level string fields of the JSON body.
  var stringFields: [String: String]

  var carriesRefreshToken: Bool {
    fieldNames.contains("refresh-token") || fieldNames.contains("refresh_token")
  }
}

/// How the fake server answers one `transact` frame.
enum FakeTransactAnswer: Sendable {
  case accept
  case refuse(String)
  case hold
}

/// One `transact` frame, with the user whose refresh token opened the socket that sent it.
struct FakeTransactFrame: Hashable, Sendable {
  var userID: String?
  var transactionID: String
  /// Each tx step as compact JSON with sorted keys.
  var steps: [String]
}

/// What the fake server did with the writes it received, in order.
enum FakeServerEvent: Hashable, Sendable {
  case received(transactionID: String, userID: String?)
  case accepted(transactionID: String)
  case refused(transactionID: String)
}

/// One triple the fake server stores.
struct FakeTriple: Hashable, Sendable {
  var entityID: String
  var attributeID: String
  var value: InstantLiveJSONValue
}

/// An Instant server for second sign-in and account-link tests.
///
/// Auth endpoints answer through ``http`` and mint a refresh token for every sign-in they verify. Every websocket
/// from ``transport`` answers `init`, `add-query`, and `transact`, and each frame is recorded with the user whose
/// refresh token opened that socket. Accepted writes change the stored triples, so a later read sees them. A
/// `$users` query by id answers with that user, the account link that lists the user among its `members`, and every
/// member of that link, which is what the server's permission rules let a member read.
actor FakeInstantServer {
  static let manyAttributeIDs: Set<String> = ["accountLinks/members"]

  private var users: [String: FakeInstantUser] = [:]
  private var userIDsByRefreshToken: [String: String] = [:]
  private var guests: [(user: FakeInstantUser, refreshToken: String)] = []
  private var magicCodes: [String: (code: String, userID: String)] = [:]
  private var oauthCodes: [String: String] = [:]
  private var idTokens: [String: String] = [:]
  private var heldPaths: Set<String> = []
  private var heldRequestCount = 0
  private var isReleasingHeldRequests = false
  private var answer: @Sendable (FakeTransactFrame) -> FakeTransactAnswer = { _ in .accept }
  private var heldTransacts: [(frame: FakeTransactFrame, steps: [InstantLiveJSONValue], socket: FakeLiveSocket)] = []
  private var serverTransactionCount = 0

  private(set) var triples: [FakeTriple] = []
  private(set) var authRequests: [FakeAuthRequest] = []
  private(set) var mintedTokens: [String] = []
  private(set) var transacts: [FakeTransactFrame] = []
  private(set) var events: [FakeServerEvent] = []
  private(set) var queryUserIDs: [String?] = []
  private(set) var closedSocketUserIDs: [String?] = []

  var signOutTokens: [String] {
    authRequests.filter { $0.path == "/runtime/signout" }.compactMap { $0.stringFields["refresh_token"] }
  }

  nonisolated var http: InstantAuthHTTPClient {
    InstantAuthHTTPClient { request in try await self.respond(to: request) }
  }

  nonisolated var transport: InstantLiveTransportClient {
    .immediate { _ in FakeLiveSocket(server: self).session }
  }

  // MARK: Seeding

  func addUser(_ user: FakeInstantUser, refreshToken: String) {
    users[user.id] = user
    userIDsByRefreshToken[refreshToken] = user.id
  }

  func addGuest(_ user: FakeInstantUser, refreshToken: String) {
    guests.append((user, refreshToken))
  }

  func expectMagicCode(email: String, code: String, signsIn userID: String) {
    magicCodes[email] = (code, userID)
  }

  func expectOAuthCode(_ code: String, signsIn userID: String) {
    oauthCodes[code] = userID
  }

  func expectIDToken(_ idToken: String, signsIn userID: String) {
    idTokens[idToken] = userID
  }

  func answerTransacts(_ answer: @escaping @Sendable (FakeTransactFrame) -> FakeTransactAnswer) {
    self.answer = answer
  }

  func insert(_ triples: [FakeTriple]) {
    self.triples.append(contentsOf: triples)
  }

  /// Holds every auth request to `path` until ``releaseHeldRequests()``, or until its task is cancelled.
  func holdRequests(to path: String) {
    heldPaths.insert(path)
  }

  func releaseHeldRequests() {
    isReleasingHeldRequests = true
  }

  func waitUntilHeldRequestArrives() async throws {
    try await waitUntil("a held auth request arrives") { self.heldRequestCount > 0 }
  }

  func waitUntilTransactCount(_ count: Int) async throws {
    try await waitUntil("\(count) transact frame(s) arrive") { self.transacts.count >= count }
  }

  /// Answers every held `transact` frame with `answer`.
  func releaseHeldTransacts(_ answer: FakeTransactAnswer) async {
    let held = heldTransacts
    heldTransacts = []
    for (frame, steps, socket) in held {
      if let reply = reply(to: frame, steps: steps, answer: answer) {
        await socket.deliver(reply)
      }
    }
  }

  private func waitUntil(
    _ condition: String,
    _ isSatisfied: () -> Bool
  ) async throws {
    let deadline = ContinuousClock.now + .seconds(5)
    while !isSatisfied() {
      guard ContinuousClock.now < deadline else {
        throw InstantError(
          code: .implementationFailed,
          operation: "wait for the fake Instant server",
          message: "Waited 5 seconds for \(condition).",
          recovery: "Inspect the second sign-in flow under test."
        )
      }
      try await Task.sleep(for: .milliseconds(2))
    }
  }

  // MARK: Auth endpoints

  private func respond(to request: URLRequest) async throws -> InstantAuthHTTPResponse {
    let path = request.url?.path ?? ""
    let body = (request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]
    authRequests.append(
      FakeAuthRequest(
        path: path,
        fieldNames: Set(body.keys),
        stringFields: body.compactMapValues { $0 as? String }
      )
    )
    if heldPaths.contains(path) {
      heldRequestCount += 1
      while !isReleasingHeldRequests {
        try await Task.sleep(for: .milliseconds(2))
      }
    }
    switch path {
    case "/runtime/auth/sign_in_guest":
      guard !guests.isEmpty else { return failure("No guest is expected.") }
      let (guest, refreshToken) = guests.removeFirst()
      addUser(guest, refreshToken: refreshToken)
      return userResponse(guest, refreshToken: refreshToken)

    case "/runtime/auth/send_magic_code":
      return InstantAuthHTTPResponse(statusCode: 200, data: Data(#"{"sent":true}"#.utf8))

    case "/runtime/auth/verify_magic_code":
      guard
        let email = body["email"] as? String,
        let expected = magicCodes[email],
        body["code"] as? String == expected.code
      else { return failure("Invalid code.") }
      return mintedResponse(for: expected.userID)

    case "/runtime/oauth/token":
      guard let code = body["code"] as? String, let userID = oauthCodes[code] else {
        return failure("Invalid authorization code.")
      }
      return mintedResponse(for: userID)

    case "/runtime/oauth/id_token":
      guard let idToken = body["id_token"] as? String, let userID = idTokens[idToken] else {
        return failure("Invalid ID token.")
      }
      return mintedResponse(for: userID)

    case "/runtime/auth/verify_refresh_token":
      guard
        let refreshToken = body["refresh-token"] as? String,
        let userID = userIDsByRefreshToken[refreshToken],
        let user = users[userID]
      else { return failure("Record not found: refresh token.") }
      return userResponse(user, refreshToken: refreshToken)

    case "/runtime/signout":
      return InstantAuthHTTPResponse(statusCode: 200, data: Data("{}".utf8))

    default:
      return InstantAuthHTTPResponse(statusCode: 404, data: Data(#"{"message":"Not found."}"#.utf8))
    }
  }

  private func mintedResponse(for userID: String) -> InstantAuthHTTPResponse {
    guard let user = users[userID] else { return failure("Unknown user \(userID).") }
    let refreshToken = "minted-\(mintedTokens.count + 1)-\(userID)"
    mintedTokens.append(refreshToken)
    userIDsByRefreshToken[refreshToken] = userID
    return userResponse(user, refreshToken: refreshToken)
  }

  private func userResponse(_ user: FakeInstantUser, refreshToken: String) -> InstantAuthHTTPResponse {
    var fields: [String: Any] = [
      "id": user.id,
      "refresh_token": refreshToken,
      "type": user.isGuest ? "guest" : "user",
    ]
    if let email = user.email {
      fields["email"] = email
    }
    let data = try! JSONSerialization.data(withJSONObject: ["user": fields, "created": false])
    return InstantAuthHTTPResponse(statusCode: 200, data: data)
  }

  private func failure(_ message: String) -> InstantAuthHTTPResponse {
    let data = try! JSONSerialization.data(withJSONObject: ["type": "param-malformed", "message": message])
    return InstantAuthHTTPResponse(statusCode: 400, data: data)
  }

  // MARK: Websocket frames

  func userID(forRefreshToken refreshToken: String?) -> String? {
    refreshToken.flatMap { userIDsByRefreshToken[$0] }
  }

  func socketClosed(userID: String?) {
    closedSocketUserIDs.append(userID)
  }

  func handle(
    _ message: InstantLiveMessage,
    userID: String?,
    socket: FakeLiveSocket
  ) -> [InstantLiveMessage] {
    switch message.op {
    case "init":
      return [
        InstantLiveMessage(
          op: "init-ok",
          clientEventID: message.clientEventID,
          fields: [
            "attrs": .array([]),
            "auth": .null,
            "session-id": .string("fake-session-\(UUID().uuidString)"),
          ]
        )
      ]

    case "add-query":
      return [queryAnswer(message, userID: userID)]

    case "transact":
      let steps = message.fields["tx-steps"]?.arrayValue ?? []
      let frame = FakeTransactFrame(
        userID: userID,
        transactionID: message.clientEventID ?? "",
        steps: steps.map(Self.render)
      )
      transacts.append(frame)
      events.append(.received(transactionID: frame.transactionID, userID: userID))
      let decision = answer(frame)
      if case .hold = decision {
        heldTransacts.append((frame, steps, socket))
        return []
      }
      return reply(to: frame, steps: steps, answer: decision).map { [$0] } ?? []

    default:
      return []
    }
  }

  private func reply(
    to frame: FakeTransactFrame,
    steps: [InstantLiveJSONValue],
    answer: FakeTransactAnswer
  ) -> InstantLiveMessage? {
    switch answer {
    case .accept:
      apply(steps)
      events.append(.accepted(transactionID: frame.transactionID))
      serverTransactionCount += 1
      return InstantLiveMessage(
        op: "transact-ok",
        clientEventID: frame.transactionID,
        fields: ["tx-id": .string("server-tx-\(serverTransactionCount)")]
      )

    case .refuse(let reason):
      events.append(.refused(transactionID: frame.transactionID))
      return InstantLiveMessage(
        op: "error",
        clientEventID: frame.transactionID,
        fields: [
          "message": .string(reason),
          "status": .number(400),
          "original-event": .object([
            "client-event-id": .string(frame.transactionID),
            "op": .string("transact"),
          ]),
        ]
      )

    case .hold:
      return nil
    }
  }

  private func queryAnswer(_ message: InstantLiveMessage, userID: String?) -> InstantLiveMessage {
    let query = message.fields["q"] ?? .object([:])
    let usersQuery = query.objectValue?["$users"]?.objectValue
    let requestedID = usersQuery?["$"]?.objectValue?["where"]?.objectValue?["id"]?.stringValue
    queryUserIDs.append(userID)
    guard let requestedID, users[requestedID] != nil else {
      return InstantLiveMessage(
        op: "add-query-ok",
        clientEventID: message.clientEventID,
        fields: ["q": query, "result": .array([])]
      )
    }
    var entityIDs = [requestedID]
    for link in triples where Self.manyAttributeIDs.contains(link.attributeID)
      && link.value == .string(requestedID)
    {
      entityIDs.append(link.entityID)
      entityIDs.append(
        contentsOf: triples.filter {
          $0.entityID == link.entityID && Self.manyAttributeIDs.contains($0.attributeID)
        }
        .compactMap(\.value.stringValue)
      )
    }
    var seen: Set<String> = []
    let rows = entityIDs.filter { seen.insert($0).inserted }.flatMap(rowTriples(for:))
    serverTransactionCount += 1
    return InstantLiveMessage(
      op: "add-query-ok",
      clientEventID: message.clientEventID,
      fields: [
        "q": query,
        "processed-tx-id": .string("server-tx-\(serverTransactionCount)"),
        "result": .array([
          .object([
            "data": .object([
              "datalog-result": .object(["join-rows": .array([.array(rows)])])
            ]),
            "child-nodes": .array([]),
          ])
        ]),
      ]
    )
  }

  private func rowTriples(for entityID: String) -> [InstantLiveJSONValue] {
    var stored = triples.filter { $0.entityID == entityID }
    if let user = users[entityID] {
      stored.append(FakeTriple(entityID: entityID, attributeID: "$users/id", value: .string(entityID)))
      if let email = user.email {
        stored.append(FakeTriple(entityID: entityID, attributeID: "$users/email", value: .string(email)))
      }
      stored.append(
        FakeTriple(
          entityID: entityID,
          attributeID: "$users/type",
          value: .string(user.isGuest ? "guest" : "user")
        )
      )
    }
    return stored.map {
      .array([.string($0.entityID), .string($0.attributeID), $0.value, .number(1_700_000_000_000)])
    }
  }

  private func apply(_ steps: [InstantLiveJSONValue]) {
    for step in steps {
      guard
        let parts = step.arrayValue,
        let op = parts.first?.stringValue,
        parts.count >= 2,
        let entityID = parts[1].stringValue
      else { continue }
      switch op {
      case "add-triple" where parts.count >= 4:
        guard let attributeID = parts[2].stringValue else { continue }
        let value = parts[3]
        if Self.manyAttributeIDs.contains(attributeID) {
          let triple = FakeTriple(entityID: entityID, attributeID: attributeID, value: value)
          if !triples.contains(triple) { triples.append(triple) }
        } else {
          triples.removeAll { $0.entityID == entityID && $0.attributeID == attributeID }
          if value != .null {
            triples.append(FakeTriple(entityID: entityID, attributeID: attributeID, value: value))
          }
        }

      case "deep-merge-triple" where parts.count >= 4:
        guard let attributeID = parts[2].stringValue else { continue }
        let current = triples.first { $0.entityID == entityID && $0.attributeID == attributeID }?.value
        triples.removeAll { $0.entityID == entityID && $0.attributeID == attributeID }
        triples.append(
          FakeTriple(
            entityID: entityID,
            attributeID: attributeID,
            value: Self.deepMerge(current ?? .object([:]), parts[3])
          )
        )

      case "retract-triple" where parts.count >= 4:
        guard let attributeID = parts[2].stringValue else { continue }
        triples.removeAll {
          $0.entityID == entityID && $0.attributeID == attributeID && $0.value == parts[3]
        }

      case "delete-entity":
        triples.removeAll { $0.entityID == entityID }

      default:
        continue
      }
    }
  }

  private static func deepMerge(
    _ current: InstantLiveJSONValue,
    _ update: InstantLiveJSONValue
  ) -> InstantLiveJSONValue {
    guard case .object(var merged) = current, case .object(let fields) = update else { return update }
    for (key, value) in fields {
      if value == .null {
        merged[key] = nil
      } else {
        merged[key] = deepMerge(merged[key] ?? .object([:]), value)
      }
    }
    return .object(merged)
  }

  static func render(_ value: InstantLiveJSONValue) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return String(decoding: (try? encoder.encode(value)) ?? Data(), as: UTF8.self)
  }
}

/// One websocket to the fake server.
actor FakeLiveSocket {
  nonisolated private let abortState = InstantLiveTestWireAbortState()
  private let server: FakeInstantServer
  private var userID: String?
  private var inbox: [InstantLiveMessage] = []
  private var waiter: InstantLiveTestPendingOperation<InstantLiveMessage>?
  private var isClosed = false

  init(server: FakeInstantServer) {
    self.server = server
  }

  nonisolated var session: InstantLiveWebSocketSession {
    InstantLiveWebSocketSession(
      send: { message in try await self.send(message) },
      receive: {
        try self.abortState.check()
        return try await self.receive()
      },
      close: { await self.close() },
      abort: { self.abortState.abort() }
    )
  }

  func deliver(_ message: InstantLiveMessage) {
    guard !abortState.isAborted, !isClosed else { return }
    if let waiter {
      self.waiter = nil
      abortState.unregister(waiter.abortToken)
      waiter.continuation.resume(returning: message)
    } else {
      inbox.append(message)
    }
  }

  private func send(_ message: InstantLiveMessage) async throws {
    try abortState.check()
    if message.op == "init" {
      userID = await server.userID(forRefreshToken: message.fields["refresh-token"]?.stringValue)
    }
    let replies = await server.handle(message, userID: userID, socket: self)
    for reply in replies {
      deliver(reply)
    }
  }

  private func receive() async throws -> InstantLiveMessage {
    try abortState.check()
    if !inbox.isEmpty {
      return inbox.removeFirst()
    }
    if isClosed {
      throw CancellationError()
    }
    let id = UUID()
    defer { clearWaiter(id: id) }
    return try await withCheckedThrowingContinuation { continuation in
      let continuation = InstantLiveTestThrowingContinuationBox(continuation)
      guard
        let abortToken = abortState.register({
          continuation.resume(throwing: CancellationError())
        })
      else {
        continuation.resume(throwing: CancellationError())
        return
      }
      waiter = InstantLiveTestPendingOperation(
        id: id,
        abortToken: abortToken,
        continuation: continuation
      )
    }
  }

  private func close() async {
    guard !isClosed else { return }
    isClosed = true
    abortState.abort()
    waiter = nil
    await server.socketClosed(userID: userID)
  }

  private func clearWaiter(id: UUID) {
    guard let waiter, waiter.id == id else { return }
    abortState.unregister(waiter.abortToken)
    self.waiter = nil
  }
}
