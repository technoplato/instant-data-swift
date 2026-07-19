import CloudKitDemoV3App
import Dependencies
import Foundation
import InstantSwiftData

public struct InstantCloudKitDemoV3LiveValidationDetails: Codable, Equatable, Sendable {
  public var counterID: String
  public var shareID: String
  public var ownerUserID: String
  public var readerUserID: String
  public var writerUserID: String
  public var ownerObservedValues: [Int]
  public var readerObservedValues: [Int]
  public var firstReaderFailure: String
  public var secondReaderFailure: String
  public var readerVisibleAfterRevocation: Bool
  public var relaunchedValue: Int
  public var relaunchedRoles: [String]
  public var relaunchedPublicShareRoles: [String]
  public var pendingMutationCount: Int
  public var failedMutationCount: Int
  public var connectionState: String
}

public enum InstantCloudKitDemoV3LiveValidation {
  public static func run(
    appID: String,
    apiURI: URL,
    websocketURI: URL,
    ownerRefreshToken: String,
    ownerUserID: String,
    readerRefreshToken: String,
    readerUserID: String,
    writerUserID: String,
    counterID: String,
    shareID: String,
    ownerMembershipID: String,
    readerMembershipID: String,
    writerMembershipID: String,
    persistenceDirectory: URL? = nil,
    onTypeScriptWriterReady: @escaping @Sendable () -> Void = {}
  ) async throws -> ValidationEvidenceRow<InstantCloudKitDemoV3LiveValidationDetails> {
    let directory =
      persistenceDirectory
      ?? FileManager.default.temporaryDirectory.appendingPathComponent(
        "instant-cloudkit-demo-v3-live-\(UUID().uuidString)",
        isDirectory: true
      )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let ownerPersistenceURL = directory.appendingPathComponent("owner.sqlite")
    let readerPersistenceURL = directory.appendingPathComponent("reader.sqlite")
    let owner = try await makeClient(
      appID: appID,
      apiURI: apiURI,
      websocketURI: websocketURI,
      persistenceURL: ownerPersistenceURL
    )
    let reader = try await makeClient(
      appID: appID,
      apiURI: apiURI,
      websocketURI: websocketURI,
      persistenceURL: readerPersistenceURL
    )
    let verifiedOwner = try await owner.signInWithRefreshToken(
      ownerRefreshToken,
      userID: "untrusted-owner"
    )
    let verifiedReader = try await reader.signInWithRefreshToken(
      readerRefreshToken,
      userID: "untrusted-reader"
    )
    guard verifiedOwner.userID == ownerUserID, verifiedReader.userID == readerUserID else {
      throw validationFailure(
        operation: "validate CloudKitDemo V3 auth",
        message: "Server-verified sharing identities did not match the expected users."
      )
    }
    _ = try await owner.connect()
    _ = try await reader.connect()

    let ownerID = InstantID<CloudKitDemoV3User>(rawValue: ownerUserID)
    let readerID = InstantID<CloudKitDemoV3User>(rawValue: readerUserID)
    let writerID = InstantID<CloudKitDemoV3User>(rawValue: writerUserID)
    let typedCounterID = InstantID<CloudKitDemoV3Counter>(rawValue: counterID)
    let typedShareID = InstantID<CloudKitDemoV3Share>(rawValue: shareID)
    let typedReaderMembershipID = InstantID<CloudKitDemoV3ShareMembership>(
      rawValue: readerMembershipID
    )
    let typedWriterMembershipID = InstantID<CloudKitDemoV3ShareMembership>(
      rawValue: writerMembershipID
    )
    let token = "cloudkit-demo-v3-\(shareID)"
    let ownerRecorder = CounterRecorder()
    let readerRecorder = CounterRecorder()
    let ownerObservation = observeCounters(client: owner, userID: ownerID, recorder: ownerRecorder)
    let readerObservation = observeCounters(
      client: reader, userID: readerID, recorder: readerRecorder)
    defer {
      ownerObservation.cancel()
      readerObservation.cancel()
    }

    try await commit(
      CreateCloudKitDemoV3SharedCounter(
        counterID: typedCounterID,
        shareID: typedShareID,
        ownerMembershipID: InstantID(rawValue: ownerMembershipID),
        ownerID: ownerID,
        title: "Canonical shared counter",
        token: token,
        createdAt: Date(timeIntervalSince1970: 1_752_918_400)
      ),
      using: owner
    )
    try await waitForValue(0, recorder: ownerRecorder, operation: "observe owner create")

    try await commit(
      AcceptCloudKitDemoV3Share(
        token: token,
        membershipID: typedReaderMembershipID,
        userID: readerID,
        acceptedAt: Date(timeIntervalSince1970: 1_752_918_401)
      ),
      using: owner
    )
    try await commit(
      AcceptCloudKitDemoV3Share(
        token: token,
        membershipID: typedWriterMembershipID,
        userID: writerID,
        acceptedAt: Date(timeIntervalSince1970: 1_752_918_402)
      ),
      using: owner
    )
    try await commit(
      ChangeCloudKitDemoV3ShareRole(
        shareID: typedShareID,
        membershipID: typedWriterMembershipID,
        counterID: typedCounterID,
        userID: writerID,
        previousRole: .reader,
        role: .writer,
        updatedAt: Date(timeIntervalSince1970: 1_752_918_403)
      ),
      using: owner
    )
    try await waitForValue(0, recorder: readerRecorder, operation: "observe reader grant")

    let firstReaderFailure = try await rejectedCommit(
      IncrementCloudKitDemoV3Counter(counterID: typedCounterID),
      using: reader,
      optimisticValue: 1,
      authoritativeValue: 0,
      recorder: readerRecorder
    )
    try await commit(
      ChangeCloudKitDemoV3ShareRole(
        shareID: typedShareID,
        membershipID: typedReaderMembershipID,
        counterID: typedCounterID,
        userID: readerID,
        previousRole: .reader,
        role: .writer,
        updatedAt: Date(timeIntervalSince1970: 1_752_918_404)
      ),
      using: owner
    )
    try await commit(
      IncrementCloudKitDemoV3Counter(counterID: typedCounterID),
      using: reader
    )
    try await waitForValue(1, recorder: ownerRecorder, operation: "observe Swift writer increment")

    onTypeScriptWriterReady()
    try await waitForValue(2, recorder: readerRecorder, operation: "observe TypeScript increment")

    try await commit(
      ChangeCloudKitDemoV3ShareRole(
        shareID: typedShareID,
        membershipID: typedReaderMembershipID,
        counterID: typedCounterID,
        userID: readerID,
        previousRole: .writer,
        role: .reader,
        updatedAt: Date(timeIntervalSince1970: 1_752_918_405)
      ),
      using: owner
    )
    let secondReaderFailure = try await rejectedCommit(
      IncrementCloudKitDemoV3Counter(counterID: typedCounterID),
      using: reader,
      optimisticValue: 3,
      authoritativeValue: 2,
      recorder: readerRecorder
    )
    try await commit(
      RevokeCloudKitDemoV3Participant(
        shareID: typedShareID,
        membershipID: typedReaderMembershipID,
        counterID: typedCounterID,
        userID: readerID,
        role: .reader,
        revokedAt: Date(timeIntervalSince1970: 1_752_918_406)
      ),
      using: owner
    )
    try await waitForEmpty(recorder: readerRecorder, operation: "observe reader revocation")

    _ = try await owner.closeConnection()
    let relaunched = try await makeClient(
      appID: appID,
      apiURI: apiURI,
      websocketURI: websocketURI,
      persistenceURL: ownerPersistenceURL
    )
    _ = try await relaunched.signInWithRefreshToken(ownerRefreshToken, userID: "untrusted-owner")
    _ = try await relaunched.connect()
    let relaunchedCounter = try await waitForCounter(
      client: relaunched,
      userID: ownerID,
      counterID: typedCounterID,
      operation: "observe shared counter after relaunch"
    )
    let publicShares = Shares()
    let publicSharesTask = Task { try await publicShares.task(using: relaunched) }
    defer { publicSharesTask.cancel() }
    let publicShare = try await waitForPublicShare(
      shares: publicShares,
      shareID: shareID
    )
    let mutations = await relaunched.runtime?.outboxMutations() ?? []
    let status = try await relaunched.connectionStatus()
    let readerVisibleAfterRevocation =
      try await reader
      .query(CloudKitDemoV3Counter.visible(to: readerID)).isEmpty == false
    _ = try await reader.closeConnection()
    _ = try await relaunched.closeConnection()

    return ValidationEvidenceRow(
      caseID: "validation.live.cloudkit-demo-v3",
      side: "swift",
      event: "shared-counter-lifecycle-complete",
      appID: appID,
      entityID: counterID,
      timestampMs: Int64((Date().timeIntervalSince1970 * 1_000).rounded()),
      ok: true,
      details: InstantCloudKitDemoV3LiveValidationDetails(
        counterID: counterID,
        shareID: shareID,
        ownerUserID: ownerUserID,
        readerUserID: readerUserID,
        writerUserID: writerUserID,
        ownerObservedValues: await ownerRecorder.values(),
        readerObservedValues: await readerRecorder.values(),
        firstReaderFailure: firstReaderFailure,
        secondReaderFailure: secondReaderFailure,
        readerVisibleAfterRevocation: readerVisibleAfterRevocation,
        relaunchedValue: relaunchedCounter.value,
        relaunchedRoles: relaunchedCounter.share?.memberships.compactMap {
          $0.shareRole?.rawValue
        } ?? [],
        relaunchedPublicShareRoles: publicShare.memberships.map(\.role.rawValue),
        pendingMutationCount: mutations.filter { $0.status == .pending }.count,
        failedMutationCount: mutations.filter { $0.status == .failed }.count,
        connectionState: status.state.rawValue
      )
    )
  }

  private static func makeClient(
    appID: String,
    apiURI: URL,
    websocketURI: URL,
    persistenceURL: URL
  ) async throws -> InstantSwiftDataClient {
    try await withDependencies {
      $0.context = .live
      $0.instantLiveTransport = .live
      try await $0.bootstrapInstantSwiftData(
        appID: appID,
        apiURI: apiURI,
        websocketURI: websocketURI,
        persistenceURL: persistenceURL,
        context: .live,
        initialAttributes: CloudKitDemoV3Schema.attributes,
        liveShareContract: .v3SharedLists
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var client
      return client
    }
  }

  private static func observeCounters(
    client: InstantSwiftDataClient,
    userID: InstantID<CloudKitDemoV3User>,
    recorder: CounterRecorder
  ) -> Task<Void, Never> {
    Task {
      let emissions = await client.observe(CloudKitDemoV3Counter.visible(to: userID).plan)
      for await emission in emissions {
        do {
          try await recorder.append(CloudKitDemoV3Counter.decode(emission.values))
        } catch {
          await recorder.fail(error)
          return
        }
      }
    }
  }

  private static func commit<Message: InstantMessage>(
    _ message: Message,
    using client: InstantSwiftDataClient
  ) async throws {
    guard let runtime = client.runtime else {
      throw validationFailure(
        operation: "commit CloudKitDemo V3 message", message: "Missing runtime.")
    }
    let prepared = try await message.prepare(using: client)
    let transactionID = "cloudkit-demo-v3-\(UUID().uuidString.lowercased())"
    _ = try await client.transact(id: transactionID) {
      for mutation in prepared.mutations { mutation }
    }
    let outcome = try await waitForMutation(runtime: runtime, transactionID: transactionID)
    if let failure = outcome {
      throw validationFailure(
        operation: "commit CloudKitDemo V3 message",
        message: "Expected server acceptance, received: \(failure)"
      )
    }
  }

  private static func rejectedCommit<Message: InstantMessage>(
    _ message: Message,
    using client: InstantSwiftDataClient,
    optimisticValue: Int,
    authoritativeValue: Int,
    recorder: CounterRecorder
  ) async throws -> String {
    guard let runtime = client.runtime else {
      throw validationFailure(
        operation: "reject CloudKitDemo V3 message", message: "Missing runtime.")
    }
    let prepared = try await message.prepare(using: client)
    let transactionID = "cloudkit-demo-v3-rejected-\(UUID().uuidString.lowercased())"
    _ = try await client.transact(id: transactionID) {
      for mutation in prepared.mutations { mutation }
    }
    try await waitForValue(
      optimisticValue,
      recorder: recorder,
      operation: "observe rejected optimistic counter value"
    )
    guard let failure = try await waitForMutation(runtime: runtime, transactionID: transactionID)
    else {
      throw validationFailure(
        operation: "reject CloudKitDemo V3 message",
        message: "Expected the reader mutation to fail."
      )
    }
    try await waitForValueAfter(
      authoritativeValue,
      after: optimisticValue,
      recorder: recorder,
      operation: "observe authoritative counter rollback"
    )
    return failure
  }

  private static func waitForMutation(
    runtime: InstantRuntime,
    transactionID: String
  ) async throws -> String? {
    var observed = false
    for _ in 0..<800 {
      let mutations = await runtime.outboxMutations()
      if let mutation = mutations.first(where: { $0.id == transactionID }) {
        observed = true
        if mutation.status == .failed {
          return mutation.failureMessage ?? "Server rejected the mutation."
        }
      } else if observed {
        return nil
      }
      try await Task.sleep(for: .milliseconds(25))
    }
    throw validationFailure(
      operation: "wait for CloudKitDemo V3 mutation",
      message: "Timed out waiting for \(transactionID)."
    )
  }

  private static func waitForValue(
    _ value: Int,
    recorder: CounterRecorder,
    operation: String
  ) async throws {
    for _ in 0..<800 {
      try await recorder.throwIfFailed()
      if await recorder.values().contains(value) { return }
      try await Task.sleep(for: .milliseconds(25))
    }
    throw validationFailure(operation: operation, message: "Timed out waiting for value \(value).")
  }

  private static func waitForValueAfter(
    _ value: Int,
    after precedingValue: Int,
    recorder: CounterRecorder,
    operation: String
  ) async throws {
    for _ in 0..<800 {
      try await recorder.throwIfFailed()
      let values = await recorder.values()
      if let index = values.lastIndex(of: precedingValue),
        values[values.index(after: index)...].contains(value)
      {
        return
      }
      try await Task.sleep(for: .milliseconds(25))
    }
    throw validationFailure(operation: operation, message: "Timed out waiting for rollback.")
  }

  private static func waitForEmpty(recorder: CounterRecorder, operation: String) async throws {
    for _ in 0..<800 {
      try await recorder.throwIfFailed()
      if await recorder.latestIsEmpty() { return }
      try await Task.sleep(for: .milliseconds(25))
    }
    throw validationFailure(operation: operation, message: "Timed out waiting for no counters.")
  }

  private static func waitForCounter(
    client: InstantSwiftDataClient,
    userID: InstantID<CloudKitDemoV3User>,
    counterID: InstantID<CloudKitDemoV3Counter>,
    operation: String
  ) async throws -> CloudKitDemoV3Counter {
    let recorder = CounterRecorder()
    let observation = observeCounters(client: client, userID: userID, recorder: recorder)
    defer { observation.cancel() }
    for _ in 0..<800 {
      try await recorder.throwIfFailed()
      if let counter = await recorder.latest().first(where: { $0.id == counterID }) {
        return counter
      }
      try await Task.sleep(for: .milliseconds(25))
    }
    throw validationFailure(operation: operation, message: "Timed out waiting for shared counter.")
  }

  private static func waitForPublicShare(
    shares: Shares,
    shareID: String
  ) async throws -> InstantShareSnapshot {
    for _ in 0..<800 {
      if let share = shares.wrappedValue.first(where: { $0.share.id == shareID }) { return share }
      if let error = shares.loadError { throw error }
      try await Task.sleep(for: .milliseconds(25))
    }
    throw validationFailure(
      operation: "observe CloudKitDemo V3 @Shares state",
      message: "Timed out waiting for share \(shareID)."
    )
  }
}

private actor CounterRecorder {
  private var emissions: [[CloudKitDemoV3Counter]] = []
  private var error: Error?

  func append(_ counters: [CloudKitDemoV3Counter]) {
    emissions.append(counters)
  }

  func fail(_ error: Error) {
    self.error = error
  }

  func throwIfFailed() throws {
    if let error { throw error }
  }

  func values() -> [Int] {
    emissions.compactMap(\.first?.value).reduce(into: []) { values, value in
      if values.last != value { values.append(value) }
    }
  }

  func latest() -> [CloudKitDemoV3Counter] {
    emissions.last ?? []
  }

  func latestIsEmpty() -> Bool {
    emissions.last?.isEmpty == true
  }
}

private func validationFailure(operation: String, message: String) -> InstantError {
  InstantError(
    code: .validationFailed,
    operation: operation,
    message: message,
    recovery: "Inspect the CloudKitDemo V3 app messages, sharing permissions, and live queries."
  )
}
