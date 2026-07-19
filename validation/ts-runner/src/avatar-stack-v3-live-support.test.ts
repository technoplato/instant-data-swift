import assert from "node:assert/strict";
import test from "node:test";

import {
  avatarStackOnlineCount,
  projectCanonicalAvatarPeer,
} from "./avatar-stack-v3-live-support.js";

test("live avatar support separates peer metadata from name-only app presence", () => {
  assert.deepEqual(
    projectCanonicalAvatarPeer({ peerId: "session-1", name: "uvwxyz" }),
    { peerId: "session-1", presence: { name: "uvwxyz" } },
  );
  assert.throws(
    () => projectCanonicalAvatarPeer({
      peerId: "session-1",
      name: "uvwxyz",
      userID: "widened-app-data",
    }),
    /exact avatar-stack peer shape/i,
  );
  assert.equal(avatarStackOnlineCount([{ peerId: "session-1", name: "uvwxyz" }]), 2);
});
