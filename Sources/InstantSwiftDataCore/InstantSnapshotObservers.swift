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

struct InstantSharesObservationKey: Hashable, Sendable {
  var appID: String
  var userID: String
}
