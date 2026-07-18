import { init } from "@instantdb/core";

import schema from "./recording-action.schema.js";

const db = init({ appId: "playback-room-typecheck", schema });
const room = db.joinRoom("recording.playback", "recording-typecheck");

room.publishPresence({
  userID: "user-typecheck",
  displayName: "Ada",
  isPlaying: true,
  offsetSeconds: 12.5,
  focusedSegmentID: "segment-typecheck",
});
room.publishTopic("reaction", { emoji: "wave", offsetSeconds: 12.5 });
room.publishTopic("commentDraft", { text: "Draft", offsetSeconds: 12.5 });
room.publishTopic("commentCommitted", { commentID: "comment-typecheck" });

room.subscribePresence(
  {
    keys: [
      "userID",
      "displayName",
      "isPlaying",
      "offsetSeconds",
      "focusedSegmentID",
    ],
  },
  (presence) => {
    presence.user?.offsetSeconds.toFixed();
    presence.user?.focusedSegmentID?.toUpperCase();
  },
);
room.subscribeTopic("reaction", (event) => {
  event.offsetSeconds.toFixed();
  event.emoji.toUpperCase();
});

// @ts-expect-error The generated schema must reject unknown room names.
db.joinRoom("unknown.room", "recording-typecheck");
// @ts-expect-error The generated presence contract requires a numeric offset.
room.publishPresence({ offsetSeconds: "12.5" });
// @ts-expect-error The generated topic contract must reject unknown topics.
room.publishTopic("unknownTopic", {});
// @ts-expect-error The generated reaction topic requires both declared fields.
room.publishTopic("reaction", { emoji: "wave" });
