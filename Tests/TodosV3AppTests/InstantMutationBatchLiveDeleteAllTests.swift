import CustomDump
import Dependencies
import Foundation
import InstantSwiftData
import Testing
@testable import TodosV3App

/// Live multi-device contract: batch delete-all must reach Instant (not local-only).
@Suite(.serialized)
struct InstantMutationBatchLiveDeleteAllTests {
  @Test
  func batchDeleteAllIsServerAcceptedAndAdminVisible() async throws {
    guard Self.liveEnabled else { return }

    let appID = ProcessInfo.processInfo.environment["INSTANT_APP_ID"]!
    let (home, dbURL) = try Self.tempDB(appID: appID, label: "batch-delete-live")
    defer { try? FileManager.default.removeItem(at: home) }

    try await withDependencies {
      try await Self.bootstrapLive(&$0, appID: appID, dbURL: dbURL)
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var db
      try await db.connect()
      _ = try await db.signInAsGuest()

      var ids: [InstantID<Todo>] = []
      for i in 0..<3 {
        let id = InstantID<Todo>(rawValue: UUID().uuidString.lowercased())
        ids.append(id)
        _ = try await db.sendAwaitingServerAcceptance(
          CreateTodo(
            id: id,
            text: "batch-delete-live-\(i)-\(UUID().uuidString.prefix(8))",
            createdAt: Date()
          ),
          timeout: .seconds(5)
        )
      }

      let afterCreate = try await db.query(Todo.query)
      #expect(afterCreate.map(\.id).filter(ids.contains).count == 3)

      let outcome = DeleteAllOutcome()
      let task = db.send(
        mutations: Todo.delete(ids: ids),
        onOptimisticCommit: { change in
          outcome.optimisticCount = change.mutationCount
        },
        onServerAccepted: { change in
          outcome.acceptedCount = change.mutationCount
        },
        onFailure: { error in
          outcome.failure = error.message
        }
      )

      try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask { await task.value }
        group.addTask { try await Task.sleep(for: .seconds(5)) }
        _ = try await group.next()
        group.cancelAll()
      }

      expectNoDifference(outcome.optimisticCount, 3)
      #expect(outcome.failure == nil, "batch delete-all failed: \(outcome.failure ?? "")")
      #expect(
        outcome.acceptedCount == 3,
        "batch delete-all never server-accepted (accepted=\(String(describing: outcome.acceptedCount)) failure=\(outcome.failure ?? "nil"))"
      )

      let remaining = try await db.query(Todo.query)
      #expect(remaining.map(\.id).filter(ids.contains).isEmpty)

      let pending = await db.pendingMutations()
      #expect(pending.filter { $0.status == .pending }.isEmpty)
    }
  }

  /// Two independent clients share one Instant app: delete-all on A must clear B.
  @Test
  func batchDeleteAllPropagatesToSecondClient() async throws {
    guard Self.liveEnabled else { return }

    let appID = ProcessInfo.processInfo.environment["INSTANT_APP_ID"]!
    let (homeA, dbA) = try Self.tempDB(appID: appID, label: "peer-a")
    let (homeB, dbB) = try Self.tempDB(appID: appID, label: "peer-b")
    defer {
      try? FileManager.default.removeItem(at: homeA)
      try? FileManager.default.removeItem(at: homeB)
    }

    var createdIDs: [InstantID<Todo>] = []

    // Client A creates three todos and waits for server acceptance.
    try await withDependencies {
      try await Self.bootstrapLive(&$0, appID: appID, dbURL: dbA)
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var db
      try await db.connect()
      _ = try await db.signInAsGuest()
      for i in 0..<3 {
        let id = InstantID<Todo>(rawValue: UUID().uuidString.lowercased())
        createdIDs.append(id)
        _ = try await db.sendAwaitingServerAcceptance(
          CreateTodo(
            id: id,
            text: "peer-delete-\(i)-\(UUID().uuidString.prefix(8))",
            createdAt: Date()
          ),
          timeout: .seconds(5)
        )
      }
    }

    // Client B must observe those todos (server truth).
    try await withDependencies {
      try await Self.bootstrapLive(&$0, appID: appID, dbURL: dbB)
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var db
      try await db.connect()
      _ = try await db.signInAsGuest()
      // Force a remote query refresh path by querying until ids appear (5s budget).
      let deadline = ContinuousClock.now + .seconds(5)
      var seen = 0
      while ContinuousClock.now < deadline {
        let rows = try await db.query(Todo.query)
        seen = rows.map(\.id).filter(createdIDs.contains).count
        if seen == 3 { break }
        try await Task.sleep(for: .milliseconds(200))
      }
      #expect(seen == 3, "peer B never saw the three created todos (seen=\(seen))")
    }

    // Client A deletes all created ids in one batch and waits for acceptance.
    try await withDependencies {
      try await Self.bootstrapLive(&$0, appID: appID, dbURL: dbA)
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var db
      try await db.connect()
      // session should restore guest refresh token from the same sqlite
      _ = try await db.sendAwaitingServerAcceptance(
        InstantMutationBatch(Todo.delete(ids: createdIDs)),
        timeout: .seconds(5)
      )
      let remaining = try await db.query(Todo.query)
      #expect(remaining.map(\.id).filter(createdIDs.contains).isEmpty)
    }

    // Client B must converge to empty for those ids.
    try await withDependencies {
      try await Self.bootstrapLive(&$0, appID: appID, dbURL: dbB)
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var db
      try await db.connect()
      let deadline = ContinuousClock.now + .seconds(5)
      var remaining = 3
      while ContinuousClock.now < deadline {
        let rows = try await db.query(Todo.query)
        remaining = rows.map(\.id).filter(createdIDs.contains).count
        if remaining == 0 { break }
        try await Task.sleep(for: .milliseconds(200))
      }
      #expect(
        remaining == 0,
        "peer B still has \(remaining) todos after peer A batch delete-all — multi-device sync failed"
      )
    }
  }

  private static var liveEnabled: Bool {
    guard let appID = ProcessInfo.processInfo.environment["INSTANT_APP_ID"],
      !appID.isEmpty,
      ProcessInfo.processInfo.environment["INSTANT_SWIFT_DATA_TRANSPORT"] == "live"
    else { return false }
    return true
  }

  private static func tempDB(appID: String, label: String) throws -> (URL, URL) {
    let home = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "instant-\(label)-\(UUID().uuidString)",
        isDirectory: true
      )
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    return (home, home.appendingPathComponent("\(appID).sqlite"))
  }

  private static func bootstrapLive(
    _ dependencies: inout DependencyValues,
    appID: String,
    dbURL: URL
  ) async throws {
    dependencies.instantLiveTransport = .live
    dependencies.instantGuestAuthenticator = .live
    dependencies.instantRefreshTokenVerifier = .live
    dependencies.instantAuthTokenInvalidator = .live
    try await dependencies.bootstrapInstantSwiftData(
      appID: appID,
      persistenceURL: dbURL,
      context: .live,
      initialAttributes: Todo.instantAttributes
    )
  }
}

private final class DeleteAllOutcome: @unchecked Sendable {
  var optimisticCount: Int?
  var acceptedCount: Int?
  var failure: String?
}
