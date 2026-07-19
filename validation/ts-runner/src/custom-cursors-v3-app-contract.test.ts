import assert from "node:assert/strict";
import test from "node:test";

import {
  customCursorAvatarURL,
  customCursorPresence,
  customCursorsV3AppContract,
  presenceAfterCursorClear,
} from "./custom-cursors-v3-app-contract.js";

test("Custom Cursors V3 preserves the exact canonical name plus dynamic cursor shape", () => {
  assert.deepEqual(customCursorsV3AppContract, {
    upstream: {
      repository: "https://github.com/instantdb/instant",
      revision: "e71017612aed4031710a35e2fcace30d38d557ac",
      recipe: "client/www/lib/recipes/custom-cursors.tsx",
      component: "client/packages/react/src/Cursors.tsx",
    },
    room: {
      type: "cursors-example",
      id: "124",
      spaceID: "cursors-space-default--cursors-example-124",
    },
    presence: {
      nameKey: "name",
    },
    avatar: {
      endpoint: "/api/avatar",
      size: 40,
    },
    fixtures: {
      swift: {
        name: "swift-custom-avatar",
        cursor: {
          x: 150,
          y: 90,
          xPercent: 25,
          yPercent: 40,
          color: "#123456",
        },
      },
      typeScript: {
        name: "typescript-custom-avatar",
        cursor: {
          x: 300,
          y: 200,
          xPercent: 75,
          yPercent: 60,
          color: "#654321",
        },
      },
    },
    compilerWarningCount: 0,
  });
});

test("Custom Cursors V3 publishes name outside the cursor payload and retains it on clear", () => {
  const fixture = customCursorsV3AppContract.fixtures.swift;
  assert.deepEqual(customCursorPresence(fixture.name, fixture.cursor), {
    name: "swift-custom-avatar",
    "cursors-space-default--cursors-example-124": fixture.cursor,
  });
  assert.deepEqual(presenceAfterCursorClear(fixture.name), {
    name: "swift-custom-avatar",
  });
});

test("Custom Cursors V3 renders the canonical encoded 40-point avatar URL", () => {
  assert.equal(
    customCursorAvatarURL("Swift & TypeScript"),
    "/api/avatar?name=Swift%20%26%20TypeScript&size=40",
  );
});
