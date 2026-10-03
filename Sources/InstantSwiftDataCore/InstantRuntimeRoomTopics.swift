import Foundation

/// A live runtime's room topic messages, in memory and bounded, since `Reactor.js` stores none (#461).
///
/// `Reactor.js` hands each `server-broadcast` to the topic's subscribers once (`_notifyBroadcastSubs`) and keeps no
/// history. Here each message, published by this runtime or received, is recorded once in one turn:
/// - every event observation receives it once, in order, without a drop (`observeEvents`);
/// - every snapshot observation receives the topic's most recent messages, at most `recentMessageLimit`, so a reader
///   that falls behind by fewer than that loses nothing;
/// - this runtime's own publications stay listable, also bounded.
///
/// Nothing touches SQLite or the operation gate, so the cost of a message does not grow with the messages before it.
/// A runtime without a live transport (the CLI's local cache) stores its topic messages in SQLite instead.
actor InstantRuntimeRoomTopics {
  /// How many recent messages a topic keeps for its snapshot observers and for `published(…)`.
  static let recentMessageLimit = 128

  private struct TopicKey: Hashable {
    var room: InstantRoomHandle
    var topic: String
  }

  private struct TopicState {
    /// Published and received messages, oldest first, at most `recentMessageLimit`.
    var recent: [InstantRoomTopicMessage] = []
    /// This runtime's own publications, oldest first, at most `recentMessageLimit`.
    var published: [InstantRoomTopicMessage] = []
  }

  private struct SnapshotObserver {
    var key: TopicKey
    var continuation: AsyncStream<[InstantRoomTopicMessage]>.Continuation
  }

  private struct EventObserver {
    var key: TopicKey
    var continuation: AsyncStream<InstantRoomTopicMessage>.Continuation
  }

  private var topics: [TopicKey: TopicState] = [:]
  private var snapshotObservers: [UUID: SnapshotObserver] = [:]
  private var eventObservers: [UUID: EventObserver] = [:]

  /// Records one message this runtime published (`peerID` nil) or received, and hands it to the topic's observers.
  func record(_ message: InstantRoomTopicMessage) {
    let key = TopicKey(room: message.room, topic: message.topic)
    var state = topics[key] ?? TopicState()
    Self.append(message, to: &state.recent)
    if message.isLocal {
      Self.append(message, to: &state.published)
    }
    topics[key] = state
    for observer in eventObservers.values where observer.key == key {
      observer.continuation.yield(message)
    }
    for observer in snapshotObservers.values where observer.key == key {
      observer.continuation.yield(state.recent)
    }
  }

  /// This runtime's own most recent publications on the topic, oldest first.
  func published(room: InstantRoomHandle, topic: String, limit: Int?) -> [InstantRoomTopicMessage] {
    let published = topics[TopicKey(room: room, topic: topic)]?.published ?? []
    guard let limit else { return published }
    return Array(published.prefix(limit))
  }

  /// Observes the topic's most recent messages, starting with the current ones.
  func observeSnapshots(room: InstantRoomHandle, topic: String) -> AsyncStream<[InstantRoomTopicMessage]> {
    let key = TopicKey(room: room, topic: topic)
    let id = UUID()
    let stream = AsyncStream<[InstantRoomTopicMessage]>.makeStream(bufferingPolicy: .bufferingNewest(1))
    snapshotObservers[id] = SnapshotObserver(key: key, continuation: stream.continuation)
    stream.continuation.yield(topics[key]?.recent ?? [])
    stream.continuation.onTermination = { @Sendable _ in
      Task { await self.removeSnapshotObserver(id) }
    }
    return stream.stream
  }

  /// Observes each message published or received on the topic after this call, once and in order. Nothing is
  /// dropped: an observation that stops reading holds every later message until it ends.
  func observeEvents(room: InstantRoomHandle, topic: String) -> AsyncStream<InstantRoomTopicMessage> {
    let key = TopicKey(room: room, topic: topic)
    let id = UUID()
    let stream = AsyncStream<InstantRoomTopicMessage>.makeStream(bufferingPolicy: .unbounded)
    eventObservers[id] = EventObserver(key: key, continuation: stream.continuation)
    stream.continuation.onTermination = { @Sendable _ in
      Task { await self.removeEventObserver(id) }
    }
    return stream.stream
  }

  func observerCount(room: InstantRoomHandle, topic: String) -> Int {
    let key = TopicKey(room: room, topic: topic)
    let snapshots = snapshotObservers.values.count(where: { $0.key == key })
    let events = eventObservers.values.count(where: { $0.key == key })
    return snapshots + events
  }

  /// Forgets the messages of a room this runtime left; its snapshot observers see none.
  func forget(_ room: InstantRoomHandle) {
    let keys = topics.keys.filter { $0.room == room }
    guard !keys.isEmpty else { return }
    for key in keys {
      topics[key] = nil
    }
    for observer in snapshotObservers.values where observer.key.room == room {
      observer.continuation.yield([])
    }
  }

  /// How many messages the topic holds, for tests: bounded whatever the number of messages.
  func heldMessageCountForTesting(room: InstantRoomHandle, topic: String) -> Int {
    let state = topics[TopicKey(room: room, topic: topic)]
    return (state?.recent.count ?? 0) + (state?.published.count ?? 0)
  }

  private func removeSnapshotObserver(_ id: UUID) {
    snapshotObservers.removeValue(forKey: id)?.continuation.finish()
  }

  private func removeEventObserver(_ id: UUID) {
    eventObservers.removeValue(forKey: id)?.continuation.finish()
  }

  private static func append(_ message: InstantRoomTopicMessage, to messages: inout [InstantRoomTopicMessage]) {
    messages.append(message)
    if messages.count > recentMessageLimit {
      messages.removeFirst(messages.count - recentMessageLimit)
    }
  }
}
