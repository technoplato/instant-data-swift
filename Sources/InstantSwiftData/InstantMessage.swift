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

extension InstantSwiftDataClient {
  @discardableResult
  public func send<Message: InstantMessage>(
    _ message: Message,
    onOptimisticCommit: @escaping @MainActor @Sendable (borrowing Message.Change) -> Void = { _ in },
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
          case let .failed(mutation):
            let error = InstantError(
              code: .permissionRejected,
              operation: "send Instant message",
              localID: mutation.id,
              serverEventID: mutation.id,
              message: mutation.failureMessage ?? "The Instant server rejected the mutation.",
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
