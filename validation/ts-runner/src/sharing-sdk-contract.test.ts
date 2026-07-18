import assert from "node:assert/strict";
import test from "node:test";
import { getOps, txInit } from "@instantdb/core";

import type { AppSchema } from "../../fixtures/sharing.schema.js";
import {
  sharingGrantTransaction,
  sharingOwnerTransaction,
  sharingQuery,
} from "./sharing-sdk-contract.js";

test("sharing query requests the complete owner and membership graph", () => {
  assert.deepStrictEqual(sharingQuery("list-e2e"), {
    v3_shared_lists: {
      $: { where: { id: "list-e2e" } },
      owner: {},
      readers: {},
      writers: {},
      share: {
        owner: {},
        memberships: { user: {} },
      },
    },
  });
});

test("owner transaction creates the typed shared root and metadata graph", () => {
  const chunks = sharingOwnerTransaction(txInit<AppSchema>(), {
    listID: "list-e2e",
    shareID: "share-e2e",
    membershipID: "membership-owner-e2e",
    ownerID: "owner-e2e",
    token: "share-token-e2e",
    title: "Canonical shared list",
    value: 1,
    now: new Date("2026-07-18T20:00:00.000Z"),
  });

  assert.equal(chunks.length, 3);
  assert.deepStrictEqual(chunks.flatMap(getOps), [
    [
      "update",
      "v3_shared_lists",
      "list-e2e",
      { title: "Canonical shared list", value: 1 },
    ],
    ["link", "v3_shared_lists", "list-e2e", { owner: "owner-e2e" }],
    [
      "update",
      "v3_shares",
      "share-e2e",
      {
        token: "share-token-e2e",
        rootNamespace: "v3_shared_lists",
        rootID: "list-e2e",
        createdAt: new Date("2026-07-18T20:00:00.000Z"),
        updatedAt: new Date("2026-07-18T20:00:00.000Z"),
      },
    ],
    [
      "link",
      "v3_shares",
      "share-e2e",
      { owner: "owner-e2e", root: "list-e2e" },
    ],
    [
      "update",
      "v3_share_memberships",
      "membership-owner-e2e",
      { role: "owner", acceptedAt: new Date("2026-07-18T20:00:00.000Z") },
    ],
    [
      "link",
      "v3_share_memberships",
      "membership-owner-e2e",
      { share: "share-e2e", user: "owner-e2e" },
    ],
  ]);
});

test("reader and writer grants use distinct typed role links", () => {
  const reader = sharingGrantTransaction(txInit<AppSchema>(), {
    listID: "list-e2e",
    shareID: "share-e2e",
    membershipID: "membership-reader-e2e",
    userID: "reader-e2e",
    role: "reader",
    acceptedAt: new Date("2026-07-18T20:01:00.000Z"),
  });
  const writer = sharingGrantTransaction(txInit<AppSchema>(), {
    listID: "list-e2e",
    shareID: "share-e2e",
    membershipID: "membership-writer-e2e",
    userID: "writer-e2e",
    role: "writer",
    acceptedAt: new Date("2026-07-18T20:02:00.000Z"),
  });

  assert.deepStrictEqual(reader.flatMap(getOps), [
    [
      "update",
      "v3_share_memberships",
      "membership-reader-e2e",
      { role: "reader", acceptedAt: new Date("2026-07-18T20:01:00.000Z") },
    ],
    [
      "link",
      "v3_share_memberships",
      "membership-reader-e2e",
      { share: "share-e2e", user: "reader-e2e" },
    ],
    ["link", "v3_shared_lists", "list-e2e", { readers: "reader-e2e" }],
  ]);
  assert.deepStrictEqual(writer.flatMap(getOps), [
    [
      "update",
      "v3_share_memberships",
      "membership-writer-e2e",
      { role: "writer", acceptedAt: new Date("2026-07-18T20:02:00.000Z") },
    ],
    [
      "link",
      "v3_share_memberships",
      "membership-writer-e2e",
      { share: "share-e2e", user: "writer-e2e" },
    ],
    ["link", "v3_shared_lists", "list-e2e", { writers: "writer-e2e" }],
  ]);
});
