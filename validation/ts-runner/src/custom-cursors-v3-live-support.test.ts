import assert from "node:assert/strict";
import test from "node:test";

import { customCursorsV3AppContract } from "./custom-cursors-v3-app-contract.js";
import {
  projectCanonicalCustomCursorPeer,
  publicCustomCursorsUserEvidence,
  visibleCustomCursorPeers,
} from "./custom-cursors-v3-live-support.js";

test("live custom cursor support keeps name beside exact dynamic cursor presence", () => {
  const spaceID = customCursorsV3AppContract.room.spaceID;
  const fixture = customCursorsV3AppContract.fixtures.swift;
  assert.deepEqual(
    projectCanonicalCustomCursorPeer({
      peerId: "session-1",
      name: fixture.name,
      [spaceID]: fixture.cursor,
    }),
    {
      peerId: "session-1",
      name: fixture.name,
      cursor: fixture.cursor,
    },
  );
  assert.deepEqual(
    projectCanonicalCustomCursorPeer({ peerId: "session-2", name: "idle-avatar" }),
    { peerId: "session-2", name: "idle-avatar", cursor: null },
  );
  assert.throws(
    () => projectCanonicalCustomCursorPeer({ peerId: "missing-name" }),
    /exact custom cursors peer shape/i,
  );
  assert.throws(
    () => projectCanonicalCustomCursorPeer({
      peerId: "session-1",
      name: fixture.name,
      [spaceID]: fixture.cursor,
      userID: "widened-app-data",
    }),
    /exact custom cursors peer shape/i,
  );
  assert.throws(
    () => projectCanonicalCustomCursorPeer({
      peerId: "session-1",
      name: fixture.name,
      [spaceID]: { ...fixture.cursor, name: "nested-extra" },
    }),
    /exact custom cursors payload shape/i,
  );
});

test("live custom cursor support renders only named peers with an active cursor", () => {
  const spaceID = customCursorsV3AppContract.room.spaceID;
  const fixture = customCursorsV3AppContract.fixtures.swift;
  assert.deepEqual(
    visibleCustomCursorPeers([
      { peerId: "active", name: fixture.name, [spaceID]: fixture.cursor },
      { peerId: "idle", name: "idle-avatar" },
    ]),
    [{ peerId: "active", name: fixture.name, cursor: fixture.cursor }],
  );
});

test("custom cursor evidence strips refresh tokens from Admin SDK users", () => {
  assert.deepEqual(
    publicCustomCursorsUserEvidence({
      app_id: "app-1",
      id: "user-1",
      email: "custom-cursor@example.com",
      created_at: "2026-07-19T04:30:00Z",
      isGuest: false,
      refresh_token: "must-not-enter-evidence",
    }),
    {
      appID: "app-1",
      id: "user-1",
      email: "custom-cursor@example.com",
      createdAt: "2026-07-19T04:30:00Z",
      isGuest: false,
    },
  );
});
