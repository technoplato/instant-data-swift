import assert from "node:assert/strict";
import test from "node:test";
import { playbackRoomContract } from "./playback-room-sdk-contract.ts";

test("playback room contract preserves exact payloads before and after reconnect", () => {
  const contract = playbackRoomContract({
    swiftUserID: "swift-user",
    typeScriptUserID: "typescript-user",
  });

  assert.equal(contract.roomType, "recording.playback");
  assert.deepEqual(contract.initial.swift.presence, {
    userID: "swift-user",
    displayName: "Swift Listener",
    isPlaying: true,
    offsetSeconds: 12.5,
    focusedSegmentID: "segment-swift",
  });
  assert.deepEqual(contract.initial.typeScript.topics, {
    reaction: { emoji: "typescript-wave", offsetSeconds: 4.25 },
    commentDraft: { text: "TypeScript draft", offsetSeconds: 4.25 },
    commentCommitted: { commentID: "comment-typescript" },
  });
  assert.deepEqual(contract.reconnect.swift.topics, {
    reaction: { emoji: "swift-rejoined", offsetSeconds: 18.75 },
    commentDraft: { text: "Swift draft after reconnect", offsetSeconds: 18.75 },
    commentCommitted: { commentID: "comment-swift-rejoined" },
  });
  assert.deepEqual(contract.reconnect.typeScript.presence, {
    userID: "typescript-user",
    displayName: "TypeScript Listener Rejoined",
    isPlaying: true,
    offsetSeconds: 9.5,
    focusedSegmentID: "segment-typescript-rejoined",
  });
});
