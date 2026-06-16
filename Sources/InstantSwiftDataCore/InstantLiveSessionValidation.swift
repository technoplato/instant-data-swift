import Foundation

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

  public static func run(
    appID: String = "live-session-validation",
    websocketURI: URL = InstantRuntimeConfiguration.defaultWebSocketURI,
    refreshToken: String? = nil,
    adminToken: String? = nil,
    query: InstantLiveJSONValue = Self.defaultQuery,
    liveTransport: InstantLiveTransportClient = .local,
    proofLevel: String = "local-protocol",
    timestamp: @escaping @Sendable () -> InstantTimestamp = {
      InstantTimestamp(milliseconds: Int64((Date().timeIntervalSince1970 * 1000).rounded()))
    },
    makeID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() },
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
    var evidence: [ValidationEvidenceRow<LiveSessionValidationDetails>] = []

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
        proofLevel: proofLevel,
        errorMessage: errorMessage
      )
    }

    func row(
      event: String,
      ok: Bool = true,
      errorMessage: String? = nil
    ) -> ValidationEvidenceRow<LiveSessionValidationDetails> {
      ValidationEvidenceRow(
        caseID: "validation.live.session",
        side: "swift",
        event: event,
        appID: appID,
        timestampMs: timestamp().milliseconds,
        ok: ok,
        details: details(errorMessage: errorMessage)
      )
    }

    var session: InstantLiveWebSocketSession?
    do {
      evidence.append(row(event: "session-url"))
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
      evidence.append(row(event: "send-init"))

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
        evidence.append(row(event: "receive-init-ok"))

      case let .error(error):
        evidence.append(row(event: "receive-error", ok: false, errorMessage: error.message))
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
      evidence.append(row(event: "send-add-query"))

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
          evidence.append(row(event: "receive-query"))
          receivedQueryEvent = true

        case let .refreshOK(refreshOK):
          refreshComputationCount = refreshOK.computations.count
          processedTransactionID = refreshOK.processedTransactionID
          evidence.append(row(event: "receive-refresh"))
          receivedQueryEvent = true

        case let .error(error):
          evidence.append(row(event: "receive-error", ok: false, errorMessage: error.message))
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
        evidence.append(row(event: "failed", ok: false, errorMessage: String(describing: error)))
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
}
