import assert from "node:assert/strict";
import test from "node:test";

import {
  projectCanonicalStroopwafelGame,
  projectCanonicalStroopwafelPoint,
  projectCanonicalStroopwafelRoom,
  publicStroopwafelV3UserEvidence,
} from "./stroopwafel-v3-live-support.js";

const users = [
  { id: "user-host", handle: "Host123", highScore: 0 },
  { id: "user-guest", handle: "Guest123", highScore: 0 },
];
const room = {
  id: "room-1",
  code: "AB12",
  hostId: "user-host",
  readyIds: ["user-guest"],
  kickedIds: [],
  currentGameId: "game-1",
  created_at: "2026-07-19T00:00:00.000Z",
  users,
};
const prompts = Array.from({ length: 14 }, (_, index) => ({
  color: (["red", "green", "blue", "yellow"] as const)[index % 4],
  label: (["green", "blue", "yellow", "red"] as const)[index % 4],
}));
const game = {
  id: "game-1",
  status: "GAME_IN_PROGRESS",
  playerIds: ["user-host", "user-guest"],
  colors: prompts,
  created_at: "2026-07-19T00:00:01.000Z",
  users,
  rooms: [room],
  points: [
    { id: "point-host", val: 0, userId: "user-host" },
    { id: "point-guest", val: 0, userId: "user-guest" },
  ],
};

test("live Stroopwafel support accepts the exact room and game graphs", () => {
  assert.deepEqual(projectCanonicalStroopwafelRoom(room), room);
  assert.deepEqual(projectCanonicalStroopwafelGame(game), game);
  assert.deepEqual(projectCanonicalStroopwafelPoint(game.points[0]), game.points[0]);
});

test("live Stroopwafel support rejects widened and malformed data", () => {
  assert.throws(
    () => projectCanonicalStroopwafelRoom({ ...room, widened: true }),
    /exact canonical Stroopwafel room/i,
  );
  assert.throws(
    () => projectCanonicalStroopwafelGame({ ...game, colors: prompts.slice(0, 13) }),
    /14 color prompts/i,
  );
  assert.throws(
    () => projectCanonicalStroopwafelGame({
      ...game,
      points: [{ id: "point-host", val: "0", userId: "user-host" }],
    }),
    /exact canonical Stroopwafel point/i,
  );
});

test("Stroopwafel evidence strips Admin SDK refresh tokens", () => {
  assert.deepEqual(
    publicStroopwafelV3UserEvidence({
      app_id: "app-1",
      id: "user-1",
      email: "stroopwafel@example.com",
      created_at: "2026-07-19T00:00:00Z",
      isGuest: false,
      refresh_token: "must-not-enter-evidence",
    }),
    {
      appID: "app-1",
      id: "user-1",
      email: "stroopwafel@example.com",
      createdAt: "2026-07-19T00:00:00Z",
      isGuest: false,
    },
  );
});
