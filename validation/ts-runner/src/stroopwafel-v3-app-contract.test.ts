import assert from "node:assert/strict";
import test from "node:test";

import {
  stroopwafelEligiblePlayerIDs,
  stroopwafelReadyIDs,
  stroopwafelScoreTap,
  stroopwafelSoftDeletedRoom,
  stroopwafelV3AppContract,
  type StroopwafelV3ColorPrompt,
  type StroopwafelV3Room,
} from "./stroopwafel-v3-app-contract.js";

const room: StroopwafelV3Room = {
  id: "room-stroopwafel-v3",
  code: "AB12",
  hostId: "user-host",
  readyIds: ["user-ready"],
  kickedIds: ["user-kicked"],
  currentGameId: "game-stroopwafel-v3",
  created_at: "2026-07-19T00:00:00.000Z",
  users: [
    { id: "user-host", handle: "Host123", highScore: 0 },
    { id: "user-ready", handle: "Ready123", highScore: 0 },
    { id: "user-waiting", handle: "Waiting123", highScore: 0 },
  ],
};

test("Stroopwafel V3 pins the exact canonical source and durable graph", () => {
  assert.deepEqual(stroopwafelV3AppContract, {
    upstream: {
      repository: "https://github.com/jsventures/stroopwafel",
      revision: "7f5e2379464d932c0e4681655cbf022f8d9c2614",
      schema: "instant.schema.ts",
      permissions: "instant.perms.ts",
    },
    namespaces: ["$users", "rooms", "games", "points"],
    links: ["roomUsers", "gameUsers", "gameRooms", "gamePoints"],
    game: {
      inProgress: "GAME_IN_PROGRESS",
      completed: "GAME_COMPLETED",
      scoreToWin: 13,
      promptCount: 14,
      colors: ["red", "green", "blue", "yellow"],
    },
    fixtures: {
      room: { id: "room-stroopwafel-v3", code: "AB12" },
      game: { id: "game-stroopwafel-v3" },
    },
    compilerWarningCount: 0,
  });
});

test("Stroopwafel V3 preserves canonical room field names and JSON arrays", () => {
  assert.deepEqual(JSON.parse(JSON.stringify(room)), room);
  assert.deepEqual(stroopwafelEligiblePlayerIDs(room), ["user-host", "user-ready"]);
  assert.deepEqual(stroopwafelReadyIDs([], "user-ready", true), ["user-ready"]);
  assert.deepEqual(stroopwafelReadyIDs(["user-ready"], "user-ready", true), ["user-ready"]);
  assert.deepEqual(stroopwafelReadyIDs(["user-ready"], "user-ready", false), []);
});

test("Stroopwafel V3 applies plus one, clamped minus two, and completion at 13", () => {
  const prompt: StroopwafelV3ColorPrompt = { color: "red", label: "green" };
  assert.deepEqual(stroopwafelScoreTap(0, prompt, "red"), {
    value: 0,
    status: "GAME_IN_PROGRESS",
    clearsCurrentGame: false,
  });
  assert.deepEqual(stroopwafelScoreTap(5, prompt, "red"), {
    value: 3,
    status: "GAME_IN_PROGRESS",
    clearsCurrentGame: false,
  });
  assert.deepEqual(stroopwafelScoreTap(12, prompt, "green"), {
    value: 13,
    status: "GAME_COMPLETED",
    clearsCurrentGame: true,
  });
});

test("Stroopwafel V3 host leave clears code and records deleted_at", () => {
  assert.deepEqual(
    stroopwafelSoftDeletedRoom(room, "2026-07-19T00:01:00.000Z"),
    {
      id: "room-stroopwafel-v3",
      hostId: "user-host",
      readyIds: ["user-ready"],
      kickedIds: ["user-kicked"],
      currentGameId: "game-stroopwafel-v3",
      created_at: "2026-07-19T00:00:00.000Z",
      deleted_at: "2026-07-19T00:01:00.000Z",
      users: room.users,
    },
  );
});
