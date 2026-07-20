import Dependencies
import Foundation
import InstantSwiftData

public struct InstantStreamsV3LiveValidationDetails: Codable, Equatable, Sendable {
  public var swiftUserID: String
  public var typeScriptClientID: String
  public var typeScriptStreamID: String
  public var typeScriptContent: String
  public var typeScriptByteCount: Int64
  public var swiftClientID: String
  public var swiftStreamID: String
  public var swiftContent: String
  public var swiftByteCount: Int64
  public var connectionState: String
}

public enum InstantStreamsV3LiveValidation {
  public static func run(
    appID: String,
    apiURI: URL,
    websocketURI: URL,
    refreshToken: String,
    expectedSwiftUserID: String,
    typeScriptClientID: String,
    swiftClientID: String,
    persistenceURL: URL? = nil,
    onReaderReady: @escaping @Sendable () -> Void = {},
    onSwiftWriterCreated: @escaping @Sendable (String) -> Void = { _ in }
  ) async throws -> ValidationEvidenceRow<InstantStreamsV3LiveValidationDetails> {
    let persistenceURL =
      persistenceURL
      ?? FileManager.default.temporaryDirectory
      .appendingPathComponent("instant-streams-v3-live-\(UUID().uuidString).sqlite")
    let client = try await withDependencies {
      $0.context = .live
      $0.instantLiveTransport = .live
      try await $0.bootstrapInstantSwiftData(
        appID: appID,
        apiURI: apiURI,
        websocketURI: websocketURI,
        persistenceURL: persistenceURL,
        context: .live
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var client
      return client
    }

    let session = try await client.signInWithRefreshToken(
      refreshToken,
      userID: "untrusted-streams-user"
    )
    guard session.userID == expectedSwiftUserID else {
      throw streamsValidationFailure(
        operation: "validate streams auth",
        message: "Server-verified Swift user did not match the expected streams user."
      )
    }
    _ = try await client.connect()

    let typeScriptSnapshots = try await client.subscribeStreamContent(clientID: typeScriptClientID)
    defer { typeScriptSnapshots.cancel() }
    onReaderReady()
    let typeScriptRead = try await streamsWithTimeout(operation: "read TypeScript stream in Swift")
    {
      for try await snapshot in typeScriptSnapshots {
        try Task.checkCancellation()
        if snapshot.done { return snapshot }
      }
      throw streamsValidationFailure(
        operation: "read TypeScript stream in Swift",
        message: "The TypeScript stream ended without a closed snapshot."
      )
    }
    typeScriptSnapshots.cancel()

    let swiftMetadata = try await client.createStream(clientID: swiftClientID)
    onSwiftWriterCreated(swiftMetadata.id)
    var offset: Int64 = 0
    for chunk in ["swift ", "to typescript 🚀"] {
      let append = try await client.appendStreamContent(
        streamID: swiftMetadata.id,
        content: chunk,
        expectedOffset: offset
      )
      offset += append.chunk.byteCount
    }
    let closed = try await client.closeStream(streamID: swiftMetadata.id)
    let swiftRead = try await client.streamContent(streamID: swiftMetadata.id)
    let status = try await client.connectionStatus()
    _ = try await client.closeConnection()

    return ValidationEvidenceRow(
      caseID: "validation.live.streams-v3",
      side: "swift",
      event: "bidirectional-streams-observed",
      appID: appID,
      entityID: swiftMetadata.id,
      timestampMs: Int64((Date().timeIntervalSince1970 * 1_000).rounded()),
      ok: true,
      details: InstantStreamsV3LiveValidationDetails(
        swiftUserID: session.userID,
        typeScriptClientID: typeScriptClientID,
        typeScriptStreamID: typeScriptRead.metadata.id,
        typeScriptContent: typeScriptRead.content,
        typeScriptByteCount: typeScriptRead.byteCount,
        swiftClientID: swiftClientID,
        swiftStreamID: swiftMetadata.id,
        swiftContent: swiftRead.content,
        swiftByteCount: closed.size ?? swiftRead.byteCount,
        connectionState: status.state.rawValue
      )
    )
  }
}

private func streamsWithTimeout<Value: Sendable>(
  operation: String,
  timeoutMilliseconds: UInt64 = 30_000,
  _ body: @escaping @Sendable () async throws -> Value
) async throws -> Value {
  try await withThrowingTaskGroup(of: Value.self) { group in
    group.addTask { try await body() }
    group.addTask {
      try await Task.sleep(nanoseconds: timeoutMilliseconds * 1_000_000)
      throw streamsValidationFailure(operation: operation, message: "Timed out.")
    }
    let value = try await group.next()!
    group.cancelAll()
    return value
  }
}

private func streamsValidationFailure(operation: String, message: String) -> InstantError {
  InstantError(
    code: .networkFailed,
    operation: operation,
    message: message,
    recovery: "Inspect the canonical stream permissions, writer, and reader events."
  )
}
