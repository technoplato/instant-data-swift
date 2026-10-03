import Foundation

/// A live runtime's room presence, held in memory as `Reactor.js` holds `_presence` (#461).
///
/// For each room it keeps the peers the server reports (the `refresh-presence` sessions map, patched by
/// `patch-presence`, without this runtime's own session), the presence this runtime published, and every observation
/// of the room. Publishing presence and applying a presence frame each take one turn here, and neither touches the
/// operation gate or SQLite, as `Reactor.js` handles both synchronously without a lock or storage
/// (`publishPresence`, `_patchPresencePeers`, `_setPresencePeers`).
///
/// A runtime without a live transport (the CLI's local cache) keeps its presence in SQLite instead, so a later launch
/// lists it.
actor InstantRuntimeRoomPresence {
  /// What a presence frame did, for the runtime's trace diagnostics.
  struct FrameSummary: Sendable {
    var peerCount: Int
    var localCount: Int
    var observerCount: Int
  }

  private struct RoomState {
    /// The server's sessions map for the room, without this runtime's own session: each value is the envelope
    /// `{peer-id, user: {id}, data}` the server keeps per session (`JoinRoomMergeV3`, hazelcast.clj).
    var sessions: JSONValue = .object([:])
    /// When each peer's `data` last changed, as this runtime received it.
    var sessionUpdatedAt: [String: InstantTimestamp] = [:]
    /// This runtime's own presence, at most one per user id, newest publication last.
    var local: [InstantRoomPresenceMember] = []

    var isEmpty: Bool {
      local.isEmpty && sessionUpdatedAt.isEmpty && sessions == .object([:])
    }
  }

  private struct Observer {
    var room: InstantRoomHandle
    var selection: InstantRoomPresenceSelection
    var continuation: AsyncStream<[InstantRoomPresenceMember]>.Continuation
    /// What this observer last received. A change outside its selection, or one that leaves its part as it was, does
    /// not wake it, as `Reactor.js` skips a handler whose slice did not change (`hasPresenceResponseChanged`).
    var last: [InstantRoomPresenceMember]
  }

  private var rooms: [InstantRoomHandle: RoomState] = [:]
  private var observers: [UUID: Observer] = [:]
  /// Counts this runtime's publications and withdrawals across every room and never restarts, so the live session can
  /// refuse a send older than one it already made.
  private var sequence: UInt64 = 0

  // MARK: - Peers

  /// Applies a `refresh-presence`: the server's whole sessions map for the room (`Reactor.js` `_setPresencePeers`).
  @discardableResult
  func replacePeers(
    in room: InstantRoomHandle,
    sessions: [String: InstantLiveJSONValue],
    excludingSessionID: String?,
    appID: String,
    receivedAt: InstantTimestamp
  ) -> FrameSummary {
    var state = rooms[room] ?? RoomState()
    var replacement = JSONValue.object(sessions.mapValues(\.jsonValue))
    if let excludingSessionID {
      replacement.dissocIn([.key(excludingSessionID)])
    }
    state.sessionUpdatedAt = Self.stamps(
      before: state.sessions,
      after: replacement,
      previous: state.sessionUpdatedAt,
      receivedAt: receivedAt
    )
    state.sessions = replacement
    return store(state, in: room, appID: appID)
  }

  /// Applies a `patch-presence`: `+`, `r` and `-` edits to the sessions map (`Reactor.js` `_patchPresencePeers`).
  @discardableResult
  func patchPeers(
    in room: InstantRoomHandle,
    edits: [InstantLiveJSONValue],
    excludingSessionID: String?,
    appID: String,
    receivedAt: InstantTimestamp
  ) throws -> FrameSummary {
    var state = rooms[room] ?? RoomState()
    var sessions = state.sessions
    for (index, edit) in edits.enumerated() {
      guard case let .array(parts) = edit,
        parts.count >= 2,
        case let .array(rawPath) = parts[0],
        let operation = parts[1].stringValue
      else {
        throw Self.malformedPatch(index: index)
      }
      let path = try rawPath.map { component -> JSONValuePathComponent in
        guard let key = component.stringValue else { throw Self.malformedPatch(index: index) }
        return .key(key)
      }
      switch operation {
      case "+":
        guard parts.count == 3 else { throw Self.malformedPatch(index: index) }
        sessions.insertIn(path, parts[2].jsonValue)
      case "r":
        guard parts.count == 3 else { throw Self.malformedPatch(index: index) }
        sessions.assocIn(path, parts[2].jsonValue)
      case "-":
        guard parts.count == 2 else { throw Self.malformedPatch(index: index) }
        sessions.dissocIn(path)
      default:
        throw Self.malformedPatch(index: index)
      }
    }
    // Ignore our own edits, as `_patchPresencePeers` deletes `draft[this._sessionId]`.
    if let excludingSessionID {
      sessions.dissocIn([.key(excludingSessionID)])
    }
    state.sessionUpdatedAt = Self.stamps(
      before: state.sessions,
      after: sessions,
      previous: state.sessionUpdatedAt,
      receivedAt: receivedAt
    )
    state.sessions = sessions
    return store(state, in: room, appID: appID)
  }

  // MARK: - This runtime's presence

  /// Records presence this runtime publishes under `member.userID`, replacing that user's earlier values, and returns
  /// the publication's sequence number for the room.
  func publish(_ member: InstantRoomPresenceMember) -> UInt64 {
    var state = rooms[member.room] ?? RoomState()
    state.local.removeAll { $0.userID == member.userID }
    state.local.append(member)
    sequence &+= 1
    store(state, in: member.room, appID: member.appID)
    return sequence
  }

  /// Withdraws the presence this runtime published under `userID`. Returns the values the session should now carry
  /// (the newest remaining publication, or `nil` when none remains) with the withdrawal's sequence number, or `nil`
  /// when there was nothing to withdraw.
  func withdraw(
    userID: String,
    in room: InstantRoomHandle,
    appID: String
  ) -> (remaining: [String: JSONValue]?, sequence: UInt64)? {
    guard var state = rooms[room], state.local.contains(where: { $0.userID == userID }) else { return nil }
    state.local.removeAll { $0.userID == userID }
    sequence &+= 1
    store(state, in: room, appID: appID)
    return (state.local.last?.values, sequence)
  }

  /// The values this runtime's session carries in `room`: its newest publication.
  func latestLocalValues(in room: InstantRoomHandle) -> [String: JSONValue]? {
    rooms[room]?.local.last?.values
  }

  // MARK: - Leaving

  /// Forgets a room this runtime left: its peers and its own presence there, as `Reactor.js` `_cleanupRoom` deletes
  /// `_presence[roomId]`. Observers see an empty room.
  func forget(_ room: InstantRoomHandle, appID: String) {
    guard rooms[room] != nil else { return }
    store(RoomState(), in: room, appID: appID)
  }

  // MARK: - Reads and observation

  func members(in room: InstantRoomHandle, appID: String) -> [InstantRoomPresenceMember] {
    rooms[room].map { Self.members(of: $0, in: room, appID: appID) } ?? []
  }

  /// Observes the selected part of `room`'s presence, starting with its current members.
  func observe(
    _ room: InstantRoomHandle,
    selection: InstantRoomPresenceSelection = .all,
    appID: String
  ) -> AsyncStream<[InstantRoomPresenceMember]> {
    let id = UUID()
    let stream = AsyncStream<[InstantRoomPresenceMember]>.makeStream(bufferingPolicy: .bufferingNewest(1))
    let current = selection.apply(to: members(in: room, appID: appID))
    observers[id] = Observer(room: room, selection: selection, continuation: stream.continuation, last: current)
    stream.continuation.yield(current)
    stream.continuation.onTermination = { @Sendable _ in
      Task { await self.removeObserver(id) }
    }
    return stream.stream
  }

  func observerCount(in room: InstantRoomHandle) -> Int {
    observers.values.count { $0.room == room }
  }

  private func removeObserver(_ id: UUID) {
    observers.removeValue(forKey: id)?.continuation.finish()
  }

  // MARK: - Internals

  @discardableResult
  private func store(_ state: RoomState, in room: InstantRoomHandle, appID: String) -> FrameSummary {
    rooms[room] = state.isEmpty ? nil : state
    let members = Self.members(of: state, in: room, appID: appID)
    var observerCount = 0
    for (id, observer) in observers where observer.room == room {
      observerCount += 1
      let slice = observer.selection.apply(to: members)
      guard observer.selection.changed(from: observer.last, to: slice) else { continue }
      observers[id]?.last = slice
      observer.continuation.yield(slice)
    }
    return FrameSummary(
      peerCount: members.count - state.local.count,
      localCount: state.local.count,
      observerCount: observerCount
    )
  }

  private static func members(
    of state: RoomState,
    in room: InstantRoomHandle,
    appID: String
  ) -> [InstantRoomPresenceMember] {
    var members = state.local
    if case let .object(sessions) = state.sessions {
      for (sessionID, rawEnvelope) in sessions {
        guard case let .object(envelope) = rawEnvelope, case let .object(values)? = envelope["data"] else { continue }
        let userID: String
        if case let .object(user)? = envelope["user"], case let .string(value)? = user["id"] {
          userID = value
        } else if case let .string(value)? = envelope["peer-id"] {
          userID = value
        } else {
          userID = sessionID
        }
        // A peer is its session, as `Reactor.js` keys `peers` by the server's session id (`buildPresenceSlice` sets
        // `peerId` to that key), so two sessions of one user stay two members (#461).
        members.append(
          InstantRoomPresenceMember(
            appID: appID,
            room: room,
            userID: userID,
            peerID: sessionID,
            values: values,
            updatedAt: state.sessionUpdatedAt[sessionID] ?? InstantTimestamp(milliseconds: 0)
          )
        )
      }
    }
    return members.sorted(by: InstantRoomPresenceMember.presenceOrder)
  }

  /// A peer's `updatedAt` moves only when its `data` changed; a frame that restates it keeps the earlier time.
  private static func stamps(
    before: JSONValue,
    after: JSONValue,
    previous: [String: InstantTimestamp],
    receivedAt: InstantTimestamp
  ) -> [String: InstantTimestamp] {
    guard case let .object(next) = after else { return [:] }
    let earlier: [String: JSONValue]
    if case let .object(sessions) = before { earlier = sessions } else { earlier = [:] }
    var stamps: [String: InstantTimestamp] = [:]
    for (sessionID, envelope) in next {
      if let stamp = previous[sessionID], Self.data(of: earlier[sessionID]) == Self.data(of: envelope) {
        stamps[sessionID] = stamp
      } else {
        stamps[sessionID] = receivedAt
      }
    }
    return stamps
  }

  private static func data(of envelope: JSONValue?) -> JSONValue? {
    guard case let .object(fields)? = envelope else { return nil }
    return fields["data"]
  }

  private static func malformedPatch(index: Int) -> InstantError {
    InstantError(
      code: .decodeFailed,
      operation: "apply Instant live presence patch",
      path: "edits[\(index)]",
      message: "Instant patch-presence contained a malformed edit.",
      recovery: "Inspect the canonical Instant patch-presence payload."
    )
  }
}

/// The signed-in user's id, kept in memory so room calls never read the auth session from SQLite (#461).
///
/// The runtime sets it wherever it publishes an auth-session change; until the first change it is unknown, and the
/// first room call reads the stored session once.
// SAFETY: `lock` protects `state`.
final class InstantRoomAuthUserIDCache: @unchecked Sendable {
  private enum State {
    case unknown
    case known(String?)
  }

  private let lock = NSLock()
  private var state = State.unknown

  /// `.some(userID)` once known (`.some(nil)` when signed out); `nil` while unknown.
  var known: String?? {
    lock.withLock {
      switch state {
      case .unknown: nil
      case let .known(userID): .some(userID)
      }
    }
  }

  func set(_ userID: String?) {
    lock.withLock { state = .known(userID) }
  }

  /// Stores a value read from SQLite only if no change was published meanwhile.
  func setIfUnknown(_ userID: String?) {
    lock.withLock {
      if case .unknown = state { state = .known(userID) }
    }
  }
}
