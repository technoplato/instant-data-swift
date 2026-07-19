import Foundation

actor InstantSnapshotObservers<Key: Hashable & Sendable, Value: Sendable> {
  private struct Observer: Sendable {
    var key: Key
    var continuation: AsyncStream<Value>.Continuation
  }

  private var observers: [UUID: Observer] = [:]

  func observe(key: Key, current value: Value) -> AsyncStream<Value> {
    let id = UUID()
    let stream = AsyncStream<Value>.makeStream(bufferingPolicy: .bufferingNewest(1))
    observers[id] = Observer(key: key, continuation: stream.continuation)
    stream.continuation.yield(value)
    stream.continuation.onTermination = { @Sendable _ in
      Task { await self.cancel(id: id) }
    }
    return stream.stream
  }

  func publish(_ value: Value, for key: Key) {
    for observer in observers.values where observer.key == key {
      observer.continuation.yield(value)
    }
  }

  func activeCount(for key: Key) -> Int {
    observers.values.filter { $0.key == key }.count
  }

  private func cancel(id: UUID) {
    observers[id] = nil
  }
}

struct InstantRoomPresenceObservationKey: Hashable, Sendable {
  var appID: String
  var room: InstantRoomHandle
}

struct InstantRoomTopicObservationKey: Hashable, Sendable {
  var appID: String
  var room: InstantRoomHandle
  var topic: String
}

struct InstantStoredFilesObservationKey: Hashable, Sendable {
  var appID: String
}

struct InstantStreamChunksObservationKey: Hashable, Sendable {
  var appID: String
  var streamID: String
}

actor InstantStreamContentObservers {
  private struct Observer: Sendable {
    var key: InstantStreamContentObservationKey
    var byteOffset: Int64
    var continuation: AsyncStream<InstantStreamContentRead>.Continuation
  }

  private var observers: [UUID: Observer] = [:]

  func observe(
    key: InstantStreamContentObservationKey,
    byteOffset: Int64,
    current value: InstantStreamContentRead? = nil
  ) -> AsyncStream<InstantStreamContentRead> {
    let id = UUID()
    let stream = AsyncStream<InstantStreamContentRead>.makeStream(bufferingPolicy: .unbounded)
    observers[id] = Observer(
      key: key,
      byteOffset: byteOffset,
      continuation: stream.continuation
    )
    if let value {
      stream.continuation.yield(value)
    }
    stream.continuation.onTermination = { @Sendable _ in
      Task { await self.cancel(id: id) }
    }
    return stream.stream
  }

  func publish(
    _ value: InstantStreamContentRead,
    for key: InstantStreamContentObservationKey,
    byteOffset: Int64
  ) {
    for observer in observers.values where observer.key == key && observer.byteOffset == byteOffset {
      observer.continuation.yield(value)
    }
  }

  func byteOffsets(for key: InstantStreamContentObservationKey) -> [Int64] {
    Array(Set(observers.values.filter { $0.key == key }.map(\.byteOffset))).sorted()
  }

  func activeCount(for key: InstantStreamContentObservationKey) -> Int {
    observers.values.filter { $0.key == key }.count
  }

  private func cancel(id: UUID) {
    observers[id] = nil
  }
}

struct InstantStreamContentObservationKey: Hashable, Sendable {
  var appID: String
  var selector: InstantStreamContentSelector
}

enum InstantStreamContentSelector: Hashable, Sendable {
  case streamID(String)
  case clientID(String)
}

struct InstantSharesObservationKey: Hashable, Sendable {
  var appID: String
  var userID: String
}
