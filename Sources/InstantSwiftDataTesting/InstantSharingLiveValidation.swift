import Foundation
import InstantSwiftData

public struct InstantSharingLiveValidationDetails: Codable, Equatable, Sendable {
  public var listID: String
  public var readerUserID: String
  public var expectedServerValue: Double
  public var rejectedOptimisticValue: Double
  public var observedValues: [Double]
  public var pendingMutationCount: Int
  public var failedMutationCount: Int
  public var failureMessage: String
  public var connectionState: String
  public var publicShareIDs: [String]
  public var publicShareRoles: [String]
  public var publicSharesCancellationClean: Bool

  public init(
    listID: String,
    readerUserID: String,
    expectedServerValue: Double,
    rejectedOptimisticValue: Double,
    observedValues: [Double],
    pendingMutationCount: Int,
    failedMutationCount: Int,
    failureMessage: String,
    connectionState: String,
    publicShareIDs: [String],
    publicShareRoles: [String],
    publicSharesCancellationClean: Bool
  ) {
    self.listID = listID
    self.readerUserID = readerUserID
    self.expectedServerValue = expectedServerValue
    self.rejectedOptimisticValue = rejectedOptimisticValue
    self.observedValues = observedValues
    self.pendingMutationCount = pendingMutationCount
    self.failedMutationCount = failedMutationCount
    self.failureMessage = failureMessage
    self.connectionState = connectionState
    self.publicShareIDs = publicShareIDs
    self.publicShareRoles = publicShareRoles
    self.publicSharesCancellationClean = publicSharesCancellationClean
  }
}

public struct InstantSharingWriterLiveValidationDetails: Codable, Equatable, Sendable {
  public var listID: String
  public var writerUserID: String
  public var expectedServerValue: Double
  public var acceptedValue: Double
  public var observedValues: [Double]
  public var pendingMutationCount: Int
  public var failedMutationCount: Int
  public var connectionState: String

  public init(
    listID: String,
    writerUserID: String,
    expectedServerValue: Double,
    acceptedValue: Double,
    observedValues: [Double],
    pendingMutationCount: Int,
    failedMutationCount: Int,
    connectionState: String
  ) {
    self.listID = listID
    self.writerUserID = writerUserID
    self.expectedServerValue = expectedServerValue
    self.acceptedValue = acceptedValue
    self.observedValues = observedValues
    self.pendingMutationCount = pendingMutationCount
    self.failedMutationCount = failedMutationCount
    self.connectionState = connectionState
  }
}

public enum InstantSharingLiveValidation {
  public static func run(
    appID: String,
    websocketURI: URL,
    refreshToken: String,
    readerUserID: String,
    listID: String,
    expectedServerValue: Double,
    rejectedOptimisticValue: Double,
    persistenceURL: URL? = nil
  ) async throws -> ValidationEvidenceRow<InstantSharingLiveValidationDetails> {
    let persistenceURL = persistenceURL ?? FileManager.default.temporaryDirectory
      .appendingPathComponent("instant-sharing-live-\(UUID().uuidString).sqlite")
    let trace = SharingLiveTrace()
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: appID,
        websocketURI: websocketURI,
        persistenceURL: persistenceURL,
        initialAttributes: sharingAttributes,
        liveTransport: trace.transport,
        liveShareContract: .v3SharedLists
      )
    )
    _ = try await runtime.signInWithRefreshToken(refreshToken, userID: readerUserID)
    let plan = InstantQueryPlan(
      id: "validation.live.sharing.reader",
      namespace: "v3_shared_lists",
      filters: [.equals(field: "id", value: .string(listID))]
    )
    let recorder = SharingValueRecorder()
    let observation = await runtime.observe(plan)
    let observationTask = Task {
      for await emission in observation {
        if let value = sharingValue(emission.values, listID: listID) {
          await recorder.append(value)
        }
      }
    }
    defer { observationTask.cancel() }

    _ = try await runtime.connect()
    do {
      try await waitForValue(
        expectedServerValue,
        recorder: recorder,
        operation: "wait for reader shared-list server value"
      )
    } catch {
      let status = try await runtime.connectionStatus()
      let values = await recorder.values()
      let lastError = status.lastErrorMessage ?? "none"
      let traceSummary = await trace.summary()
      throw InstantError(
        code: .networkFailed,
        operation: "wait for reader shared-list server value",
        message: "Observed \(values); connection=\(status.state.rawValue); lastError=\(lastError); trace=\(traceSummary).",
        recovery: "Inspect the live sharing query, permission error, and refetch sequence."
      )
    }

    let publicShares = Shares()
    let publicSharesTask = Task {
      try await publicShares.task(using: InstantSwiftDataClient(runtime: runtime))
    }
    defer { publicSharesTask.cancel() }
    let publicSnapshot: InstantShareSnapshot
    do {
      publicSnapshot = try await waitForPublicShare(
        listID: listID,
        shares: publicShares
      )
    } catch {
      let status = try await runtime.connectionStatus()
      let projected = publicShares.wrappedValue.map {
        "\($0.share.id):\($0.share.rootNamespace):\($0.share.rootID)"
      }
      let oneShot = try? await runtime.shares().map {
        "\($0.share.id):\($0.share.rootNamespace):\($0.share.rootID)"
      }
      let traceSummary = await trace.summary()
      let lastError = status.lastErrorMessage ?? "none"
      throw InstantError(
        code: .networkFailed,
        operation: "wait for public @Shares live graph",
        message:
          "Projected \(projected); oneShot=\(String(describing: oneShot)); "
          + "loadError=\(String(describing: publicShares.loadError)); "
          + "connection=\(status.state.rawValue); lastError="
          + "\(lastError); trace=\(traceSummary).",
        recovery: "Inspect the live @Shares query registration and projection sequence."
      )
    }

    let transactionID = "validation-sharing-reader-rejected-\(UUID().uuidString.lowercased())"
    let now = InstantTimestamp(milliseconds: Int64((Date().timeIntervalSince1970 * 1000).rounded()))
    try await runtime.transact(
      InstantStoreTransaction(
        id: transactionID,
        operations: [
          .requireEntityExists(entityID: listID, namespace: "v3_shared_lists"),
          .insert(
            InstantTriple(
              entityID: listID,
              attributeID: "v3_shared_lists/value",
              value: .number(rejectedOptimisticValue),
              txID: transactionID,
              txTime: now
            )
          ),
        ]
      ),
      createdAt: now
    )
    try await waitForValue(
      rejectedOptimisticValue,
      recorder: recorder,
      operation: "wait for reader optimistic shared-list value"
    )
    try await waitForFailedMutation(runtime, id: transactionID)
    try await waitForValueAfter(
      expectedServerValue,
      after: rejectedOptimisticValue,
      recorder: recorder,
      operation: "wait for authoritative shared-list rollback"
    )

    let mutations = await runtime.outboxMutations()
    let pendingMutationCount = mutations.filter { $0.status == .pending }.count
    let failed = mutations.filter { $0.status == .failed }
    guard pendingMutationCount == 0,
      failed.count == 1,
      let failureMessage = failed.first?.failureMessage,
      failureMessage.localizedCaseInsensitiveContains("permission")
    else {
      throw InstantError(
        code: .validationFailed,
        operation: "validate live sharing rejection outbox",
        message: "Expected one permission failure and zero pending mutations.",
        recovery: "Keep rejected optimistic writes failed, refetched, and non-pending."
      )
    }
    let status = try await runtime.connectionStatus()
    let values = await recorder.values()
    publicSharesTask.cancel()
    let publicSharesCancellationClean: Bool
    do {
      try await publicSharesTask.value
      publicSharesCancellationClean = false
    } catch is CancellationError {
      publicSharesCancellationClean = true
    }
    _ = try await runtime.closeConnection()

    return ValidationEvidenceRow(
      caseID: "validation.live.sharing",
      side: "swift",
      event: "reader-rejection-reconciled",
      appID: appID,
      entityID: listID,
      timestampMs: now.milliseconds,
      ok: true,
      details: InstantSharingLiveValidationDetails(
        listID: listID,
        readerUserID: readerUserID,
        expectedServerValue: expectedServerValue,
        rejectedOptimisticValue: rejectedOptimisticValue,
        observedValues: values,
        pendingMutationCount: pendingMutationCount,
        failedMutationCount: failed.count,
        failureMessage: failureMessage,
        connectionState: status.state.rawValue,
        publicShareIDs: [publicSnapshot.share.id],
        publicShareRoles: publicSnapshot.memberships.map { $0.role.rawValue },
        publicSharesCancellationClean: publicSharesCancellationClean
      )
    )
  }

  public static func runWriter(
    appID: String,
    websocketURI: URL,
    refreshToken: String,
    writerUserID: String,
    listID: String,
    expectedServerValue: Double,
    acceptedValue: Double,
    persistenceURL: URL? = nil
  ) async throws -> ValidationEvidenceRow<InstantSharingWriterLiveValidationDetails> {
    let persistenceURL = persistenceURL ?? FileManager.default.temporaryDirectory
      .appendingPathComponent("instant-sharing-writer-live-\(UUID().uuidString).sqlite")
    let trace = SharingLiveTrace()
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: appID,
        websocketURI: websocketURI,
        persistenceURL: persistenceURL,
        initialAttributes: sharingAttributes,
        liveTransport: trace.transport
      )
    )
    _ = try await runtime.signInWithRefreshToken(refreshToken, userID: writerUserID)
    let plan = InstantQueryPlan(
      id: "validation.live.sharing.writer",
      namespace: "v3_shared_lists",
      filters: [.equals(field: "id", value: .string(listID))]
    )
    let recorder = SharingValueRecorder()
    let observation = await runtime.observe(plan)
    let observationTask = Task {
      for await emission in observation {
        if let value = sharingValue(emission.values, listID: listID) {
          await recorder.append(value)
        }
      }
    }
    defer { observationTask.cancel() }

    _ = try await runtime.connect()
    do {
      try await waitForValue(
        expectedServerValue,
        recorder: recorder,
        operation: "wait for writer shared-list server value"
      )
    } catch {
      let status = try await runtime.connectionStatus()
      let values = await recorder.values()
      let lastError = status.lastErrorMessage ?? "none"
      let traceSummary = await trace.summary()
      throw InstantError(
        code: .networkFailed,
        operation: "wait for writer shared-list server value",
        message: "Observed \(values); connection=\(status.state.rawValue); lastError=\(lastError); trace=\(traceSummary).",
        recovery: "Inspect the live sharing writer query and permission contract."
      )
    }

    let transactionID = "validation-sharing-writer-accepted-\(UUID().uuidString.lowercased())"
    let now = InstantTimestamp(milliseconds: Int64((Date().timeIntervalSince1970 * 1000).rounded()))
    try await runtime.transact(
      InstantStoreTransaction(
        id: transactionID,
        operations: [
          .requireEntityExists(entityID: listID, namespace: "v3_shared_lists"),
          .insert(
            InstantTriple(
              entityID: listID,
              attributeID: "v3_shared_lists/value",
              value: .number(acceptedValue),
              txID: transactionID,
              txTime: now
            )
          ),
        ]
      ),
      createdAt: now
    )
    try await waitForValue(
      acceptedValue,
      recorder: recorder,
      operation: "wait for writer accepted optimistic value"
    )
    try await waitForMutationRemoval(runtime, id: transactionID)

    let mutations = await runtime.outboxMutations()
    let pendingMutationCount = mutations.filter { $0.status == .pending }.count
    let failedMutationCount = mutations.filter { $0.status == .failed }.count
    guard pendingMutationCount == 0, failedMutationCount == 0 else {
      throw InstantError(
        code: .validationFailed,
        operation: "validate live sharing writer outbox",
        message: "Expected the accepted writer mutation to leave no pending or failed mutations.",
        recovery: "Confirm writer permissions and transact-ok handling."
      )
    }
    let status = try await runtime.connectionStatus()
    let values = await recorder.values()
    _ = try await runtime.closeConnection()

    return ValidationEvidenceRow(
      caseID: "validation.live.sharing",
      side: "swift",
      event: "writer-update-confirmed",
      appID: appID,
      entityID: listID,
      timestampMs: now.milliseconds,
      ok: true,
      details: InstantSharingWriterLiveValidationDetails(
        listID: listID,
        writerUserID: writerUserID,
        expectedServerValue: expectedServerValue,
        acceptedValue: acceptedValue,
        observedValues: values,
        pendingMutationCount: pendingMutationCount,
        failedMutationCount: failedMutationCount,
        connectionState: status.state.rawValue
      )
    )
  }

  private static let sharingAttributes: [InstantAttribute] = [
    .primaryKey(namespace: "v3_shared_lists"),
    InstantAttribute(
      id: "v3_shared_lists/title",
      namespace: "v3_shared_lists",
      name: "title",
      valueType: .string,
      isIndexed: true
    ),
    InstantAttribute(
      id: "v3_shared_lists/value",
      namespace: "v3_shared_lists",
      name: "value",
      valueType: .number,
      isIndexed: true
    ),
  ]

  private static func sharingValue(
    _ values: [InstantEntitySnapshot],
    listID: String
  ) -> Double? {
    guard let root = values.first(where: { $0.id == listID }),
      case let .number(value) = root.values["value"]?.first
    else { return nil }
    return value
  }

  private static func waitForValue(
    _ value: Double,
    recorder: SharingValueRecorder,
    operation: String
  ) async throws {
    for _ in 0..<400 {
      if await recorder.contains(value) { return }
      try await Task.sleep(for: .milliseconds(25))
    }
    throw timeout(operation)
  }

  private static func waitForValueAfter(
    _ value: Double,
    after precedingValue: Double,
    recorder: SharingValueRecorder,
    operation: String
  ) async throws {
    for _ in 0..<400 {
      let values = await recorder.values()
      if let precedingIndex = values.lastIndex(of: precedingValue),
        values[values.index(after: precedingIndex)...].contains(value)
      {
        return
      }
      try await Task.sleep(for: .milliseconds(25))
    }
    throw timeout(operation)
  }

  private static func waitForFailedMutation(
    _ runtime: InstantRuntime,
    id: String
  ) async throws {
    for _ in 0..<400 {
      if await runtime.outboxMutations().contains(where: { $0.id == id && $0.status == .failed }) {
        return
      }
      try await Task.sleep(for: .milliseconds(25))
    }
    throw timeout("wait for reader sharing permission failure")
  }

  private static func waitForPublicShare(
    listID: String,
    shares: Shares
  ) async throws -> InstantShareSnapshot {
    for _ in 0..<400 {
      if let snapshot = shares.wrappedValue.first(where: { $0.share.rootID == listID }) {
        return snapshot
      }
      if let error = shares.loadError { throw error }
      try await Task.sleep(for: .milliseconds(25))
    }
    throw timeout("wait for public @Shares live graph")
  }

  private static func waitForMutationRemoval(
    _ runtime: InstantRuntime,
    id: String
  ) async throws {
    for _ in 0..<400 {
      if !(await runtime.outboxMutations()).contains(where: { $0.id == id }) {
        return
      }
      try await Task.sleep(for: .milliseconds(25))
    }
    throw timeout("wait for writer sharing transaction confirmation")
  }

  private static func timeout(_ operation: String) -> InstantError {
    InstantError(
      code: .networkFailed,
      operation: operation,
      message: "Timed out after 10 seconds.",
      recovery: "Inspect the live sharing query, permission error, and refetch sequence."
    )
  }
}

private actor SharingValueRecorder {
  private var recordedValues: [Double] = []

  func append(_ value: Double) {
    guard recordedValues.last != value else { return }
    recordedValues.append(value)
  }

  func contains(_ value: Double) -> Bool {
    recordedValues.contains(value)
  }

  func values() -> [Double] {
    recordedValues
  }
}

private actor SharingLiveTrace {
  private var sentOps: [String] = []
  private var receivedOps: [String] = []
  private var addQueries: [String] = []
  private var queryResults: [String] = []

  nonisolated var transport: InstantLiveTransportClient {
    let live = InstantLiveTransportClient.live
    return InstantLiveTransportClient { request in
      let session = try await live.connect(request)
      return InstantLiveWebSocketSession(
        send: { message in
          await self.recordSent(message)
          try await session.send(message)
        },
        receive: {
          let message = try await session.receive()
          await self.recordReceived(message)
          return message
        },
        close: {
          await session.close()
        }
      )
    }
  }

  func summary() -> String {
    "sent=\(sentOps), received=\(receivedOps), queries=\(addQueries), results=\(queryResults)"
  }

  private func recordSent(_ message: InstantLiveMessage) {
    sentOps.append(message.op)
    if message.op == "add-query" {
      addQueries.append(String(describing: message.fields["q"]))
    }
  }

  private func recordReceived(_ message: InstantLiveMessage) {
    receivedOps.append(message.op)
    if message.op == "add-query-ok" || message.op == "add-query-exists" {
      let result = String(describing: message.fields["result"])
      let processed = String(describing: message.fields["processed-tx-id"])
      queryResults.append(
        "result=\(result), processed=\(processed)"
      )
    }
  }
}
