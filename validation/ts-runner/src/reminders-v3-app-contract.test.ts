import assert from "node:assert/strict";
import test from "node:test";

import {
  remindersV3AppContract,
  remindersV3CanWrite,
  remindersV3ReplaceTagIDs,
  type RemindersV3List,
  type RemindersV3Reminder,
} from "./reminders-v3-app-contract.js";

test("Reminders V3 pins the SQLiteData source and exact Instant graph", () => {
  assert.deepEqual(remindersV3AppContract, {
    upstream: {
      repository: "https://github.com/pointfreeco/sqlite-data",
      revision: "0c79d7a5748fc6d9ce7a1ba2b50f31b175305049",
      schema: "Examples/Reminders/Schema.swift",
      tests: [
        "Examples/RemindersTests/RemindersListsTests.swift",
        "Examples/RemindersTests/RemindersDetailsTests.swift",
        "Examples/RemindersTests/SearchRemindersTests.swift",
        "Tests/SQLiteDataTests/CloudKitTests/SharingTests.swift",
        "Tests/SQLiteDataTests/CloudKitTests/SharingPermissionsTests.swift",
      ],
    },
    namespaces: [
      "$users",
      "remindersLists",
      "reminders",
      "tags",
      "v3_share_memberships",
      "v3_shares",
    ],
    links: [
      "remindersList",
      "remindersTags",
      "remindersListsOwner",
      "remindersListsReaders",
      "remindersListsWriters",
      "v3_share_membershipsShare",
      "v3_share_membershipsUser",
      "v3_sharesOwner",
      "v3_sharesRoot",
    ],
    priority: { low: 1, medium: 2, high: 3 },
    fixtures: {
      list: "00000000-0000-4000-8000-000000000401",
      swiftReminder: "00000000-0000-4000-8000-000000000402",
      share: "00000000-0000-4000-8000-000000000403",
      ownerMembership: "00000000-0000-4000-8000-000000000404",
      readerMembership: "00000000-0000-4000-8000-000000000405",
      typeScriptReminder: "00000000-0000-4000-8000-000000000406",
      swiftTag: "00000000-0000-4000-8000-000000000407",
      typeScriptTag: "00000000-0000-4000-8000-000000000408",
    },
    compilerWarningCount: 0,
  });
});

test("Reminders V3 preserves exact scalar and nested relation shapes", () => {
  const swiftReminder: RemindersV3Reminder = {
    id: remindersV3AppContract.fixtures.swiftReminder,
    title: "Pack lunch",
    notes: "Fruit and water",
    isCompleted: false,
    isFlagged: true,
    dueDate: "2023-11-15T22:13:20.000Z",
    priority: remindersV3AppContract.priority.high,
    position: 0,
    createdAt: "2023-11-14T22:13:21.000Z",
    tags: [{ id: remindersV3AppContract.fixtures.swiftTag, title: "swift" }],
  };
  const list: RemindersV3List = {
    id: remindersV3AppContract.fixtures.list,
    title: "Family",
    color: "#4a99ef",
    position: 0,
    createdAt: "2023-11-14T22:13:20.000Z",
    owner: { id: "owner-user" },
    readers: [{ id: "reader-user" }],
    writers: [],
    reminders: [swiftReminder],
  };

  assert.deepEqual(JSON.parse(JSON.stringify(list)), list);
});

test("Reminders V3 reader and writer roles retain SQLiteData sharing semantics", () => {
  assert.equal(remindersV3CanWrite("owner"), true);
  assert.equal(remindersV3CanWrite("writer"), true);
  assert.equal(remindersV3CanWrite("reader"), false);
  assert.deepEqual(
    remindersV3ReplaceTagIDs(["swift", "shared"], ["typescript", "shared"]),
    ["typescript", "shared"],
  );
});
