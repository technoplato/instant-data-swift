import assert from "node:assert/strict";
import test from "node:test";

import {
  mergeTileGameEmptyState,
  mergeTileGameV3AppContract,
} from "./merge-tile-game-v3-app-contract.js";
import {
  projectCanonicalMergeTileBoard,
  projectCanonicalMergeTilePeer,
  publicMergeTileGameUserEvidence,
} from "./merge-tile-game-v3-live-support.js";

test("live merge tile support accepts only the fixed 16-cell board", () => {
  const board = {
    id: mergeTileGameV3AppContract.board.id,
    state: mergeTileGameEmptyState(),
  };
  assert.deepEqual(projectCanonicalMergeTileBoard(board), board);
  assert.throws(
    () => projectCanonicalMergeTileBoard({ ...board, extra: true }),
    /exact Merge Tile Game board shape/i,
  );
  const missingCell = { ...board.state };
  delete missingCell["3-3"];
  assert.throws(
    () => projectCanonicalMergeTileBoard({ ...board, state: missingCell }),
    /all 16 canonical cells/i,
  );
  assert.throws(
    () => projectCanonicalMergeTileBoard({
      ...board,
      state: { ...board.state, "0-0": 42 },
    }),
    /allowed string colors/i,
  );
});

test("live merge tile support rejects widened or invalid peer presence", () => {
  assert.deepEqual(
    projectCanonicalMergeTilePeer({ peerId: "peer-1", color: "#e76f51" }),
    { peerId: "peer-1", color: "#e76f51" },
  );
  assert.throws(
    () => projectCanonicalMergeTilePeer({
      peerId: "peer-1",
      color: "#e76f51",
      userID: "widened-app-data",
    }),
    /exact Merge Tile Game peer shape/i,
  );
  assert.throws(
    () => projectCanonicalMergeTilePeer({ peerId: "peer-1", color: "#000000" }),
    /canonical color/i,
  );
});

test("merge tile evidence strips refresh tokens from Admin SDK users", () => {
  assert.deepEqual(
    publicMergeTileGameUserEvidence({
      app_id: "app-1",
      id: "user-1",
      email: "merge-tile@example.com",
      created_at: "2026-07-19T04:45:00Z",
      isGuest: false,
      refresh_token: "must-not-enter-evidence",
    }),
    {
      appID: "app-1",
      id: "user-1",
      email: "merge-tile@example.com",
      createdAt: "2026-07-19T04:45:00Z",
      isGuest: false,
    },
  );
});
