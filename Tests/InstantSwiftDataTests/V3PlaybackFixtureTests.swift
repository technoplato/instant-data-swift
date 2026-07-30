import CustomDump
import Dependencies
import Foundation
import InstantSwiftData
import Testing

#if canImport(SwiftUI)
  import SwiftUI
  #if os(macOS)
    import AppKit
  #endif

  @Suite
  struct V3PlaybackFixtureTests {
    @Test @MainActor
    func playbackRoomSyntaxCompilesWithTypedDynamicIdentity() {
      let screen = V3PlaybackRoomFixture(recordingID: "recording-a")
      let view: any View = screen
      _ = view

      let first = V3PlaybackRooms.activeRecording("recording-a")
      let second = V3PlaybackRooms.activeRecording("recording-b")

      expectNoDifference(
        first.handle,
        InstantRoomHandle(type: "recording.playback", id: "recording-a")
      )
      #expect(first != second)
      expectNoDifference(V3PlaybackRoomSchema.Topic.reaction.rawValue, "reaction")
    }

    @Test
    func roomWrapperOwnsJoinCancellationAndLeaveLifecycle() async throws {
      let recorder = V3PlaybackRoomRecorder()
      let client = v3PlaybackRoomClient(recorder)
      let room = Room<V3PlaybackRoomSchema>()
      let target = V3PlaybackRooms.activeRecording("recording-lifecycle")

      let task = Task {
        try await room.task(target, using: client)
      }
      try await waitForV3PlaybackRoomCondition(
        operation: "wait for typed room join"
      ) {
        await recorder.joined().count == 1 && room.wrappedValue.isJoined
      }

      expectNoDifference(room.wrappedValue.handle, target.handle)
      expectNoDifference(room.wrappedValue.error, nil)

      task.cancel()
      do {
        try await task.value
        Issue.record("Expected the room lifecycle task to cancel.")
      } catch is CancellationError {
      } catch {
        Issue.record("Expected CancellationError, got \(error).")
      }

      try await waitForV3PlaybackRoomCondition(
        operation: "wait for typed room leave"
      ) {
        await recorder.left().count == 1 && !room.wrappedValue.isJoined
      }
      let joined = await recorder.joined()
      let left = await recorder.left()
      expectNoDifference(joined, [target.handle].compactMap { $0 })
      expectNoDifference(left, [target.handle].compactMap { $0 })
    }

    @Test
    func roomWrapperReplacesDynamicRoomWithoutStaleState() async throws {
      let recorder = V3PlaybackRoomRecorder()
      let client = v3PlaybackRoomClient(recorder)
      let room = Room<V3PlaybackRoomSchema>()
      let first = V3PlaybackRooms.activeRecording("recording-first")
      let second = V3PlaybackRooms.activeRecording("recording-second")

      let firstTask = Task {
        try await room.task(first, using: client)
      }
      try await waitForV3PlaybackRoomCondition(
        operation: "wait for first dynamic room join"
      ) {
        await recorder.joined().count == 1 && room.wrappedValue.isJoined
      }

      firstTask.cancel()
      do {
        try await firstTask.value
        Issue.record("Expected the first dynamic room task to cancel.")
      } catch is CancellationError {
      } catch {
        Issue.record("Expected CancellationError, got \(error).")
      }

      let secondTask = Task {
        try await room.task(second, using: client)
      }
      try await waitForV3PlaybackRoomCondition(
        operation: "wait for replacement dynamic room join"
      ) {
        await recorder.joined().count == 2 && room.wrappedValue.isJoined
      }

      expectNoDifference(room.wrappedValue.handle, second.handle)
      let firstLeaveCount = await recorder.left().count
      expectNoDifference(firstLeaveCount, 1)

      secondTask.cancel()
      do {
        try await secondTask.value
        Issue.record("Expected the replacement dynamic room task to cancel.")
      } catch is CancellationError {
      } catch {
        Issue.record("Expected CancellationError, got \(error).")
      }

      try await waitForV3PlaybackRoomCondition(
        operation: "wait for replacement dynamic room leave"
      ) {
        await recorder.left().count == 2 && !room.wrappedValue.isJoined
      }
      let joined = await recorder.joined()
      let left = await recorder.left()
      expectNoDifference(joined, [first.handle, second.handle].compactMap { $0 })
      expectNoDifference(left, [first.handle, second.handle].compactMap { $0 })
    }

    @Test @MainActor
    func presenceWrapperPublishesObservesDecodesAndCancels() async throws {
      let recorder = V3PlaybackPresenceRecorder()
      let client = v3PlaybackPresenceClient(recorder)
      let room = V3PlaybackRooms.activeRecording("recording-presence")
      let presence = Presence<V3PlaybackPresence>()
      let current = V3PlaybackPresence(
        userID: InstantID(rawValue: "current-user"),
        displayName: "Current Listener",
        isPlaying: true,
        offsetSeconds: 12.5,
        focusedSegmentID: InstantID(rawValue: "segment-current")
      )

      let observationTask = Task { @MainActor in
        try await presence.task(in: room, using: client)
      }
      try await waitForV3PlaybackRoomCondition(
        operation: "wait for typed presence observation"
      ) {
        await recorder.observedRooms().count == 1
      }

      try await presence.publish(current, in: room, using: client)
      let published = await recorder.publishedValues()
      expectNoDifference(
        published,
        [
          [
            "displayName": .string("Current Listener"),
            "focusedSegmentID": .string("segment-current"),
            "isPlaying": .bool(true),
            "offsetSeconds": .number(12.5),
            "userID": .string("current-user"),
          ]
        ]
      )

      await recorder.yield(
        [
          InstantRoomPresenceMember(
            appID: "playback-test",
            room: try #require(room.handle),
            userID: "remote-user",
            values: [
              "displayName": .string("Remote Listener"),
              "focusedSegmentID": .string("segment-remote"),
              "isPlaying": .bool(false),
              "offsetSeconds": .number(3.25),
            ],
            updatedAt: InstantTimestamp(milliseconds: 1_000)
          )
        ]
      )
      try await waitForV3PlaybackRoomCondition(
        operation: "wait for typed presence decode"
      ) {
        await MainActor.run {
          presence.loadError != nil
            || presence.wrappedValue
              == [
              V3PlaybackPresence(
                userID: InstantID(rawValue: "remote-user"),
                displayName: "Remote Listener",
                isPlaying: false,
                offsetSeconds: 3.25,
                focusedSegmentID: InstantID(rawValue: "segment-remote")
              )
            ]
        }
      }
      expectNoDifference(
        presence.wrappedValue,
        [
          V3PlaybackPresence(
            userID: InstantID(rawValue: "remote-user"),
            displayName: "Remote Listener",
            isPlaying: false,
            offsetSeconds: 3.25,
            focusedSegmentID: InstantID(rawValue: "segment-remote")
          )
        ]
      )
      expectNoDifference(presence.loadError, nil)
      expectNoDifference(presence.isLoading, false)

      try await presence.publish(nil, in: room, using: client)
      let leaveCount = await recorder.leaveCount()
      expectNoDifference(leaveCount, 1)

      observationTask.cancel()
      do {
        try await observationTask.value
        Issue.record("Expected the typed presence observation to cancel.")
      } catch is CancellationError {
      } catch {
        Issue.record("Expected CancellationError, got \(error).")
      }
      try await waitForV3PlaybackRoomCondition(
        operation: "wait for typed presence observation cleanup"
      ) {
        await recorder.terminationCount() == 1
      }
    }

    @Test @MainActor
    func topicWrapperPublishesObservesDecodesAndCancels() async throws {
      let recorder = V3PlaybackTopicRecorder()
      let callbacks = V3PlaybackTopicCallbacks()
      let client = v3PlaybackTopicClient(recorder)
      let room = V3PlaybackRooms.activeRecording("recording-topic")
      let topic = Topic<V3PlaybackReaction, V3PlaybackRoomSchema.Topic>(.reaction)
      let reaction = V3PlaybackReaction(emoji: "heart", offsetSeconds: 8.5)

      let observationTask = Task { @MainActor in
        try await topic.task(in: room, using: client)
      }
      try await waitForV3PlaybackRoomCondition(
        operation: "wait for typed topic observation"
      ) {
        await recorder.observed().count == 1
      }

      let publishTask = topic.wrappedValue.publish(
        reaction,
        using: client,
        onPublished: { event in
          callbacks.published.append(event.topicID)
        },
        onFailure: { error in
          callbacks.failures.append(error)
        }
      )
      await publishTask.value

      let published = await recorder.published()
      expectNoDifference(
        published,
        [
          V3PublishedTopic(
            room: try #require(room.handle),
            topic: "reaction",
            payload: .object(
              [
                "emoji": .string("heart"),
                "offsetSeconds": .number(8.5),
              ]
            )
          )
        ]
      )
      expectNoDifference(callbacks.published, ["topic-message-1"])
      expectNoDifference(callbacks.failures, [])

      await recorder.yield(
        [
          InstantRoomTopicMessage(
            id: "topic-message-remote",
            appID: "playback-test",
            room: try #require(room.handle),
            topic: "reaction",
            userID: "remote-user",
            payload: .object(
              [
                "emoji": .string("sparkles"),
                "offsetSeconds": .number(4.25),
              ]
            ),
            createdAt: InstantTimestamp(milliseconds: 2_000)
          )
        ]
      )
      try await waitForV3PlaybackRoomCondition(
        operation: "wait for typed topic decode"
      ) {
        await MainActor.run {
          topic.wrappedValue.messages
            == [V3PlaybackReaction(emoji: "sparkles", offsetSeconds: 4.25)]
        }
      }
      expectNoDifference(topic.wrappedValue.loadError, nil)
      expectNoDifference(topic.wrappedValue.isLoading, false)

      observationTask.cancel()
      do {
        try await observationTask.value
        Issue.record("Expected the typed topic observation to cancel.")
      } catch is CancellationError {
      } catch {
        Issue.record("Expected CancellationError, got \(error).")
      }
      try await waitForV3PlaybackRoomCondition(
        operation: "wait for typed topic observation cleanup"
      ) {
        await recorder.terminationCount() == 1
      }
    }

    #if os(macOS)
      @Test @MainActor
      func joinedRoomStateInvalidatesAHostedSwiftUIView() async throws {
        let recorder = V3PlaybackRoomRecorder()
        let renders = V3PlaybackRoomRenderRecorder()
        let client = v3PlaybackRoomClient(recorder)

        try await withDependencies {
          $0.defaultInstantSwiftData = client
        } operation: {
          let hostingView = NSHostingView(
            rootView: V3PlaybackRoomRenderingFixture(renders: renders)
          )
          hostingView.frame = NSRect(x: 0, y: 0, width: 320, height: 80)
          hostingView.layoutSubtreeIfNeeded()

          try await waitForV3PlaybackRoomCondition(
            operation: "wait for hosted typed room join"
          ) {
            await recorder.joined().count == 1
          }
          try await waitForV3PlaybackRoomCondition(
            operation: "wait for hosted typed room join invalidation"
          ) {
            await MainActor.run {
              renders.values.contains(true)
            }
          }

          withExtendedLifetime(hostingView) {}
        }

        #expect(renders.values.first == false)
        #expect(renders.values.contains(true))
      }

      @Test @MainActor
      func scopedClientOwnsDefaultTopicPublicationInAHostedSwiftUIView() async throws {
        let recorder = V3PlaybackTopicRecorder()
        let client = v3PlaybackTopicClient(recorder)
        let hostingView = NSHostingView(
          rootView: V3PlaybackScopedTopicRoutingFixture(recorder: recorder)
            .dependency(\.defaultInstantSwiftData, client)
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: 320, height: 80)
        hostingView.layoutSubtreeIfNeeded()

        try await waitForV3PlaybackRoomCondition(
          operation: "wait for hosted scoped topic publication"
        ) {
          await recorder.published().count == 1
        }

        withExtendedLifetime(hostingView) {}
      }
    #endif
  }

  @MainActor
  private struct V3PlaybackRoomFixture: View {
    let recordingID: String

    @Room
    private var room: InstantRoom<V3PlaybackRoomSchema>

    @Presence
    private var listeners: [V3PlaybackPresence]

    @Topic(V3PlaybackRoomSchema.Topic.reaction)
    private var reactions: InstantTopic<V3PlaybackReaction>

    var body: some View {
      Text("\(room.id ?? "Joining"): \(listeners.count): \(reactions.messages.count)")
        .instantRoom(
          $room,
          V3PlaybackRooms.activeRecording(recordingID)
        )
        .presence(
          $listeners,
          in: room,
          publishing: V3PlaybackPresence(
            userID: InstantID(rawValue: "current-user"),
            displayName: "Current Listener",
            isPlaying: false,
            offsetSeconds: 0,
            focusedSegmentID: nil
          )
        )
        .instantTopic($reactions, in: room)
    }
  }

  #if os(macOS)
    @MainActor
    private struct V3PlaybackRoomRenderingFixture: View {
      @Room private var room: InstantRoom<V3PlaybackRoomSchema>
      let renders: V3PlaybackRoomRenderRecorder

      var body: some View {
        renders.record(room.isJoined)
        return Text(room.isJoined ? "Joined" : "Joining")
          .instantRoom(
            $room,
            V3PlaybackRooms.activeRecording("recording-hosted")
          )
      }
    }

    @MainActor
    private struct V3PlaybackScopedTopicRoutingFixture: View {
      @Room private var room: InstantRoom<V3PlaybackRoomSchema> =
        V3PlaybackRooms.activeRecording("recording-scoped-topic")
      @Topic(V3PlaybackRoomSchema.Topic.reaction)
      private var reactions: InstantTopic<V3PlaybackReaction>
      @State private var didPublish = false

      let recorder: V3PlaybackTopicRecorder

      var body: some View {
        Text("Scoped topic")
          .instantTopic($reactions, in: room)
          .task {
            do {
              try await waitForV3PlaybackRoomCondition(
                operation: "wait for hosted scoped topic observation"
              ) {
                await recorder.observed().count == 1
              }
              guard !didPublish else { return }
              didPublish = true
              await reactions.publish(
                V3PlaybackReaction(emoji: "sparkles", offsetSeconds: 2)
              ).value
            } catch {
              Issue.record(error)
            }
          }
      }
    }

    @MainActor
    private final class V3PlaybackRoomRenderRecorder {
      private(set) var values: [Bool] = []

      func record(_ value: Bool) {
        values.append(value)
      }
    }
  #endif

  private enum V3PlaybackRooms {
    static func activeRecording(
      _ id: String
    ) -> InstantRoom<V3PlaybackRoomSchema> {
      InstantRoom(type: "recording.playback", id: id)
    }
  }

  private struct V3PlaybackRoomSchema: InstantRoomSchema {
    typealias Presence = V3PlaybackPresence

    enum Topic: String, InstantRoomTopic {
      typealias RoomSchema = V3PlaybackRoomSchema

      case reaction
      case commentDraft
      case commentCommitted
    }
  }

  private struct V3PlaybackPresence: Codable, Equatable, Sendable {
    var userID: InstantID<V3PlaybackUser>
    var displayName: String
    var isPlaying: Bool
    var offsetSeconds: Double
    var focusedSegmentID: InstantID<V3PlaybackSegment>?
  }

  private struct V3PlaybackReaction: Codable, Equatable, Sendable {
    var emoji: String
    var offsetSeconds: Double
  }

  private enum V3PlaybackUser {}
  private enum V3PlaybackSegment {}

  private actor V3PlaybackRoomRecorder {
    private var joinedRooms: [InstantRoomHandle] = []
    private var leftRooms: [InstantRoomHandle] = []

    func recordJoin(_ room: InstantRoomHandle) {
      joinedRooms.append(room)
    }

    func recordLeave(_ room: InstantRoomHandle) {
      leftRooms.append(room)
    }

    func joined() -> [InstantRoomHandle] {
      joinedRooms
    }

    func left() -> [InstantRoomHandle] {
      leftRooms
    }
  }

  private actor V3PlaybackPresenceRecorder {
    private var rooms: [InstantRoomHandle] = []
    private var values: [[String: JSONValue]] = []
    private var leaves = 0
    private var terminations = 0
    private var continuation:
      AsyncStream<[InstantRoomPresenceMember]>.Continuation?

    func observe(
      room: InstantRoomHandle
    ) -> AsyncStream<[InstantRoomPresenceMember]> {
      rooms.append(room)
      let stream = AsyncStream<[InstantRoomPresenceMember]>.makeStream(
        bufferingPolicy: .bufferingNewest(1)
      )
      continuation = stream.continuation
      stream.continuation.onTermination = { @Sendable _ in
        Task {
          await self.recordTermination()
        }
      }
      return stream.stream
    }

    func recordPublished(_ value: [String: JSONValue]) {
      values.append(value)
    }

    func recordLeave() {
      leaves += 1
    }

    func recordTermination() {
      terminations += 1
    }

    func yield(_ members: [InstantRoomPresenceMember]) {
      continuation?.yield(members)
    }

    func observedRooms() -> [InstantRoomHandle] {
      rooms
    }

    func publishedValues() -> [[String: JSONValue]] {
      values
    }

    func leaveCount() -> Int {
      leaves
    }

    func terminationCount() -> Int {
      terminations
    }
  }

  private struct V3PublishedTopic: Equatable, Sendable {
    var room: InstantRoomHandle
    var topic: String
    var payload: JSONValue
  }

  @MainActor
  private final class V3PlaybackTopicCallbacks {
    var published: [String] = []
    var failures: [InstantError] = []
  }

  private actor V3PlaybackTopicRecorder {
    private var observations: [(InstantRoomHandle, String)] = []
    private var publications: [V3PublishedTopic] = []
    private var terminations = 0
    private var continuation:
      AsyncStream<[InstantRoomTopicMessage]>.Continuation?

    func observe(
      room: InstantRoomHandle,
      topic: String
    ) -> AsyncStream<[InstantRoomTopicMessage]> {
      observations.append((room, topic))
      let stream = AsyncStream<[InstantRoomTopicMessage]>.makeStream(
        bufferingPolicy: .bufferingNewest(1)
      )
      continuation = stream.continuation
      stream.continuation.onTermination = { @Sendable _ in
        Task {
          await self.recordTermination()
        }
      }
      return stream.stream
    }

    func recordPublished(_ publication: V3PublishedTopic) {
      publications.append(publication)
    }

    func recordTermination() {
      terminations += 1
    }

    func yield(_ messages: [InstantRoomTopicMessage]) {
      continuation?.yield(messages)
    }

    func observed() -> [(InstantRoomHandle, String)] {
      observations
    }

    func published() -> [V3PublishedTopic] {
      publications
    }

    func terminationCount() -> Int {
      terminations
    }
  }

  private func v3PlaybackRoomClient(
    _ recorder: V3PlaybackRoomRecorder
  ) -> InstantSwiftDataClient {
    InstantSwiftDataClient(
      transact: { _ in fatalError("Unused playback room transaction") },
      query: { _ in [] },
      observe: { _ in AsyncStream { $0.finish() } },
      pendingMutations: { [] },
      localID: { $0 },
      joinRoom: { room in
        await recorder.recordJoin(room)
        return room
      },
      leaveRoom: { room in
        await recorder.recordLeave(room)
        return room
      }
    )
  }

  private func v3PlaybackPresenceClient(
    _ recorder: V3PlaybackPresenceRecorder
  ) -> InstantSwiftDataClient {
    InstantSwiftDataClient(
      transact: { _ in fatalError("Unused playback presence transaction") },
      query: { _ in [] },
      observe: { _ in AsyncStream { $0.finish() } },
      pendingMutations: { [] },
      localID: { $0 },
      setRoomPresence: { room, _, values in
        await recorder.recordPublished(values)
        return InstantRoomPresenceMember(
          appID: "playback-test",
          room: room,
          userID: "current-user",
          values: values,
          updatedAt: InstantTimestamp(milliseconds: 500)
        )
      },
      observeRoomPresence: { room in
        await recorder.observe(room: room)
      },
      leaveRoomPresence: { _, _ in
        await recorder.recordLeave()
        return "current-user"
      }
    )
  }

  private func v3PlaybackTopicClient(
    _ recorder: V3PlaybackTopicRecorder
  ) -> InstantSwiftDataClient {
    InstantSwiftDataClient(
      transact: { _ in fatalError("Unused playback topic transaction") },
      query: { _ in [] },
      observe: { _ in AsyncStream { $0.finish() } },
      pendingMutations: { [] },
      localID: { $0 },
      publishRoomTopicMessage: { room, topic, _, payload in
        await recorder.recordPublished(
          V3PublishedTopic(room: room, topic: topic, payload: payload)
        )
        return InstantRoomTopicMessage(
          id: "topic-message-1",
          appID: "playback-test",
          room: room,
          topic: topic,
          userID: "current-user",
          payload: payload,
          createdAt: InstantTimestamp(milliseconds: 1_500)
        )
      },
      observeRoomTopicMessages: { room, topic in
        await recorder.observe(room: room, topic: topic)
      }
    )
  }

  private func waitForV3PlaybackRoomCondition(
    operation: String,
    condition: @escaping @Sendable () async -> Bool
  ) async throws {
    let deadline = ContinuousClock.now + .seconds(2)
    while !(await condition()) {
      guard ContinuousClock.now < deadline else {
        throw InstantError(
          code: .implementationFailed,
          operation: operation,
          message: "Timed out waiting for playback room fixture state.",
          recovery: "Inspect the typed room lifecycle and fixture client."
        )
      }
      try await Task.sleep(for: .milliseconds(10))
    }
  }
#endif
