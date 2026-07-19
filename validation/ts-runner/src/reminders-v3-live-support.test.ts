import assert from "node:assert/strict";
import test from "node:test";

import {
  projectCanonicalRemindersV3List,
  projectCanonicalRemindersV3Reminder,
} from "./reminders-v3-live-support.js";

test("projects the canonical shared Reminders list graph", () => {
  assert.deepEqual(
    projectCanonicalRemindersV3List({
      id: "00000000-0000-4000-8000-000000000401",
      title: "Family",
      color: "#4a99ef",
      position: 0,
      createdAt: 1_700_000_000_000,
      owner: { id: "owner-user" },
      readers: [],
      writers: [{ id: "reader-user" }],
      reminders: [],
      share: {
        id: "00000000-0000-4000-8000-000000000403",
        token: "reminders-v3-share",
        rootNamespace: "remindersLists",
        rootID: "00000000-0000-4000-8000-000000000401",
        createdAt: 1_700_000_000_000,
        updatedAt: 1_700_000_001_000,
        owner: { id: "owner-user" },
        memberships: [
          {
            id: "00000000-0000-4000-8000-000000000404",
            role: "owner",
            acceptedAt: 1_700_000_000_000,
            user: { id: "owner-user" },
          },
          {
            id: "00000000-0000-4000-8000-000000000405",
            role: "writer",
            acceptedAt: 1_700_000_001_000,
            user: { id: "reader-user" },
          },
        ],
      },
    }),
    {
      id: "00000000-0000-4000-8000-000000000401",
      title: "Family",
      color: "#4a99ef",
      position: 0,
      createdAt: 1_700_000_000_000,
      owner: { id: "owner-user" },
      readers: [],
      writers: [{ id: "reader-user" }],
      reminders: [],
      share: {
        id: "00000000-0000-4000-8000-000000000403",
        token: "reminders-v3-share",
        rootNamespace: "remindersLists",
        rootID: "00000000-0000-4000-8000-000000000401",
        createdAt: 1_700_000_000_000,
        updatedAt: 1_700_000_001_000,
        owner: { id: "owner-user" },
        memberships: [
          {
            id: "00000000-0000-4000-8000-000000000404",
            role: "owner",
            acceptedAt: 1_700_000_000_000,
            user: { id: "owner-user" },
          },
          {
            id: "00000000-0000-4000-8000-000000000405",
            role: "writer",
            acceptedAt: 1_700_000_001_000,
            user: { id: "reader-user" },
          },
        ],
      },
    },
  );
});

test("projects canonical numeric priority, nullable due date, and tags", () => {
  assert.deepEqual(
    projectCanonicalRemindersV3Reminder({
      id: "00000000-0000-4000-8000-000000000406",
      title: "TypeScript reminder",
      notes: "Created by @instantdb/core",
      isCompleted: false,
      isFlagged: false,
      dueDate: null,
      priority: 2,
      position: 1,
      createdAt: 1_700_000_002_000,
      tags: [{ id: "typescript", title: "TypeScript" }],
    }),
    {
      id: "00000000-0000-4000-8000-000000000406",
      title: "TypeScript reminder",
      notes: "Created by @instantdb/core",
      isCompleted: false,
      isFlagged: false,
      priority: 2,
      position: 1,
      createdAt: 1_700_000_002_000,
      tags: [{ id: "typescript", title: "TypeScript" }],
    },
  );
});

test("rejects drifted Reminders wire shapes", () => {
  assert.throws(
    () => projectCanonicalRemindersV3Reminder({
      id: "reminder",
      title: "Wrong priority",
      notes: "",
      isCompleted: false,
      isFlagged: false,
      priority: "medium",
      position: 0,
      createdAt: 1,
      tags: [],
    }),
    /canonical Reminders V3 reminder shape/,
  );
});
