import Dependencies
import Foundation

public protocol InstantMessage: Sendable {
  associatedtype Change: Sendable

  func prepare(using client: InstantSwiftDataClient) async throws
    -> InstantPreparedMessage<Change>
}

public struct InstantPreparedMessage<Change: Sendable>: Sendable {
  public let change: Change
  public let mutations: [InstantMutation]

  public init(
    change: Change,
    @InstantMutationBuilder mutations: @Sendable () throws -> [InstantMutation]
  ) rethrows {
    self.change = change
    self.mutations = try mutations()
  }
}

public enum InstantMessageFailureDisposition: Hashable, Sendable {
  case retainForRetry
  case discard
}

/// Change payload for ``InstantMutationBatch`` (bulk `transact` via `send`).
public struct InstantMutationBatchChange: Hashable, Sendable {
  public var mutationCount: Int

  public init(mutationCount: Int) {
    self.mutationCount = mutationCount
  }
}

/// Library-level bulk mutation message — Instant’s `db.transact([...])` with
/// `send` lifecycle callbacks (`onOptimisticCommit` / `onServerAccepted` /
/// `onFailure`) without inventing an app-specific `InstantMessage` type.
///
/// ```swift
/// db.send(
///   InstantMutationBatch(Todo.delete(ids: todos.map(\.id))),
///   onOptimisticCommit: { ... },
///   onServerAccepted: { ... },
///   onFailure: { ... }
/// )
/// ```
public struct InstantMutationBatch: InstantMessage {
  public var mutations: [InstantMutation]

  public init(_ mutations: [InstantMutation]) {
    self.mutations = mutations
  }

  public func prepare(using client: InstantSwiftDataClient) async throws
    -> InstantPreparedMessage<InstantMutationBatchChange>
  {
    _ = client
    let mutations = self.mutations
    guard !mutations.isEmpty else {
      throw InstantError(
        code: .validationFailed,
        operation: "prepare InstantMutationBatch",
        message: "Cannot send an empty mutation batch.",
        recovery: "Pass at least one InstantMutation."
      )
    }
    return InstantPreparedMessage(
      change: InstantMutationBatchChange(mutationCount: mutations.count)
    ) {
      for mutation in mutations {
        mutation
      }
    }
  }
}

extension InstantSwiftDataClient {
  /// Convenience for ``InstantMutationBatch`` + standard `send` callbacks.
  @discardableResult
  public func send(
    mutations: [InstantMutation],
    onOptimisticCommit:
      @escaping @MainActor @Sendable (borrowing InstantMutationBatchChange) -> Void = { _ in },
    onServerAccepted:
      @escaping @MainActor @Sendable (borrowing InstantMutationBatchChange) -> Void = { _ in },
    onFailure: @escaping @MainActor @Sendable (InstantError) -> Void = { _ in }
  ) -> Task<Void, Never> {
    send(
      InstantMutationBatch(mutations),
      onOptimisticCommit: onOptimisticCommit,
      onServerAccepted: onServerAccepted,
      onFailure: onFailure
    )
  }
}

extension InstantSwiftDataClient {
  /// Sends one typed message and returns its change only after Instant accepts the mutation.
  ///
  /// The optimistic write remains durable on timeout or cancellation. Server rejection also
  /// remains retained for retry unless `onServerRejected` explicitly returns `.discard`.
  @available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
  public func sendAwaitingServerAcceptance<Message: InstantMessage>(
    _ message: Message,
    timeout: Duration = .seconds(10),
    onServerRejected:
      @escaping @Sendable (InstantError) async -> InstantMessageFailureDisposition = { _ in
        .retainForRetry
      }
  ) async throws -> Message.Change {
    guard timeout >= .zero else {
      throw InstantError(
        code: .validationFailed,
        operation: "send Instant message awaiting server acceptance",
        message: "The server acknowledgement timeout must be greater than or equal to zero.",
        recovery: "Pass a non-negative timeout."
      )
    }
    guard let runtime else {
      throw InstantError(
        code: .implementationFailed,
        operation: "send Instant message awaiting server acceptance",
        message: "This Instant Swift Data client has no runtime lifecycle.",
        recovery: "Use a runtime-backed client when server acknowledgement is required."
      )
    }

    let prepared = try await message.prepare(using: self)
    guard !prepared.mutations.isEmpty else {
      throw InstantError(
        code: .validationFailed,
        operation: "send Instant message awaiting server acceptance",
        message: "The prepared message did not contain any mutations.",
        recovery: "Return at least one typed mutation from InstantMessage.prepare(using:)."
      )
    }

    let transactionID = runtime.configuration.makeID()
    return try await runtime.withAutomaticMutationRetrySuspended(id: transactionID) {
      let lifecycle = try await runtime.observeMutationLifecycle(id: transactionID)
      let mutations = prepared.mutations
      _ = try await transact(id: transactionID) {
        for mutation in mutations {
          mutation
        }
      }

      let event = try await awaitInstantMessageTerminalLifecycle(
        lifecycle,
        transactionID: transactionID,
        timeout: timeout
      )
      switch event {
      case .serverAccepted:
        return prepared.change

      case .failed(let mutation):
        var error = mutation.rejectionError(
          operation: "send Instant message awaiting server acceptance",
          recovery: "Inspect the deployed schema and permissions, then retry the action."
        )
        if await onServerRejected(error) == .discard {
          do {
            _ = try await runtime.discardFailedMutation(
              id: mutation.id,
              allowingActiveDisposition: true
            )
            error.localMutationDisposition = .discarded
          } catch var discardError as InstantError {
            discardError.localMutationDisposition = .retainedUnknown
            throw discardError
          }
        }
        throw error

      case .waiting:
        throw InstantError(
          code: .implementationFailed,
          operation: "send Instant message awaiting server acceptance",
          localID: transactionID,
          message: "The mutation lifecycle returned a non-terminal waiting event.",
          recovery: "Inspect the mutation lifecycle observer implementation."
        )
      }
    }
  }

  @discardableResult
  public func send<Message: InstantMessage>(
    _ message: Message,
    onOptimisticCommit:
      @escaping @MainActor @Sendable (borrowing Message.Change) -> Void = { _ in },
    onServerAccepted: @escaping @MainActor @Sendable (borrowing Message.Change) -> Void = { _ in },
    onFailure: @escaping @MainActor @Sendable (InstantError) -> Void = { _ in }
  ) -> Task<Void, Never> {
    Task {
      let messageType = String(reflecting: Message.self)
      InstantDiagnostics.shared.record(
        .info,
        subsystem: "instant-swift-data",
        category: "message",
        event: "message-send.started",
        message: "Started sending a typed Instant message.",
        metadata: ["messageType": messageType]
      )
      do {
        let prepared = try await message.prepare(using: self)
        guard !prepared.mutations.isEmpty else {
          throw InstantError(
            code: .validationFailed,
            operation: "send Instant message",
            message: "The prepared message did not contain any mutations.",
            recovery: "Return at least one typed mutation from InstantMessage.prepare(using:)."
          )
        }

        @Dependency(\.uuid) var uuid
        let transactionID =
          runtime?.configuration.makeID()
          ?? uuid().uuidString.lowercased()
        InstantDiagnostics.shared.record(
          .debug,
          subsystem: "instant-swift-data",
          category: "message",
          event: "message-send.prepared",
          message: "Prepared a typed Instant message.",
          metadata: [
            "messageType": messageType,
            "mutationCount": String(prepared.mutations.count),
            "hasRuntimeLifecycle": String(runtime != nil),
          ],
          correlationID: transactionID
        )
        let lifecycle = try await runtime?.observeMutationLifecycle(id: transactionID)
        let mutations = prepared.mutations
        _ = try await transact(id: transactionID) {
          for mutation in mutations {
            mutation
          }
        }
        await onOptimisticCommit(prepared.change)
        InstantDiagnostics.shared.record(
          .notice,
          subsystem: "instant-swift-data",
          category: "message",
          event: "message-send.optimistic-commit",
          message: "Typed Instant message committed optimistically.",
          metadata: ["messageType": messageType],
          correlationID: transactionID
        )

        guard let lifecycle else {
          InstantDiagnostics.shared.record(
            .debug,
            subsystem: "instant-swift-data",
            category: "message",
            event: "message-send.finished-without-server-lifecycle",
            message: "Typed Instant message finished without a runtime lifecycle stream.",
            metadata: ["messageType": messageType],
            correlationID: transactionID
          )
          return
        }
        for await event in lifecycle {
          try Task.checkCancellation()
          switch event {
          case .waiting:
            continue
          case .serverAccepted:
            await onServerAccepted(prepared.change)
            InstantDiagnostics.shared.record(
              .notice,
              subsystem: "instant-swift-data",
              category: "message",
              event: "message-send.server-accepted",
              message: "Instant accepted the typed message mutation.",
              metadata: ["messageType": messageType],
              correlationID: transactionID
            )
            return
          case .failed(let mutation):
            let error = mutation.rejectionError(
              operation: "send Instant message",
              recovery: "Inspect the deployed schema and permissions, then retry the action."
            )
            InstantDiagnostics.shared.record(
              error: error,
              subsystem: "instant-swift-data",
              category: "message",
              event: "message-send.server-rejected",
              message: "Instant rejected the typed message mutation.",
              metadata: ["messageType": messageType],
              correlationID: transactionID
            )
            await onFailure(error)
            return
          }
        }
      } catch is CancellationError {
        InstantDiagnostics.shared.record(
          .debug,
          subsystem: "instant-swift-data",
          category: "message",
          event: "message-send.cancelled",
          message: "Typed Instant message send was cancelled.",
          metadata: ["messageType": messageType]
        )
      } catch let error as InstantError {
        InstantDiagnostics.shared.record(
          error: error,
          subsystem: "instant-swift-data",
          category: "message",
          event: "message-send.failed",
          message: "Typed Instant message send failed.",
          metadata: ["messageType": messageType]
        )
        await onFailure(error)
      } catch {
        let wrappedError = InstantError(
          code: .implementationFailed,
          operation: "send Instant message",
          message: String(describing: error),
          recovery: "Inspect the message preparation and typed mutation implementation."
        )
        InstantDiagnostics.shared.record(
          error: wrappedError,
          subsystem: "instant-swift-data",
          category: "message",
          event: "message-send.failed",
          message: "Typed Instant message send failed.",
          metadata: ["messageType": messageType]
        )
        await onFailure(wrappedError)
      }
    }
  }
}

@available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
private func awaitInstantMessageTerminalLifecycle(
  _ lifecycle: AsyncStream<InstantMutationLifecycleEvent>,
  transactionID: String,
  timeout: Duration
) async throws -> InstantMutationLifecycleEvent {
  try await withThrowingTaskGroup(of: InstantMutationLifecycleEvent.self) { group in
    group.addTask {
      for await event in lifecycle {
        try Task.checkCancellation()
        switch event {
        case .waiting:
          continue
        case .serverAccepted, .failed:
          return event
        }
      }
      try Task.checkCancellation()
      throw InstantError(
        code: .implementationFailed,
        operation: "send Instant message awaiting server acceptance",
        localID: transactionID,
        message: "The mutation lifecycle ended before a server result arrived.",
        recovery: "Inspect the runtime lifecycle observer and live connection."
      )
    }
    group.addTask {
      try await ContinuousClock().sleep(for: timeout)
      throw InstantError(
        code: .networkFailed,
        operation: "send Instant message awaiting server acceptance",
        localID: transactionID,
        message: "Timed out waiting for mutation '\(transactionID)' to be accepted by Instant.",
        recovery: "Inspect the live connection and retained outbox mutation before retrying."
      )
    }
    defer { group.cancelAll() }
    guard let event = try await group.next() else {
      throw InstantError(
        code: .implementationFailed,
        operation: "send Instant message awaiting server acceptance",
        localID: transactionID,
        message: "No mutation lifecycle task produced a result.",
        recovery: "Inspect the acknowledgement task group implementation."
      )
    }
    return event
  }
}
