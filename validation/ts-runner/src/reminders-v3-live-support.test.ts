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
      createdAt: new Date("2023-11-14T22:13:20.000Z"),
      owner: {
        id: "owner-user",
        email: "owner@example.com",
        displayName: "Owner",
        username: "owner",
      },
      readers: [],
      writers: [{ id: "reader-user" }],
      reminders: [],
      share: {
        id: "00000000-0000-4000-8000-000000000403",
        token: "reminders-v3-share",
        rootNamespace: "remindersLists",
        rootID: "00000000-0000-4000-8000-000000000401",
        createdAt: new Date("2023-11-14T22:13:20.000Z"),
        updatedAt: new Date("2023-11-14T22:13:21.000Z"),
        owner: { id: "owner-user" },
        memberships: [
          {
            id: "00000000-0000-4000-8000-000000000404",
            role: "owner",
            acceptedAt: new Date("2023-11-14T22:13:20.000Z"),
            user: { id: "owner-user" },
          },
          {
            id: "00000000-0000-4000-8000-000000000405",
            role: "writer",
            acceptedAt: new Date("2023-11-14T22:13:21.000Z"),
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
      createdAt: new Date("2023-11-14T22:13:20.000Z"),
      owner: {
        id: "owner-user",
        email: "owner@example.com",
        displayName: "Owner",
        username: "owner",
      },
      readers: [],
      writers: [{ id: "reader-user" }],
      reminders: [],
      share: {
        id: "00000000-0000-4000-8000-000000000403",
        token: "reminders-v3-share",
        rootNamespace: "remindersLists",
        rootID: "00000000-0000-4000-8000-000000000401",
        createdAt: new Date("2023-11-14T22:13:20.000Z"),
        updatedAt: new Date("2023-11-14T22:13:21.000Z"),
        owner: { id: "owner-user" },
        memberships: [
          {
            id: "00000000-0000-4000-8000-000000000404",
            role: "owner",
            acceptedAt: new Date("2023-11-14T22:13:20.000Z"),
            user: { id: "owner-user" },
          },
          {
            id: "00000000-0000-4000-8000-000000000405",
            role: "writer",
            acceptedAt: new Date("2023-11-14T22:13:21.000Z"),
            user: { id: "reader-user" },
          },
        ],
      },
    },
  );
});

test("projects canonical Date, numeric priority, nullable due date, and tags", () => {
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
      createdAt: new Date("2023-11-14T22:13:22.000Z"),
      tags: [{ id: "00000000-0000-4000-8000-000000000408", title: "typescript" }],
    }),
    {
      id: "00000000-0000-4000-8000-000000000406",
      title: "TypeScript reminder",
      notes: "Created by @instantdb/core",
      isCompleted: false,
      isFlagged: false,
      priority: 2,
      position: 1,
      createdAt: new Date("2023-11-14T22:13:22.000Z"),
      tags: [{ id: "00000000-0000-4000-8000-000000000408", title: "typescript" }],
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
      createdAt: new Date("2023-11-14T22:13:20.000Z"),
      tags: [],
    }),
    /canonical Reminders V3 reminder shape/,
  );
});
