import assert from "node:assert/strict";
import test from "node:test";

import { projectCanonicalSyncUpsV3SyncUp } from "./syncups-v3-live-support.js";

test("projects the canonical nested SyncUps graph", () => {
  const date = new Date("2026-07-19T08:00:00.000Z");
  assert.deepEqual(
    projectCanonicalSyncUpsV3SyncUp({
      id: "00000000-0000-4000-8000-000000000501",
      seconds: 300,
      theme: "appOrange",
      title: "Design",
      attendees: [
        { id: "00000000-0000-4000-8000-000000000502", name: "Blob" },
      ],
      meetings: [
        {
          id: "00000000-0000-4000-8000-000000000503",
          date,
          transcript: "Reviewed launch risks.",
        },
      ],
    }),
    {
      id: "00000000-0000-4000-8000-000000000501",
      seconds: 300,
      theme: "appOrange",
      title: "Design",
      attendees: [
        { id: "00000000-0000-4000-8000-000000000502", name: "Blob" },
      ],
      meetings: [
        {
          id: "00000000-0000-4000-8000-000000000503",
          date,
          transcript: "Reviewed launch risks.",
        },
      ],
    },
  );
});

test("rejects drifted SyncUps scalar, theme, child, and Date shapes", () => {
  const base = {
    id: "sync-up",
    seconds: 300,
    theme: "appOrange",
    title: "Design",
    attendees: [{ id: "attendee", name: "Blob" }],
    meetings: [
      { id: "meeting", date: new Date("2026-07-19T08:00:00.000Z"), transcript: "Notes" },
    ],
  };

  for (const drifted of [
    { ...base, seconds: 300.5 },
    { ...base, theme: "orange" },
    { ...base, attendees: [{ id: "attendee", name: "Blob", syncUp: "sync-up" }] },
    { ...base, meetings: [{ id: "meeting", date: 1_784_467_200_000, transcript: "Notes" }] },
  ]) {
    assert.throws(
      () => projectCanonicalSyncUpsV3SyncUp(drifted),
      /canonical SyncUps V3 nested graph shape/,
    );
  }
});
