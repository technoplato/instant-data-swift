import Dependencies
import Foundation

public enum InstantSyncPolicy: String, CaseIterable, Hashable, Codable, Sendable, Identifiable {
  case automatic
  case manual
  case offlineOnly
  case readOnly
  case whenAuthenticated

  public var id: Self { self }

  public static var displayCases: [Self] {
    [.automatic, .manual, .offlineOnly, .readOnly, .whenAuthenticated]
  }

  public var title: String {
    switch self {
    case .automatic: "Automatic"
    case .manual: "Manual"
    case .offlineOnly: "Offline only"
    case .readOnly: "Read only"
    case .whenAuthenticated: "When signed in"
    }
  }
}

public enum InstantSyncPhase: String, Hashable, Codable, Sendable {
  case cached
  case connecting
  case connected
  case authenticated
  case reconnecting
  case offline
  case failed

  public var title: String {
    switch self {
    case .cached: "Cached"
    case .connecting: "Connecting"
    case .connected: "Connected"
    case .authenticated: "Online"
    case .reconnecting: "Reconnecting"
    case .offline: "Offline"
    case .failed: "Sync error"
    }
  }
}

public struct InstantSyncFlushStartedEvent: Hashable, Sendable {
  public var pendingCount: Int

  public init(pendingCount: Int) {
    self.pendingCount = pendingCount
  }
}

public struct InstantSyncFlushAcceptedEvent: Hashable, Sendable {
  public var acceptedMutationCount: Int
  public var pendingCount: Int

  public init(acceptedMutationCount: Int, pendingCount: Int) {
    self.acceptedMutationCount = acceptedMutationCount
    self.pendingCount = pendingCount
  }
}

#if canImport(SwiftUI)
  import SwiftUI

  @MainActor
  public final class InstantSyncStatusState: ObservableObject {
    @Published public var policy: InstantSyncPolicy
    @Published public var usesPremiumGate: Bool
    @Published public private(set) var phase: InstantSyncPhase = .cached
    @Published public private(set) var connection: InstantConnectionStatus?
    @Published public private(set) var pendingOutboxCount = 0
    @Published public private(set) var lastRemoteChangeDescription = "No remote changes"
    @Published public private(set) var lastError: InstantError?

    private var hasAuthenticated = false
    private var observationTask: Task<Void, Never>?
    private var activeFlush: Task<Void, Never>?
    private var flushGeneration = 0

    public init(
      policy: InstantSyncPolicy = .automatic,
      usesPremiumGate: Bool = false
    ) {
      self.policy = policy
      self.usesPremiumGate = usesPremiumGate
    }

    public var summary: String {
      if synchronizationBlocker != nil {
        return "Local sync recovery required"
      }
      if phase == .failed, let message = lastError?.message, !message.isEmpty {
        return message
      }
      if phase == .authenticated, pendingOutboxCount > 0 {
        return "\(pendingOutboxCount) pending"
      }
      return phase.title
    }

    /// The local persistence condition preventing synchronization, if any.
    public var synchronizationBlocker: InstantSynchronizationBlocker? {
      connection?.synchronizationBlocker
    }

    public var canFlush: Bool {
      synchronizationBlocker == nil
        && pendingOutboxCount > 0
        && (phase == .authenticated || phase == .connected)
    }

    public func startObservationIfNeeded() {
      @Dependency(\.defaultInstantSwiftData) var client
      startObservationIfNeeded(using: client)
    }

    public func startObservationIfNeeded(using client: InstantSwiftDataClient) {
      guard observationTask == nil else { return }
      observationTask = Task { @MainActor [weak self] in
        do {
          let subscription = try await client.subscribeConnectionStatus()
          for try await status in subscription {
            try Task.checkCancellation()
            self?.apply(status)
          }
        } catch is CancellationError {
        } catch {
          guard let self else { return }
          self.lastError = Self.syncError(error, operation: "observe sync status")
          self.phase = .failed
        }
        self?.observationTask = nil
      }
    }

    public func stopObservation() {
      observationTask?.cancel()
      observationTask = nil
    }

    @discardableResult
    public func flush(
      onStarted: @escaping @MainActor @Sendable (InstantSyncFlushStartedEvent) -> Void = { _ in },
      onAccepted: @escaping @MainActor @Sendable (InstantSyncFlushAcceptedEvent) -> Void = { _ in },
      onFailure: @escaping @MainActor @Sendable (InstantError) -> Void = { _ in }
    ) -> Task<Void, Never> {
      @Dependency(\.defaultInstantSwiftData) var client
      return flush(
        using: client,
        onStarted: onStarted,
        onAccepted: onAccepted,
        onFailure: onFailure
      )
    }

    @discardableResult
    public func flush(
      using client: InstantSwiftDataClient,
      onStarted: @escaping @MainActor @Sendable (InstantSyncFlushStartedEvent) -> Void = { _ in },
      onAccepted: @escaping @MainActor @Sendable (InstantSyncFlushAcceptedEvent) -> Void = { _ in },
      onFailure: @escaping @MainActor @Sendable (InstantError) -> Void = { _ in }
    ) -> Task<Void, Never> {
      activeFlush?.cancel()
      flushGeneration += 1
      let generation = flushGeneration
      let task = Task { @MainActor [weak self] in
        do {
          let pendingCount = await client.pendingMutationCount()
          try Task.checkCancellation()
          guard let self, self.flushGeneration == generation else { return }
          self.pendingOutboxCount = pendingCount
          onStarted(InstantSyncFlushStartedEvent(pendingCount: pendingCount))

          let result = try await client.flushPendingMutations()
          try Task.checkCancellation()
          guard self.flushGeneration == generation else { return }
          self.pendingOutboxCount = result.pendingMutationCount
          self.activeFlush = nil
          onAccepted(
            InstantSyncFlushAcceptedEvent(
              acceptedMutationCount: result.confirmed.count,
              pendingCount: result.pendingMutationCount
            )
          )
        } catch is CancellationError {
          guard let self, self.flushGeneration == generation else { return }
          self.activeFlush = nil
        } catch {
          guard let self, self.flushGeneration == generation else { return }
          let error = Self.syncError(error, operation: "flush sync outbox")
          self.lastError = error
          self.phase = .failed
          self.activeFlush = nil
          onFailure(error)
        }
      }
      activeFlush = task
      return task
    }

    private func apply(_ status: InstantConnectionStatus) {
      connection = status
      pendingOutboxCount = status.pendingMutationCount
      if let transactionID = status.processedTransactionID, !transactionID.isEmpty {
        lastRemoteChangeDescription = transactionID
      }
      if status.synchronizationBlocker != nil {
        lastError = nil
      } else if let message = status.lastErrorMessage, !message.isEmpty {
        lastError = InstantError(
          code: .networkFailed,
          operation: "observe sync status",
          message: message,
          recovery: "Inspect the Instant connection and retry when connectivity returns."
        )
      } else if status.state != .errored {
        lastError = nil
      }

      switch status.state {
      case .connecting:
        phase = .connecting
      case .opened:
        phase = .connected
      case .authenticated:
        hasAuthenticated = true
        phase = .authenticated
      case .closed:
        phase = hasAuthenticated && policy != .offlineOnly ? .reconnecting : .offline
      case .errored:
        phase = .failed
      }
    }

    private static func syncError(_ error: Error, operation: String) -> InstantError {
      if let error = error as? InstantError { return error }
      return InstantError(
        code: .networkFailed,
        operation: operation,
        message: String(describing: error),
        recovery: "Inspect the Instant connection and retry the sync action."
      )
    }
  }

  @dynamicMemberLookup
  @MainActor
  public struct InstantSyncStatusProjection {
    fileprivate let state: InstantSyncStatusState

    public subscript<Value>(
      dynamicMember keyPath: ReferenceWritableKeyPath<InstantSyncStatusState, Value>
    ) -> Binding<Value> {
      Binding(
        get: { state[keyPath: keyPath] },
        set: { state[keyPath: keyPath] = $0 }
      )
    }
  }

  @MainActor
  @propertyWrapper
  public struct InstantSyncStatus: DynamicProperty {
    @StateObject private var state: InstantSyncStatusState

    public init() {
      _state = StateObject(wrappedValue: InstantSyncStatusState())
    }

    public var wrappedValue: InstantSyncStatusState { state }

    public var projectedValue: InstantSyncStatusProjection {
      InstantSyncStatusProjection(state: state)
    }

    public mutating func update() {
      state.startObservationIfNeeded()
    }
  }
#endif
