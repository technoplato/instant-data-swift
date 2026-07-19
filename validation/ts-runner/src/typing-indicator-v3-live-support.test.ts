import assert from "node:assert/strict";
import test from "node:test";

import {
  activeTypingPeerIDs,
  exactTypingIndicatorFrames,
  phaseForTypingIndicatorPresence,
  projectCanonicalTypingPeer,
  typeScriptPatchObservedTypingIndicatorFrames,
} from "./typing-indicator-v3-live-support.js";

test("live typing support preserves the canonical absent, true, false, and null frames", () => {
  const frames = exactTypingIndicatorFrames("typescript-peer");

  assert.deepEqual(frames, [
    { phase: "initial", presence: { id: "typescript-peer" } },
    { phase: "active", presence: { id: "typescript-peer", "chat-input": true } },
    { phase: "inactive", presence: { id: "typescript-peer", "chat-input": false } },
    { phase: "cleared", presence: { id: "typescript-peer", "chat-input": null } },
  ]);
  assert.deepEqual(frames.map(({ presence }) => phaseForTypingIndicatorPresence(presence)), [
    "initial",
    "active",
    "inactive",
    "cleared",
  ]);
  assert.deepEqual(typeScriptPatchObservedTypingIndicatorFrames("typescript-peer"), [
    ...frames,
  ]);
});

test("live typing support filters only true remote peers and rejects widened shapes", () => {
  assert.deepEqual(
    activeTypingPeerIDs(
      [
        { id: "swift-peer", "chat-input": true },
        { id: "typescript-peer", "chat-input": true },
        { id: "idle-peer", "chat-input": false },
        { id: "cleared-peer", "chat-input": null },
      ],
      "typescript-peer",
    ),
    ["swift-peer"],
  );
  assert.deepEqual(
    projectCanonicalTypingPeer({
      id: "swift-peer",
      "chat-input": true,
      peerId: "canonical-session-id",
    }),
    {
      peerId: "canonical-session-id",
      presence: { id: "swift-peer", "chat-input": true },
    },
  );
  assert.throws(
    () => projectCanonicalTypingPeer({
      id: "peer",
      "chat-input": true,
      peerId: "canonical-session-id",
      displayName: "No",
    }),
    /exact typing-indicator presence shape/i,
  );
});
