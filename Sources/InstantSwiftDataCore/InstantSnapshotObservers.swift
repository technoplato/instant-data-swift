import Foundation

actor InstantSnapshotObservers<Key: Hashable & Sendable, Value: Sendable> {
  private struct Observer: Sendable {
    var key: Key
    var continuation: AsyncStream<Value>.Continuation
  }

  private var observers: [UUID: Observer] = [:]

  func observe(key: Key, current value: Value) -> AsyncStream<Value> {
    observeLease(key: key, current: value).stream
  }

  func observeLease(
    key: Key,
    current value: Value
  ) -> InstantManagedStreamLease<AsyncStream<Value>> {
    let id = UUID()
    let stream = AsyncStream<Value>.makeStream(bufferingPolicy: .bufferingNewest(1))
    observers[id] = Observer(key: key, continuation: stream.continuation)
    stream.continuation.yield(value)
    let lease = InstantManagedStreamLease(
      stream: stream.stream,
      onCancellationRequested: {
        stream.continuation.finish()
      },
      cancelAndWait: {
        await self.cancel(id: id)
      }
    )
    let cancellationRequest = lease.cancellationRequest
    stream.continuation.onTermination = { @Sendable _ in
      cancellationRequest()
    }
    return lease
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
    observers.removeValue(forKey: id)?.continuation.finish()
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

/// One write to a stream, which each observation applies to the read it last received.
enum InstantStreamContentChange: Sendable {
  /// `chunk` was appended; `metadata` is the stream's metadata after the append.
  case appended(InstantStreamContentChunk, metadata: InstantStreamMetadata)
  /// The stream closed; `metadata` carries its final size and any abort reason.
  case closed(InstantStreamMetadata)

  var metadata: InstantStreamMetadata {
    switch self {
    case let .appended(_, metadata), let .closed(metadata): metadata
    }
  }
}

actor InstantStreamContentObservers {
  private struct Observer: Sendable {
    var key: InstantStreamContentObservationKey
    var byteOffset: Int64
    var continuation: AsyncStream<InstantStreamContentRead>.Continuation
    /// The read this observation last received. The next write extends it, so an append costs its own bytes rather
    /// than a read of the whole stream; `nil` until the observation has a read.
    var latest: InstantStreamContentRead?
  }

  private var observers: [UUID: Observer] = [:]

  /// Observes the stream content `key` selects from `byteOffset`, starting with `current`.
  ///
  /// Every read is the stream's content from `byteOffset` so far, so an older queued read is superseded. The
  /// observation ends after its first `done` read: a done stream changes no more, and upstream `Stream.ts` closes a
  /// reader at done (`onStreamAppend`).
  func observe(
    key: InstantStreamContentObservationKey,
    byteOffset: Int64,
    current value: InstantStreamContentRead? = nil
  ) -> AsyncStream<InstantStreamContentRead> {
    let stream = AsyncStream<InstantStreamContentRead>.makeStream(
      bufferingPolicy: .bufferingNewest(1)
    )
    if let value {
      stream.continuation.yield(value)
      if value.done {
        stream.continuation.finish()
        return stream.stream
      }
    }
    let id = UUID()
    observers[id] = Observer(
      key: key,
      byteOffset: byteOffset,
      continuation: stream.continuation,
      latest: value
    )
    stream.continuation.onTermination = { @Sendable _ in
      Task { await self.cancel(id: id) }
    }
    return stream.stream
  }

  /// Applies `change` to every observation of `key`, as upstream `Stream.ts` hands a reader only the new bytes.
  ///
  /// Returns the byte offsets of the observations it could not extend: one with no read yet, or one whose read does
  /// not end where the change begins. The caller reads the stored stream for those and publishes the read.
  func publish(
    _ change: InstantStreamContentChange,
    for key: InstantStreamContentObservationKey
  ) -> Set<Int64> {
    var unextended: Set<Int64> = []
    for (id, observer) in observers where observer.key == key {
      guard let read = Self.read(applying: change, to: observer.latest, from: observer.byteOffset) else {
        unextended.insert(observer.byteOffset)
        continue
      }
      deliver(read, to: id)
    }
    return unextended
  }

  /// Delivers a read of the stored stream to the observations of `key` from `byteOffset`.
  func publish(
    _ value: InstantStreamContentRead,
    for key: InstantStreamContentObservationKey,
    byteOffset: Int64
  ) {
    for (id, observer) in observers where observer.key == key && observer.byteOffset == byteOffset {
      deliver(value, to: id)
    }
  }

  func activeCount(for key: InstantStreamContentObservationKey) -> Int {
    observers.values.filter { $0.key == key }.count
  }

  /// Ends the observations `isEnded` selects, as when the server refuses the stream subscription behind them.
  func finish(where isEnded: (InstantStreamContentObservationKey, Int64) -> Bool) {
    for (id, observer) in observers where isEnded(observer.key, observer.byteOffset) {
      observers[id] = nil
      observer.continuation.finish()
    }
  }

  /// The read an observation's `latest` read becomes after `change`, or `nil` when only a stored read can say.
  ///
  /// The result equals what reading the stored stream from `byteOffset` returns after the change, which is what
  /// Scribe's `materializeMedia` relies on when it takes the `content` of the first `done` read.
  static func read(
    applying change: InstantStreamContentChange,
    to latest: InstantStreamContentRead?,
    from byteOffset: Int64
  ) -> InstantStreamContentRead? {
    switch change {
    case let .appended(chunk, metadata):
      guard let latest else {
        // An observation that began before the stream existed here: the stream's first chunk is all of it.
        guard chunk.offset == 0, byteOffset == 0 else { return nil }
        return InstantStreamContentRead(
          metadata: metadata,
          byteOffset: 0,
          byteCount: chunk.byteCount,
          content: chunk.content,
          done: metadata.done,
          abortReason: metadata.abortReason
        )
      }
      guard latest.byteOffset + latest.byteCount == chunk.offset else { return nil }
      var content = latest.content
      content.append(chunk.content)
      return InstantStreamContentRead(
        metadata: metadata,
        byteOffset: latest.byteOffset,
        byteCount: latest.byteCount + chunk.byteCount,
        content: content,
        done: metadata.done,
        abortReason: metadata.abortReason
      )
    case let .closed(metadata):
      guard let latest, latest.byteOffset + latest.byteCount == metadata.size else { return nil }
      return InstantStreamContentRead(
        metadata: metadata,
        byteOffset: latest.byteOffset,
        byteCount: latest.byteCount,
        content: latest.content,
        done: metadata.done,
        abortReason: metadata.abortReason
      )
    }
  }

  private func deliver(_ read: InstantStreamContentRead, to id: UUID) {
    guard var observer = observers[id] else { return }
    observer.continuation.yield(read)
    if read.done {
      observers[id] = nil
      observer.continuation.finish()
    } else {
      observer.latest = read
      observers[id] = observer
    }
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
