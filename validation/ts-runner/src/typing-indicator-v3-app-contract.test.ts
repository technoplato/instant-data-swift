import assert from "node:assert/strict";
import test from "node:test";

import { typingIndicatorV3AppContract } from "./typing-indicator-v3-app-contract.js";

test("Typing Indicator V3 preserves the exact canonical presence frames", () => {
  assert.deepEqual(typingIndicatorV3AppContract, {
    upstream: {
      repository: "https://github.com/instantdb/instant",
      revision: "e71017612aed4031710a35e2fcace30d38d557ac",
      recipe: "client/www/lib/recipes/typing-indicator.tsx",
      helper: "client/packages/react-common/src/InstantReactRoom.ts",
    },
    room: {
      type: "typing-indicator-example",
      id: "1234",
      inputName: "chat-input",
    },
    frames: {
      initialPresence: { id: "typescript-peer" },
      activePatch: { "chat-input": true },
      inactivePatch: { "chat-input": false },
      timeoutPatch: { "chat-input": null },
    },
    activePeers: [{ id: "swift-peer", "chat-input": true }],
    ignoredPeers: [
      { id: "idle-peer", "chat-input": false },
      { id: "cleared-peer", "chat-input": null },
    ],
    compilerWarningCount: 0,
  });
});
