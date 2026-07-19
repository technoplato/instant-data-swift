import assert from "node:assert/strict";
import test from "node:test";

import {
  projectCanonicalCursorPeer,
  publicCursorsUserEvidence,
  visibleCursorPeers,
} from "./cursors-v3-live-support.js";
import { cursorsV3AppContract } from "./cursors-v3-app-contract.js";

test("live cursor support separates peer metadata from exact dynamic presence", () => {
  const spaceID = cursorsV3AppContract.room.spaceID;
  assert.deepEqual(
    projectCanonicalCursorPeer({
      peerId: "session-1",
      [spaceID]: cursorsV3AppContract.fixtures.swift,
    }),
    {
      peerId: "session-1",
      cursor: cursorsV3AppContract.fixtures.swift,
    },
  );
  assert.deepEqual(
    projectCanonicalCursorPeer({ peerId: "session-2" }),
    { peerId: "session-2", cursor: null },
  );
  assert.throws(
    () => projectCanonicalCursorPeer({
      peerId: "session-1",
      [spaceID]: cursorsV3AppContract.fixtures.swift,
      userID: "widened-app-data",
    }),
    /exact cursors peer shape/i,
  );
  assert.throws(
    () => projectCanonicalCursorPeer({
      peerId: "session-1",
      [spaceID]: { ...cursorsV3AppContract.fixtures.swift, name: "extra" },
    }),
    /exact cursors payload shape/i,
  );
});

test("live cursor support renders only peers with a cursor", () => {
  const spaceID = cursorsV3AppContract.room.spaceID;
  assert.deepEqual(
    visibleCursorPeers([
      { peerId: "active", [spaceID]: cursorsV3AppContract.fixtures.swift },
      { peerId: "idle" },
    ]),
    [{ peerId: "active", cursor: cursorsV3AppContract.fixtures.swift }],
  );
});

test("cursor evidence strips refresh tokens from Admin SDK users", () => {
  assert.deepEqual(
    publicCursorsUserEvidence({
      app_id: "app-1",
      id: "user-1",
      email: "cursor@example.com",
      created_at: "2026-07-19T04:00:00Z",
      isGuest: false,
      refresh_token: "must-not-enter-evidence",
    }),
    {
      appID: "app-1",
      id: "user-1",
      email: "cursor@example.com",
      createdAt: "2026-07-19T04:00:00Z",
      isGuest: false,
    },
  );
});
