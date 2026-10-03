import CustomDump
import Foundation
@testable import InstantSwiftDataCore
import Testing

/// A clock a test sets, for the runtime's `now`.
// SAFETY: `lock` guards `milliseconds` for every read and write.
private final class WriteFailureTestClock: @unchecked Sendable {
  private let lock = NSLock()
  private var milliseconds: Int64

  init(_ milliseconds: Int64) {
    self.milliseconds = milliseconds
  }

  var now: InstantTimestamp {
    lock.withLock { InstantTimestamp(milliseconds: milliseconds) }
  }

  func set(_ value: Int64) {
    lock.withLock { milliseconds = value }
  }
}

/// #482 part C: Scribe's save lane retries the write at its head until it succeeds, and could not tell "this will never
/// succeed" from "try again later". Every failure a write throws, and every failed mutation, now says which it is; and a
/// cheap read says whether the connection is healthy, without the operation gate or SQLite.
@Suite(.serialized)
struct InstantWriteFailureKindTests {
  static func kind(of operation: () async throws -> Void) async -> InstantWriteFailureKind? {
    do {
      try await operation()
      return nil
    } catch {
      return InstantWriteFailureKind(classifying: error)
    }
  }

  static func insert(_ entityID: String, _ attributeID: String, _ value: InstantValue, tx: String)
    -> InstantTripleOperation
  {
    .insert(
      InstantTriple(
        entityID: entityID,
        attributeID: attributeID,
        value: value,
        txID: tx,
        txTime: InstantTimestamp(milliseconds: 1_700_000_000_000)
      )
    )
  }

  @Test
  func aWriteToANamespaceTheSchemaDoesNotDeclareIsRejectedAsAnUnknownAttribute() async throws {
    let runtime = try await InstantOfflineRuntimeFixture.offlineRuntime("kind-unknown-namespace")
    let kind = await Self.kind {
      _ = try await runtime.transact(
        InstantStoreTransaction(id: "tx-nope", operations: [Self.insert("x", "nope/text", .string("a"), tx: "tx-nope")])
      )
    }
    expectNoDifference(kind, .rejected(.unknownAttribute))
  }

  @Test
  func aValueOfTheWrongTypeIsRejectedAsAnInvalidValue() async throws {
    let runtime = try await InstantOfflineRuntimeFixture.offlineRuntime("kind-wrong-type")
    let kind = await Self.kind {
      _ = try await runtime.transact(
        InstantStoreTransaction(
          id: "tx-wrong-type",
          operations: [Self.insert("todo-x", "todos/isCompleted", .string("yes"), tx: "tx-wrong-type")]
        )
      )
    }
    expectNoDifference(kind, .rejected(.invalidValue))
  }

  @Test
  func creatingAnEntityThatExistsIsRejectedAsAnInvalidWrite() async throws {
    let runtime = try await InstantOfflineRuntimeFixture.offlineRuntime("kind-strict-create")
    try await InstantOfflineRuntimeFixture.createTodo("twice", in: runtime)
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_000_001)
    let kind = await Self.kind {
      _ = try await runtime.transact(
        InstantStoreTransaction(
          id: "tx-twice-again",
          operations: TodoExample.createOperations(
            id: "todo-twice",
            text: "again",
            createdAt: createdAt,
            transactionID: "tx-twice-again"
          )
        ),
        createdAt: createdAt
      )
    }
    expectNoDifference(kind, .rejected(.invalidWrite))
  }

  /// The entity may still arrive by sync from another device, so updating it before it does is not permanent.
  @Test
  func updatingAnEntityThatIsNotHereYetIsUnknown() async throws {
    let runtime = try await InstantOfflineRuntimeFixture.offlineRuntime("kind-strict-update")
    let kind = await Self.kind {
      _ = try await runtime.transact(
        InstantStoreTransaction(
          id: "tx-update-missing",
          operations: [
            .requireEntityExists(entityID: "todo-elsewhere", namespace: TodoExample.namespace),
            Self.insert("todo-elsewhere", "todos/text", .string("edited"), tx: "tx-update-missing"),
          ]
        )
      )
    }
    expectNoDifference(kind, .unknown)
  }

  @Test
  func reusingAPendingTransactionIDForOtherOperationsIsRejectedAsAnInvalidWrite() async throws {
    let runtime = try await InstantOfflineRuntimeFixture.offlineRuntime("kind-reused-id")
    try await InstantOfflineRuntimeFixture.createTodo("reused", in: runtime)
    let kind = await Self.kind {
      _ = try await runtime.transact(
        InstantStoreTransaction(
          id: "tx-reused",
          operations: [Self.insert("todo-reused", "todos/text", .string("other"), tx: "tx-reused")]
        )
      )
    }
    expectNoDifference(kind, .rejected(.invalidWrite))
  }

  /// A write cancelled while it waits for the operation gate never ran; trying it again can succeed.
  @Test
  func aWriteCancelledWhileItWaitsIsTransient() async throws {
    let releaseFirst = AsyncStream<Void>.makeStream()
    let firstPaused = AsyncStream<Void>.makeStream()
    let runtime = try await InstantOfflineRuntimeFixture.offlineRuntime("kind-cancelled") { configuration in
      configuration.onLocalMutationPersistedBeforeStorePublicationForTesting = { transactionID in
        guard transactionID == "tx-held" else { return }
        firstPaused.continuation.yield()
        var iterator = releaseFirst.stream.makeAsyncIterator()
        _ = await iterator.next()
      }
    }
    let held = Task { try await InstantOfflineRuntimeFixture.createTodo("held", in: runtime) }
    var paused = firstPaused.stream.makeAsyncIterator()
    _ = await paused.next()
    let waiting = Task {
      await Self.kind { try await InstantOfflineRuntimeFixture.createTodo("cancelled", in: runtime) }
    }
    try await Task.sleep(for: .milliseconds(200))
    waiting.cancel()
    let kind = await waiting.value
    releaseFirst.continuation.yield()
    try await held.value
    expectNoDifference(kind, .transient)
  }

  /// Errors the runtime builds elsewhere, and errors that are not the library's, by their code, operation and message.
  @Test
  func everyFailureHasTheKindItsCauseImplies() {
    func error(
      _ code: InstantError.Code,
      operation: String = "transact",
      message: String,
      serverStatus: Int? = nil,
      serverType: String? = nil
    ) -> InstantError {
      InstantError(
        code: code,
        operation: operation,
        serverStatus: serverStatus,
        serverType: serverType,
        message: message,
        recovery: "None."
      )
    }
    let cases: [(String, any Error, InstantWriteFailureKind)] = [
      ("offline", error(.networkFailed, message: "The Instant live session is not open."), .transient),
      ("a local permission rule", error(.permissionRejected, message: "Not allowed."), .rejected(.permissionDenied)),
      ("SQLite busy", error(.persistenceFailed, message: "database is locked"), .transient),
      ("SQLite locked table", error(.persistenceFailed, message: "database table is locked"), .transient),
      ("SQLite I/O", error(.persistenceFailed, message: "disk I/O error"), .transient),
      ("SQLite full", error(.persistenceFailed, message: "database or disk is full"), .transient),
      ("SQLite memory", error(.persistenceFailed, message: "out of memory"), .transient),
      (
        "the store changed under the write",
        error(
          .persistenceFailed,
          operation: "persist transaction",
          message: "The local store changed repeatedly while persisting transaction 'tx'."
        ),
        .transient
      ),
      ("a corrupt store", error(.persistenceFailed, message: "database disk image is malformed"), .unknown),
      ("auth", error(.authFailed, message: "No session."), .unknown),
      ("decode", error(.decodeFailed, message: "Bad row."), .unknown),
      ("implementation", error(.implementationFailed, message: "Bug."), .unknown),
      (
        "a lookup that matched two entities",
        error(.validationFailed, operation: "lookup entity", message: "Lookup ref 'x' matched more than one local entity."),
        .unknown
      ),
      (
        "a required fact that is not here",
        error(.validationFailed, operation: "require triple", message: "No existing triple was found."),
        .unknown
      ),
      (
        "a server refusal",
        error(.validationFailed, message: "Record not unique.", serverStatus: 400, serverType: "record-not-unique"),
        .rejected(.refusedByServer)
      ),
      (
        "a server timeout",
        error(.validationFailed, message: "Operation timed out.", serverStatus: 500, serverType: "timeout"),
        .transient
      ),
      ("a rate limit", error(.validationFailed, message: "Slow down.", serverStatus: 429), .transient),
      ("a merge on a link", error(.validationFailed, message: "Merge is not supported for ref attributes."), .rejected(.invalidWrite)),
      (
        "a required attribute set to null",
        error(.validationFailed, message: "Required attribute 'todos/text' cannot be set to null."),
        .rejected(.invalidValue)
      ),
      ("an undeclared link", error(.validationFailed, message: "No ref attribute named 'todos/owner' is declared."), .rejected(.unknownAttribute)),
      ("a cancelled call", CancellationError(), .transient),
      (
        "a value that cannot be encoded",
        EncodingError.invalidValue(Double.nan, .init(codingPath: [], debugDescription: "NaN")),
        .rejected(.invalidValue)
      ),
      ("no network", URLError(.notConnectedToInternet), .transient),
      ("a bad URL", URLError(.badURL), .unknown),
      ("another error", NSError(domain: "Other", code: 1), .unknown),
    ]
    for (label, failure, expected) in cases {
      expectNoDifference(InstantWriteFailureKind(classifying: failure), expected, "\(label)")
    }
  }

  @Test
  func everyFailedMutationSaysWhetherTryingAgainCanHelp() {
    func failed(_ failure: InstantMutationFailure?, message: String? = nil) -> PendingMutation {
      var mutation = PendingMutation(
        id: "tx",
        createdAt: InstantTimestamp(milliseconds: 1),
        transaction: InstantStoreTransaction(id: "tx", operations: []),
        status: .failed,
        failureMessage: failure?.message ?? message
      )
      mutation.failure = failure
      return mutation
    }
    let cases: [(String, PendingMutation, InstantWriteFailureKind?)] = [
      (
        "a permission refusal",
        failed(InstantMutationFailure(code: .permissionRejected, message: "Permission denied", status: 400, type: "permission-denied")),
        .rejected(.permissionDenied)
      ),
      (
        "a server validation refusal",
        failed(InstantMutationFailure(code: .validationFailed, message: "Invalid value", status: 400, type: "validation-failed")),
        .rejected(.refusedByServer)
      ),
      (
        "a server timeout the library retries",
        failed(InstantMutationFailure(code: .validationFailed, message: "Operation timed out", status: 500)),
        .transient
      ),
      (
        "an attribute the library could not resolve yet",
        failed(InstantMutationFailure(code: .validationFailed, message: "Could not resolve 'todos/text' from the attrs.")),
        .transient
      ),
      (
        "the library's own size quarantine",
        failed(
          InstantMutationFailure(
            code: .validationFailed,
            message: "Instant quarantined durable mutation 'tx' because its 9-byte body exceeds the 8-byte automatic-delivery limit."
          )
        ),
        .rejected(.invalidWrite)
      ),
      ("an older row with only a permission message", failed(nil, message: "Permission denied: not perms-pass?"), .rejected(.permissionDenied)),
      ("an older row with another message", failed(nil, message: "Something went wrong."), .unknown),
    ]
    for (label, mutation, expected) in cases {
      expectNoDifference(mutation.failureKind, expected, "\(label)")
    }
    var pending = failed(nil, message: "Permission denied")
    pending.status = .pending
    expectNoDifference(pending.failureKind, nil, "only a failed mutation has a failure kind")
  }

  /// The server refuses a write of this device: the failed mutation the Sync view lists says no retry can help.
  @Test
  func aWriteTheServerRefusesForPermissionFailsAsRejected() async throws {
    let fixture = try await InstantRefusalHeldByServerTests.Fixture.make("kind-refused") {
      $0.refusedReSendServerResultWaitMilliseconds = 0
    }
    await fixture.first.enqueue(fixture.addQueryOK(text: "created", processedTransactionID: 2))
    try await fixture.transact("tx-refused", at: 1, text: "refused", isCompleted: false)
    _ = try await InstantSupersededReplayTests.waitForTransacts(2, on: fixture.first)
    await fixture.first.enqueue(InstantSupersededReplayTests.refused("tx-refused"))
    try await InstantSupersededReplayTests.waitUntil("the refusal is recorded") {
      await InstantSupersededReplayTests.mutation("tx-refused", in: fixture.runtime)?.status == .failed
    }
    let failed = await fixture.runtime.failedMutations(limit: 10)
    expectNoDifference(failed.map(\.id), ["tx-refused"])
    expectNoDifference(failed.first?.failureKind, .rejected(.permissionDenied))
    _ = try await fixture.runtime.closeConnection()
  }
}

/// #482 part C: `connectionHealth()` follows the socket, local commits, the server's acknowledgements and results, and
/// the pending count, from counters in memory.
@Suite(.serialized)
struct InstantConnectionHealthTests {
  static func date(_ milliseconds: Int64) -> Date {
    Date(timeIntervalSince1970: Double(milliseconds) / 1_000)
  }

  @Test
  func anOfflineRuntimeIsNotOpenAndCountsItsLocalCommits() async throws {
    let clock = WriteFailureTestClock(1_800_000_000_000)
    let runtime = try await InstantOfflineRuntimeFixture.offlineRuntime("health-offline") { configuration in
      configuration.now = { clock.now }
    }
    expectNoDifference(runtime.connectionHealth(), InstantConnectionHealth(isOpen: false))

    clock.set(1_800_000_000_500)
    try await InstantOfflineRuntimeFixture.createTodo("offline", in: runtime)
    expectNoDifference(
      runtime.connectionHealth(),
      InstantConnectionHealth(
        isOpen: false,
        lastLocalCommitAt: Self.date(1_800_000_000_500),
        pendingCount: 1
      )
    )
  }

  @Test
  func healthFollowsTheSocketTheServersAnswersAndThePendingCount() async throws {
    let clock = WriteFailureTestClock(1_800_000_000_000)
    let fixture = try await InstantRefusalHeldByServerTests.Fixture.make("health-live") { configuration in
      configuration.now = { clock.now }
    }
    let runtime = fixture.runtime
    // The fixture connected, created the todo and had the server accept it, all at the clock's first reading.
    expectNoDifference(
      runtime.connectionHealth(),
      InstantConnectionHealth(
        isOpen: true,
        lastLocalCommitAt: Self.date(1_800_000_000_000),
        lastServerAcknowledgementAt: Self.date(1_800_000_000_000),
        lastServerResultAt: nil,
        pendingCount: 0
      )
    )

    clock.set(1_800_000_001_000)
    try await fixture.transact("tx-second", at: 2, text: "second", isCompleted: false)
    let afterCommit = runtime.connectionHealth()
    expectNoDifference(afterCommit.lastLocalCommitAt, Self.date(1_800_000_001_000))
    expectNoDifference(afterCommit.pendingCount, 1)

    clock.set(1_800_000_002_000)
    await fixture.first.enqueue(fixture.addQueryOK(text: "second", processedTransactionID: 3))
    try await InstantSupersededReplayTests.waitUntil("the query's answer is counted") {
      runtime.connectionHealth().lastServerResultAt == Self.date(1_800_000_002_000)
    }

    _ = try await InstantSupersededReplayTests.waitForTransacts(2, on: fixture.first)
    clock.set(1_800_000_003_000)
    await fixture.first.enqueue(InstantSupersededReplayTests.accepted("tx-second", transactionID: 4))
    try await InstantSupersededReplayTests.waitUntil("the acknowledgement is counted") {
      runtime.connectionHealth().pendingCount == 0
    }
    let afterAcknowledgement = runtime.connectionHealth()
    expectNoDifference(afterAcknowledgement.lastServerAcknowledgementAt, Self.date(1_800_000_003_000))
    #expect(afterAcknowledgement.isOpen)

    _ = try await runtime.closeConnection()
    #expect(!runtime.connectionHealth().isOpen, "a closed connection is not open")
  }
}
