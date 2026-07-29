# Playback Screen, V3

> Design target: use current `Sources/` declarations and compiling fixtures in
> `Tests/` as the authoritative inventory of usable symbols.

URI: `recordings.playback`
(`voicetrail://recordings/:recordingID/playback`)

This screen demonstrates rooms, presence, topics, infinite comments, and
queryable files. The wrappers own observation. The call sites publish
messages and handle side effects for the specific user action.

The stable `recordingID` is a dynamic query input for this screen identity, so
the modifiers replace wrapper keys when that identity changes. Once attached,
the wrappers emit cached and optimistic state first and own live observation;
the screen never fetches, subscribes, or merges those values manually.

Implementation status (2026-07-18): the room/presence/topic surface is proven
through automatic disconnect and rejoin at `f1ddcea`. A fresh credentialed app
observed exact presence plus all three topic payloads in both directions before
and after the forced Swift transport loss, with no call-site socket management.
The recorded syntax is settled for app integration.

```swift
import SwiftUI
import Dependencies
import InstantSwiftData

struct VoiceTrailPlaybackScreen: View {
  let recordingID:
    InstantID<Recording>

  @InstantAuth(
    VoiceTrailUser.self,
    providers: VoiceTrailAuthProviders.self
  )
  private var auth

  @InstantAudioPlayer
  private var player

  @Dependency(\.defaultInstantSwiftData)
  private var db

  @Dependency(\.analytics)
  private var analytics

  @Dependency(\.haptics)
  private var haptics

  @Dependency(\.toast)
  private var toast

  @FetchOne
  private var recording:
    RecordingPlayback?

  @FetchOne
  private var audioFile:
    InstantFile<RecordingAudioPath>?

  /// Room membership is wrapper-owned state.
  ///
  /// The view sends presence and topic messages, but it does not manage
  /// socket lifetime or reconnection.
  @Room
  private var room:
    InstantRoom<ActiveRecordingRoom>

  @Presence
  private var listeners:
    [ActiveRecordingPresence]

  @Topic(
    ActiveRecordingRoom.Topic.reaction
  )
  private var reactions:
    InstantTopic<RecordingReaction>

  @Topic(
    ActiveRecordingRoom.Topic.commentDraft
  )
  private var commentDrafts:
    InstantTopic<RecordingCommentDraft>

  @InfiniteQuery
  private var comments:
    [RecordingComment]

  @State
  private var commentText = ""

  var body: some View {
    Group {
      if let recording {
        content(recording)
      } else {
        ProgressView()
      }
    }
    .instantFetch(
      $recording,
      Recording.playbackHeader(
        id: recordingID,
        viewer: .currentUser
      )
    )
    .instantFetch(
      $audioFile,
      InstantFile
        .wherePath(
          .recordingAudio(recordingID)
        )
        .one()
    )
    .instantRoom(
      $room,
      VoiceTrailRooms
        .activeRecording(recordingID)
    )
    .presence(
      $listeners,
      in: room,
      publishing: currentPresence
    )
    .instantTopic(
      $reactions,
      in: room
    )
    .instantTopic(
      $commentDrafts,
      in: room
    )
    .instantInfiniteQuery(
      $comments,
      RecordingComment.timeline(
        recording: recordingID,
        limit: 40
      )
    )
  }

  private var currentPresence:
    ActiveRecordingPresence? {
    guard let user = auth.user else {
      return nil
    }

    return ActiveRecordingPresence(
      userID: user.id,
      displayName: user.displayName,
      isPlaying: player.isPlaying,
      offset: player.currentTime,
      focusedSegmentID: nil
    )
  }

  private func content(
    _ recording: RecordingPlayback
  ) -> some View {
    VStack(spacing: 0) {
      header(recording)
      listenerStrip
      scrubber(recording)
      reactionBar
      commentComposer
      commentsList
    }
    .toolbar {
      ToolbarItemGroup(
        placement: .primaryAction
      ) {
        Button {
          shareButtonTapped(recording)
        } label: {
          Label(
            "Share",
            systemImage:
              "square.and.arrow.up"
          )
        }

        Button(role: .destructive) {
          deleteAudioButtonTapped()
        } label: {
          Label(
            "Delete audio",
            systemImage: "trash"
          )
        }
        .disabled(audioFile == nil)
      }
    }
  }

  private func header(
    _ recording: RecordingPlayback
  ) -> some View {
    VStack(
      alignment: .leading,
      spacing: 6
    ) {
      Text(recording.recording.title)
        .font(.title2.bold())

      Text(
        recording.recording.duration
          .formatted(
            .voiceTrailDuration
          )
      )
      .foregroundStyle(.secondary)
    }
    .frame(
      maxWidth: .infinity,
      alignment: .leading
    )
    .padding()
  }

  private var listenerStrip:
    some View {
    ScrollView(
      .horizontal,
      showsIndicators: false
    ) {
      HStack {
        ForEach(listeners) { listener in
          ListenerPill(listener: listener)
        }
      }
      .padding(.horizontal)
    }
  }

  private func scrubber(
    _ recording: RecordingPlayback
  ) -> some View {
    VStack {
      Slider(
        value: $player.currentSeconds,
        in:
          0
          ...
          recording.recording
            .duration
            .seconds
      )

      HStack {
        Button {
          player.skipBackward(
            seconds: 10
          )
        } label: {
          Label(
            "Back",
            systemImage: "gobackward.10"
          )
        }

        Button {
          playButtonTapped()
        } label: {
          Label(
            player.isPlaying
              ? "Pause"
              : "Play",
            systemImage:
              player.isPlaying
                ? "pause.fill"
                : "play.fill"
          )
        }
      }
    }
    .padding(.horizontal)
  }

  private var reactionBar:
    some View {
    HStack {
      ForEach(
        RecordingReaction.Kind.allCases
      ) { kind in
        Button {
          reactionButtonTapped(kind)
        } label: {
          Text(kind.title)
        }
      }
    }
    .padding()
  }

  private var commentComposer:
    some View {
    HStack {
      TextField(
        "Comment",
        text: $commentText
      )
      .onChange(of: commentText) { _, text in
        draftChanged(text)
      }

      Button {
        commentSendButtonTapped()
      } label: {
        Label(
          "Send",
          systemImage: "paperplane.fill"
        )
      }
      .disabled(commentText.isEmpty)
    }
    .padding()
  }

  private var commentsList:
    some View {
    List(comments) { comment in
      RecordingCommentRow(comment: comment)
        .onAppear {
          if comment.id == comments.last?.id {
            $comments.loadNextPage()
          }
        }
    }
  }

  private func playButtonTapped() {
    player.togglePlayback()
    haptics.selectionChanged()
  }

  private func reactionButtonTapped(
    _ kind: RecordingReaction.Kind
  ) {
    reactions.publish(
      RecordingReaction(
        kind: kind,
        offset: player.currentTime
      ),
      onPublished: { event in
        analytics.track(
          .recordingReactionSent(
            event.topicID,
            kind: kind
          )
        )
        haptics.success()
      },
      onFailure: { error in
        toast.show(error.recoveryMessage)
        haptics.error()
      }
    )
  }

  private func draftChanged(
    _ text: String
  ) {
    commentDrafts.publish(
      RecordingCommentDraft(
        text: text,
        offset: player.currentTime
      )
    )
  }

  private func commentSendButtonTapped() {
    let text = commentText
    commentText = ""

    db.send(
      CreateRecordingComment(
        recordingID: recordingID,
        text: text,
        offset: player.currentTime
      ),
      onOptimisticCommit: {
        (
          change:
            borrowing RecordingCommentCreatedChange
        ) in
        analytics.track(
          .recordingCommentCreated(
            change.commentID
          )
        )
        haptics.success()
      },
      onFailure: { error in
        commentText = text
        toast.show(error.recoveryMessage)
        haptics.error()
      }
    )
  }

  private func shareButtonTapped(
    _ recording: RecordingPlayback
  ) {
    recording.share()
  }

  private func deleteAudioButtonTapped() {
    guard let audioFile else { return }

    db.send(
      DeleteRecordingAudio(
        recordingID: recordingID,
        fileID: audioFile.id
      ),
      onOptimisticCommit: {
        (
          change:
            borrowing RecordingAudioDeletedChange
        ) in
        analytics.track(
          .audioDeleted(
            change.recordingID
          )
        )
        haptics.success()
      },
      onFailure: { error in
        toast.show(error.recoveryMessage)
        haptics.error()
      }
    )
  }
}

enum VoiceTrailRooms {
  static func activeRecording(
    _ id: InstantID<Recording>
  ) -> InstantRoom<ActiveRecordingRoom> {
    InstantRoom(
      type: "recording.playback",
      id: id.rawValue
    )
  }
}

struct ActiveRecordingRoom:
  InstantRoomSchema {
  typealias Presence =
    ActiveRecordingPresence

  enum Topic:
    String,
    InstantRoomTopic {
    typealias RoomSchema =
      ActiveRecordingRoom

    case reaction
    case commentDraft
    case commentCommitted
  }
}

struct ActiveRecordingPresence:
  Identifiable,
  Codable,
  Sendable,
  Equatable {
  var id:
    InstantID<VoiceTrailUser> {
    userID
  }

  var userID:
    InstantID<VoiceTrailUser>
  var displayName: String
  var isPlaying: Bool
  /// Canonical Instant wire value. Product code reads `offset` as `Duration`.
  var offsetSeconds: Double
  var focusedSegmentID:
    InstantID<TranscriptionSegment>?

  var offset: Duration {
    .seconds(offsetSeconds)
  }

  init(
    userID: InstantID<VoiceTrailUser>,
    displayName: String,
    isPlaying: Bool,
    offset: Duration,
    focusedSegmentID: InstantID<TranscriptionSegment>?
  ) {
    self.userID = userID
    self.displayName = displayName
    self.isPlaying = isPlaying
    let components = offset.components
    offsetSeconds =
      Double(components.seconds)
      + Double(components.attoseconds) / 1e18
    self.focusedSegmentID = focusedSegmentID
  }

  static func patch(
    offset: Duration,
    isPlaying: Bool
  ) -> InstantPresencePatch<Self> {
    let components = offset.components
    let offsetSeconds =
      Double(components.seconds)
      + Double(components.attoseconds) / 1e18
    InstantPresencePatch {
      Set(\.offsetSeconds, offsetSeconds)
      Set(\.isPlaying, isPlaying)
    }
  }
}
```

`ActiveRecordingPresence` therefore keeps the product-facing `Duration`
convenience without sending Foundation's synthesized duration shape. Its exact
room payload is `userID: string`, `displayName: string`, `isPlaying: boolean`,
`offsetSeconds: number`, and optional `focusedSegmentID: string`.
