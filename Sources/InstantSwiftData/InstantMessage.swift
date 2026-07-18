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
        let lifecycle = try await runtime?.observeMutationLifecycle(id: transactionID)
        let mutations = prepared.mutations
        _ = try await transact(id: transactionID) {
          for mutation in mutations {
            mutation
          }
        }
        await onOptimisticCommit(prepared.change)

        guard let lifecycle else { return }
        for await event in lifecycle {
          try Task.checkCancellation()
          switch event {
          case .waiting:
            continue
          case .serverAccepted:
            await onServerAccepted(prepared.change)
            return
          case let .failed(mutation):
            await onFailure(
              InstantError(
                code: .permissionRejected,
                operation: "send Instant message",
                localID: mutation.id,
                serverEventID: mutation.id,
                message: mutation.failureMessage ?? "The Instant server rejected the mutation.",
                recovery: "Inspect the deployed schema and permissions, then retry the action."
              )
            )
            return
          }
        }
      } catch is CancellationError {
      } catch let error as InstantError {
        await onFailure(error)
      } catch {
        await onFailure(
          InstantError(
            code: .implementationFailed,
            operation: "send Instant message",
            message: String(describing: error),
            recovery: "Inspect the message preparation and typed mutation implementation."
          )
        )
      }
    }
  }
}
