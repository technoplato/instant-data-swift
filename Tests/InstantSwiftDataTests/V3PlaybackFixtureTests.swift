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
    #endif
  }

  @MainActor
  private struct V3PlaybackRoomFixture: View {
    let recordingID: String

    @Room
    private var room: InstantRoom<V3PlaybackRoomSchema>

    var body: some View {
      Text(room.id ?? "Joining")
        .instantRoom(
          $room,
          V3PlaybackRooms.activeRecording(recordingID)
        )
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
    struct Presence: Codable, Sendable {
      var displayName: String
    }

    enum Topic: String, InstantRoomTopic {
      case reaction
      case commentDraft
    }
  }

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
