import Foundation
import InstantSwiftDataCore

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

  public init(
    listID: String,
    readerUserID: String,
    expectedServerValue: Double,
    rejectedOptimisticValue: Double,
    observedValues: [Double],
    pendingMutationCount: Int,
    failedMutationCount: Int,
    failureMessage: String,
    connectionState: String
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
        liveTransport: trace.transport
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
