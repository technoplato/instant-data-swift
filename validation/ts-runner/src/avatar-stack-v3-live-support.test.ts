import assert from "node:assert/strict";
import test from "node:test";

import {
  avatarStackOnlineCount,
  publicAvatarStackUserEvidence,
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

test("avatar evidence strips refresh tokens from canonical Admin SDK users", () => {
  assert.deepEqual(
    publicAvatarStackUserEvidence({
      app_id: "app-1",
      id: "user-1",
      email: "avatar@example.com",
      created_at: "2026-07-19T03:40:40Z",
      isGuest: false,
      refresh_token: "must-not-enter-evidence",
    }),
    {
      appID: "app-1",
      id: "user-1",
      email: "avatar@example.com",
      createdAt: "2026-07-19T03:40:40Z",
      isGuest: false,
    },
  );
});
