import assert from "node:assert/strict";
import test from "node:test";

import {
  syncUpsV3AppContract,
  syncUpsV3Themes,
  type SyncUpsV3SyncUp,
} from "./syncups-v3-app-contract.js";

test("SyncUps V3 pins the SQLiteData source and exact Instant graph", () => {
  assert.deepEqual(syncUpsV3AppContract.namespaces, ["syncUps", "attendees", "meetings"]);
  assert.deepEqual(syncUpsV3AppContract.links, ["syncUpsAttendees", "syncUpsMeetings"]);
  assert.equal(
    syncUpsV3AppContract.upstream.revision,
    "0c79d7a5748fc6d9ce7a1ba2b50f31b175305049",
  );
  assert.equal(syncUpsV3AppContract.compilerWarningCount, 0);
});

test("SyncUps V3 preserves every upstream theme string", () => {
  assert.deepEqual(syncUpsV3Themes, [
    "appIndigo",
    "appMagenta",
    "appOrange",
    "appPurple",
    "appTeal",
    "appYellow",
    "bubblegum",
    "buttercup",
    "lavender",
    "navy",
    "oxblood",
    "periwinkle",
    "poppy",
    "seafoam",
    "sky",
    "tan",
  ]);
});

test("SyncUps V3 preserves nested child and Date shapes", () => {
  const date = new Date("2026-07-19T08:00:00.000Z");
  const syncUp: SyncUpsV3SyncUp = {
    id: syncUpsV3AppContract.fixtures.syncUp,
    seconds: 300,
    theme: "appOrange",
    title: "Design",
    attendees: [
      { id: syncUpsV3AppContract.fixtures.swiftAttendee, name: "Blob" },
    ],
    meetings: [
      {
        id: syncUpsV3AppContract.fixtures.swiftMeeting,
        date,
        transcript: "Reviewed launch risks.",
      },
    ],
  };

  assert.deepEqual(structuredClone(syncUp), syncUp);
});
