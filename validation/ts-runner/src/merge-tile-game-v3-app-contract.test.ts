import assert from "node:assert/strict";
import test from "node:test";

import {
  mergeTileGameBoardPatch,
  mergeTileGameEmptyState,
  mergeTileGameMergedState,
  mergeTileGamePresence,
  mergeTileGameV3AppContract,
} from "./merge-tile-game-v3-app-contract.js";

test("Merge Tile Game V3 pins the exact canonical board, room, and palette", () => {
  assert.deepEqual(mergeTileGameV3AppContract, {
    upstream: {
      repository: "https://github.com/instantdb/instant",
      revision: "e71017612aed4031710a35e2fcace30d38d557ac",
      recipe: "client/www/lib/recipes/merge-tile-game.tsx",
    },
    namespace: "boards",
    board: {
      id: "83c059e2-ed47-42e5-bdd9-6de88d26c521",
      size: 4,
      emptyColor: "#f5f3f0",
    },
    room: {
      type: "tile-game-example",
      id: "_defaultRoomId",
    },
    colors: ["#e76f51", "#2a9d8f", "#e9c46a", "#264653", "#f4a261", "#d4a0d0"],
    fixtures: {
      swift: { cell: "0-0", color: "#e76f51" },
      typeScript: { cell: "0-1", color: "#2a9d8f" },
    },
    compilerWarningCount: 0,
  });
});

test("Merge Tile Game V3 creates the exact 4 by 4 empty board", () => {
  const state = mergeTileGameEmptyState();
  assert.equal(Object.keys(state).length, 16);
  assert.deepEqual(state, {
    "0-0": "#f5f3f0", "0-1": "#f5f3f0", "0-2": "#f5f3f0", "0-3": "#f5f3f0",
    "1-0": "#f5f3f0", "1-1": "#f5f3f0", "1-2": "#f5f3f0", "1-3": "#f5f3f0",
    "2-0": "#f5f3f0", "2-1": "#f5f3f0", "2-2": "#f5f3f0", "2-3": "#f5f3f0",
    "3-0": "#f5f3f0", "3-1": "#f5f3f0", "3-2": "#f5f3f0", "3-3": "#f5f3f0",
  });
});

test("Merge Tile Game V3 deep-merges one cell without overwriting another client", () => {
  const swift = mergeTileGameV3AppContract.fixtures.swift;
  const typeScript = mergeTileGameV3AppContract.fixtures.typeScript;
  const first = mergeTileGameMergedState(
    mergeTileGameEmptyState(),
    mergeTileGameBoardPatch(swift.cell, swift.color),
  );
  const second = mergeTileGameMergedState(
    first,
    mergeTileGameBoardPatch(typeScript.cell, typeScript.color),
  );

  assert.deepEqual(mergeTileGameBoardPatch(swift.cell, swift.color), {
    state: { "0-0": "#e76f51" },
  });
  assert.equal(second[swift.cell], swift.color);
  assert.equal(second[typeScript.cell], typeScript.color);
  assert.equal(Object.keys(second).length, 16);
});

test("Merge Tile Game V3 publishes only the canonical color presence", () => {
  assert.deepEqual(mergeTileGamePresence("#e76f51"), { color: "#e76f51" });
});
