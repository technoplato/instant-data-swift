import Foundation

public enum InstantMutationLifecycleEvent: Hashable, Sendable {
  case waiting
  case serverAccepted(PendingMutation)
  case failed(PendingMutation)
}
