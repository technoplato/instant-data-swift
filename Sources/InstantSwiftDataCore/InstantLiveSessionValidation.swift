import Foundation

public struct LiveSessionRuntimeProjection: Sendable {
  public var cachedEntityIDs: [String]
  public var cachedTodoTexts: [String]
  public var observedSnapshot: InstantLiveJSONValue?

  public init(
    cachedEntityIDs: [String],
    cachedTodoTexts: [String] = [],
    observedSnapshot: InstantLiveJSONValue? = nil
  ) {
    self.cachedEntityIDs = cachedEntityIDs
    self.cachedTodoTexts = cachedTodoTexts
    self.observedSnapshot = observedSnapshot
  }
}

public struct LiveSessionValidationDetails: Codable, Equatable, Sendable {
  public var websocketURL: String
  public var sentOps: [String]
  public var receivedOps: [String]
  public var clientEventIDs: [String]
  public var sessionID: String?
  public var attrCount: Int
  public var queryResultCount: Int
  public var refreshComputationCount: Int
  public var processedTransactionID: String?
  public var transactionID: String?
  public var transactionISN: String?
  public var observedEntityID: String?
  public var runtimeCachePath: String?
  public var appliedRefreshCount: Int
  public var appliedRefreshTransactionIDs: [String]
  public var appliedInsertedTripleCount: Int
  public var appliedMergedAttributeCount: Int
  public var cachedEntityIDs: [String]
  public var cachedTodoTexts: [String]
  public var observedSnapshot: InstantLiveJSONValue?
  public var pendingMutationCount: Int
  public var proofLevel: String
  public var remoteBoundary: String
  public var errorMessage: String?

  public init(
    websocketURL: String,
    sentOps: [String] = [],
    receivedOps: [String] = [],
    clientEventIDs: [String] = [],
    sessionID: String? = nil,
    attrCount: Int = 0,
    queryResultCount: Int = 0,
    refreshComputationCount: Int = 0,
    processedTransactionID: String? = nil,
    transactionID: String? = nil,
    transactionISN: String? = nil,
    observedEntityID: String? = nil,
    runtimeCachePath: String? = nil,
    appliedRefreshCount: Int = 0,
    appliedRefreshTransactionIDs: [String] = [],
    appliedInsertedTripleCount: Int = 0,
    appliedMergedAttributeCount: Int = 0,
    cachedEntityIDs: [String] = [],
    cachedTodoTexts: [String] = [],
    observedSnapshot: InstantLiveJSONValue? = nil,
    pendingMutationCount: Int = 0,
    proofLevel: String,
    remoteBoundary: String = "pending-cross-client-sync",
    errorMessage: String? = nil
  ) {
    self.websocketURL = websocketURL
    self.sentOps = sentOps
    self.receivedOps = receivedOps
    self.clientEventIDs = clientEventIDs
    self.sessionID = sessionID
    self.attrCount = attrCount
    self.queryResultCount = queryResultCount
    self.refreshComputationCount = refreshComputationCount
    self.processedTransactionID = processedTransactionID
    self.transactionID = transactionID
    self.transactionISN = transactionISN
    self.observedEntityID = observedEntityID
    self.runtimeCachePath = runtimeCachePath
    self.appliedRefreshCount = appliedRefreshCount
    self.appliedRefreshTransactionIDs = appliedRefreshTransactionIDs
    self.appliedInsertedTripleCount = appliedInsertedTripleCount
    self.appliedMergedAttributeCount = appliedMergedAttributeCount
    self.cachedEntityIDs = cachedEntityIDs
    self.cachedTodoTexts = cachedTodoTexts
    self.observedSnapshot = observedSnapshot
    self.pendingMutationCount = pendingMutationCount
    self.proofLevel = proofLevel
    self.remoteBoundary = remoteBoundary
    self.errorMessage = errorMessage
  }
}

public struct LiveSessionValidationResult: Sendable {
  public var appID: String
  public var websocketURL: URL
  public var evidence: [ValidationEvidenceRow<LiveSessionValidationDetails>]

  public init(
    appID: String,
    websocketURL: URL,
    evidence: [ValidationEvidenceRow<LiveSessionValidationDetails>]
  ) {
    self.appID = appID
    self.websocketURL = websocketURL
    self.evidence = evidence
  }
}

public struct LiveSessionValidationFailure: Error, Sendable, CustomStringConvertible {
  public var message: String
  public var instantError: InstantError?
  public var evidence: [ValidationEvidenceRow<LiveSessionValidationDetails>]

  public init(
    error: Error,
    evidence: [ValidationEvidenceRow<LiveSessionValidationDetails>]
  ) {
    self.message = String(describing: error)
    self.instantError = error as? InstantError
    self.evidence = evidence
  }

  public var description: String {
    message
  }
}

public enum InstantSwiftDataLiveSessionValidation {
  public static let defaultQuery: InstantLiveJSONValue = .object([
    TodoExample.namespace: .object([:])
  ])
  public static let defaultTransactionSteps: [InstantTransportStep] = [
    .addTriple(
      entity: .id("live-transaction-note"),
      attributeID: "todos/id",
      value: .string("live-transaction-note")
    ),
    .addTriple(
      entity: .id("live-transaction-note"),
      attributeID: "todos/text",
      value: .string("Swift live transaction")
    ),
    .addTriple(
      entity: .id("live-transaction-note"),
      attributeID: "todos/isCompleted",
      value: .bool(false)
    ),
  ]

  public static func run(
    appID: String = "live-session-validation",
    caseID: String = "validation.live.session",
    websocketURI: URL = InstantRuntimeConfiguration.defaultWebSocketURI,
    refreshToken: String? = nil,
    adminToken: String? = nil,
    query: InstantLiveJSONValue = Self.defaultQuery,
    includeTransaction: Bool = false,
    transactionSteps: [InstantTransportStep] = Self.defaultTransactionSteps,
    resolveTransactionAttributeIDs: Bool = false,
    expectedExternalRefreshEntityID: String? = nil,
    applyRefreshesToRuntime: Bool = false,
    runtimePersistenceURL: URL? = nil,
    liveTransport: InstantLiveTransportClient = .local,
    proofLevel: String = "local-protocol",
    timestamp: @escaping @Sendable () -> InstantTimestamp = {
      InstantTimestamp(milliseconds: Int64((Date().timeIntervalSince1970 * 1000).rounded()))
    },
    makeID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() },
    onEvidence: (@Sendable (ValidationEvidenceRow<LiveSessionValidationDetails>) throws -> Void)? = nil,
    runtimeProjection:
      (@Sendable (InstantRuntime) async throws -> LiveSessionRuntimeProjection)? = nil,
    eventTimeoutMilliseconds: UInt64 = 10_000,
    maxServerEvents: Int = 4
  ) async throws -> LiveSessionValidationResult {
    guard maxServerEvents > 0 else {
      throw InstantError(
        code: .validationFailed,
        operation: "validate Instant live session",
        message: "maxServerEvents must be greater than 0.",
        recovery: "Pass a positive maxServerEvents value for the live session smoke."
      )
    }

    let request = InstantLiveSessionRequest(
      appID: appID,
      websocketURI: websocketURI,
      refreshToken: refreshToken,
      adminToken: adminToken
    )
    let websocketURL = try request.sessionURL()
    var sentOps: [String] = []
    var receivedOps: [String] = []
    var clientEventIDs: [String] = []
    var sessionID: String?
    var attrCount = 0
    var queryResultCount = 0
    var refreshComputationCount = 0
    var processedTransactionID: String?
    var transactionID: String?
    var transactionISN: String?
    var observedEntityID: String?
    var initAttrs: [InstantLiveJSONValue] = []
    var runtimeCachePath: String?
    var appliedRefreshCount = 0
    var appliedRefreshTransactionIDs: [String] = []
    var appliedInsertedTripleCount = 0
    var appliedMergedAttributeCount = 0
    var cachedEntityIDs: [String] = []
    var cachedTodoTexts: [String] = []
    var observedSnapshot: InstantLiveJSONValue?
    var pendingMutationCount = 0
    var evidence: [ValidationEvidenceRow<LiveSessionValidationDetails>] = []
    var runtime: InstantRuntime?

    func details(errorMessage: String? = nil) -> LiveSessionValidationDetails {
      LiveSessionValidationDetails(
        websocketURL: websocketURL.absoluteString,
        sentOps: sentOps,
        receivedOps: receivedOps,
        clientEventIDs: clientEventIDs,
        sessionID: sessionID,
        attrCount: attrCount,
        queryResultCount: queryResultCount,
        refreshComputationCount: refreshComputationCount,
        processedTransactionID: processedTransactionID,
        transactionID: transactionID,
        transactionISN: transactionISN,
        observedEntityID: observedEntityID,
        runtimeCachePath: runtimeCachePath,
        appliedRefreshCount: appliedRefreshCount,
        appliedRefreshTransactionIDs: appliedRefreshTransactionIDs,
        appliedInsertedTripleCount: appliedInsertedTripleCount,
        appliedMergedAttributeCount: appliedMergedAttributeCount,
        cachedEntityIDs: cachedEntityIDs,
        cachedTodoTexts: cachedTodoTexts,
        observedSnapshot: observedSnapshot,
        pendingMutationCount: pendingMutationCount,
        proofLevel: proofLevel,
        errorMessage: errorMessage
      )
    }

    func row(
      event: String,
      ok: Bool = true,
      entityID: String? = nil,
      errorMessage: String? = nil
    ) -> ValidationEvidenceRow<LiveSessionValidationDetails> {
      ValidationEvidenceRow(
        caseID: caseID,
        side: "swift",
        event: event,
        appID: appID,
        entityID: entityID,
        timestampMs: timestamp().milliseconds,
        ok: ok,
        details: details(errorMessage: errorMessage)
      )
    }

    func record(
      event: String,
      ok: Bool = true,
      entityID: String? = nil,
      errorMessage: String? = nil
    ) throws {
      let evidenceRow = row(
        event: event,
        ok: ok,
        entityID: entityID,
        errorMessage: errorMessage
      )
      evidence.append(evidenceRow)
      try onEvidence?(evidenceRow)
    }

    func refreshWithRuntimeAttributes(_ refreshOK: InstantLiveRefreshOK) -> InstantLiveRefreshOK {
      guard refreshOK.attrs.isEmpty, !initAttrs.isEmpty else { return refreshOK }
      return InstantLiveRefreshOK(
        clientEventID: refreshOK.clientEventID,
        processedTransactionID: refreshOK.processedTransactionID,
        attrs: initAttrs,
        computations: refreshOK.computations
      )
    }

    func applyRefreshToRuntime(_ refreshOK: InstantLiveRefreshOK) async throws {
      guard let runtime else { return }
      let applied = try await runtime.applyLiveRefresh(refreshWithRuntimeAttributes(refreshOK))
      appliedRefreshCount += 1
      appliedRefreshTransactionIDs.append(applied.transaction.id)
      appliedInsertedTripleCount += applied.insertedTripleCount
      appliedMergedAttributeCount += applied.mergedAttributeCount
      if let runtimeProjection {
        let projection = try await runtimeProjection(runtime)
        cachedEntityIDs = projection.cachedEntityIDs
        cachedTodoTexts = projection.cachedTodoTexts
        observedSnapshot = projection.observedSnapshot
      } else {
        let todos = try await TodoExample.decode(runtime.query(TodoExample.query))
        cachedEntityIDs = todos.map(\.id)
        cachedTodoTexts = todos.map(\.text)
      }
      pendingMutationCount = await runtime.pendingMutations().count
    }

    var session: InstantLiveWebSocketSession?
    do {
      try record(event: "session-url")
      if applyRefreshesToRuntime {
        let cacheURL = try runtimePersistenceURL ?? Self.temporaryRuntimeCacheURL(
          appID: appID,
          caseID: caseID
        )
        runtimeCachePath = cacheURL.path
        runtime = try await InstantRuntime.bootstrap(
          configuration: InstantRuntimeConfiguration(
            appID: appID,
            persistenceURL: cacheURL,
            initialAttributes: TodoExample.attributes
          )
        )
      }

      let openedSession = try await liveTransport.connect(request)
      session = openedSession

      let initClientEventID = makeID()
      clientEventIDs.append(initClientEventID)
      let initMessage = request.initMessage(clientEventID: initClientEventID)
      try await instantLiveWithTimeout(
        operation: "validate Instant live init",
        timeoutMilliseconds: eventTimeoutMilliseconds
      ) {
        try await openedSession.send(initMessage)
      }
      sentOps.append(initMessage.op)
      try record(event: "send-init")

      let initEnvelope = try await instantLiveWithTimeout(
        operation: "validate Instant live init",
        timeoutMilliseconds: eventTimeoutMilliseconds
      ) {
        try await openedSession.receive()
      }
      let initEvent = InstantLiveServerEvent(message: initEnvelope)
      receivedOps.append(initEvent.op)
      switch initEvent {
      case let .initOK(initOK):
        guard !initOK.sessionID.isEmpty else {
          throw validationError(
            operation: "validate Instant live init",
            message: "Expected init-ok to include a session-id."
          )
        }
        sessionID = initOK.sessionID
        attrCount = initOK.attrs.count
        initAttrs = initOK.attrs
        try record(event: "receive-init-ok")

      case let .error(error):
        try record(event: "receive-error", ok: false, errorMessage: error.message)
        throw validationError(
          operation: "validate Instant live init",
          message: "Instant live init returned an error: \(error.message)"
        )

      default:
        throw validationError(
          operation: "validate Instant live init",
          message: "Expected init-ok, received \(initEvent.op)."
        )
      }

      let queryClientEventID = makeID()
      clientEventIDs.append(queryClientEventID)
      let addQuery = InstantLiveMessage.addQuery(query, clientEventID: queryClientEventID)
      try await instantLiveWithTimeout(
        operation: "validate Instant live query",
        timeoutMilliseconds: eventTimeoutMilliseconds
      ) {
        try await openedSession.send(addQuery)
      }
      sentOps.append(addQuery.op)
      try record(event: "send-add-query")

      var receivedQueryEvent = false
      for _ in 0..<maxServerEvents {
        let envelope = try await instantLiveWithTimeout(
          operation: "validate Instant live query",
          timeoutMilliseconds: eventTimeoutMilliseconds
        ) {
          try await openedSession.receive()
        }
        let event = InstantLiveServerEvent(message: envelope)
        receivedOps.append(event.op)
        switch event {
        case let .addQueryOK(queryOK), let .addQueryExists(queryOK):
          queryResultCount = queryOK.result.count
          processedTransactionID = queryOK.processedTransactionID
          try record(event: "receive-query")
          receivedQueryEvent = true

        case let .refreshOK(refreshOK):
          refreshComputationCount = refreshOK.computations.count
          processedTransactionID = refreshOK.processedTransactionID
          try record(event: "receive-refresh")
          receivedQueryEvent = true

        case let .error(error):
          try record(event: "receive-error", ok: false, errorMessage: error.message)
          throw validationError(
            operation: "validate Instant live query",
            message: "Instant live query returned an error: \(error.message)"
          )

        default:
          continue
        }

        if receivedQueryEvent {
          break
        }
      }

      guard receivedQueryEvent else {
        throw validationError(
          operation: "validate Instant live query",
          message:
            "Expected add-query-ok, add-query-exists, or refresh-ok within \(maxServerEvents) server event(s)."
        )
      }

      if let expectedExternalRefreshEntityID {
        var receivedExternalRefresh = false
        for _ in 0..<(maxServerEvents * 4) {
          let envelope = try await instantLiveWithTimeout(
            operation: "validate Instant live external refresh",
            timeoutMilliseconds: eventTimeoutMilliseconds
          ) {
            try await openedSession.receive()
          }
          let event = InstantLiveServerEvent(message: envelope)
          receivedOps.append(event.op)
          switch event {
          case let .refreshOK(refreshOK):
            refreshComputationCount = refreshOK.computations.count
            processedTransactionID = refreshOK.processedTransactionID
            if refreshOK.computations.containsResultEntityID(expectedExternalRefreshEntityID) {
              try await applyRefreshToRuntime(refreshOK)
              if runtime != nil, !cachedEntityIDs.contains(expectedExternalRefreshEntityID) {
                throw validationError(
                  operation: "validate Instant live external refresh",
                  message:
                    "Expected applied refresh-ok to cache entity id '\(expectedExternalRefreshEntityID)'."
                )
              }
              observedEntityID = expectedExternalRefreshEntityID
              try record(
                event: "receive-external-refresh",
                entityID: expectedExternalRefreshEntityID
              )
              receivedExternalRefresh = true
            }

          case let .error(error):
            try record(event: "receive-error", ok: false, errorMessage: error.message)
            throw validationError(
              operation: "validate Instant live external refresh",
              message: "Instant live external refresh returned an error: \(error.message)"
            )

          default:
            continue
          }

          if receivedExternalRefresh {
            break
          }
        }

        guard receivedExternalRefresh else {
          throw validationError(
            operation: "validate Instant live external refresh",
            message:
              "Expected refresh-ok containing entity id '\(expectedExternalRefreshEntityID)' within \(maxServerEvents * 4) server event(s)."
          )
        }
      }

      if includeTransaction {
        let transactClientEventID = makeID()
        clientEventIDs.append(transactClientEventID)
        let resolvedTransactionSteps = resolveTransactionAttributeIDs
          ? try InstantLiveMutationEncoder.resolveAttributeIDs(
            in: transactionSteps,
            attrs: initAttrs
          )
          : transactionSteps
        let transact = try InstantLiveMessage.transact(
          resolvedTransactionSteps,
          clientEventID: transactClientEventID
        )
        try await instantLiveWithTimeout(
          operation: "validate Instant live transaction",
          timeoutMilliseconds: eventTimeoutMilliseconds
        ) {
          try await openedSession.send(transact)
        }
        sentOps.append(transact.op)
        try record(event: "send-transact")

        var receivedTransactOK = false
        var receivedTransactionRefresh = false
        var pendingRefreshOK: InstantLiveRefreshOK?

        func acceptRefresh(_ refreshOK: InstantLiveRefreshOK) throws -> Bool {
          guard let transactionID,
            refreshOK.processedTransactionID == transactionID
          else {
            return false
          }
          refreshComputationCount = refreshOK.computations.count
          processedTransactionID = refreshOK.processedTransactionID
          try record(event: "receive-transaction-refresh")
          receivedTransactionRefresh = true
          return true
        }

        for _ in 0..<(maxServerEvents * 2) {
          let envelope = try await instantLiveWithTimeout(
            operation: "validate Instant live transaction",
            timeoutMilliseconds: eventTimeoutMilliseconds
          ) {
            try await openedSession.receive()
          }
          let event = InstantLiveServerEvent(message: envelope)
          receivedOps.append(event.op)
          switch event {
          case let .transactOK(transactOK):
            transactionID = transactOK.transactionID
            transactionISN = transactOK.isn
            try record(event: "receive-transact-ok")
            receivedTransactOK = true
            if let pendingRefreshOK {
              _ = try acceptRefresh(pendingRefreshOK)
            }

          case let .refreshOK(refreshOK):
            if !(try acceptRefresh(refreshOK)) {
              pendingRefreshOK = refreshOK
            }

          case let .error(error):
            try record(event: "receive-error", ok: false, errorMessage: error.message)
            throw validationError(
              operation: "validate Instant live transaction",
              message: "Instant live transaction returned an error: \(error.message)"
            )

          default:
            continue
          }

          if receivedTransactOK && receivedTransactionRefresh {
            break
          }
        }

        guard receivedTransactOK else {
          throw validationError(
            operation: "validate Instant live transaction",
            message:
              "Expected transact-ok within \(maxServerEvents * 2) server event(s)."
          )
        }
        guard receivedTransactionRefresh else {
          throw validationError(
            operation: "validate Instant live transaction",
            message:
              "Expected refresh-ok with processed-tx-id matching the transaction id within \(maxServerEvents * 2) server event(s)."
          )
        }
      }

      await openedSession.close()
      session = nil
      return LiveSessionValidationResult(
        appID: appID,
        websocketURL: websocketURL,
        evidence: evidence
      )
    } catch {
      if let session {
        await session.close()
      }
      if !evidence.contains(where: { !$0.ok }) {
        try? record(event: "failed", ok: false, errorMessage: String(describing: error))
      }
      throw LiveSessionValidationFailure(error: error, evidence: evidence)
    }
  }

  private static func validationError(operation: String, message: String) -> InstantError {
    InstantError(
      code: .validationFailed,
      operation: operation,
      message: message,
      recovery: "Inspect the Instant live WebSocket protocol smoke evidence."
    )
  }

  private static func temporaryRuntimeCacheURL(appID: String, caseID: String) throws -> URL {
    let safeAppID = appID.replacingUnsafePathCharacters()
    let safeCaseID = caseID.replacingUnsafePathCharacters()
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "InstantLiveSessionValidation-\(safeCaseID)-\(safeAppID)-\(UUID().uuidString)",
        isDirectory: true
      )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("state.sqlite")
  }

}

private extension String {
  func replacingUnsafePathCharacters() -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
    return unicodeScalars.map { scalar in
      allowed.contains(scalar) ? String(scalar) : "-"
    }
    .joined()
  }
}

private extension Array where Element == InstantLiveJSONValue {
  func containsResultEntityID(_ entityID: String) -> Bool {
    contains { computation in
      guard let object = computation.objectValue else { return false }
      for key in ["instaql-result", "result", "data"] {
        if object[key]?.containsEntityID(entityID) == true {
          return true
        }
      }
      return false
    }
  }
}

private extension InstantLiveJSONValue {
  func containsEntityID(_ entityID: String) -> Bool {
    switch self {
    case .null, .bool, .number:
      false

    case let .string(value):
      value == entityID

    case let .array(values):
      values.contains { $0.containsEntityID(entityID) }

    case let .object(values):
      values.values.contains { $0.containsEntityID(entityID) }
    }
  }
}
