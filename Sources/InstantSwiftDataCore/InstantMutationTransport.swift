import Foundation

public struct InstantMutationTransportRequest: Hashable, Encodable, Sendable {
  public var appID: String
  public var apiURI: URL
  public var websocketURI: URL
  public var mutations: [InstantTransportMutation]

  public init(
    appID: String,
    apiURI: URL,
    websocketURI: URL,
    mutations: [InstantTransportMutation]
  ) {
    self.appID = appID
    self.apiURI = apiURI
    self.websocketURI = websocketURI
    self.mutations = mutations
  }
}

public struct InstantMutationTransportResponse: Hashable, Codable, Sendable {
  public var results: [InstantMutationTransportResult]

  public init(results: [InstantMutationTransportResult]) {
    self.results = results
  }
}

public struct InstantMutationTransportResult: Hashable, Codable, Sendable, Identifiable {
  public enum Outcome: String, Codable, Sendable {
    case confirmed
    case failed
  }

  public enum Acceptance: String, Codable, Sendable {
    case serverAccepted
  }

  public var id: String { mutationID }
  public var mutationID: String
  public var outcome: Outcome
  public var acceptance: Acceptance?
  public var message: String?

  public init(
    mutationID: String,
    outcome: Outcome,
    acceptance: Acceptance? = nil,
    message: String? = nil
  ) {
    self.mutationID = mutationID
    self.outcome = outcome
    self.acceptance = acceptance
    self.message = message
  }
}

public struct InstantMutationTransportFlushResult: Hashable, Encodable, Sendable {
  public var request: InstantMutationTransportRequest
  public var results: [InstantMutationTransportResult]
  public var confirmed: [PendingMutation]
  public var failed: [PendingMutation]
  public var pendingMutationCount: Int
  public var mutationCount: Int

  public init(
    request: InstantMutationTransportRequest,
    results: [InstantMutationTransportResult],
    confirmed: [PendingMutation],
    failed: [PendingMutation],
    pendingMutationCount: Int,
    mutationCount: Int
  ) {
    self.request = request
    self.results = results
    self.confirmed = confirmed
    self.failed = failed
    self.pendingMutationCount = pendingMutationCount
    self.mutationCount = mutationCount
  }
}

// SAFETY: `lock` linearizes one run against the one permitted synchronous
// abort, and protects taking/nilling both `@Sendable` closures. Neither closure
// is invoked while the lock is held.
private final class InstantAbortableOperationState<Value: Sendable>: @unchecked Sendable {
  private let lock = NSLock()
  private var didStart = false
  private var isAborted = false
  private var operation: (@Sendable () async throws -> Value)?
  private var abortOperation: (@Sendable () -> Void)?

  init(
    operation: @escaping @Sendable () async throws -> Value,
    abort: @escaping @Sendable () -> Void
  ) {
    self.operation = operation
    self.abortOperation = abort
  }

  func takeOperationToRun() -> (@Sendable () async throws -> Value)? {
    lock.withLock {
      guard !isAborted, !didStart, let operation else { return nil }
      didStart = true
      self.operation = nil
      return operation
    }
  }

  func finishRun() {
    lock.withLock { abortOperation = nil }
  }

  func abort() {
    let operation = lock.withLock { () -> (@Sendable () -> Void)? in
      guard !isAborted else { return nil }
      isAborted = true
      self.operation = nil
      defer { abortOperation = nil }
      return abortOperation
    }
    operation?()
  }
}

/// One asynchronous operation paired with its prompt cancellation boundary.
///
/// `abort()` is synchronous and idempotent across every copy of the value. It
/// requests that the exact external operation stop; callers must still await
/// `run()` to learn when all resources owned by that operation are released.
public struct InstantAbortableOperation<Value: Sendable>: Sendable {
  private let state: InstantAbortableOperationState<Value>

  public init(
    run operation: @escaping @Sendable () async throws -> Value,
    abort: @escaping @Sendable () -> Void
  ) {
    self.state = InstantAbortableOperationState(
      operation: operation,
      abort: abort
    )
  }

  public func run() async throws -> Value {
    guard let operation = state.takeOperationToRun() else { throw CancellationError() }
    defer { state.finishRun() }
    return try await operation()
  }

  public func abort() {
    state.abort()
  }
}

public typealias InstantMutationTransportOperation =
  InstantAbortableOperation<InstantMutationTransportResponse>

public struct InstantMutationTransportClient: Sendable {
  public var send:
    @Sendable (InstantMutationTransportRequest) async throws -> InstantMutationTransportResponse
  {
    didSet {
      let send = self.send
      prepareOperation = Self.cooperativeOperation(send: send)
    }
  }
  var prepareOperation:
    @Sendable (InstantMutationTransportRequest) -> InstantMutationTransportOperation

  public init(
    send:
      @escaping @Sendable (InstantMutationTransportRequest) async throws
      -> InstantMutationTransportResponse
  ) {
    self.send = send
    self.prepareOperation = Self.cooperativeOperation(send: send)
  }

  private init(
    prepareOperation:
      @escaping @Sendable (InstantMutationTransportRequest)
      -> InstantMutationTransportOperation
  ) {
    self.prepareOperation = prepareOperation
    self.send = { request in
      try await prepareOperation(request).run()
    }
  }

  private static func cooperativeOperation(
    send:
      @escaping @Sendable (InstantMutationTransportRequest) async throws
      -> InstantMutationTransportResponse
  ) -> @Sendable (InstantMutationTransportRequest) -> InstantMutationTransportOperation {
    { request in
      InstantMutationTransportOperation(
        run: { try await send(request) },
        // Compatibility clients predate a synchronous external abort handle.
        // Their operation remains cancellation-cooperative through its Task.
        abort: {}
      )
    }
  }
}

extension InstantMutationTransportClient {
  /// Builds a transport that exposes a fresh abortable operation per request.
  public static func preparedOperations(
    _ prepareOperation:
      @escaping @Sendable (InstantMutationTransportRequest)
      -> InstantMutationTransportOperation
  ) -> Self {
    Self(prepareOperation: prepareOperation)
  }

  public static let local = Self.preparedOperations { request in
    InstantMutationTransportOperation(
      run: {
        InstantMutationTransportResponse(
          results: request.mutations.map { mutation in
            InstantMutationTransportResult(
              mutationID: mutation.mutationID,
              outcome: .confirmed
            )
          }
        )
      },
      // The local operation has no external resource and completes promptly.
      abort: {}
    )
  }
}
