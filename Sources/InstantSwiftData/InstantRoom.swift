import Dependencies
import Foundation
#if canImport(SwiftUI)
  import Combine
  import SwiftUI
#endif

public protocol InstantRoomTopic: RawRepresentable, Hashable, Sendable
where RawValue == String {}

public protocol InstantRoomSchema: Sendable {
  associatedtype Presence: Codable & Sendable
  associatedtype Topic: InstantRoomTopic
}

private struct InstantRoomState: Sendable {
  var handle: InstantRoomHandle?
  var isJoined = false
  var error: InstantError?
  var generation = 0
}

// SAFETY: every room state read and mutation is serialized by `lock`; SwiftUI
// notifications are delivered on the main executor.
private final class InstantRoomStateStorage: @unchecked Sendable {
  private let lock = NSLock()
  private var state: InstantRoomState

  #if canImport(SwiftUI)
    let objectWillChange = ObservableObjectPublisher()
  #endif

  init(handle: InstantRoomHandle? = nil) {
    self.state = InstantRoomState(handle: handle)
  }

  func read<Value>(_ body: (InstantRoomState) -> Value) -> Value {
    lock.lock()
    defer { lock.unlock() }
    return body(state)
  }

  @discardableResult
  func update<Value>(_ body: (inout InstantRoomState) -> Value) -> Value {
    lock.lock()
    let value = body(&state)
    lock.unlock()
    publishChange()
    return value
  }

  private func publishChange() {
    #if canImport(SwiftUI)
      if Thread.isMainThread {
        objectWillChange.send()
      } else {
        DispatchQueue.main.async { [weak self] in
          self?.objectWillChange.send()
        }
      }
    #endif
  }
}

#if canImport(SwiftUI)
  extension InstantRoomStateStorage: ObservableObject {}
#endif

// SAFETY: replacement and access of the SwiftUI-retained storage are serialized
// by `lock`.
private final class InstantRoomStorageReference: @unchecked Sendable {
  private let lock = NSLock()
  private var storage: InstantRoomStateStorage

  init(_ storage: InstantRoomStateStorage) {
    self.storage = storage
  }

  var value: InstantRoomStateStorage {
    get {
      lock.lock()
      defer { lock.unlock() }
      return storage
    }
    set {
      lock.lock()
      defer { lock.unlock() }
      storage = newValue
    }
  }
}

public struct InstantRoom<Schema: InstantRoomSchema>: Sendable {
  private let storage: InstantRoomStateStorage

  public init(type: String, id: String) {
    self.storage = InstantRoomStateStorage(
      handle: InstantRoomHandle(type: type, id: id)
    )
  }

  fileprivate init(storage: InstantRoomStateStorage) {
    self.storage = storage
  }

  public var handle: InstantRoomHandle? {
    storage.read(\.handle)
  }

  public var type: String? {
    handle?.type
  }

  public var id: String? {
    handle?.id
  }

  public var isJoined: Bool {
    storage.read(\.isJoined)
  }

  public var error: InstantError? {
    storage.read(\.error)
  }
}

extension InstantRoom: Equatable {
  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.handle == rhs.handle
  }
}

extension InstantRoom: Hashable {
  public func hash(into hasher: inout Hasher) {
    hasher.combine(handle)
  }
}

@propertyWrapper
// SAFETY: cross-actor room state is routed through lock-protected storage;
// SwiftUI's StateObject is reconciled only from the main-actor update hook.
public struct Room<Schema: InstantRoomSchema>: @unchecked Sendable {
  private let storageReference: InstantRoomStorageReference

  #if canImport(SwiftUI)
    @StateObject private var storageObserver: InstantRoomStateStorage
  #endif

  private var storage: InstantRoomStateStorage {
    storageReference.value
  }

  public init() {
    let storage = InstantRoomStateStorage()
    self.storageReference = InstantRoomStorageReference(storage)
    #if canImport(SwiftUI)
      self._storageObserver = StateObject(wrappedValue: storage)
    #endif
  }

  public init(wrappedValue: InstantRoom<Schema>) {
    let storage = InstantRoomStateStorage(handle: wrappedValue.handle)
    self.storageReference = InstantRoomStorageReference(storage)
    #if canImport(SwiftUI)
      self._storageObserver = StateObject(wrappedValue: storage)
    #endif
  }

  public var wrappedValue: InstantRoom<Schema> {
    InstantRoom(storage: storage)
  }

  public var projectedValue: Self {
    self
  }

  public func task(_ room: InstantRoom<Schema>) async throws {
    @Dependency(\.defaultInstantSwiftData) var client
    try await task(room, using: client)
  }

  public func task(
    _ room: InstantRoom<Schema>,
    using client: InstantSwiftDataClient
  ) async throws {
    guard let handle = room.handle else {
      let error = InstantError(
        code: .validationFailed,
        operation: "join typed room",
        message: "The Instant room has no type or id.",
        recovery: "Construct InstantRoom with a room type and id before attaching it."
      )
      storage.update {
        $0.error = error
        $0.isJoined = false
      }
      throw error
    }

    let generation = storage.update { state in
      state.generation += 1
      state.handle = handle
      state.isJoined = false
      state.error = nil
      return state.generation
    }

    var didJoin = false
    do {
      _ = try await client.joinRoom(handle)
      didJoin = true
      try Task.checkCancellation()
      storage.update { state in
        guard state.generation == generation else { return }
        state.isJoined = true
        state.error = nil
      }

      try await Task.sleep(nanoseconds: .max)
    } catch is CancellationError {
      if didJoin {
        _ = try? await client.leaveRoom(handle)
      }
      storage.update { state in
        guard state.generation == generation else { return }
        state.isJoined = false
        state.error = nil
      }
      throw CancellationError()
    } catch let error as InstantError {
      storage.update { state in
        guard state.generation == generation else { return }
        state.isJoined = false
        state.error = error
      }
      throw error
    } catch {
      let error = InstantError(
        code: .implementationFailed,
        operation: "join typed room",
        message: String(describing: error),
        recovery: "Inspect the configured InstantSwiftDataClient room operations."
      )
      storage.update { state in
        guard state.generation == generation else { return }
        state.isJoined = false
        state.error = error
      }
      throw error
    }
  }
}

#if canImport(SwiftUI)
  @MainActor
  extension Room: DynamicProperty {
    public mutating func update() {
      storageReference.value = storageObserver
    }
  }

  extension View {
    public func instantRoom<Schema: InstantRoomSchema>(
      _ room: Room<Schema>,
      _ value: InstantRoom<Schema>
    ) -> some View {
      @Dependency(\.defaultInstantSwiftData) var client
      return instantRoom(room, value, using: client)
    }

    public func instantRoom<Schema: InstantRoomSchema>(
      _ room: Room<Schema>,
      _ value: InstantRoom<Schema>,
      using client: InstantSwiftDataClient
    ) -> some View {
      task(id: value) {
        do {
          try await room.task(value, using: client)
        } catch is CancellationError {
        } catch {
          // Room records its renderable failure on the wrapped value.
        }
      }
    }
  }
#endif
