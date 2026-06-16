import Foundation

public struct CloudKitDemoValidationDetails: Codable, Equatable, Sendable {
  public var cachePath: String
  public var authUserID: String?
  public var counterIDs: [String]
  public var counterCounts: [Int]
  public var sharedCounterIDs: [String]
  public var shareIDs: [String]
  public var shareRoles: [InstantShareRole]
  public var shareMemberCounts: [Int]
  public var shareMemberUserIDs: [String]
  public var rejectedOperations: [String]
  public var pendingMutationIDs: [String]
  public var pendingMutationCount: Int
  public var storeRevision: Int64
  public var outboxRevision: Int64

  public init(
    cachePath: String,
    authUserID: String?,
    counterIDs: [String],
    counterCounts: [Int],
    sharedCounterIDs: [String],
    shareIDs: [String],
    shareRoles: [InstantShareRole],
    shareMemberCounts: [Int],
    shareMemberUserIDs: [String],
    rejectedOperations: [String] = [],
    pendingMutationIDs: [String],
    pendingMutationCount: Int,
    storeRevision: Int64,
    outboxRevision: Int64
  ) {
    self.cachePath = cachePath
    self.authUserID = authUserID
    self.counterIDs = counterIDs
    self.counterCounts = counterCounts
    self.sharedCounterIDs = sharedCounterIDs
    self.shareIDs = shareIDs
    self.shareRoles = shareRoles
    self.shareMemberCounts = shareMemberCounts
    self.shareMemberUserIDs = shareMemberUserIDs
    self.rejectedOperations = rejectedOperations
    self.pendingMutationIDs = pendingMutationIDs
    self.pendingMutationCount = pendingMutationCount
    self.storeRevision = storeRevision
    self.outboxRevision = outboxRevision
  }
}

public struct CloudKitDemoValidationResult: Sendable {
  public var appID: String
  public var cacheURL: URL
  public var counterID: String
  public var shareID: String
  public var evidence: [ValidationEvidenceRow<CloudKitDemoValidationDetails>]

  public init(
    appID: String,
    cacheURL: URL,
    counterID: String,
    shareID: String,
    evidence: [ValidationEvidenceRow<CloudKitDemoValidationDetails>]
  ) {
    self.appID = appID
    self.cacheURL = cacheURL
    self.counterID = counterID
    self.shareID = shareID
    self.evidence = evidence
  }
}

public enum InstantSwiftDataCloudKitDemoValidation {
  private static let caseID = "validation.cloudkit.demo"

  public static func run(
    appID: String = "cloudkit-demo-validation",
    cacheURL: URL? = nil,
    timestamp: @escaping @Sendable () -> InstantTimestamp = {
      InstantTimestamp(milliseconds: Int64((Date().timeIntervalSince1970 * 1000).rounded()))
    },
    makeID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() }
  ) async throws -> CloudKitDemoValidationResult {
    let cacheURL =
      cacheURL
      ?? FileManager.default.temporaryDirectory
        .appendingPathComponent("InstantSwiftDataCloudKitDemoValidation-\(makeID())", isDirectory: true)
        .appendingPathComponent("state.sqlite")
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: appID,
        persistenceURL: cacheURL,
        initialAttributes: CounterExample.attributes,
        now: timestamp,
        makeID: makeID
      )
    )
    var evidence: [ValidationEvidenceRow<CloudKitDemoValidationDetails>] = []

    _ = try await runtime.signInWithRefreshToken("owner-refresh", userID: "user-1")
    let counterID = "validation-cloudkit-demo-counter"
    let createTransactionID = "validation.cloudkit.demo.create"
    let createdAt = timestamp()
    try await runtime.transact(
      InstantStoreTransaction(
        id: createTransactionID,
        operations: CounterExample.createOperations(
          id: counterID,
          count: 2,
          createdAt: createdAt,
          transactionID: createTransactionID
        )
      ),
      createdAt: createdAt,
      source: "validation.cloudkit.demo.owner-create"
    )
    evidence.append(
      try await evidenceRow(
        event: "owner-create",
        runtime: runtime,
        cacheURL: cacheURL,
        timestamp: timestamp,
        entityID: counterID
      )
    )

    let createdShare = try await runtime.createShare(
      rootNamespace: CounterExample.namespace,
      rootID: counterID
    )
    guard createdShare.share.rootNamespace == CounterExample.namespace,
      createdShare.share.rootID == counterID,
      createdShare.memberships.map(\.role) == [.owner]
    else {
      throw validationError(
        operation: "validate CloudKitDemo share create",
        message: "Expected owner share metadata for the created counter."
      )
    }
    evidence.append(
      try await evidenceRow(
        event: "share-create",
        runtime: runtime,
        cacheURL: cacheURL,
        timestamp: timestamp,
        entityID: counterID
      )
    )

    _ = try await runtime.signInWithRefreshToken("invitee-refresh", userID: "user-2")
    let acceptedShare = try await runtime.acceptShare(token: createdShare.share.token)
    guard acceptedShare.memberships.map(\.role) == [.owner, .reader] else {
      throw validationError(
        operation: "validate CloudKitDemo share accept",
        message: "Expected accepted share to add the invitee as a reader."
      )
    }
    evidence.append(
      try await evidenceRow(
        event: "reader-accept",
        runtime: runtime,
        cacheURL: cacheURL,
        timestamp: timestamp,
        entityID: counterID
      )
    )

    let pendingBeforeReaderReject = await runtime.pendingMutations()
    let readerTransactionID = "validation.cloudkit.demo.reader.increment"
    do {
      let now = timestamp()
      try await runtime.transact(
        InstantStoreTransaction(
          id: readerTransactionID,
          operations: CounterExample.updateCountOperations(
            id: counterID,
            count: 3,
            updatedAt: now,
            transactionID: readerTransactionID
          )
        ),
        createdAt: now,
        source: "validation.cloudkit.demo.reader-increment"
      )
      throw validationError(
        operation: "validate CloudKitDemo reader rejection",
        message: "Expected a reader write to the shared counter to be rejected."
      )
    } catch let error as InstantError {
      guard error.operation == "write shared root", error.message.contains("reader access") else {
        throw error
      }
    }
    let rowsAfterReaderReject = try await sharedCounters(runtime: runtime)
    guard rowsAfterReaderReject.map(\.counter.count) == [2],
      await runtime.pendingMutations().map(\.id) == pendingBeforeReaderReject.map(\.id)
    else {
      throw validationError(
        operation: "validate CloudKitDemo reader rejection",
        message: "Expected reader rejection to leave the counter and outbox unchanged."
      )
    }
    evidence.append(
      try await evidenceRow(
        event: "reader-reject",
        runtime: runtime,
        cacheURL: cacheURL,
        timestamp: timestamp,
        entityID: counterID,
        rejectedOperations: ["reader-increment"]
      )
    )

    _ = try await runtime.signInWithRefreshToken("owner-refresh", userID: "user-1")
    let promotedShare = try await runtime.updateShareMembershipRole(
      shareID: createdShare.share.id,
      userID: "user-2",
      role: .writer
    )
    guard promotedShare.memberships.map(\.role) == [.owner, .writer] else {
      throw validationError(
        operation: "validate CloudKitDemo writer promotion",
        message: "Expected owner role update to promote the invitee to writer."
      )
    }
    evidence.append(
      try await evidenceRow(
        event: "writer-promote",
        runtime: runtime,
        cacheURL: cacheURL,
        timestamp: timestamp,
        entityID: counterID
      )
    )

    _ = try await runtime.signInWithRefreshToken("invitee-refresh", userID: "user-2")
    let writerTransactionID = "validation.cloudkit.demo.writer.increment"
    let writerUpdatedAt = timestamp()
    try await runtime.transact(
      InstantStoreTransaction(
        id: writerTransactionID,
        operations: CounterExample.updateCountOperations(
          id: counterID,
          count: 3,
          updatedAt: writerUpdatedAt,
          transactionID: writerTransactionID
        )
      ),
      createdAt: writerUpdatedAt,
      source: "validation.cloudkit.demo.writer-increment"
    )
    let writerRows = try await sharedCounters(runtime: runtime)
    guard writerRows.map(\.counter.count) == [3],
      writerRows.map(\.shareRole) == [.writer]
    else {
      throw validationError(
        operation: "validate CloudKitDemo writer update",
        message: "Expected a promoted writer to update and see the shared counter."
      )
    }
    evidence.append(
      try await evidenceRow(
        event: "writer-update",
        runtime: runtime,
        cacheURL: cacheURL,
        timestamp: timestamp,
        entityID: counterID
      )
    )

    let relaunchedRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: appID,
        persistenceURL: cacheURL,
        initialAttributes: CounterExample.attributes,
        now: timestamp,
        makeID: makeID
      )
    )
    guard try await relaunchedRuntime.authSession()?.userID == "user-2" else {
      throw validationError(
        operation: "validate CloudKitDemo relaunch",
        message: "Expected the invitee auth session to persist across relaunch."
      )
    }
    let relaunchedRows = try await sharedCounters(runtime: relaunchedRuntime)
    guard relaunchedRows.map(\.counter.count) == [3],
      relaunchedRows.map(\.shareRole) == [.writer],
      relaunchedRows.map(\.shareMemberCount) == [2]
    else {
      throw validationError(
        operation: "validate CloudKitDemo relaunch",
        message: "Expected relaunched invitee state to preserve the shared counter and writer role."
      )
    }
    evidence.append(
      try await evidenceRow(
        event: "relaunch",
        runtime: relaunchedRuntime,
        cacheURL: cacheURL,
        timestamp: timestamp,
        entityID: counterID
      )
    )

    return CloudKitDemoValidationResult(
      appID: appID,
      cacheURL: cacheURL,
      counterID: counterID,
      shareID: createdShare.share.id,
      evidence: evidence
    )
  }

  private static func evidenceRow(
    event: String,
    runtime: InstantRuntime,
    cacheURL: URL,
    timestamp: @escaping @Sendable () -> InstantTimestamp,
    entityID: String,
    rejectedOperations: [String] = []
  ) async throws -> ValidationEvidenceRow<CloudKitDemoValidationDetails> {
    let session = try await runtime.authSession()
    let rows = try await sharedCounters(runtime: runtime)
    let shares = try await runtime.shares()
    let pending = await runtime.pendingMutations()
    let state = try await runtime.persistence.loadState()

    return ValidationEvidenceRow(
      caseID: caseID,
      side: "swift",
      event: event,
      appID: runtime.configuration.appID,
      entityID: entityID,
      timestampMs: timestamp().milliseconds,
      ok: true,
      details: CloudKitDemoValidationDetails(
        cachePath: cacheURL.path,
        authUserID: session?.userID,
        counterIDs: rows.map(\.counter.id),
        counterCounts: rows.map(\.counter.count),
        sharedCounterIDs: rows.filter(\.isShared).map(\.counter.id),
        shareIDs: rows.compactMap(\.shareID),
        shareRoles: rows.compactMap(\.shareRole),
        shareMemberCounts: rows.map(\.shareMemberCount),
        shareMemberUserIDs: Array(Set(shares.flatMap(\.memberships).map(\.userID))).sorted(),
        rejectedOperations: rejectedOperations,
        pendingMutationIDs: pending.map(\.id),
        pendingMutationCount: pending.count,
        storeRevision: state.storeRevision,
        outboxRevision: state.outboxRevision
      )
    )
  }

  private static func sharedCounters(runtime: InstantRuntime) async throws -> [SharedCounterRecord] {
    let session = try await runtime.authSession()
    let counters = try await CounterExample.decode(runtime.query(CounterExample.query))
    let shares = try await runtime.shares()
    return CounterExample.sharedRows(
      counters: counters,
      shares: shares,
      userID: session?.userID
    )
  }

  private static func validationError(operation: String, message: String) -> InstantError {
    InstantError(
      code: .validationFailed,
      operation: operation,
      message: message,
      recovery: "Inspect the CloudKitDemo validation evidence stream."
    )
  }
}
