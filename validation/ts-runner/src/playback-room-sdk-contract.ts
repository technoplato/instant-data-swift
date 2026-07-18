export type PlaybackRoomPresence = {
  userID: string;
  displayName: string;
  isPlaying: boolean;
  offsetSeconds: number;
  focusedSegmentID: string;
};

export type PlaybackRoomTopics = {
  reaction: { emoji: string; offsetSeconds: number };
  commentDraft: { text: string; offsetSeconds: number };
  commentCommitted: { commentID: string };
};

export type PlaybackRoomPeerPayloads = {
  presence: PlaybackRoomPresence;
  topics: PlaybackRoomTopics;
};

export type PlaybackRoomContract = {
  roomType: "recording.playback";
  initial: {
    swift: PlaybackRoomPeerPayloads;
    typeScript: PlaybackRoomPeerPayloads;
  };
  reconnect: {
    swift: PlaybackRoomPeerPayloads;
    typeScript: PlaybackRoomPeerPayloads;
  };
};

export function playbackRoomContract(users: {
  swiftUserID: string;
  typeScriptUserID: string;
}): PlaybackRoomContract {
  return {
    roomType: "recording.playback",
    initial: {
      swift: {
        presence: {
          userID: users.swiftUserID,
          displayName: "Swift Listener",
          isPlaying: true,
          offsetSeconds: 12.5,
          focusedSegmentID: "segment-swift",
        },
        topics: {
          reaction: { emoji: "swift-wave", offsetSeconds: 12.5 },
          commentDraft: { text: "Swift draft", offsetSeconds: 12.5 },
          commentCommitted: { commentID: "comment-swift" },
        },
      },
      typeScript: {
        presence: {
          userID: users.typeScriptUserID,
          displayName: "TypeScript Listener",
          isPlaying: false,
          offsetSeconds: 4.25,
          focusedSegmentID: "segment-typescript",
        },
        topics: {
          reaction: { emoji: "typescript-wave", offsetSeconds: 4.25 },
          commentDraft: { text: "TypeScript draft", offsetSeconds: 4.25 },
          commentCommitted: { commentID: "comment-typescript" },
        },
      },
    },
    reconnect: {
      swift: {
        presence: {
          userID: users.swiftUserID,
          displayName: "Swift Listener Rejoined",
          isPlaying: false,
          offsetSeconds: 18.75,
          focusedSegmentID: "segment-swift-rejoined",
        },
        topics: {
          reaction: { emoji: "swift-rejoined", offsetSeconds: 18.75 },
          commentDraft: {
            text: "Swift draft after reconnect",
            offsetSeconds: 18.75,
          },
          commentCommitted: { commentID: "comment-swift-rejoined" },
        },
      },
      typeScript: {
        presence: {
          userID: users.typeScriptUserID,
          displayName: "TypeScript Listener Rejoined",
          isPlaying: true,
          offsetSeconds: 9.5,
          focusedSegmentID: "segment-typescript-rejoined",
        },
        topics: {
          reaction: { emoji: "typescript-rejoined", offsetSeconds: 9.5 },
          commentDraft: {
            text: "TypeScript draft after reconnect",
            offsetSeconds: 9.5,
          },
          commentCommitted: { commentID: "comment-typescript-rejoined" },
        },
      },
    },
  };
}
