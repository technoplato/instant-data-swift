import Foundation

extension InstantLiveMessage {
  static func subscribeStream(
    clientID: String? = nil,
    streamID: String? = nil,
    offset: Int64 = 0,
    ruleParams: InstantLiveJSONValue? = nil,
    clientEventID: String
  ) throws -> Self {
    let normalizedClientID = clientID?.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedStreamID = streamID?.trimmingCharacters(in: .whitespacesAndNewlines)
    guard normalizedClientID?.isEmpty == false || normalizedStreamID?.isEmpty == false else {
      throw InstantError(
        code: .validationFailed,
        operation: "subscribe to Instant stream",
        message: "A client ID or stream ID is required.",
        recovery: "Provide clientID or streamID when creating the stream reader."
      )
    }
    guard offset >= 0 else {
      throw InstantError(
        code: .validationFailed,
        operation: "subscribe to Instant stream",
        path: "offset",
        message: "The stream byte offset cannot be negative.",
        recovery: "Use zero to read from the beginning or a positive byte offset to resume."
      )
    }

    var fields: [String: InstantLiveJSONValue] = [:]
    if let normalizedStreamID, !normalizedStreamID.isEmpty {
      fields["stream-id"] = .string(normalizedStreamID)
    }
    if let normalizedClientID, !normalizedClientID.isEmpty {
      fields["client-id"] = .string(normalizedClientID)
    }
    if offset != 0 {
      fields["offset"] = .number(Double(offset))
    }
    if let ruleParams {
      fields["rule-params"] = ruleParams
    }
    return Self(op: "subscribe-stream", clientEventID: clientEventID, fields: fields)
  }

  static func unsubscribeStream(
    subscriptionEventID: String,
    clientEventID: String
  ) -> Self {
    Self(
      op: "unsubscribe-stream",
      clientEventID: clientEventID,
      fields: ["subscribe-event-id": .string(subscriptionEventID)]
    )
  }
}

actor InstantLiveStreamReaderState {
  private let clientID: String?
  private let streamID: String?
  private let ruleParams: InstantLiveJSONValue?
  private var seenOffset: Int64
  private var currentSubscriptionEventID: String?
  private var pendingFailure: InstantError?

  init(
    clientID: String? = nil,
    streamID: String? = nil,
    initialByteOffset: Int64 = 0,
    ruleParams: InstantLiveJSONValue? = nil
  ) throws {
    _ = try InstantLiveMessage.subscribeStream(
      clientID: clientID,
      streamID: streamID,
      offset: initialByteOffset,
      ruleParams: ruleParams,
      clientEventID: "validation"
    )
    self.clientID = clientID
    self.streamID = streamID
    self.ruleParams = ruleParams
    self.seenOffset = initialByteOffset
  }

  var subscriptionEventID: String? {
    currentSubscriptionEventID
  }

  func recordSeenOffset(_ offset: Int64) {
    guard offset >= seenOffset else { return }
    seenOffset = offset
  }

  func recordSubscriptionEventID(_ eventID: String) {
    currentSubscriptionEventID = eventID
  }

  func subscribeMessage(clientEventID: String) throws -> InstantLiveMessage {
    try InstantLiveMessage.subscribeStream(
      clientID: clientID,
      streamID: streamID,
      offset: seenOffset,
      ruleParams: ruleParams,
      clientEventID: clientEventID
    )
  }

  func reconnect(
    clientEventID: String,
    send: @escaping @Sendable (InstantLiveMessage) async throws -> Void
  ) async throws {
    let message = try subscribeMessage(clientEventID: clientEventID)
    do {
      try await send(message)
      currentSubscriptionEventID = clientEventID
      pendingFailure = nil
    } catch {
      let failure = InstantError(
        code: .networkFailed,
        operation: "resubscribe to Instant stream",
        serverEventID: clientEventID,
        message: error.localizedDescription,
        recovery: "Reconnect the live transport and retry the stream subscription."
      )
      pendingFailure = failure
      throw failure
    }
  }

  func checkForFailure() throws {
    if let pendingFailure {
      throw pendingFailure
    }
  }
}
